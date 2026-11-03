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
  required String sessionId,
  required FileAttachment file,
  String? botId,
  String? roomId,
}) async {
  final l10n = context.l10n;
  final id = file.attachmentId;
  if (id == null) return;
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
