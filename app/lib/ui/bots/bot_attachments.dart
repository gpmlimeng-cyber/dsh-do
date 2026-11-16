// Attachments in a Bot's chat and in a group chat. The ＋ panel and the system
// pickers are the chat page's own; what differs here is where the bytes go:
// photos are staged first (`stage-image`) and named as ids in `send`, files are
// staged and travel as receipts.
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/attachments.dart';
import '../../state/bots_state.dart' show dsBotProvider;
import '../chat/widgets/attachments.dart';
import '../chat/widgets/plus_panel.dart';
import 'bot_image_attachments.dart';

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
  final choice = await showPlusPanel(context, files: files, sessionId: sessionId, goal: onGoal != null);
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

/// The staged ids of the photos and the receipts of the files in [sessionId].
///
/// The host's `send` takes ids, not bytes: each photo goes up first through
/// [DsBotApi.stageImage] and the message names it. One at a time on purpose: a
/// failure says which file it was, and the conversation keeps whatever arrived
/// before it.
Future<({List<String> images, List<String> receipts})> stageBotAttachments(
  DshClient client,
  String sessionId,
  List<DraftAttachment> attachments, {
  required DsBotApi api,
}) async {
  final images = <String>[];
  final receipts = <String>[];
  for (final attachment in attachments) {
    if (attachment.isImage) {
      images.add(await api.stageImage(attachment.mediaType!, base64Encode(attachment.bytes)));
    } else {
      final receipt = await client.uploadFile(sessionId, attachment.bytes, name: attachment.name);
      receipts.add(receipt.receiptId);
    }
  }
  return (images: images, receipts: receipts);
}

/// A line's pictures (ids the host sent) and its file cards, in that order.
///
/// Pictures need the host's `images` capability: an older host sends only a
/// count, and the bubble keeps its 「图片」 placeholder. `image-preview` decides
/// whether a thumbnail is asked for at all (without it the bytes are the full
/// picture, so the tile waits for a tap).
Widget? botItemAttachments(
  BuildContext context,
  WidgetRef ref,
  DsBotItem item,
  String? sessionId, {
  void Function(FileAttachment file)? onOpenFile,
}) {
  final canImages = ref.watch(dsBotProvider.select((status) => status.supports('images')));
  final images = sessionId == null || item.imageRefs.isEmpty || !canImages
      ? null
      : BotImageAttachments(sessionId: sessionId, refs: item.imageRefs);
  final files = botFileCards(item, onOpenFile: onOpenFile);
  if (images == null) return files;
  if (files == null) return images;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [images, const SizedBox(height: 4), files],
  );
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
  final cards = botFileCards(item, onOpenFile: onOpenFile);
  // 图片仍交给聊天自己的组件；文件卡在本地画，因为上游的 SentAttachments
  // 这一版不再渲染文件，也不收 onOpenFile。
  final parts = <Widget>[
    if (images.isNotEmpty) SentAttachments.echoed(sessionId: sessionId, images: images, files: const []),
    ?cards,
  ];
  if (parts.isEmpty) return null;
  return parts.length == 1 ? parts.first : Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [for (final (i, part) in parts.indexed) ...[if (i > 0) const SizedBox(height: 4), part]],
  );
}

/// 一条消息里的文件卡：点一下由调用方打开。
Widget? botFileCards(DsBotItem item, {void Function(FileAttachment file)? onOpenFile}) {
  final files = [
    for (final file in item.files)
      if (!file.isImage) FileAttachment(attachmentId: file.id, name: file.name, bytes: file.bytes),
  ];
  if (files.isEmpty) return null;
  return Wrap(
    alignment: WrapAlignment.end,
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final file in files)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpenFile == null ? null : () => onOpenFile(file),
          child: FileCard(name: file.name ?? '', bytes: file.bytes),
        ),
    ],
  );
}
