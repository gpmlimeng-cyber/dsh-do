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
  const TurnUsageCard({super.key, required this.turns});

  /// Every turn of the conversation, oldest first; the ones without usage are
  /// skipped and only the newest [capacity] are drawn.
  final List<TurnTrace> turns;

  static const int capacity = 12;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final recent = [
      for (final trace in turns.reversed)
        if (!trace.usage.isEmpty) trace,
    ].take(capacity).toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    final peak = recent.fold<int>(0, (most, trace) => trace.usage.total > most ? trace.usage.total : most);
    return ListPageCard(
      title: l10n.hubSessionTurnUsage,
      // Same rhythm as the usage groups above (SheetGroup: 6 + 6).
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      children: [
        for (final trace in recent)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    l10n.hubSessionTurn(trace.turn),
                    style: AppType.tabular(theme.textTheme.bodySmall!.copyWith(color: dsh.textTertiary)),
                  ),
                ),
                Expanded(
                  child: TimelineBar(
                    start: Duration.zero,
                    duration: Duration(milliseconds: trace.usage.total),
                    total: Duration(milliseconds: peak <= 0 ? 1 : peak),
                    color: theme.colorScheme.primary.withValues(alpha: 0.75),
                    height: 6,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  child: Text(
                    formatTokens(trace.usage.total),
                    textAlign: TextAlign.right,
                    style: AppType.tabular(
                      theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    trace.usage.cacheHitRate == null
                        ? ''
                        : l10n.hubSessionCacheHit(formatPercent(trace.usage.cacheHitRate!)),
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
