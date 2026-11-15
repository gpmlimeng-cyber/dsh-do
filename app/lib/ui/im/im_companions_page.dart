// 轻松模式的「伙伴」：单列联系人列表（对标 Miffan 的 ImPartnersTab）。
//
// 每一行：头像（56，带状态点/未读点）+ 名字 + 一句话（角色）+ 右侧状态 + 发消息。
// 点行进资料卡；点「发消息」才进时间线。状态只做「正在忙 / 等你确认」两项，
// 数据来自 live.bots 与 questionOf/approvals，列表里不跑动画。
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../bots/bot_avatar.dart';
import '../bots/install_card.dart';
import '../bots/new_bot_page.dart';
import '../features/feature_widgets.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'im_bot_profile_page.dart';
import 'im_page_scaffold.dart';
import 'im_strings.dart';

class ImCompanionsPage extends ConsumerWidget {
  const ImCompanionsPage({super.key, required this.onOpenBot});

  /// 进时间线；点行本身则进资料卡。
  final ValueChanged<String> onOpenBot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dsBotProvider);
    final team = status.team;
    return ImPageScaffold(
      backdrop: false,
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
          : team.bots.isEmpty
          ? _Empty(onCreate: () => Navigator.of(context).push(NewBotPage.route()))
          : _CompanionList(team: team, live: status.live, inbox: ref.watch(dsBotInboxProvider), onOpenBot: onOpenBot),
    );
  }
}

/// 0 伙伴：给一个创建入口，而不是空白列表。
class _Empty extends StatelessWidget {
  const _Empty({this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Icon(AppIcons.pet, size: 44, color: colors.textTertiary),
        const SizedBox(height: 16),
        Text(
          ImStrings.emptyBotsTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          ImStrings.emptyBotsBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            icon: const Icon(AppIcons.add, size: 18),
            label: Text(ImStrings.emptyBotsCreate),
            onPressed: onCreate,
          ),
        ),
      ],
    );
  }
}

class _CompanionList extends StatelessWidget {
  const _CompanionList({required this.team, required this.live, required this.inbox, required this.onOpenBot});

  final DsBotTeam team;
  final DsBotLive live;
  final DsBotInbox inbox;
  final ValueChanged<String> onOpenBot;

  bool _waiting(DsBot bot) =>
      live.questionOf(bot) != null ||
      live.viewOf(bot) != null ||
      bot.waiting ||
      live.approvals.any((a) => a.botId == bot.id);

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: team.bots.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final bot = team.bots[i];
        return _CompanionRow(
          bot: bot,
          busy: live.bots[bot.id] != null,
          waiting: _waiting(bot),
          unread: inbox.unreadOf(bot.id),
          onOpenProfile: () => Navigator.of(context).push(ImBotProfilePage.route(bot.id)),
          onOpenChat: () => onOpenBot(bot.id),
        );
      },
    );
  }
}

class _CompanionRow extends StatelessWidget {
  const _CompanionRow({
    required this.bot,
    required this.busy,
    required this.waiting,
    required this.unread,
    required this.onOpenProfile,
    required this.onOpenChat,
  });

  final DsBot bot;
  final bool busy;
  final bool waiting;
  final int unread;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final role = bot.role.trim();
    final oneLiner = role.isEmpty ? ImStrings.memoryHint : role;
    final (statusText, statusColor) = waiting
        ? (ImStrings.companionWaiting, colors.warning)
        : busy
        ? (ImStrings.companionBusy, theme.colorScheme.primary)
        : (null, null);
    final dotTone = waiting
        ? colors.warning
        : busy
        ? theme.colorScheme.primary
        : null;
    return Semantics(
      button: true,
      label: [bot.name, oneLiner, if (statusText != null) statusText].join('，'),
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedSuperellipseBorder(borderRadius: AppShape.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpenProfile,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 56,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      BotAvatar(bot: bot, size: 56),
                      if (dotTone != null)
                        Positioned(
                          right: 1,
                          bottom: 1,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: dotTone,
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.colorScheme.surfaceContainerLow, width: 2),
                            ),
                          ),
                        ),
                      if (unread > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            constraints: const BoxConstraints(minWidth: 16),
                            decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bot.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        oneLiner,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ),
                ),
                if (statusText != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      statusText,
                      style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
                    ),
                  ),
                IconButton(
                  key: ValueKey('companion-message-${bot.id}'),
                  tooltip: ImStrings.profileSend,
                  onPressed: onOpenChat,
                  icon: Icon(AppIcons.chat, size: 20, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
