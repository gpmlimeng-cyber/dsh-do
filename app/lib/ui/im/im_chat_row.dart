// 轻松模式「消息」里的一行：48 头像 + 名字 + 一行预览 + 时间/未读。
//
// 为什么另写一行而不是复用 `BotRow`：`BotRow` 是 `ListPageRow`（卡片里 52/64
// 高的设置行），IM 要的是 72 高、无卡片、可全宽分隔线的微信式行。
// 头像、未读徽标、状态文案的取值逻辑照抄 `bots_page.dart:147-257`，
// 不抽公共函数——那会动专业页面，约定是专业页面零改动。
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart' show DsBotInbox;
import '../bots/bot_avatar.dart';
import '../bots/bot_format.dart';
import '../theme/theme.dart';

class ImChatRow extends StatelessWidget {
  const ImChatRow({
    super.key,
    required this.bot,
    required this.team,
    required this.live,
    required this.inbox,
    required this.onTap,
  });

  final DsBot bot;
  final DsBotTeam team;
  final DsBotLive live;
  final DsBotInbox inbox;
  final VoidCallback onTap;

  static const height = 72.0;
  static const avatarSize = 48.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = DshColors.of(context);
    final work = live.bots[bot.id];
    final doing = workPhrase(work, activity: live.activity[bot.id]);
    final notice = inbox.latest[bot.id];
    final unread = inbox.unreadOf(bot.id);
    final question = team.questionOf(bot) != null || team.viewOf(bot) != null;
    final String preview;
    Color? previewColor;
    // M3：等你确认（琥珀）> 正在输入 > 已完成。专业首页是「工作中」优先，
    // 这里按需求反着来：Bot 一边干活一边等人回答时，要让人先看到「等你确认」。
    if (question) {
      preview = l10n.commonWaitingAnswer;
      previewColor = colors.warning;
    } else if (doing != null) {
      preview = doing;
      previewColor = colors.info;
    } else if (bot.waiting) {
      preview = l10n.botsChooseModelStart;
      previewColor = colors.warning;
    } else if (notice != null && notice.roomId == null && notice.text.isNotEmpty) {
      preview = notice.text;
    } else {
      preview = bot.role.isEmpty ? l10n.botsNoChats : bot.role;
    }
    return ImChatRowShell(
      avatar: BotAvatar(bot: bot, size: avatarSize, working: work != null),
      name: bot.name,
      preview: preview,
      previewColor: previewColor,
      time: notice?.time,
      unread: unread,
      semanticsLabel: [
        bot.name,
        if (team.isMain(bot.id)) l10n.botsMainBot,
        preview,
        if (unread > 0) l10n.botsUnreadCount(unread),
      ].join(l10n.botsListSeparator),
      onTap: onTap,
    );
  }
}

class ImRoomRow extends StatelessWidget {
  const ImRoomRow({
    super.key,
    required this.room,
    required this.team,
    required this.live,
    required this.inbox,
    required this.onTap,
  });

  final DsBotRoom room;
  final DsBotTeam team;
  final DsBotLive live;
  final DsBotInbox inbox;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = DshColors.of(context);
    final notice = inbox.latest[room.id];
    final unread = inbox.unreadOf(room.id);
    final working = live.rooms[room.id] ?? const <DsBotWork>[];
    final waiting = live.approvals.any((a) => a.roomId == room.id && a.answerable);
    final String preview;
    Color? previewColor;
    if (waiting) {
      preview = l10n.botsMemberNeedsApproval;
      previewColor = colors.warning;
    } else if (working.isNotEmpty) {
      final names = [for (final w in working) team.bot(w.botId)?.name ?? 'Bot'];
      preview = names.length == 1
          ? l10n.botsNamedWorking(names.first)
          : l10n.botsNamesWorking(names.take(2).join(l10n.botsNameSeparator));
      previewColor = colors.info;
    } else {
      final line = roomPreview(room, team);
      preview = line.isEmpty ? l10n.botsMemberCount(room.members.length) : line;
    }
    return ImChatRowShell(
      avatar: RoomAvatar(room: room, team: team, size: ImChatRow.avatarSize),
      name: room.name,
      preview: preview,
      previewColor: previewColor,
      time: notice?.time,
      unread: unread,
      semanticsLabel: [
        room.name,
        preview,
        if (unread > 0) l10n.botsUnreadCount(unread),
      ].join(l10n.botsListSeparator),
      onTap: onTap,
    );
  }
}

/// 一行的骨架：左头像、中间两行、右时间 + 未读。
class ImChatRowShell extends StatelessWidget {
  const ImChatRowShell({
    super.key,
    required this.avatar,
    required this.name,
    required this.preview,
    required this.onTap,
    required this.semanticsLabel,
    this.previewColor,
    this.time,
    this.unread = 0,
  });

  final Widget avatar;
  final String name;
  final String preview;
  final Color? previewColor;
  final DateTime? time;
  final int unread;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    return Semantics(
      button: true,
      onTap: onTap,
      label: semanticsLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: ImChatRow.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: previewColor ?? colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      shortTime(time),
                      style: theme.textTheme.labelSmall?.copyWith(color: colors.textTertiary),
                    ),
                    if (unread > 0) ...[const SizedBox(height: 6), ImUnreadBadge(unread)],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 未读数字：主色胶囊，一位数是圆的（与 `UnreadBadge` 同规格，这里不引列表页）。
class ImUnreadBadge extends StatelessWidget {
  const ImUnreadBadge(this.count, {super.key});

  final int count;

  static const height = 20.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: height, minHeight: height, maxHeight: height),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: scheme.primary, shape: const StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Center(
            widthFactor: 1,
            child: Text(
              count > 99 ? '99+' : '$count',
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onPrimary,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
