/// Speech recognition the app performs itself, under 语音输入 › 云端.
///
/// The engine only transcribes through recognizers it has registered, and a
/// `cloud` one would need a plugin this host does not ship. Nothing in the app
/// needs it: a provider the app can already reach, whose model declares audio
/// input, *is* a speech endpoint, and the recorded WAV can go straight there.
///
/// Two request shapes are in use among the providers one meets here:
///  * chat — `POST {base}/chat/completions` with the audio as an `input_audio`
///    content part (Xiaomi MiMo and the other OpenAI-compatible multimodal
///    endpoints). Tried first.
///  * whisper — `POST {base}/audio/transcriptions`, multipart (OpenAI, Groq,
///    SiliconFlow's SenseVoice). Tried when the first one is refused.
/// Which one answered is remembered per model, so only the first dictation
/// pays for the guess.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'provider_keys.dart';
import 'providers_state.dart';

/// One model the app can recognize speech with: a provider configured on the
/// active engine, plus the model entry that declares audio input.
class CloudSpeechModel {
  const CloudSpeechModel({
    required this.providerId,
    required this.providerName,
    required this.modelId,
    required this.baseUrl,
    required this.api,
    this.apiKey,
  });

  /// The engine route the provider lives on (`custom-mimo`).
  final String providerId;

  /// What the provider list calls it (`MIMO`).
  final String providerName;

  /// `mimo-v2.5-asr`.
  final String modelId;

  /// `https://api.example.com/v1`.
  final String baseUrl;

  /// The protocol the provider was declared with.
  final ProviderApi? api;

  /// The key as this phone keeps it (see [ProviderKeyVault]); null when the
  /// provider was set up in the web page and never typed here.
  final String? apiKey;

  /// What the preferences store: one recognizer per provider and model.
  String get id => '$providerId/$modelId';

  /// Shown under 云端语音模型.
  String get name => providerName;

  /// Shown as the row's second line.
  String get subtitle => modelId;

  /// A key is here, so the request can be made without a detour.
  bool get ready => (apiKey ?? '').isNotEmpty;
}

/// The cloud speech models the active engine's providers offer.
final cloudSpeechModelsProvider = FutureProvider.autoDispose<List<CloudSpeechModel>>((ref) async {
  final snapshot = await ref.watch(customProvidersProvider.future);
  if (snapshot == null) return const [];
  final keys = await ref.watch(providerKeyVaultProvider).readAll();
  final models = <CloudSpeechModel>[];
  for (final provider in snapshot.providers) {
    if (provider.baseUrl.isEmpty) continue;
    final key = keys[provider.id];
    // A model declared 「文本和音频」 is the reliable answer; a model that only
    // says so in its name (`mimo-v2.5-asr`, a whisper endpoint) is the second
    // one, so a provider set up without the input type still shows up.
    final declared = [
      for (final model in provider.models)
        if (model.acceptsAudio(routeDefault: provider.defaults.input)) model,
    ];
    final speech = declared.isNotEmpty
        ? declared
        : [
            for (final model in provider.models)
              if (_speechName.hasMatch(model.id)) model,
          ];
    for (final model in speech) {
      models.add(
        CloudSpeechModel(
          providerId: provider.id,
          providerName: provider.displayName,
          modelId: model.id,
          baseUrl: provider.baseUrl,
          api: provider.api,
          apiKey: key,
        ),
      );
    }
  }
  return models;
});

/// Model names that say what they are, when the provider did not.
final _speechName = RegExp(r'asr|whisper|transcri|speech|sensevoice|paraformer', caseSensitive: false);

/// Which cloud model was picked, and (per model) which request shape worked.
///
/// Kept in the preferences rather than on the engine: the call is the app's.
abstract class CloudSpeechPrefs {
  /// One model id (`custom-mimo/mimo-v2.5-asr`).
  static const selectedKey = 'voice_cloud_model';

  static String shapeKey(String modelId) => 'voice_cloud_shape_${Uri.encodeComponent(modelId)}';

  static Future<String?> selected() async {
    try {
      return (await SharedPreferences.getInstance()).getString(selectedKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> select(String? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null || id.isEmpty) {
        await prefs.remove(selectedKey);
      } else {
        await prefs.setString(selectedKey, id);
      }
    } catch (_) {
      // Preferences unreadable: the pick lasts this run only.
    }
  }

  static Future<String?> shape(String modelId) async {
    try {
      return (await SharedPreferences.getInstance()).getString(shapeKey(modelId));
    } catch (_) {
      return null;
    }
  }

  static Future<void> rememberShape(String modelId, String shape) async {
    try {
      await (await SharedPreferences.getInstance()).setString(shapeKey(modelId), shape);
    } catch (_) {
      // Only an optimisation.
    }
  }
}

/// The picked model among [models], or null when nothing usable is picked.
CloudSpeechModel? pickedCloudSpeechModel(
  List<CloudSpeechModel> models,
  String? id,
) {
  if (id == null || id.isEmpty) return null;
  for (final model in models) {
    if (model.id == id) return model;
  }
  return null;
}

/// What the composer asks for before recording: the picked model among the
/// providers this engine has, or null.
Future<CloudSpeechModel?> resolveCloudSpeechModelFrom(WidgetRef ref) async {
  final id = await CloudSpeechPrefs.selected();
  if (id == null || id.isEmpty) return null;
  final models = await ref.read(cloudSpeechModelsProvider.future);
  return pickedCloudSpeechModel(models, id);
}

/// A request the provider refused or could not answer. [message] is for the
/// diagnostics log; the composer shows its own sentence.
class CloudSpeechError implements Exception {
  const CloudSpeechError(this.message);

  final String message;

  @override
  String toString() => 'CloudSpeechError: $message';
}

/// Long enough for a slow provider, short enough that the mic does not look
/// stuck.
const cloudSpeechTimeout = Duration(seconds: 60);

/// Transcribes [wav] with [model]'s provider and returns the text (empty when
/// the provider heard nothing).
Future<String> transcribeCloudSpeech({
  required CloudSpeechModel model,
  required Uint8List wav,
  String? language,
  http.Client? transport,
}) async {
  final key = model.apiKey;
  if (key == null || key.isEmpty) {
    throw CloudSpeechError('${model.id}: no key on this phone');
  }
  final base = model.baseUrl.replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) throw CloudSpeechError('${model.id}: no base URL');
  final client = transport ?? http.Client();
  final remembered = await CloudSpeechPrefs.shape(model.id);
  final order = remembered == 'whisper' ? const ['whisper', 'chat'] : const ['chat', 'whisper'];
  final failures = <String>[];
  try {
    for (final shape in order) {
      try {
        final text = shape == 'chat'
            ? await _chatCompletions(client, base, key, model, wav, language)
            : await _transcriptions(client, base, key, model, wav, language);
        if (remembered != shape) unawaited(CloudSpeechPrefs.rememberShape(model.id, shape));
        return text;
      } on CloudSpeechError catch (error) {
        failures.add(error.message);
      }
    }
  } finally {
    if (transport == null) client.close();
  }
  throw CloudSpeechError(failures.join(' | '));
}

/// `POST {base}/chat/completions`: the audio as an `input_audio` part.
Future<String> _chatCompletions(
  http.Client client,
  String base,
  String key,
  CloudSpeechModel model,
  Uint8List wav,
  String? language,
) async {
  final body = jsonEncode({
    'model': model.modelId,
    'stream': false,
    'messages': [
      {
        'role': 'user',
        'content': [
          {
            'type': 'input_audio',
            'input_audio': {
              'data': 'data:audio/wav;base64,${base64Encode(wav)}',
              'format': 'wav',
            },
          },
        ],
      },
    ],
    // Xiaomi MiMo reads this; providers that do not know it ignore it.
    'asr_options': {'language': (language == null || language.isEmpty) ? 'auto' : language},
  });
  final response = await client
      .post(
        Uri.parse('$base/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
          'api-key': key,
        },
        body: body,
      )
      .timeout(cloudSpeechTimeout);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw CloudSpeechError('chat ${response.statusCode}: ${_excerpt(response.bodyBytes)}');
  }
  final text = _chatText(_decode(response.bodyBytes));
  if (text == null) {
    throw CloudSpeechError('chat: no text in ${_excerpt(response.bodyBytes)}');
  }
  return text.trim();
}

/// `POST {base}/audio/transcriptions`, multipart: the OpenAI Whisper shape.
Future<String> _transcriptions(
  http.Client client,
  String base,
  String key,
  CloudSpeechModel model,
  Uint8List wav,
  String? language,
) async {
  final request = http.MultipartRequest('POST', Uri.parse('$base/audio/transcriptions'))
    ..headers['Authorization'] = 'Bearer $key'
    ..headers['api-key'] = key
    ..fields['model'] = model.modelId
    ..fields['response_format'] = 'json';
  if (language != null && language.isNotEmpty) request.fields['language'] = language;
  request.files.add(http.MultipartFile.fromBytes('file', wav, filename: 'speech.wav'));
  final streamed = await client.send(request).timeout(cloudSpeechTimeout);
  final response = await http.Response.fromStream(streamed).timeout(cloudSpeechTimeout);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw CloudSpeechError('transcriptions ${response.statusCode}: ${_excerpt(response.bodyBytes)}');
  }
  final json = _decode(response.bodyBytes);
  if (json is Map) {
    final text = json['text'];
    if (text is String) return text.trim();
  }
  throw CloudSpeechError('transcriptions: no text in ${_excerpt(response.bodyBytes)}');
}

/// The assistant's words in a chat-completions answer, `content` being either a
/// string or a list of parts.
String? _chatText(Object? json) {
  if (json is! Map) return null;
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  if (first is! Map) return null;
  final message = first['message'];
  if (message is Map) {
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map && part['text'] is String) buffer.write(part['text'] as String);
      }
      return buffer.isEmpty ? null : buffer.toString();
    }
  }
  final text = first['text'];
  return text is String ? text : null;
}

Object? _decode(Uint8List bytes) {
  try {
    return jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } catch (_) {
    return null;
  }
}

/// The start of an answer, for the log: enough to see what the provider said,
/// never the whole body.
String _excerpt(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true).replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length > 200 ? '${text.substring(0, 200)}…' : text;
}
