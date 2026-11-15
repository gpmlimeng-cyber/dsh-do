// Bot 聊天里的图片消息：宿主只给 `imageRefs`（图片 id），字节要按 id 去取。
//
// 契约（宿主 ds-bot 1.3.6，架构核对）：
// - `image(sessionId, attachmentId, preview:)` → `{mime, data(base64)}`；
//   `sessionId` 是会话（Bot 当前段或群），不是 botId。
// - `preview:true` 只给缩略（最长边 512 的 jpeg），小图原样回、不保证有 preview 字段。
// - 能力判断用 `hello.supports('images')` / `('image-preview')`，不按版本号。
// - 老宿主没有 `imageRefs`：气泡保持原来的「图片」占位（这里不渲染）。
//
// 缓存：进程内 LRU（按 boot + 会话 + 附件 + 预览/原图），64MB 或 200 条，并发 3，
// 同 key 去重；失败不自动重试，点一下再来（每次都是一次 500 条历史回扫）。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../chat/widgets/attachments.dart' show openAttachmentGallery;
import '../chat/widgets/image_gallery.dart' show ViewerImage;
import '../theme/app_icons.dart';
import '../theme/theme.dart';

/// One cached picture: which host, which conversation, which attachment, which
/// size. A new boot or another host is another key.
typedef BotImageKey = ({String boot, String sessionId, String attachmentId, bool preview});

final botImageProvider = FutureProvider.autoDispose.family<Uint8List, BotImageKey>((ref, key) async {
  final api = ref.watch(dsBotProvider.notifier).api;
  if (api == null) throw const DshTransportException('not connected');
  return BotImageCache.instance.load(
    key,
    () => api.image(key.sessionId, key.attachmentId, preview: key.preview),
  );
});

/// Process-wide LRU with a small concurrency window: one picture is a few MB
/// and the host walks 500 history entries per call, so a bubble wall must not
/// turn into a request storm.
class BotImageCache {
  BotImageCache._();

  static final instance = BotImageCache._();

  static const maxBytes = 64 * 1024 * 1024;
  static const maxEntries = 200;
  static const concurrency = 3;

  final _entries = <String, Uint8List>{};
  final _inflight = <String, Future<Uint8List>>{};
  String? _boot;
  final _waiters = <Completer<void>>[];
  int _totalBytes = 0;
  int _active = 0;

  static String keyOf(BotImageKey key) =>
      '${key.boot}|${key.sessionId}|${key.attachmentId}|${key.preview ? 'preview' : 'full'}';

  /// A new boot (another host or a restart) makes every id mean something
  /// else: drop what is held rather than show someone else's picture.
  void noteBoot(String boot) {
    if (_boot == null) {
      _boot = boot;
      return;
    }
    if (_boot == boot) return;
    _boot = boot;
    clear();
  }

  /// [fetch] answers the host's base64; the bytes are what stays cached.
  Future<Uint8List> load(BotImageKey key, Future<({String mime, String data})> Function() fetch) {
    noteBoot(key.boot);
    final id = keyOf(key);
    final hit = _entries.remove(id);
    if (hit != null) {
      // Re-insert: Map order is the recency order.
      _entries[id] = hit;
      return Future.value(hit);
    }
    final running = _inflight[id];
    if (running != null) return running;
    final future = _run(id, fetch);
    _inflight[id] = future;
    return future.whenComplete(() => _inflight.remove(id));
  }

  Future<Uint8List> _run(String id, Future<({String mime, String data})> Function() fetch) async {
    await _acquire();
    try {
      final answer = await fetch();
      final bytes = base64Decode(answer.data);
      _put(id, bytes);
      return bytes;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < concurrency) {
      _active++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // The slot goes straight to the next waiter: _active stays as it is.
      _waiters.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  void _put(String id, Uint8List bytes) {
    _totalBytes += bytes.length;
    _entries[id] = bytes;
    while (_entries.length > maxEntries || _totalBytes > maxBytes) {
      final oldest = _entries.keys.first;
      final gone = _entries.remove(oldest);
      if (gone == null) break;
      _totalBytes -= gone.length;
    }
  }

  /// Drops everything (a host switch: another boot's ids mean nothing here).
  void clear() {
    _entries.clear();
    _totalBytes = 0;
  }

  @visibleForTesting
  int get cachedBytes => _totalBytes;

  @visibleForTesting
  int get cachedCount => _entries.length;
}

/// The pictures of one message, as thumbnails. Tapping opens the gallery; a
/// failed thumbnail says so and asks again on tap.
class BotImageAttachments extends ConsumerWidget {
  const BotImageAttachments({super.key, required this.sessionId, required this.refs});

  final String sessionId;
  final List<DsBotImageRef> refs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (refs.isEmpty) return const SizedBox.shrink();
    final status = ref.watch(dsBotProvider);
    final boot = status.hello?.boot ?? '';
    final canPreview = status.supports('images') && status.supports('image-preview');
    final single = refs.length == 1;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < refs.length; i++)
          _BotImageTile(
            ref: refs[i],
            refs: refs,
            index: i,
            sessionId: sessionId,
            boot: boot,
            preview: canPreview,
            single: single,
          ),
      ],
    );
  }
}

class _BotImageTile extends ConsumerWidget {
  const _BotImageTile({
    required this.ref,
    required this.refs,
    required this.index,
    required this.sessionId,
    required this.boot,
    required this.preview,
    required this.single,
  });

  final DsBotImageRef ref;
  final List<DsBotImageRef> refs;
  final int index;
  final String sessionId;
  final String boot;
  final bool preview;
  final bool single;

  BotImageKey get _key => (boot: boot, sessionId: sessionId, attachmentId: ref.attachmentId, preview: preview);

  void _openGallery(BuildContext context, WidgetRef ref) {
    // The bubble may unmount while the viewer is open: read through the
    // container, never a disposed WidgetRef.
    final container = ProviderScope.containerOf(context, listen: false);
    List<ViewerImage> galleryFor(bool thumbnail) => [
      for (final other in refs)
        ViewerImage.lazy(
          name: other.name ?? '',
          heroTag: 'bot-img-$sessionId-${other.attachmentId}',
          load: () async => MemoryImage(
            await container.read(
              botImageProvider((boot: boot, sessionId: sessionId, attachmentId: other.attachmentId, preview: thumbnail)).future,
            ),
          ),
        ),
    ];
    openAttachmentGallery(context, galleryFor(false), initialPage: index);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final box = single ? const Size(160, 160) : const Size.square(88);
    if (!preview) {
      // 宿主没有 image-preview：不请求缩略（会拿原图），先占位，点开再取。
      return _BotImagePlaceholder(
        size: box,
        onTap: () => _openGallery(context, ref),
      );
    }
    final bytes = ref.watch(botImageProvider(_key));
    return switch (bytes) {
      AsyncData(:final value) => GestureDetector(
        onTap: () => _openGallery(context, ref),
        child: ClipRRect(
          borderRadius: AppShape.radiusMd,
          child: Image.memory(
            value,
            width: box.width,
            height: box.height,
            fit: BoxFit.cover,
            cacheWidth: 520,
            gaplessPlayback: true,
            errorBuilder: (context, _, _) => _BotImagePlaceholder(size: box, failed: true, onTap: () {}),
          ),
        ),
      ),
      AsyncError() => _BotImagePlaceholder(
        size: box,
        failed: true,
        onTap: () => ref.invalidate(botImageProvider(_key)),
      ),
      _ => _BotImagePlaceholder(size: box, onTap: () {}),
    };
  }
}

class _BotImagePlaceholder extends StatelessWidget {
  const _BotImagePlaceholder({required this.size, required this.onTap, this.failed = false});

  final Size size;
  final VoidCallback onTap;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      image: true,
      button: true,
      label: context.l10n.chatImage,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size.width,
          height: size.height,
          decoration: ShapeDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
            shape: AppShape.card,
          ),
          child: Center(
            child: Icon(
              failed ? AppIcons.imageBroken : AppIcons.image,
              size: 22,
              color: DshColors.of(context).textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
