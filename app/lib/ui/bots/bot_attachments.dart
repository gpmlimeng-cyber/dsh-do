// Attachments in a Bot's chat and in a group chat. The ＋ panel and the system
// pickers are the chat page's own; what differs here is where the bytes go:
// images ride inline in `send`, files are staged first and travel as receipts.
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/attachments.dart';
import '../chat/widgets/plus_panel.dart';

/// Opens the ＋ panel and returns what it picked; null when cancelled.
///
/// [files] false leaves 文件 out (DSH Remote stages no files). No `sessionId`:
/// the panel's 本对话 (permissions, plan mode) belongs to a chat page, not to a
/// Bot's conversation or a group.
Future<List<DraftAttachment>?> pickBotAttachments(
  BuildContext context,
  WidgetRef ref, {
  bool files = true,
}) async {
  final choice = await showPlusPanel(context, files: files);
  if (choice is! AttachChoice) return null;
  final picker = ref.read(attachmentPickerProvider);
  final PickedAttachments picked;
  try {
    picked = switch (choice.source) {
      AttachSource.gallery => PickedAttachments(await picker.pickImages(limit: maxAttachments)),
      AttachSource.camera => PickedAttachments([?await picker.takePhoto()]),
      AttachSource.files => await picker.pickFiles(limit: maxAttachments),
    };
  } on PlatformException {
    return null;
  }
  if (picked.problem case final problem? when context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(problem)));
  }
  return picked.attachments;
}

/// Inline images and the receipts of the files staged in [sessionId].
///
/// Uploads one at a time on purpose: a failure says which file it was, and the
/// conversation keeps whatever arrived before it.
Future<({List<PromptImage> images, List<String> receipts})> stageBotAttachments(
  DshClient client,
  String sessionId,
  List<DraftAttachment> attachments,
) async {
  final images = <PromptImage>[];
  final receipts = <String>[];
  for (final attachment in attachments) {
    if (attachment.isImage) {
      images.add(PromptImage.fromBytes(attachment.bytes, mediaType: attachment.mediaType!, name: attachment.name));
    } else {
      final receipt = await client.uploadFile(sessionId, attachment.bytes, name: attachment.name);
      receipts.add(receipt.receiptId);
    }
  }
  return (images: images, receipts: receipts);
}
