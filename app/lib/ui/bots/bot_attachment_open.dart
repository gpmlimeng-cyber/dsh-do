import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import 'bot_action_scope.dart';
import 'bot_file_text_body.dart';

/// Opens a file a Bot message attached: the Host's bounded text, in a sheet.
///
/// `file-text` answers only for files the Host can read as text (a long post's
/// file, a text attachment); anything else comes back `bot/unavailable`, and the
/// page says so rather than opening an empty sheet.
Future<void> openBotAttachmentFile(
  BuildContext context,
  WidgetRef ref, {
  required FileAttachment file,
  String? botId,
  String? roomId,
}) async {
  final l10n = context.l10n;
  // A zip or an APK read as text is a sheet of mojibake; say so instead.
  if (!_looksTextual(file.name)) {
    _say(context, l10n.chatAttachmentNoPreview);
    return;
  }
  final id = file.attachmentId;
  // A Host that sends neither id nor attachmentId names the file but gives the
  // phone no way to fetch it; saying so beats a tap that does nothing.
  if (id == null || id.isEmpty) {
    _say(context, l10n.chatOpenAttachmentFailed);
    return;
  }
  final api = BotActionScope(ref, botId: botId, roomId: roomId).api;
  if (api == null) {
    _say(context, l10n.commonNotConnected);
    return;
  }
  final DsBotFileText text;
  try {
    text = await api.readAttachmentText(DsBotAttachmentRef(id: id, name: file.name));
  } catch (_) {
    if (context.mounted) _say(context, l10n.commonFailed);
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FileTextSheet(name: file.name ?? '', value: text),
  );
}

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));

/// The file's text: the name on top, then [BotFileTextBody] — which says itself
/// when the Host only returned the first stretch.
class _FileTextSheet extends StatelessWidget {
  const _FileTextSheet({required this.name, required this.value});

  final String name;
  final DsBotFileText value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: BotFileTextBody(value: value),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text the sheet can show: the extensions a conversation actually carries.
const _textExtensions = {
  'txt', 'md', 'markdown', 'json', 'jsonl', 'log', 'csv', 'tsv', 'yaml', 'yml',
  'xml', 'html', 'htm', 'css', 'js', 'mjs', 'ts', 'tsx', 'dart', 'py', 'sh',
  'ini', 'toml', 'conf', 'diff', 'patch', 'sql', 'svg',
};

bool _looksTextual(String? name) {
  final lower = (name ?? '').toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0 || dot == lower.length - 1) return true; // no extension: let the host try
  return _textExtensions.contains(lower.substring(dot + 1));
}
