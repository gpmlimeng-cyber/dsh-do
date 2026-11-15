// 轻松模式的「消息」：一条平铺的会话列表 + 顶部置顶瓦片（照 Miffan）。
//
// - 不分组：Bot 与群聊混在一起，按最近活跃排序，主 Bot 不再强制在前。
// - 置顶单独一块头像瓦片，不混在列表里：1 个居中大瓦片，2–3 个一行均分，
//   再多横向滚动；长按瓦片或行出「置顶/取消置顶」，状态存本机（im.pinned）。
// - 未读是 `DsBotInbox` 的内存计数：冷启动清零，别当持久未读用。
import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../bots/bot_avatar.dart';
import '../bots/install_card.dart';
import '../bots/mascot_mood.dart';
import '../bots/new_bot_page.dart';
import '../bots/new_room_sheet.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import '../features/feature_kit.dart' show QuietSpinner;
import '../features/feature_widgets.dart';
import '../shell/page_frame.dart' show GlassIconButton;
import '../shell/session_search_page.dart' show showSessionSearch;
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'im_chat_row.dart';
import 'im_page_scaffold.dart';
import 'im_pinned.dart';
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
      backdrop: false,
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

/// 一条会话：Bot 或群聊，混排时只需要 id、名字、时间和两个回调。
class _Entry {
  const _Entry.bot(DsBot this.bot, this.time) : room = null;
  const _Entry.room(DsBotRoom this.room, this.time) : bot = null;

  final DsBot? bot;
  final DsBotRoom? room;
  final DateTime? time;

  String get key => bot != null ? 'bot:${bot!.id}' : 'room:${room!.id}';
  String get name => bot?.name ?? room!.name;
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
    final pinnedIds = ref.watch(imPinnedProvider);
    final readOnly = status.readOnly != null;
    DateTime? latest(String id) => inbox.latest[id]?.time;
    // 排序时间：宿主给的 lastAt 最准，其次本次运行收到的通知，最后创建时间。
    DateTime? latestOf(List<DateTime?> values) {
      for (final value in values) {
        if (value != null) return value;
      }
      return null;
    }

    final entries = <_Entry>[
      for (final bot in team.bots) _Entry.bot(bot, latestOf([bot.lastAt, latest(bot.id), bot.createdAt])),
      for (final room in team.rooms) _Entry.room(room, latestOf([room.lastAt, latest(room.id), room.createdAt])),
    ]..sort((a, b) => (b.time ?? DateTime(0)).compareTo(a.time ?? DateTime(0)));
    if (entries.isEmpty) {
      return _Empty(
        onCreate: readOnly ? null : () => Navigator.of(context).push(NewBotPage.route()),
        onDiscover: onGoDiscover,
      );
    }
    final pinned = [for (final entry in entries) if (pinnedIds.contains(entry.key)) entry];
    final rest = [for (final entry in entries) if (!pinnedIds.contains(entry.key)) entry];
    void open(_Entry entry) {
      if (entry.bot case final bot?) {
        onOpenBot(bot.id);
      } else if (entry.room case final room?) {
        onOpenRoom(room.id);
      }
    }

    void longPress(_Entry entry) => unawaited(_pinSheet(context, ref, entry));

    Widget rowFor(_Entry entry) {
      final bot = entry.bot;
      if (bot != null) {
        final mood = mascotMoodOf(status: status, live: status.live, inbox: inbox, bot: bot, team: team);
        return ImChatRow(
          bot: bot,
          team: team,
          live: status.live,
          inbox: inbox,
          emotion: mood.emotion.id,
          onTap: () => open(entry),
          onLongPress: () => longPress(entry),
        );
      }
      final room = entry.room!;
      final mood = mascotRoomMoodOf(status: status, live: status.live, inbox: inbox, room: room);
      return ImRoomRow(
        room: room,
        team: team,
        live: status.live,
        inbox: inbox,
        emotion: mood.emotion.id,
        onTap: () => open(entry),
        onLongPress: () => longPress(entry),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(dsBotProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.only(top: 2, bottom: 24),
        children: [
          if (pinned.isNotEmpty)
            _PinnedArea(
              key: const Key('im-pinned-area'),
              entries: pinned,
              team: team,
              inbox: inbox,
              onOpen: open,
              onLongPress: longPress,
            ),
          if (pinned.isNotEmpty && rest.isNotEmpty) const SizedBox(height: 6),
          for (final entry in rest) rowFor(entry),
        ],
      ),
    );
  }

  Future<void> _pinSheet(BuildContext context, WidgetRef ref, _Entry entry) async {
    final pinned = ref.read(imPinnedProvider).contains(entry.key);
    final choice = await showAppSheet<String>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(entry.name),
            SheetGroup(
              children: [
                ListTile(
                  leading: Icon(pinned ? AppIcons.pinActive : AppIcons.pin),
                  title: Text(pinned ? ImStrings.unpin : ImStrings.pin),
                  onTap: () => Navigator.pop(sheet, 'pin'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice == 'pin') await ref.read(imPinnedProvider.notifier).toggle(entry.key);
  }
}

/// 顶部置顶瓦片：1 个居中大瓦片，2–3 个一行均分，再多横向滚动。
class _PinnedArea extends StatelessWidget {
  const _PinnedArea({
    super.key,
    required this.entries,
    required this.team,
    required this.inbox,
    required this.onOpen,
    required this.onLongPress,
  });

  final List<_Entry> entries;
  final DsBotTeam team;
  final DsBotInbox inbox;
  final ValueChanged<_Entry> onOpen;
  final ValueChanged<_Entry> onLongPress;

  // 尺寸照 Miffan：1 个居中大瓦片（96），2–3 个一行均分（76），4 个以上一行最多
  // 4 个、均分并换行（不横向滚动，用户要的是换行）。
  static const _columns = 4;
  static const _singleWidth = 220.0;
  static const _rowWidth = 112.0;

  Widget _tile(BuildContext context, _Entry entry, {required double width, required double avatar}) => SizedBox(
    width: width,
    child: _PinnedTile(
      key: ValueKey('im-pinned-tile-${entry.key}'),
      entry: entry,
      team: team,
      inbox: inbox,
      onTap: () => onOpen(entry),
      onLongPress: () => onLongPress(entry),
      avatarSize: avatar,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    if (entries.length == 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Center(child: _tile(context, entries.first, width: _singleWidth, avatar: 96)),
      );
    }
    if (entries.length <= 3) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [for (final entry in entries) _tile(context, entry, width: _rowWidth, avatar: 76)],
        ),
      );
    }
    // 4 个以上：自适应宽度、一行最多 4 个均分、溢出换行；每格固定大小（-1 留出
    // 浮点误差，免得第 4 个被折到下一行）。
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.maxWidth - 24) / _columns - 1;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            runSpacing: 4,
            children: [for (final entry in entries) _tile(context, entry, width: cell, avatar: 76)],
          ),
        );
      },
    );
  }
}

class _PinnedTile extends StatelessWidget {
  const _PinnedTile({
    super.key,
    required this.entry,
    required this.team,
    required this.inbox,
    required this.onTap,
    required this.onLongPress,
    required this.avatarSize,
  });

  final _Entry entry;
  final DsBotTeam team;
  final DsBotInbox inbox;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final bot = entry.bot;
    final room = entry.room;
    final unread = bot != null ? inbox.unreadOf(bot.id) : inbox.unreadOf(room!.id);
    final avatar = bot != null
        ? BotAvatar(bot: bot, size: avatarSize)
        : RoomAvatar(room: room!, team: team, size: avatarSize);
    return Semantics(
      button: true,
      label: entry.name,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppShape.radiusLg,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  avatar,
                  if (unread > 0)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: ImUnreadBadge(unread),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(fontSize: 12.5, color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 团队还读不出来时的几种状态：离线 / 中继 / 没装 / 装旧了 / 失败 / 加载中。
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
