// 记忆全屏页: 按范围分节（自己 → 团队；群聊只有「群聊」），每节带容量，
// 节内按 topic 分组。数据一次取全，行按需构建。

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../common/list_page_row.dart';
import '../features/feature_kit.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_memory_common.dart';

/// One line of the page: a section header, a topic heading, or an entry.
sealed class _MemoryLine {
  const _MemoryLine();
}

class _SectionLine extends _MemoryLine {
  const _SectionLine(this.scope, {this.used, this.limit});
  final String scope;

  /// Characters used and the host's cap; null when the host sent no sizes.
  final int? used;
  final int? limit;
}

class _TopicLine extends _MemoryLine {
  const _TopicLine(this.topic);
  final String topic;
}

class _EntryLine extends _MemoryLine {
  const _EntryLine(this.entry);
  final DsBotMemoryEntry entry;
}

class BotMemoryPage extends ConsumerStatefulWidget {
  const BotMemoryPage({super.key, this.botId, this.roomId});

  final String? botId;
  final String? roomId;

  static Route<void> route({String? botId, String? roomId}) =>
      MaterialPageRoute<void>(builder: (_) => BotMemoryPage(botId: botId, roomId: roomId));

  @override
  ConsumerState<BotMemoryPage> createState() => _BotMemoryPageState();
}

class _BotMemoryPageState extends ConsumerState<BotMemoryPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(dsBotProvider);
    final key = (botId: widget.botId, roomId: widget.roomId);
    final memory = ref.watch(dsBotMemoryProvider(key));
    final writable = status.ready && status.readOnly == null;
    final canEdit = writable && status.supports('memory-edit');
    final canAct = writable && !memory.isLoading && !memory.hasError;
    final view = memory.value;
    final lines = view == null ? const <_MemoryLine>[] : _linesOf(view, room: widget.roomId != null);
    final entries = view?.entries.length ?? 0;
    return AppPage(
      title: l10n.botsMemory,
      subtitle: Text(l10n.botsMemoryCount(entries)),
      slivers: [
        if (memory.hasError)
          SliverToBoxAdapter(
            child: ListPageCard(
              children: [
                ListPageRow(
                  icon: AppIcons.error,
                  title: l10n.botsMemoryReadFailed,
                  onTap: () => ref.invalidate(dsBotMemoryProvider(key)),
                ),
              ],
            ),
          )
        else if (memory.isLoading && view == null)
          const SliverToBoxAdapter(child: QuietSpinner(padding: EdgeInsets.symmetric(vertical: 24)))
        else ...[
          if (view?.summary case final summary? when summary.trim().isNotEmpty)
            SliverToBoxAdapter(
              child: ListPageCard(
                title: l10n.botsSummary,
                children: [
                  ListPageRow(icon: AppIcons.summary, title: summary.trim(), titleMaxLines: 6, chevron: false),
                ],
              ),
            ),
          if (entries == 0)
            SliverToBoxAdapter(child: EmptyView(icon: AppIcons.bookmark, title: l10n.botsNoMemory)),
          SliverList.builder(
            itemCount: lines.length,
            itemBuilder: (context, index) => switch (lines[index]) {
              _SectionLine(:final scope, :final used, :final limit) => _SectionHeader(
                label: switch (scope) {
                  'team' => l10n.botsTeam,
                  'group' => l10n.botsGroupChat,
                  _ => l10n.botsSelf,
                },
                used: used,
                limit: limit,
              ),
              _TopicLine(:final topic) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 16, 2),
                child: Text(
                  topic,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              _EntryLine(:final entry) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: ListPageRow(
                  icon: memoryScopeIcon(entry.scope),
                  title: entry.text,
                  titleMaxLines: 4,
                  subtitle: memoryEntryDetail(entry),
                  chevron: false,
                  onTap: canAct
                      ? () => openMemoryEntry(
                          context,
                          ref,
                          botId: widget.botId,
                          roomId: widget.roomId,
                          entry: entry,
                          canEdit: canEdit,
                        )
                      : null,
                ),
              ),
            },
          ),
          if (canEdit)
            SliverToBoxAdapter(
              child: ListPageCard(
                children: [
                  ListPageRow(
                    icon: AppIcons.add,
                    title: l10n.botsAddMemory,
                    chevron: false,
                    onTap: canAct
                        ? () => addMemoryEntry(context, ref, botId: widget.botId, roomId: widget.roomId)
                        : null,
                  ),
                ],
              ),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// The page's lines: a Bot shows 自己 then 团队, a group only 群聊. Entries keep
/// the order the host sent and group by topic inside their section.
List<_MemoryLine> _linesOf(DsBotMemoryView view, {required bool room}) {
  final scopes = room ? const ['group'] : const ['own', 'team'];
  final out = <_MemoryLine>[];
  for (final scope in scopes) {
    out.add(
      _SectionLine(scope, used: view.sizes[scope], limit: view.limits['main']),
    );
    final topics = <String?, List<DsBotMemoryEntry>>{};
    for (final entry in view.entries) {
      if (entry.scope != scope) continue;
      topics.putIfAbsent(entry.topic, () => []).add(entry);
    }
    for (final group in topics.entries) {
      if (group.key case final topic? when topic.isNotEmpty) out.add(_TopicLine(topic));
      out.addAll([for (final entry in group.value) _EntryLine(entry)]);
    }
  }
  return out;
}

/// 「自己」 with 「1,234 / 4,000」 and a hairline bar under it; the numbers only,
/// no unit, and no bar before the host has said how much is used.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.used, this.limit});

  final String label;
  final int? used;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final numbers = used == null || limit == null
        ? null
        : '${NumberFormat.decimalPattern().format(used)} / ${NumberFormat.decimalPattern().format(limit)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
              if (numbers case final text?)
                Text(
                  text,
                  style: theme.textTheme.labelSmall?.copyWith(color: DshColors.of(context).textTertiary),
                ),
            ],
          ),
          if (used != null && limit != null && limit! > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (used! / limit!).clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
