// Composer dictation. Automatic mode uses the engine's voice model when it is
// ready (the on-device SenseVoice model, voice settings); otherwise the system
// service, retried once with engine transcription after a non-user service
// failure. Audio is recorded again; the system service's earlier audio is never
// claimed to be recoverable.

import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../diagnostics/app_error_log.dart';
import '../../../l10n/l10n.dart';
import '../../../state/voice_settings.dart';
import '../mention/mention_text_controller.dart';
import 'voice_bridge.dart';

enum VoicePhase { idle, starting, listening, transcribing }

enum VoiceEngine { system, engine }

/// Why a probe of the engine's voice model found nothing usable. The tap that
/// made the probe says which one it was: 「系统识别用不了」 is a wrong answer
/// when the model is on the phone and the engine has simply not loaded it.
enum VoiceProbeFailure {
  /// The host changed under the probe, or no client was there yet.
  host,

  /// The phone cannot record for the engine.
  recorder,

  /// The engine answers without a speech API at all (its plugin is not loaded).
  noApi,

  /// The speech API answered, but no provider is usable.
  noModel,

  /// The provider is on its way (checking, loading, waking): not missing, and
  /// worth waiting a moment for rather than falling back to the phone.
  preparing,

  /// The probe ran out of time.
  timeout,

  /// The probe failed for another reason.
  failed,
}

class VoiceMessage {
  const VoiceMessage(this.text, {this.openSettings = false, this.change = false});
  final String text;

  /// The app's system settings page (microphone permission) helps.
  final bool openSettings;

  /// Another way of dictating would do (no recognizer, no service, the
  /// service failed, the voice model not downloaded): the toast offers
  /// 「更换」, to 设置 › 语音输入 (the mode and the voice model).
  final bool change;
}

/// Complete Android SpeechRecognizer error table; unknown/vendor codes remain visible.
String voiceErrorText(int code) => switch (code) {
  1 => appL10n.voiceErrorNetworkTimeout,
  2 => appL10n.voiceErrorNetwork,
  3 => appL10n.voiceErrorAudio,
  4 => appL10n.voiceErrorServer,
  5 => appL10n.voiceErrorClient,
  6 => appL10n.voiceErrorSpeechTimeout,
  7 => appL10n.voiceErrorNoMatch,
  8 => appL10n.voiceErrorBusy,
  9 => appL10n.voiceErrorPermission,
  10 => appL10n.voiceErrorTooManyRequests,
  11 => appL10n.voiceErrorDisconnected,
  12 => appL10n.voiceErrorLanguageUnsupported,
  13 => appL10n.voiceErrorLanguageUnavailable,
  14 => appL10n.voiceErrorSupportCheck,
  15 => appL10n.voiceErrorDownloadEvents,
  VoiceError.recorderFailed => appL10n.chatVoiceMicrophoneFailed,
  _ => appL10n.voiceErrorUnknown(code),
};

class _VoiceTarget {
  const _VoiceTarget(this.client, this.generation, this.catalog);
  final DshClient client;
  final MuxGeneration? generation;
  final SpeechCatalog catalog;

  bool current(DshClient? active) => identical(client, active) && identical(generation, client.mux.generation);
}

class VoiceInputController extends ChangeNotifier with WidgetsBindingObserver {
  VoiceInputController({
    required this.input,
    required this.bridge,
    required this.client,
    Future<VoiceMode> Function()? mode,
    bool Function()? modelReady,
    bool Function()? hostIsLocal,
    this.onRecognized,
    this.requiredProviderId,
    bool observeLifecycle = true,
  }) : _mode = mode ?? _automatic,
       _modelReady = modelReady ?? _noModel,
       _hostIsLocal = hostIsLocal ?? _notLocal,
       _observing = observeLifecycle {
    if (_observing) WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  static Future<VoiceMode> _automatic() async => VoiceMode.auto;
  static bool _noModel() => false;
  static bool _notLocal() => false;

  /// Optional strict offline provider for the pet foreground fallback.
  final String? requiredProviderId;
  final TextEditingController input;
  final VoiceBridge bridge;
  final DshClient? Function() client;
  final Future<VoiceMode> Function() _mode;

  /// The on-device voice model is ready for this host (voice settings):
  /// automatic mode then records for it instead of trying the phone service.
  final bool Function() _modelReady;

  /// The engine runs on this phone, where asking it costs nothing: the model's
  /// readiness is the engine's answer, not the download page's memory of it.
  final bool Function() _hostIsLocal;
  final bool _observing;
  void Function(VoiceMessage message)? onMessage;

  /// A dictation put its words in the composer (usage statistics).
  final VoidCallback? onRecognized;
  final level = ValueNotifier<double>(0);

  VoiceCapabilities _caps = VoiceCapabilities.none;
  _VoiceTarget? _catalog;
  _VoiceTarget? _target;
  DshClient? _probedClient;
  MuxGeneration? _probedGeneration;
  Future<void>? _refreshing;
  int _catalogProbe = 0;
  bool _disposed = false;
  bool _foreground = true;
  bool _requestingPermission = false;

  VoicePhase _phase = VoicePhase.idle;
  VoiceEngine? _engine;
  VoiceMode _runMode = VoiceMode.auto;
  int _operation = 0;
  bool _fallbackTried = false;
  bool _switching = false;
  DshClient? _runClient;
  MuxGeneration? _runGeneration;
  StreamSubscription<VoiceEvent>? _events;
  Timer? _finalTimeout;

  /// Why the last probe found no engine model; null when it found one.
  VoiceProbeFailure? _probeFailure;

  /// The probe's own words, for the diagnostics bundle. Never shown to a user.
  String? _probeDetail;

  /// The catalog as the last probe saw it (providers, phase, selection).
  String? _catalogSummary;

  /// The microphone grant, read without asking; for the diagnostics bundle.
  String _micPermission = '?';

  /// Writes down what a tap of the voice key acted on, and which way it went.
  ///
  /// Unconditional: a fall to the phone's recognizer that leaves nothing
  /// behind cannot be told apart from a broken model or a missing grant.
  void _diag(String branch) {
    final detail = (_probeDetail ?? '-').replaceAll('\n', ' ');
    final short = detail.length > 300 ? detail.substring(0, 300) : detail;
    appErrorLog.record(
      AppErrorSource.platform,
      'voice: branch=$branch '
          'recorder=${_caps.recorder} recognizer=${_caps.recognizer} '
          'systemUnreliable=${_caps.systemUnreliable} mic=$_micPermission '
          'hostIsLocal=${_hostIsLocal()} modelReady=${_modelReady()} '
          'mode=${_runMode.name} probe=${_probeFailure?.name ?? 'ok'} '
          'detail=$short catalog=${_catalogSummary ?? '-'}',
      StackTrace.current,
    );
  }

  TextEditingValue? _base;
  int _anchorStart = 0;
  int _anchorEnd = 0;
  String _heard = '';

  VoicePhase get phase => _phase;
  bool get active => _phase != VoicePhase.idle;
  VoiceEngine? get engine => _engine;
  bool get engineReady => _caps.recorder && (_catalog?.current(client()) ?? false);
  bool get available => _caps.recognizer || engineReady;

  bool _current(int operation) => !_disposed && active && operation == _operation;
  // Phone recognition does not use the Host transport. A different client
  // still changes the draft's owner; engine recording/fallback keeps its generation.
  bool get _hostCurrent =>
      identical(_runClient, client()) &&
      (_engine == VoiceEngine.system || identical(_runGeneration, _runClient?.mux.generation));

  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  /// A model change must not be absorbed by a probe of its previous state.
  /// Wait for that probe, without replaying the event onto a replacement host.
  Future<void> refreshAfterModelChange() async {
    if (_disposed) return;
    final c = client();
    final generation = c?.mux.generation;
    await _refreshing;
    if (_disposed || !identical(client(), c) || !identical(c?.mux.generation, generation)) return;
    // The model may be another one now: the old answer is not this answer.
    _catalog = null;
    await refresh();
  }

  Future<void> _refresh() async {
    final caps = await bridge.capabilities();
    if (_disposed) return;
    _caps = caps;
    final c = client();
    final generation = c?.mux.generation;
    _probedClient = c;
    _probedGeneration = generation;
    if (!(_catalog?.current(c) ?? false)) _catalog = null;
    // A working system service must not wait for a slow engine probe. The
    // fallback and explicit Engine mode probe on demand, including on ROMs
    // that report a system service which fails as soon as it is called.
    // A working answer is not probed again: on a busy engine the probe can
    // take seconds, and dictation must not wait for a round that is streaming.
    if (_catalog == null && caps.recorder && (!caps.recognizer || _hostIsLocal())) {
      await _readCatalog(c, generation);
    }
    if (!_disposed) notifyListeners();
  }

  Future<_VoiceTarget?> _readCatalog(
    DshClient? c,
    MuxGeneration? generation, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (c == null || !_caps.recorder || !identical(client(), c) || !identical(c.mux.generation, generation)) {
      _probeFailure = c == null || !identical(client(), c) ? VoiceProbeFailure.host : VoiceProbeFailure.recorder;
      return null;
    }
    final probe = ++_catalogProbe;
    _VoiceTarget? target;
    var failure = VoiceProbeFailure.noModel;
    String? detail;
    String? summary;
    try {
      // A busy engine (a long round streaming) answers late; 4 s called that
      // a missing model. The model is local, so waiting is cheap.
      var catalog = await c.speechCatalog().timeout(timeout);
      if (catalog == null) {
        // No speech API on this host: its plugin is not loaded, or it is older
        // than the API. A different failure from "no provider is usable".
        failure = VoiceProbeFailure.noApi;
        detail = 'speech/catalog answered null (no speech API on this host)';
      } else if (requiredProviderId case final id?) {
        final provider = catalog.providers.where((p) => p.id == id && p.location == 'host-local').firstOrNull;
        if (provider != null && !provider.usable && _preparing(provider.phase)) {
          failure = VoiceProbeFailure.preparing;
          detail = 'provider=$id phase=${provider.phase}';
          catalog = null;
        } else if (provider == null || !provider.usable) {
          failure = VoiceProbeFailure.noModel;
          catalog = null;
        } else {
          catalog = SpeechCatalog(
            providers: catalog.providers,
            providerId: id,
            language: catalog.language,
            maxAudioBytes: catalog.maxAudioBytes,
            maxDurationSeconds: catalog.maxDurationSeconds,
          );
        }
      }
      summary = _summarize(catalog);
      if (catalog?.selected?.usable ?? false) target = _VoiceTarget(c, generation, catalog!);
      if (target == null && detail == null) {
        final selectedId = catalog?.selected?.id;
        final phase = catalog?.providers.where((p) => p.id == selectedId).firstOrNull?.phase;
        // Preparing is not missing: the model is being checked or loaded, and
        // the tap may not be handed to the phone as if there were no model.
        if (phase != null && _preparing(phase)) failure = VoiceProbeFailure.preparing;
        detail = 'selected=${selectedId ?? '-'} phase=${phase ?? '-'}';
      }
    } on TimeoutException catch (error) {
      failure = VoiceProbeFailure.timeout;
      detail = '$error';
    } catch (error) {
      // Missing speech bundle, unavailable provider, or disconnected host.
      failure = VoiceProbeFailure.failed;
      detail = '$error';
    }
    if (_disposed || !identical(client(), c) || !identical(c.mux.generation, generation)) return null;
    if (probe == _catalogProbe) {
      // A probe that never answered keeps the last catalog we saw.
      _catalogSummary = summary ?? _catalogSummary;
      if (target != null) {
        _catalog = target;
        _probeFailure = null;
        _probeDetail = null;
      } else {
        // A busy engine does not take a working model away. Only an answer
        // that says there is none (no API, no usable provider) clears it.
        if (failure == VoiceProbeFailure.noApi ||
            failure == VoiceProbeFailure.noModel ||
            failure == VoiceProbeFailure.preparing) {
          _catalog = null;
        }
        _probeFailure = failure;
        _probeDetail = detail;
      }
    }
    return target;
  }

  /// A provider on its way: preparation states that become usable by
  /// themselves in a moment (they are not a failed or missing model).
  static bool _preparing(String phase) =>
      const {'downloading', 'checking', 'loading', 'waking', 'cancelling'}.contains(phase);

  /// `id(phase)` per provider plus the selection, short enough for a log line.
  static String _summarize(SpeechCatalog? catalog) {
    if (catalog == null) return 'none';
    final providers = [
      for (final p in catalog.providers) '${p.id}(${p.phase}${p.usable ? ',usable' : ''})',
    ].join(' ');
    return 'selected=${catalog.providerId ?? '-'} providers=[${providers.isEmpty ? '-' : providers}]';
  }

  Future<String> _readPermission() async {
    try {
      return switch (await bridge.permission()) {
        VoicePermission.granted => 'granted',
        VoicePermission.denied => 'denied',
        VoicePermission.blocked => 'blocked',
      };
    } catch (_) {
      return 'unknown';
    }
  }

  /// Probes until the model is usable, the answer is a real failure, or
  /// [budget] runs out — `checking` must not become a fall to the phone.
  /// Reports [onWaiting] once, when it first has to wait.
  Future<_VoiceTarget?> _readCatalogWaiting(
    int operation, {
    Duration budget = const Duration(seconds: 4),
    VoidCallback? onWaiting,
  }) async {
    final end = DateTime.now().add(budget);
    var waiting = false;
    while (true) {
      final target = await _readCatalog(_runClient, _runGeneration, timeout: const Duration(seconds: 2));
      if (!_current(operation)) return null;
      if (target != null) return target;
      if (_probeFailure != VoiceProbeFailure.preparing) return null;
      if (!waiting) {
        waiting = true;
        onWaiting?.call();
      }
      if (!DateTime.now().isBefore(end)) {
        _probeFailure = VoiceProbeFailure.preparing;
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!_current(operation)) return null;
    }
  }

  void ensureFresh() {
    if (_disposed) return;
    if (active && !_hostCurrent) {
      // Composer calls this while building. Restoring the draft notifies its
      // persistence listener, so defer it until after this synchronous build.
      // A queued check from an older run must never cancel its replacement.
      final operation = _operation;
      scheduleMicrotask(() {
        if (_current(operation) && !_hostCurrent) unawaited(cancel());
      });
    }
    final c = client();
    if (_refreshing != null || (identical(c, _probedClient) && identical(c?.mux.generation, _probedGeneration))) return;
    scheduleMicrotask(() => unawaited(refresh()));
  }

  Future<void> start() async {
    if (active || _disposed || !_foreground) return;
    final operation = ++_operation;
    _fallbackTried = false;
    _switching = false;
    _runClient = client();
    _runGeneration = _runClient?.mux.generation;
    _setPhase(VoicePhase.starting);
    final VoicePermission permission;
    _requestingPermission = true;
    try {
      permission = await bridge.requestPermission();
    } on PlatformException {
      if (_current(operation)) {
        _finish();
        _say(VoiceMessage(appL10n.chatVoiceMicrophoneFailed));
      }
      return;
    } finally {
      if (operation == _operation) _requestingPermission = false;
    }
    if (!_current(operation)) return;
    if (!_foreground || !_hostCurrent) {
      await cancel();
      return;
    }
    if (permission != VoicePermission.granted) {
      _diag('permission-${permission.name}');
      _finish();
      _say(
        permission == VoicePermission.blocked
            ? VoiceMessage(appL10n.chatVoicePermissionOff, openSettings: true)
            : VoiceMessage(appL10n.chatVoicePermissionNeeded),
      );
      return;
    }
    final VoiceMode mode;
    try {
      mode = await _mode();
    } catch (_) {
      if (_current(operation)) {
        _finish();
        _say(VoiceMessage(appL10n.voiceSettingsFailed));
      }
      return;
    }
    if (!_current(operation)) return;
    _runMode = mode;
    _micPermission = await _readPermission();
    await refresh();
    if (!_current(operation)) return;
    if (!_hostCurrent) {
      await cancel();
      return;
    }
    final system =
        _runMode == VoiceMode.system || (_runMode == VoiceMode.auto && _caps.recognizer && !_caps.systemUnreliable);
    if (system && !_caps.recognizer) {
      _diag('no-system-recognizer');
      _finish();
      _say(VoiceMessage(appL10n.voiceChooseSystem, change: true));
      return;
    }
    final value = input.value;
    _base = value;
    _anchorStart = value.selection.isValid ? value.selection.start : value.text.length;
    _anchorEnd = value.selection.isValid ? value.selection.end : value.text.length;
    _heard = '';
    final asked = system && _runMode == VoiceMode.auto && _caps.recorder && (_modelReady() || _hostIsLocal());
    if (system && _runMode == VoiceMode.auto && !asked) _diag('system-no-probe');
    if (asked) {
      // The voice model first: phone services on Chinese ROMs report
      // themselves available and then fail. The engine has the last word; a
      // stale "ready" leaves the phone service as it was.
      // An answer from this same engine is good enough to record with: a
      // round streaming on it can delay a fresh probe past any timeout, and
      // dictation must not fail because the group is busy.
      var target = (_catalog?.current(client()) ?? false) ? _catalog : null;
      if (target == null) {
        // A model that is checking or loading is worth a few seconds: the
        // phone's recognizer is not what the person chose.
        target = await _readCatalogWaiting(
          operation,
          onWaiting: () => _say(VoiceMessage(appL10n.voiceEnginePreparing)),
        );
        if (!_current(operation)) return;
      }
      // The engine was too busy to answer in time: the model that worked a
      // moment ago still works, so use that answer rather than the phone's
      // service.
      if (target == null && _probeFailure == VoiceProbeFailure.timeout && (_catalog?.current(client()) ?? false)) {
        target = _catalog;
        _probeFailure = null;
      }
      if (target != null) {
        _diag('engine');
        await _startRecorder(operation, target);
        return;
      }
      if (_probeFailure == VoiceProbeFailure.preparing) {
        _diag('engine-preparing');
        _finish();
        _say(VoiceMessage(appL10n.voiceEnginePreparingTimeout, change: true));
        return;
      }
      // The engine was asked and did not answer in time: 「系统识别用不了」 is a
      // wrong answer, and the phone's service is not what the user chose.
      if (_probeFailure == VoiceProbeFailure.timeout || _probeFailure == VoiceProbeFailure.failed) {
        _diag('engine-busy');
        _finish();
        _say(VoiceMessage(appL10n.voiceEngineBusy, change: true));
        return;
      }
      // The model is on this phone and the user pointed the app at it, but the
      // engine does not have it: saying 「系统识别用不了」 here blames the wrong
      // side — say what the probe found instead.
      final engineMissing = _probeFailure == VoiceProbeFailure.noApi || _probeFailure == VoiceProbeFailure.noModel;
      if (engineMissing && _modelReady()) {
        _diag('engine-missing');
        _finish();
        _say(VoiceMessage(appL10n.voiceEngineModelMissing, change: true));
        return;
      }
      _diag('system-after-probe');
    }
    if (!system) {
      final target = await _readCatalogWaiting(
        operation,
        onWaiting: () => _say(VoiceMessage(appL10n.voiceEnginePreparing)),
      );
      if (!_current(operation)) return;
      if (target == null) {
        _diag('engine-mode-failed');
        if (_probeFailure == VoiceProbeFailure.preparing) {
          _finish();
          _say(VoiceMessage(appL10n.voiceEnginePreparingTimeout, change: true));
          return;
        }
        _finish();
        final busy = _probeFailure == VoiceProbeFailure.timeout || _probeFailure == VoiceProbeFailure.failed;
        final engineMissing =
            _modelReady() && _probeFailure != null && _probeFailure != VoiceProbeFailure.host && !busy;
        _say(
          VoiceMessage(
            busy
                ? appL10n.voiceEngineBusy
                : engineMissing
                ? appL10n.voiceEngineModelMissing
                : _runMode == VoiceMode.engine
                ? appL10n.voiceConfigureEngine
                : appL10n.voiceConfigureEither,
            change: true,
          ),
        );
        return;
      }
      _diag('engine-mode');
      await _startRecorder(operation, target);
      return;
    }
    _engine = VoiceEngine.system;
    _diag('system');
    _listen(operation);
    try {
      await bridge.startRecognizer();
    } on PlatformException catch (error) {
      if (_current(operation) && _engine == VoiceEngine.system) _error(operation, _platformCode(error));
      return;
    }
    if (!_current(operation) || _engine != VoiceEngine.system || _switching || _phase != VoicePhase.starting) return;
    HapticFeedback.lightImpact();
    _setPhase(VoicePhase.listening);
  }

  void _listen(int operation) {
    unawaited(_events?.cancel());
    _events = bridge.events.listen((event) => _onEvent(operation, event));
  }

  static int _platformCode(PlatformException error) {
    final details = error.details;
    if (details is Map && details['code'] is num) return (details['code'] as num).toInt();
    return switch (error.code) {
      'permission' => 9,
      'audio' => VoiceError.recorderFailed,
      _ => 5,
    };
  }

  Future<void> _startRecorder(int operation, _VoiceTarget target, {bool fallback = false}) async {
    if (!_current(operation) || !target.current(client())) return;
    _target = target;
    _engine = VoiceEngine.engine;
    _switching = false;
    _listen(operation);
    try {
      await bridge.startRecorder(maxSeconds: (target.catalog.maxSeconds - 1).clamp(1, 600));
    } on PlatformException catch (error) {
      if (_current(operation)) {
        _finish();
        _say(VoiceMessage(voiceErrorText(_platformCode(error))));
      }
      return;
    }
    if (!_current(operation) || _phase != VoicePhase.starting) return;
    if (!target.current(client())) {
      await cancel();
      return;
    }
    HapticFeedback.lightImpact();
    _setPhase(VoicePhase.listening);
    if (fallback) _say(VoiceMessage(appL10n.voiceFallbackStarted));
  }

  Future<void> _fallback(int operation) async {
    _fallbackTried = true;
    _switching = true;
    _engine = null;
    _finalTimeout?.cancel();
    _finalTimeout = null;
    unawaited(_events?.cancel());
    _events = null;
    _restoreDraft();
    _heard = '';
    _setPhase(VoicePhase.starting);
    try {
      await bridge.cancel();
    } catch (_) {}
    if (!_current(operation)) return;
    if (!_hostCurrent) {
      _finish();
      _say(VoiceMessage(appL10n.commonEngineUnreachable));
      return;
    }
    final target = await _readCatalog(_runClient, _runGeneration);
    if (!_current(operation)) return;
    if (target == null) {
      _finish();
      _say(VoiceMessage(appL10n.voiceConfigureEither, change: true));
      return;
    }
    await _startRecorder(operation, target, fallback: true);
  }

  Future<void> stop() async {
    if (_phase != VoicePhase.listening) return;
    final operation = _operation;
    HapticFeedback.lightImpact();
    _setPhase(VoicePhase.transcribing);
    if (_engine == VoiceEngine.system) {
      _finalTimeout = Timer(const Duration(seconds: 6), () {
        if (!_current(operation) || _engine != VoiceEngine.system) return;
        unawaited(bridge.cancel());
        _completeSystem(_heard);
      });
      try {
        await bridge.stop();
      } on PlatformException catch (error) {
        if (_current(operation) && _engine == VoiceEngine.system) _error(operation, _platformCode(error));
      }
      return;
    }
    await _transcribe(operation);
  }

  Future<void> _transcribe(int operation) async {
    final target = _target;
    Uint8List? wav;
    try {
      wav = await bridge.stop();
    } on PlatformException catch (error) {
      if (_current(operation)) {
        _finish();
        _say(VoiceMessage(voiceErrorText(_platformCode(error))));
      }
      return;
    }
    if (!_current(operation)) return;
    if (target == null || !target.current(client())) {
      _finish();
      _say(VoiceMessage(appL10n.commonEngineUnreachable));
      return;
    }
    if (wav == null || wav.length < 44 + 9600) {
      _finish();
      _say(VoiceMessage(appL10n.chatVoiceNotHeard));
      return;
    }
    try {
      final transcript = await target.client.transcribe(
        wav,
        providerId: target.catalog.providerId,
        language: target.catalog.language,
      );
      if (!_current(operation)) return;
      if (!target.current(client())) {
        _finish();
        return;
      }
      if (transcript.text.isEmpty) {
        _finish();
        _say(VoiceMessage(appL10n.chatVoiceNotHeard));
        return;
      }
      _apply(transcript.text, provisional: false);
      onRecognized?.call();
      _finish();
    } catch (_) {
      if (!_current(operation)) return;
      _finish();
      _say(VoiceMessage(appL10n.chatVoiceTranscriptionFailed, change: true));
    }
  }

  void _restoreDraft() {
    final base = _base;
    if (base == null) return;
    final mentions = input;
    if (mentions is MentionTextController) mentions.provisional = TextRange.empty;
    input.value = base;
  }

  Future<void> cancel() async {
    if (!active) return;
    _restoreDraft();
    _finish();
    try {
      await bridge.cancel();
    } catch (_) {}
  }

  void _error(int operation, int code) {
    // The app holds the microphone permission (checked before starting), so
    // ERROR_INSUFFICIENT_PERMISSIONS here is the service's own: Xiaomi's 小爱
    // without its permissions, a vendor service refusing other apps.
    if (_engine == VoiceEngine.system &&
        _runMode == VoiceMode.auto &&
        !_fallbackTried &&
        (VoiceError.canFallback(code) || code == VoiceError.permission)) {
      unawaited(_fallback(operation));
      return;
    }
    final heard = _heard;
    if (heard.trim().isEmpty) {
      _restoreDraft();
    } else {
      _apply(heard, provisional: false);
      onRecognized?.call();
    }
    _finish();
    if (!VoiceError.noSpeech.contains(code) || heard.trim().isEmpty) _say(VoiceMessage(voiceErrorText(code)));
  }

  void _onEvent(int operation, VoiceEvent event) {
    if (!_current(operation) || _switching) return;
    switch (event) {
      case VoiceLevel(:final value):
        level.value = value.clamp(0.0, 1.0);
      case VoicePartial(:final text):
        if (_engine != VoiceEngine.system) return;
        _heard = text;
        _apply(text, provisional: true);
      case VoiceFinal(:final text):
        if (_engine != VoiceEngine.system) return;
        _completeSystem(text.isEmpty ? _heard : text);
      case VoiceError(:final code):
        _error(operation, code);
      case VoiceLimit():
        if (_engine == VoiceEngine.engine && _phase == VoicePhase.listening) unawaited(stop());
      case VoiceEnd():
        if (_engine == VoiceEngine.system) {
          _completeSystem(_heard);
        }
    }
  }

  void _completeSystem(String text) {
    if (text.trim().isEmpty) {
      _restoreDraft();
      _finish();
      _say(VoiceMessage(appL10n.chatVoiceNotHeard));
    } else {
      _apply(text, provisional: false);
      onRecognized?.call();
      _finish();
    }
  }

  /// Puts [heard] at the anchor of the starting draft.
  void _apply(String heard, {required bool provisional}) {
    final base = _base;
    if (base == null) return;
    final text = base.text;
    final spoken = heard.trim();
    final before = text.substring(0, _anchorStart);
    final after = text.substring(_anchorEnd);
    final lead = spoken.isNotEmpty && _needsSpace(before, spoken) ? ' ' : '';
    final trail = spoken.isNotEmpty && _needsSpace(spoken, after) ? ' ' : '';
    final inserted = '$lead$spoken$trail';
    final caret = _anchorStart + inserted.length;
    final mentions = input;
    if (mentions is MentionTextController) {
      mentions.provisional = TextRange.empty;
    }
    input.value = TextEditingValue(
      text: '$before$inserted$after',
      selection: TextSelection.collapsed(offset: caret - trail.length),
    );
    if (mentions is MentionTextController && provisional && spoken.isNotEmpty) {
      mentions.provisional = TextRange(
        start: _anchorStart + lead.length,
        end: _anchorStart + lead.length + spoken.length,
      );
    }
  }

  /// Latin words on both sides of the seam get a space; CJK does not.
  static bool _needsSpace(String left, String right) {
    if (left.isEmpty || right.isEmpty) return false;
    final a = left.codeUnitAt(left.length - 1);
    final b = right.codeUnitAt(0);
    bool word(int u) => (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
    // `Hello,` + `world` too.
    final leftEnds = word(a) || ',.!?;:'.codeUnits.contains(a);
    return leftEnds && word(b);
  }

  void _finish() {
    _operation++;
    _requestingPermission = false;
    _switching = false;
    _target = null;
    _finalTimeout?.cancel();
    _finalTimeout = null;
    unawaited(_events?.cancel());
    _events = null;
    final mentions = input;
    if (mentions is MentionTextController) {
      mentions.provisional = TextRange.empty;
    }
    _base = null;
    _engine = null;
    level.value = 0;
    _setPhase(VoicePhase.idle);
  }

  void _setPhase(VoicePhase phase) {
    if (_phase == phase || _disposed) return;
    _phase = phase;
    notifyListeners();
  }

  void _say(VoiceMessage message) {
    if (!_disposed) onMessage?.call(message);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _foreground = false;
        if (active && !_requestingPermission) unawaited(cancel());
      case AppLifecycleState.resumed:
        _foreground = true;
        unawaited(refresh());
      default:
        break;
    }
  }

  @override
  void dispose() {
    if (active) {
      unawaited(bridge.cancel().catchError((_) {}));
    }
    _operation++;
    _disposed = true;
    _finalTimeout?.cancel();
    unawaited(_events?.cancel());
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    level.dispose();
    super.dispose();
  }
}
