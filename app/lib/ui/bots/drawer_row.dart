// The one row the sessions drawer shows for DS Bot, in place of the team's
// own Sessions (Bots' chats in all their parts, groups, members' hidden group
// Sessions), which the drawer leaves out (`dsBotOwnedSessionsProvider`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../common/status_dot.dart';
import '../theme/theme.dart';
import 'bots_page.dart';

/// 「DS Bot · 3 个 Bot」 on the drawer's 44dp row grid, a breathing dot while a
/// Bot works, the unread count otherwise; nothing on a host without DS Bot.
/// 认不到 DS Bot 的那一行：说清是「没有」还是「需要更新」，点它进 Bots 页。
class _HintRow extends StatelessWidget {
  const _HintRow({required this.label, required this.action, required this.onOpen});

  final String label;
  final String action;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey('dsbot-drawer-hint'),
        onTap: onOpen,
        customBorder: Squircle.border(AppShape.md),
        child: Ink(
          height: DsBotDrawerRow.height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              StatusDot(tone: StatusTone.warn, size: 6),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: dsh.warning),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                action,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DsBotDrawerRow extends ConsumerWidget {
  const DsBotDrawerRow({super.key, this.onOpen});

  /// Defaults to pushing the Bots home; the drawer passes its own (closing
  /// itself first).
  final VoidCallback? onOpen;

  static const height = 44.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final status = ref.watch(dsBotProvider);
    final team = status.team;
    if (!status.ready || team == null) {
      // 认不出 DS Bot 时不要静默：这台主机上 Bot 列表与群会话都读不到，用户只会
      // 看到「全是普通会话」，以为数据丢了。给一行明说的提示，点进去是 Bots 页
      // 的安装卡（那台主机缺插件、或版本太老握手不过）。
      final hint = switch (status.availability) {
        DsBotAvailability.missing => l10n.stateBotMissing,
        DsBotAvailability.outdated => l10n.botsUpdateRequired,
        _ => null,
      };
      if (hint == null) return const SizedBox.shrink();
      return _HintRow(
        label: hint,
        action: l10n.botsInstall,
        onOpen: onOpen ?? () => Navigator.of(context).push(BotsPage.route()),
      );
    }
    final unread = ref.watch(dsBotInboxProvider.select((inbox) => inbox.total));
    final working = status.live.bots.isNotEmpty;
    final theme = Theme.of(context);
    final shape = Squircle.border(AppShape.md);
    final count = l10n.botsBotCount(team.bots.length);
    final open = onOpen ?? () => Navigator.of(context).push(BotsPage.route());
    return Semantics(
      button: true,
      onTap: open,
      label: [
        'DS Bot',
        count,
        if (working) l10n.botsActivelyRunning,
        if (unread > 0) l10n.botsUnreadCount(unread),
      ].join(l10n.botsListSeparator),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('dsbot-drawer-row'),
          onTap: open,
          customBorder: shape,
          child: Ink(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'DS Bot'),
                        TextSpan(
                          text: ' · $count',
                          style: TextStyle(color: DshColors.of(context).textTertiary),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15,
                      height: 1.4,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const Spacer(),
                if (unread > 0) UnreadBadge(unread) else if (working) const StatusDot(tone: StatusTone.busy, size: 7),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
