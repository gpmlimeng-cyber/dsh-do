// 轻松模式的「伙伴」：我的 Bot 网格。点开先进行对话（资料卡在 P4 再接，
// 资料卡页面见 轻松模式-组件树.md §4）。
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../bots/bot_avatar.dart';
import '../bots/install_card.dart';
import '../features/feature_widgets.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'im_page_scaffold.dart';
import 'im_strings.dart';

class ImCompanionsPage extends ConsumerWidget {
  const ImCompanionsPage({super.key, required this.onOpenBot});

  final ValueChanged<String> onOpenBot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dsBotProvider);
    final team = status.team;
    return ImPageScaffold(
      title: ImStrings.companionsTitle,
      child: team == null
          ? ListView(
              padding: const EdgeInsets.only(top: 24),
              children: [
                switch (status.availability) {
                  DsBotAvailability.offline => const FeatureOffline(),
                  DsBotAvailability.missing || DsBotAvailability.outdated => DsBotInstallCard(status: status),
                  DsBotAvailability.failed => FeatureMessage(
                    icon: AppIcons.error,
                    title: context.l10n.botsTeamLoadFailed,
                    body: status.error,
                    action: (context.l10n.commonRetry, () => ref.read(dsBotProvider.notifier).retry()),
                  ),
                  _ => const SizedBox.shrink(),
                },
              ],
            )
          : _Grid(team: team, onOpenBot: onOpenBot),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.team, required this.onOpenBot});

  final DsBotTeam team;
  final ValueChanged<String> onOpenBot;

  static const _spacing = 12.0;
  static const _columns = 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - _spacing * (_columns - 1)) / _columns;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Wrap(
            spacing: _spacing,
            runSpacing: _spacing,
            children: [
              for (final bot in team.bots)
                SizedBox(
                  width: width,
                  child: _CompanionCard(bot: bot, onTap: () => onOpenBot(bot.id)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CompanionCard extends StatelessWidget {
  const _CompanionCard({required this.bot, required this.onTap});

  final DsBot bot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final role = bot.role.trim();
    return Semantics(
      button: true,
      label: role.isEmpty ? bot.name : '${bot.name}，$role',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppShape.radiusMd,
        onTap: onTap,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedSuperellipseBorder(borderRadius: AppShape.radiusMd),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BotAvatar(bot: bot, size: 56),
                const SizedBox(height: 12),
                Text(
                  bot.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  role.isEmpty ? ImStrings.memoryHint : role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
