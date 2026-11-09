// Attachments in a Bot's chat and in a group chat. The ＋ panel and the system
// pickers are the chat page's own; what differs here is where the bytes go:
// images ride inline in `send`, files are staged first and travel as receipts.
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/attachments.dart';
import '../chat/widgets/attachments.dart';
import '../chat/widgets/plus_panel.dart';

/// Opens the ＋ panel and returns what it picked; null when cancelled.
///
/// [files] false leaves 文件 out (DSH Remote stages no files). [sessionId]
/// is the conversation the panel's 本对话 card acts on: a Bot has one, a
/// group chat does not, and the card is left out without it. [limit] is the
/// room left in the tray, so the picker stops at the same nine the chat page
/// allows.
Future<List<DraftAttachment>?> pickBotAttachments(
  BuildContext context,
  WidgetRef ref, {
  bool files = true,
  int limit = maxAttachments,
  String? sessionId,
  String? roomId,
  Future<void> Function()? onGoal,
}) async {
  final choice = await showPlusPanel(context, files: files, sessionId: sessionId, roomId: roomId);
  if (choice is GoalChoice) {
    if (onGoal != null) await onGoal();
    return null;
  }
  if (choice is! AttachChoice) return null;
  // The panel was a page: the caller may be gone by the time it closes.
  if (!context.mounted) return null;
  final picker = ref.read(attachmentPickerProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final PickedAttachments picked;
  try {
    picked = switch (choice.source) {
      AttachSource.gallery => PickedAttachments(await picker.pickImages(limit: limit)),
      AttachSource.camera => PickedAttachments([?await picker.takePhoto()]),
      AttachSource.files => await picker.pickFiles(limit: limit),
    };
  } on PlatformException catch (error) {
    // A refused permission is the common case, and saying nothing looks broken.
    if (!context.mounted) return null;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          error.code.contains('denied') || error.code.contains('permission')
              ? context.l10n.chatAttachmentPermission
              : context.l10n.chatOpenAttachmentFailed,
        ),
      ),
    );
    return null;
  } catch (_) {
    if (!context.mounted) return null;
    messenger?.showSnackBar(SnackBar(content: Text(context.l10n.chatReadFailed)));
    return null;
  }
  if (picked.problem case final problem?) {
    messenger?.showSnackBar(SnackBar(content: Text(problem)));
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

/// The attachments a line carries, as the chat's own row of pictures and file
/// cards. Null when the host only counted them (nothing to fetch by) or the
/// conversation's Session is not known yet.
Widget? botLineAttachments(
  DsBotItem item,
  String? sessionId, {
  void Function(FileAttachment file)? onOpenFile,
}) {
  if (sessionId == null || item.files.isEmpty) return null;
  final images = [
    for (final file in item.files)
      if (file.isImage)
        ImageAttachment(
          attachmentId: file.id,
          mediaType: file.mediaType ?? 'image',
          name: file.name,
          bytes: file.bytes,
          width: file.width,
          height: file.height,
        ),
  ];
  final files = [
    for (final file in item.files)
      if (!file.isImage) FileAttachment(attachmentId: file.id, name: file.name),
  ];
  if (images.isEmpty && files.isEmpty) return null;
  // File cards label themselves from the file name: the host has no media type
  // for a file, so the extension is the only hint there is.
  return SentAttachments.echoed(sessionId: sessionId, images: images, files: files, onOpenFile: onOpenFile);
}
