// The group's own line, worked out once for the group header and the group
// usage page: who is speaking, how many members have said something, whether
// an approval is pending.
//
// The deck's activity line above the composer is the upstream one
// (ActivityStripSlot) now: it reads the running member's own Session in the
// group. The only thing only a group can say — who else is running — is
// RoomOthersStrip in bot_composer_deck.dart. Nothing here draws.

import 'package:dsh_client/dsh_client.dart';

import '../../l10n/l10n.dart';
import '../common/status_dot.dart' show StatusTone;
import 'bot_format.dart' show workPhrase;

/// The group's own line, worked out once for the header and the deck:
/// [label]/[tone] are the header's; [activity] is the deck's line (null while
/// nobody runs), with the member it belongs to and the step's start time for the
/// clock; [spoken] is how many members have said something this round.
typedef RoomStatus = ({
  String label,
  StatusTone tone,
  String? activity,
  DateTime? since,
  DsBot? bot,
  int spoken,
  bool waiting,
  DsBotWork? work,
  int others,
  /// The members running besides [bot], so the line can show their faces
  /// instead of a bare 「+N」.
  List<DsBot> otherBots,
  /// How many members the group has: 「已说 3/6」 needs the whole count.
  int members,
  String? sessionId,
});

/// The header's line and the deck's activity line, from the group's live state.
RoomStatus roomStatusOf({
  required L10n l10n,
  required DsBotTeam team,
  required DsBotRoom room,
  required DsBotLive live,
  required bool running,
  required String? speaking,
  required DsBotRoomProgress? progress,
  ({String label, StatusTone tone})? flash,
}) {
  final working = live.rooms[room.id] ?? const <DsBotWork>[];
  final approvals = [
    for (final approval in live.approvals)
      if (approval.roomId == room.id && approval.answerable) approval,
  ];
  // Whose turn it is: the chat's own speaker wins, then the first member the
  // Host marks as speaking.
  String? speakingWorkId;
  for (final work in working) {
    if (work.speaking) {
      speakingWorkId = work.botId;
      break;
    }
  }
  final speaker = team.bot(speaking ?? speakingWorkId);
  // The header states the moment, never the tool: who runs what and for how
  // long is the deck's line below, and saying it twice reads as two events.
  final waiting = approvals.isNotEmpty;
  final (String label, StatusTone tone) = switch (()) {
    _ when waiting => (l10n.botsMemberNeedsApproval, StatusTone.warn),
    _ when speaker != null || working.isNotEmpty || running => (l10n.botsDiscussing, StatusTone.busy),
    // A round just finished (or failed): said once, briefly, instead of the
    // member's own line in the flow. Never over a run or a pending approval.
    _ when flash != null => (flash.label, flash.tone),
    _ when room.paused => (l10n.commonPaused, StatusTone.warn),
    _ => (l10n.botsMemberCount(room.members.length), StatusTone.ok),
  };
  final spoken = [for (final id in progress?.spokenBy ?? const <String>[]) ?team.bot(id)?.name].length;
  // The deck's line: what is happening now, never an idle state. The main seat
  // is whoever speaks, else the member whose step started first; the rest fold
  // into 「+N」.
  DsBotWork? mainWork;
  DsBot? mainBot;
  if (speaker != null) {
    mainBot = speaker;
    final work = _workOf(working, speaker.id);
    mainWork = work;
  } else if (working.isNotEmpty) {
    // Whose step started first: the one that has been going longest.
    var first = working.first;
    for (final work in working) {
      final a = first.since ?? DateTime(9999);
      final b = work.since ?? DateTime(9999);
      if (b.isBefore(a)) first = work;
    }
    mainWork = first;
    mainBot = team.bot(first.botId);
  }
  final others = [for (final work in working) if (work.botId != mainWork?.botId) work].length;
  final (String? activity, DateTime? since) = switch (()) {
    _ when speaker != null => (l10n.botsNamedSpeaking(speaker.name), mainWork?.since),
    _ when working.isNotEmpty => (
      l10n.botsNamedActivity(mainBot?.name ?? 'Bot', workPhrase(mainWork) ?? l10n.botsWorking),
      mainWork?.since,
    ),
    _ when running => (l10n.botsDiscussing, null),
    _ => (null, null),
  };
  return (
    label: label,
    tone: tone,
    activity: activity,
    since: since,
    bot: mainBot,
    spoken: spoken,
    waiting: waiting,
    work: mainWork,
    others: others,
    otherBots: [
      for (final work in working)
        if (work.botId != mainWork?.botId)
          if (team.bot(work.botId) case final other?) other,
    ],
    members: room.members.length,
    sessionId: mainBot == null ? null : _memberSession(room, mainBot),
  );
}

/// The step of [botId], when the host names one.
DsBotWork? _workOf(List<DsBotWork> working, String botId) {
  for (final work in working) {
    if (work.botId == botId) return work;
  }
  return null;
}

/// The Session that holds a member's work here (its group Session, else its own).
String? _memberSession(DsBotRoom room, DsBot bot) {
  final inRoom = room.sessions[bot.id];
  return inRoom == null || inRoom.isEmpty ? bot.sessionId : inRoom;
}
