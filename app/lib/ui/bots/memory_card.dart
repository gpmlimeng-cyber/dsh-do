// A Bot's or a group's memory on its details page: the summary, the latest
// entries (tap to edit or remove), 「添加记忆」, and the way to the full page.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../../state/hosts_state.dart';
import '../common/list_page_row.dart';
import '../features/feature_kit.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_memory_common.dart';
import 'bot_memory_page.dart';

class BotMemoryCard extends ConsumerStatefulWidget {
  const BotMemoryCard({super.key, this.botId, this.roomId});

  final String? botId;
  final String? roomId;

  @override
  ConsumerState<BotMemoryCard> createState() => _BotMemoryCardState();
}

typedef _MemoryOwner = ({HostRef host, DsBotApi? api, String? boot, String? botId, String? roomId});

class _BotMemoryCardState extends ConsumerState<BotMemoryCard> {
  String? get botId => widget.botId;
  String? get roomId => widget.roomId;
  _MemoryOwner? _owner;
  DsBotMemoryView? _cached;
  ProviderSubscription<DsBotStatus>? _status;

  _MemoryOwner _ownerOf(DsBotStatus status) => (
    host: status.host,
    api: ref.read(dsBotProvider.notifier).api,
    boot: status.hello?.boot,
    botId: botId,
    roomId: roomId,
  );

  void _discardDifferentOwner(DsBotStatus status) {
    final owner = _ownerOf(status);
    if (!status.ready || _owner != owner) {
      _cached = null;
      _owner = status.ready ? owner : null;
    }
  }

  bool _canAct(_MemoryOwner owner) {
    if (!mounted) return false;
    final status = ref.read(dsBotProvider);
    final memory = ref.read(dsBotMemoryProvider(_key));
    return status.ready &&
        status.readOnly == null &&
        _ownerOf(status) == owner &&
        !memory.isLoading &&
        !memory.hasError;
  }

  @override
  void initState() {
    super.initState();
    // Clear immediately, including transitions that happen between two frames.
    _status = ref.listenManual(dsBotProvider, (_, next) => _discardDifferentOwner(next));
  }

  @override
  void dispose() {
    _status?.close();
    super.dispose();
  }

  ({String? botId, String? roomId}) get _key => (botId: botId, roomId: roomId);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(dsBotProvider);
    final memory = ref.watch(dsBotMemoryProvider(_key));
    final dsh = DshColors.of(context);
    final writable = status.ready && status.readOnly == null;
    final canEdit = writable && status.supports('memory-edit');
    _discardDifferentOwner(status);
    final owner = _ownerOf(status);
    if (status.ready && !memory.isLoading && !memory.hasError) _cached = memory.value;
    final view = status.ready ? _cached : null;
    final canAct = writable && !memory.isLoading && !memory.hasError;
    // Rows waiting on a refresh look disabled; on a read-only host they keep
    // full opacity, like the details page's other read-only rows.
    final rowOpacity = writable && !canAct ? 0.5 : 1.0;
    final updateLabel = memory.hasError
        ? l10n.readListFailed
        : memory.isLoading
        ? l10n.readListUpdating
        : null;
    final entries = view?.entries ?? const <DsBotMemoryEntry>[];
    // Entries come oldest first: the card takes the newest few, in that order.
    final shown = entries.length > memoryCardLimit
        ? entries.sublist(entries.length - memoryCardLimit)
        : entries;
    return ListPageCard(
      title: view == null
          ? l10n.botsMemory
          : '${l10n.botsMemoryCount(entries.length)}${updateLabel == null ? '' : ' · $updateLabel'}',
      children: [
        if (view == null && memory.isLoading)
          const QuietSpinner(padding: EdgeInsets.symmetric(vertical: 20))
        else if (view == null)
          ListPageRow(
            icon: AppIcons.error,
            title: l10n.botsMemoryReadFailed,
            onTap: () => ref.invalidate(dsBotMemoryProvider(_key)),
          )
        else ...[
          if (view.summary case final summary? when summary.trim().isNotEmpty)
            ListPageRow(icon: AppIcons.summary, title: l10n.botsSummary, subtitle: summary.trim(), subtitleMaxLines: 4),
          // The card is an overview: the newest entries, then the way to all.
          for (final entry in shown)
            Opacity(
              opacity: rowOpacity,
              child: ListPageRow(
                icon: memoryScopeIcon(entry.scope),
                title: entry.text,
                titleMaxLines: 3,
                subtitle: memoryEntryMeta(entry),
                chevron: false,
                onTap: canAct
                    ? () {
                        if (_canAct(owner)) {
                          openMemoryEntry(
                            context,
                            ref,
                            botId: botId,
                            roomId: roomId,
                            entry: entry,
                            canEdit: canEdit,
                          );
                        }
                      }
                    : null,
              ),
            ),
          if (entries.isEmpty) ListPageRow(icon: AppIcons.empty, iconColor: dsh.textTertiary, title: l10n.botsNoMemory),
          if (canEdit)
            Opacity(
              opacity: rowOpacity,
              child: ListPageRow(
                icon: AppIcons.add,
                title: l10n.botsAddMemory,
                chevron: false,
                onTap: canAct
                    ? () {
                        if (_canAct(owner)) addMemoryEntry(context, ref, botId: botId, roomId: roomId);
                      }
                    : null,
              ),
            ),
          if (entries.isNotEmpty)
            ListPageRow(
              icon: AppIcons.bookmark,
              title: l10n.botsMemoryCount(entries.length),
              onTap: () => Navigator.of(context).push(BotMemoryPage.route(botId: botId, roomId: roomId)),
            ),
          if (memory.hasError)
            ListPageRow(
              icon: AppIcons.error,
              title: l10n.botsMemoryReadFailed,
              onTap: () => ref.invalidate(dsBotMemoryProvider(_key)),
            ),
        ],
      ],
    );
  }
}
