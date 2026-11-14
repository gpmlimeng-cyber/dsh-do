// 轻松模式的「消息」：Bot 与群聊行式列表。
//
// 顺序与专业首页一致（`bots_page.dart:88-95`）：主 Bot 先，其余按最近活动，
// 群聊在后。未读是 `DsBotInbox` 的内存计数：冷启动清零，别当持久未读用。
import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../bots/install_card.dart';
import '../bots/new_bot_page.dart';
import '../bots/new_room_sheet.dart';
import '../common/app_sheet.dart';
import '../features/feature_kit.dart' show QuietSpinner;
import '../common/sheet_title_bar.dart';
import '../features/feature_widgets.dart';
import '../shell/page_frame.dart' show GlassIconButton;
import '../shell/session_search_page.dart' show showSessionSearch;
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'im_chat_row.dart';
import 'im_page_scaffold.dart';
import 'im_strings.dart';

class ImMessagesPage extends ConsumerWidget {
  const ImMessagesPage({
    super.key,
    required this.onOpenBot,
    required this.onOpenRoom,
    required this.onGoDiscover,
  });

  final ValueChanged<String> onOpenBot;
  final ValueChanged<String> onOpenRoom;
  final VoidCallback onGoDiscover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dsBotProvider);
    final team = status.team;
    return ImPageScaffold(
      title: ImStrings.messagesTitle,
      actions: [
        GlassIconButton(
          icon: AppIcons.search,
          tooltip: ImStrings.search,
          size: 40,
          iconSize: 20,
          grouped: false,
          onPressed: team == null ? null : () => _search(context, team),
        ),
        const SizedBox(width: 6),
        GlassIconButton(
          icon: AppIcons.add,
          tooltip: ImStrings.newBot,
          size: 40,
          iconSize: 20,
          grouped: false,
          onPressed: status.readOnly != null ? null : () => _compose(context),
        ),
      ],
      child: team == null
          ? _NotReady(status: status)
          : _List(status: status, team: team, onOpenBot: onOpenBot, onOpenRoom: onOpenRoom, onGoDiscover: onGoDiscover),
    );
  }

  Future<void> _search(BuildContext context, DsBotTeam team) async {
    final id = await showSessionSearch(context);
    if (id == null || !context.mounted) return;
    for (final bot in team.bots) {
      if (bot.id == id || bot.sessionId == id) {
        onOpenBot(bot.id);
        return;
      }
    }
    for (final room in team.rooms) {
      if (room.id == id || room.sessionId == id) {
        onOpenRoom(room.id);
        return;
      }
    }
    // 普通会话没有轻量页面可开：说清楚，别把人扔回专业界面。
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(ImStrings.notInLight)));
  }

  Future<void> _compose(BuildContext context) async {
    // 面板只负责选；选完再开对应的页面/sheet。
    final choice = await showAppSheet<String>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(ImStrings.newBot),
            SheetGroup(
              children: [
                ListTile(
                  leading: const Icon(AppIcons.bot),
                  title: Text(ImStrings.newBot),
                  onTap: () => Navigator.pop(sheet, 'bot'),
                ),
                ListTile(
                  leading: const Icon(AppIcons.newGroupChat),
                  title: Text(ImStrings.newRoom),
                  onTap: () => Navigator.pop(sheet, 'room'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'bot') {
      await Navigator.of(context).push(NewBotPage.route());
    } else {
      await showNewRoomSheet(context);
    }
  }
}

class _List extends ConsumerWidget {
  const _List({
    required this.status,
    required this.team,
    required this.onOpenBot,
    required this.onOpenRoom,
    required this.onGoDiscover,
  });

  final DsBotStatus status;
  final DsBotTeam team;
  final ValueChanged<String> onOpenBot;
  final ValueChanged<String> onOpenRoom;
  final VoidCallback onGoDiscover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(dsBotInboxProvider);
    final readOnly = status.readOnly != null;
    DateTime? latest(String id) => inbox.latest[id]?.time;
    int newest(DateTime? a, DateTime? b) => (b ?? DateTime(0)).compareTo(a ?? DateTime(0));
    final mains = <DsBot>[];
    for (final id in team.mainBotIds) {
      final bot = team.bot(id);
      if (bot != null) mains.add(bot);
    }
    final others = <DsBot>[
      for (final bot in team.bots)
        if (!team.isMain(bot.id)) bot,
    ]..sort((a, b) => newest(latest(a.id) ?? a.createdAt, latest(b.id) ?? b.createdAt));
    final rooms = [...team.rooms]..sort((a, b) => newest(latest(a.id) ?? a.createdAt, latest(b.id) ?? b.createdAt));
    if (team.bots.isEmpty && team.rooms.isEmpty) {
      return _Empty(onCreate: readOnly ? null : () => Navigator.of(context).push(NewBotPage.route()), onDiscover: onGoDiscover);
    }
    final children = <Widget>[];
    void group(String title, List<Widget> rows) {
      if (rows.isEmpty) return;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: DshColors.of(context).textTertiary),
        ),
      ));
      children.addAll(rows);
    }

    group(ImStrings.pinnedGroup, [
      for (final bot in mains)
        ImChatRow(bot: bot, team: team, live: status.live, inbox: inbox, onTap: () => onOpenBot(bot.id)),
    ]);
    group(ImStrings.chatsGroup, [
      for (final bot in others)
        ImChatRow(bot: bot, team: team, live: status.live, inbox: inbox, onTap: () => onOpenBot(bot.id)),
    ]);
    group(ImStrings.roomsGroup, [
      for (final room in rooms)
        ImRoomRow(room: room, team: team, live: status.live, inbox: inbox, onTap: () => onOpenRoom(room.id)),
    ]);
    return RefreshIndicator(
      onRefresh: () => ref.read(dsBotProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: children,
      ),
    );
  }
}

/// 团队还读不出来时的四种状态：离线 / 中继 / 没装 / 装旧了 / 失败 / 加载中。
class _NotReady extends ConsumerWidget {
  const _NotReady({required this.status});

  final DsBotStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.only(top: 24),
      children: [
        switch (status.availability) {
          DsBotAvailability.offline => const FeatureOffline(),
          DsBotAvailability.relay => FeatureMessage(
            icon: AppIcons.disconnected,
            title: l10n.botsRelayUnavailable,
            body: l10n.botsUseSsh,
          ),
          DsBotAvailability.missing || DsBotAvailability.outdated => DsBotInstallCard(status: status),
          DsBotAvailability.failed => FeatureMessage(
            icon: AppIcons.error,
            title: l10n.botsTeamLoadFailed,
            body: status.error,
            action: (l10n.commonRetry, () => ref.read(dsBotProvider.notifier).retry()),
          ),
          _ => const QuietSpinner(),
        },
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate, required this.onDiscover});

  final VoidCallback? onCreate;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.bot, size: 56, color: theme.colorScheme.onSurface.withValues(alpha: 0.35)),
            const SizedBox(height: 14),
            Text(ImStrings.emptyBotsTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              ImStrings.emptyBotsBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onCreate, child: Text(ImStrings.emptyBotsCreate)),
            const SizedBox(height: 6),
            TextButton(onPressed: onDiscover, child: Text(ImStrings.emptyBotsDiscover)),
          ],
        ),
      ),
    );
  }
}
