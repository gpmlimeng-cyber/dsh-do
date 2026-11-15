// The "每轮用量" card: one row per recent turn — the turn, a bar of the tokens
// it spent, the total and the cache hit rate. The conversation's context tab
// and a group's draw the same card, so they cannot drift apart.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../common/list_page_row.dart';
import '../theme/theme.dart';
import 'trajectory_sheet.dart' show TimelineBar;
import 'usage_sheet.dart' show formatPercent, formatTokens;

class TurnUsageCard extends StatelessWidget {
  const TurnUsageCard({super.key, required List<TurnTrace> turns})
    : entries = const [],
      turns = turns;

  /// Turns from more than one conversation (a group draws each member's). The
  /// label replaces 「第 N 轮」, because turn numbers restart per conversation.
  const TurnUsageCard.entries({super.key, required this.entries}) : turns = const [];

  /// Every turn of the conversation, oldest first; the ones without usage are
  /// skipped and only the newest [capacity] are drawn.
  final List<TurnTrace> turns;

  /// The same, each with the label its row shows instead of the turn number.
  final List<({String? label, TurnTrace trace})> entries;

  static const int capacity = 12;

  /// Oldest first, whichever way the rows were given.
  List<({String? label, TurnTrace trace})> get _rows => entries.isNotEmpty
      ? entries
      : [for (final trace in turns) (label: null, trace: trace)];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final recent = [
      for (final row in _rows.reversed)
        if (!row.trace.usage.isEmpty) row,
    ].take(capacity).toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    final peak = recent.fold<int>(0, (most, row) => row.trace.usage.total > most ? row.trace.usage.total : most);
    return ListPageCard(
      title: l10n.hubSessionTurnUsage,
      // Same rhythm as the usage groups above (SheetGroup: 6 + 6).
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      children: [
        for (final row in recent)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    row.label ?? l10n.hubSessionTurn(row.trace.turn),
                    style: AppType.tabular(theme.textTheme.bodySmall!.copyWith(color: dsh.textTertiary)),
                  ),
                ),
                Expanded(
                  child: TimelineBar(
                    start: Duration.zero,
                    duration: Duration(milliseconds: row.trace.usage.total),
                    total: Duration(milliseconds: peak <= 0 ? 1 : peak),
                    color: theme.colorScheme.primary.withValues(alpha: 0.75),
                    height: 6,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  child: Text(
                    formatTokens(row.trace.usage.total),
                    textAlign: TextAlign.right,
                    style: AppType.tabular(
                      theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    row.trace.usage.cacheHitRate == null
                        ? ''
                        : l10n.hubSessionCacheHit(formatPercent(row.trace.usage.cacheHitRate!)),
                    textAlign: TextAlign.right,
                    style: AppType.tabular(theme.textTheme.bodySmall!.copyWith(color: dsh.textTertiary)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
