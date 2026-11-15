// 把 App 的运行状态咬成吉祥物情绪（`state/mascot_emotion.dart` 的纯函数入口）。
//
// 状态来源与优先级都在 `emotionFor` 里，这里只做「字段从哪来」的收集：
// 连接态、在干什么、等不等人、有没有未读。列表里拿不到 per-bot 的错误，
// 所以 `error` 只有聊天页传得进来。
import 'package:dsh_client/dsh_client.dart';

import '../../state/bots_state.dart';
import '../../state/mascot_emotion.dart';

/// 连接态：ready 且 feed 连着才算 online。
MascotLink mascotLinkOf(DsBotStatus status) => switch (status.availability) {
  DsBotAvailability.offline || DsBotAvailability.relay => MascotLink.offline,
  DsBotAvailability.connecting => MascotLink.boot,
  DsBotAvailability.failed || DsBotAvailability.missing || DsBotAvailability.outdated => MascotLink.failed,
  DsBotAvailability.ready => status.feedConnected ? MascotLink.online : MascotLink.retrying,
};

/// 单聊行/聊天页用：这个 Bot 现在的情绪。
MascotMood mascotMoodOf({
  required DsBotStatus status,
  required DsBotLive live,
  required DsBotInbox inbox,
  required DsBot bot,
  required DsBotTeam team,
  bool? error,
  bool? paused,
  DateTime? settledAt,
  DateTime? now,
}) {
  final waiting = team.questionOf(bot) != null || team.viewOf(bot) != null || bot.waiting;
  return emotionFor(
    MascotMoment(
      link: mascotLinkOf(status),
      work: mascotWorkOf(live.bots[bot.id], activity: live.activity[bot.id]),
      waiting: waiting || live.approvals.any((a) => a.botId == bot.id),
      error: error ?? false,
      paused: paused ?? false,
      unread: inbox.unreadOf(bot.id) > 0,
      settledAt: settledAt,
    ),
    now: now,
  );
}

/// 群聊行用：群整体的等待/运行状态（具体成员的情绪在群页里各画各的）。
MascotMood mascotRoomMoodOf({
  required DsBotStatus status,
  required DsBotLive live,
  required DsBotInbox inbox,
  required DsBotRoom room,
  DateTime? now,
}) {
  final working = live.rooms[room.id] ?? const <DsBotWork>[];
  final waiting = live.approvals.any((a) => a.roomId == room.id && a.answerable);
  return emotionFor(
    MascotMoment(
      link: mascotLinkOf(status),
      work: working.isEmpty ? MascotWork.none : MascotWork.thinking,
      waiting: waiting,
      unread: inbox.unreadOf(room.id) > 0,
    ),
    now: now,
  );
}
