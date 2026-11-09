import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../performance/performance_state.dart';
import 'provider_keys.dart';
import 'read_list_epoch.dart';

/// 群目标在顶栏怎么摆：简单模式加一颗圆形进度环，完整模式把群名收成
/// 圆形头像、旁边排一颗完整的胶囊。
enum GoalBarStyle { simple, full }

/// User settings: the DeepSeek API key (and custom-provider keys, see
/// [ProviderKeyVault]) live in the Android Keystore-backed secure storage;
/// plain preferences go to SharedPreferences.
class AppSettings {
  const AppSettings({
    this.apiKey = '',
    this.themeMode = ThemeMode.system,
    this.autoStartLocal = true,
    this.autoStartLocalExplicit = true,
    this.autoApproveCommands = false,
    this.phoneStorage = false,
    this.webPhoneLayout = true,
    this.hardwareEnterSends = false,
    this.chatTextScale = 1.0,
    this.foldCompletedTurns = true,
    this.showThinking = true,
    this.flatBubbles = false,
    this.bubbleWidth = 0.82,
    this.visualReplies = true,
    this.goalBarStyle = GoalBarStyle.simple,
    this.customProviderIds = const {},
    this.loaded = false,
  });

  final String apiKey;
  final ThemeMode themeMode;

  /// Start the local DSH automatically when the app opens.
  final bool autoStartLocal;

  /// A stored user choice. Policy defaults never create this preference.
  final bool autoStartLocalExplicit;

  /// New local sessions use DSH's `danger-full-access` preset (commands run without asking).
  /// Off by default: there is no sandbox on Android, so each command escalation asks first.
  final bool autoApproveCommands;

  /// Mount the phone's shared storage at /sdcard in the Linux environment.
  final bool phoneStorage;

  /// Fit the embedded DSH Web to a phone (`assets/web/`). Off shows the
  /// official layout untouched, e.g. to check a plugin that restyles it.
  final bool webPhoneLayout;

  /// Hardware Enter sends; Shift+Enter and the software keyboard still insert newlines.
  final bool hardwareEnterSends;

  /// Size of chat content relative to the system setting (header and
  /// composer keep theirs). One of [chatTextScales].
  final double chatTextScale;

  /// A normally finished turn folds its thinking, tool calls and interim
  /// messages into one summary line above the answer (DSH Web's default).
  final bool foldCompletedTurns;

  /// 显示思考过程: off hides a turn's thinking everywhere, finished or running.
  final bool showThinking;

  /// 消息布局: true draws the person's message as plain text at full width,
  /// false as a bubble (the default).
  final bool flatBubbles;

  /// 气泡宽度, as the share of the reading column a bubble may take.
  final double bubbleWidth;

  /// Tell the local DSH it may answer with ```dsh-ui views (charts, cards,
  /// options): a section of the managed AGENTS.md, written at engine start.
  /// Off only drops the instructions; views that arrive are still drawn.
  final bool visualReplies;

  /// 群目标显示: the top bar's goal capsule, simple (a ring beside the name) or
  /// full (the name shrinks to an avatar, the goal takes the bar).
  final GoalBarStyle goalBarStyle;

  /// Custom providers created on the local engine whose key is kept on the
  /// phone ([ProviderKeyVault]). Known at launch, before the engine runs, so
  /// the first-run gate can tell "has a model to talk to" without it.
  final Set<String> customProviderIds;
  final bool loaded;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  /// A DeepSeek key or a custom provider on the local engine.
  bool get hasModelAccess => hasApiKey || customProviderIds.isNotEmpty;

  AppSettings copyWith({
    String? apiKey,
    ThemeMode? themeMode,
    bool? autoStartLocal,
    bool? autoStartLocalExplicit,
    bool? autoApproveCommands,
    bool? phoneStorage,
    bool? webPhoneLayout,
    bool? hardwareEnterSends,
    double? chatTextScale,
    bool? foldCompletedTurns,
    bool? showThinking,
    bool? flatBubbles,
    double? bubbleWidth,
    bool? visualReplies,
    GoalBarStyle? goalBarStyle,
    Set<String>? customProviderIds,
    bool? loaded,
  }) => AppSettings(
    apiKey: apiKey ?? this.apiKey,
    themeMode: themeMode ?? this.themeMode,
    autoStartLocal: autoStartLocal ?? this.autoStartLocal,
    autoStartLocalExplicit: autoStartLocalExplicit ?? this.autoStartLocalExplicit,
    autoApproveCommands: autoApproveCommands ?? this.autoApproveCommands,
    phoneStorage: phoneStorage ?? this.phoneStorage,
    webPhoneLayout: webPhoneLayout ?? this.webPhoneLayout,
    hardwareEnterSends: hardwareEnterSends ?? this.hardwareEnterSends,
    chatTextScale: chatTextScale ?? this.chatTextScale,
    foldCompletedTurns: foldCompletedTurns ?? this.foldCompletedTurns,
    showThinking: showThinking ?? this.showThinking,
    flatBubbles: flatBubbles ?? this.flatBubbles,
    bubbleWidth: bubbleWidth ?? this.bubbleWidth,
    visualReplies: visualReplies ?? this.visualReplies,
    goalBarStyle: goalBarStyle ?? this.goalBarStyle,
    customProviderIds: customProviderIds ?? this.customProviderIds,
    loaded: loaded ?? this.loaded,
  );
}

/// Chat text sizes offered in settings: (scale, label).
List<(double, String)> get chatTextScales => [
  (0.9, appL10n.stateSizeSmall),
  (1.0, appL10n.stateSizeStandard),
  (1.15, appL10n.stateSizeLarge),
  (1.3, appL10n.stateSizeExtraLarge),
];

class SettingsController extends Notifier<AppSettings> {
  static const _apiKeyKey = 'deepseek_api_key';
  static const _themeKey = 'theme_mode';
  static const _autoStartKey = 'auto_start_local';
  static const _autoApproveKey = 'auto_approve_commands';
  static const _phoneStorageKey = 'phone_storage';
  static const _webPhoneLayoutKey = 'web_phone_layout';
  static const _hardwareEnterKey = 'hardware_enter_sends';
  static const _chatTextScaleKey = 'chat_text_scale';
  static const _foldTurnsKey = 'fold_completed_turns';
  static const _showThinkingKey = 'show_thinking';
  static const _flatBubblesKey = 'flat_bubbles';
  static const _goalBarStyleKey = 'goal_bar_style';
  static const _bubbleWidthKey = 'bubble_width';
  static const _visualRepliesKey = 'visual_replies';
  static const _secure = FlutterSecureStorage();
  late Future<void> _loaded;

  @override
  AppSettings build() {
    ref.listen(performanceDefaultsProvider.select((p) => p.autoStartLocal), (_, next) {
      if (!state.autoStartLocalExplicit) state = state.copyWith(autoStartLocal: next);
    });
    _loaded = _load();
    return const AppSettings(autoStartLocalExplicit: false);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    await performanceReady(ref);
    if (!ref.mounted) return;
    String apiKey = '';
    try {
      apiKey = await _secure.read(key: _apiKeyKey) ?? '';
    } catch (_) {
      // Keystore unavailable or corrupted; the user can re-enter the key.
    }
    if (!ref.mounted) return;
    var providerIds = const <String>{};
    try {
      providerIds = (await ref.read(providerKeyVaultProvider).readAll()).keys.toSet();
    } catch (_) {
      // Same: the providers still work, only the self-heal copy is gone.
    }
    if (!ref.mounted) return;
    state = AppSettings(
      apiKey: apiKey,
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString(_themeKey),
        orElse: () => ThemeMode.system,
      ),
      autoStartLocal: prefs.getBool(_autoStartKey) ?? ref.read(performanceDefaultsProvider).autoStartLocal,
      autoStartLocalExplicit: prefs.containsKey(_autoStartKey),
      autoApproveCommands: prefs.getBool(_autoApproveKey) ?? false,
      phoneStorage: prefs.getBool(_phoneStorageKey) ?? false,
      webPhoneLayout: prefs.getBool(_webPhoneLayoutKey) ?? true,
      hardwareEnterSends: prefs.getBool(_hardwareEnterKey) ?? false,
      chatTextScale: _knownScale(prefs.getDouble(_chatTextScaleKey)),
      foldCompletedTurns: prefs.getBool(_foldTurnsKey) ?? true,
      showThinking: prefs.getBool(_showThinkingKey) ?? true,
      flatBubbles: prefs.getBool(_flatBubblesKey) ?? false,
      bubbleWidth: prefs.getDouble(_bubbleWidthKey) ?? 0.82,
      visualReplies: prefs.getBool(_visualRepliesKey) ?? true,
      goalBarStyle: GoalBarStyle.values.firstWhere(
        (style) => style.name == prefs.getString(_goalBarStyleKey),
        orElse: () => GoalBarStyle.simple,
      ),
      customProviderIds: providerIds,
      loaded: true,
    );
  }

  /// Keeps [key] for the local engine's custom provider [id] (see
  /// [ProviderKeyVault]).
  Future<void> saveProviderKey(String id, String key) async {
    ref.read(readListCredentialEpochProvider.notifier).advance();
    await ref.read(providerKeyVaultProvider).write(id, key);
    state = state.copyWith(customProviderIds: {...state.customProviderIds, id});
  }

  Future<void> removeProviderKey(String id) async {
    ref.read(readListCredentialEpochProvider.notifier).advance();
    await ref.read(providerKeyVaultProvider).delete(id);
    state = state.copyWith(customProviderIds: {...state.customProviderIds}..remove(id));
  }

  Future<void> setApiKey(String key) async {
    ref.read(readListCredentialEpochProvider.notifier).advance();
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _secure.delete(key: _apiKeyKey);
    } else {
      await _secure.write(key: _apiKeyKey, value: trimmed);
    }
    state = state.copyWith(apiKey: trimmed);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setAutoApproveCommands(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoApproveKey, value);
    state = state.copyWith(autoApproveCommands: value);
  }

  Future<void> setPhoneStorage(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_phoneStorageKey, value);
    state = state.copyWith(phoneStorage: value);
  }

  static double _knownScale(double? v) => chatTextScales.any((s) => s.$1 == v) ? v! : 1.0;

  Future<void> setChatTextScale(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_chatTextScaleKey, value);
    state = state.copyWith(chatTextScale: value);
  }

  Future<void> setShowThinking(bool value) async {
    state = state.copyWith(showThinking: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showThinkingKey, value);
  }

  Future<void> setGoalBarStyle(GoalBarStyle value) async {
    state = state.copyWith(goalBarStyle: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_goalBarStyleKey, value.name);
  }

  Future<void> setFlatBubbles(bool value) async {
    state = state.copyWith(flatBubbles: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_flatBubblesKey, value);
  }

  Future<void> setBubbleWidth(double value) async {
    state = state.copyWith(bubbleWidth: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_bubbleWidthKey, value);
  }

  Future<void> setFoldCompletedTurns(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_foldTurnsKey, value);
    state = state.copyWith(foldCompletedTurns: value);
  }

  /// Takes effect at the next engine start (the instructions live in the
  /// managed AGENTS.md, written before DSH starts).
  Future<void> setVisualReplies(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_visualRepliesKey, value);
    state = state.copyWith(visualReplies: value);
  }

  Future<void> setWebPhoneLayout(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_webPhoneLayoutKey, value);
    state = state.copyWith(webPhoneLayout: value);
  }

  Future<void> setHardwareEnterSends(bool value) async {
    await _loaded;
    if (!ref.mounted) return;
    state = state.copyWith(hardwareEnterSends: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hardwareEnterKey, value);
  }

  Future<void> setAutoStartLocal(bool value) async {
    await _loaded;
    if (!ref.mounted) return;
    state = state.copyWith(autoStartLocal: value, autoStartLocalExplicit: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStartKey, value);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
