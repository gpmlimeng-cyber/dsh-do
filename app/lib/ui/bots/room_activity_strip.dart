// The group chat's status line in the deck above the composer: who is running
// what, with the clock ticking beside it, in the same kind of pill the todo and
// goal bars use. It shows only while a member runs — an idle group keeps the
// header's own line (已说 N / 待批准 / 成员数), so the same words never appear
// twice on one screen.
//
// The header and this line read the same state; [roomStatusOf] works the words
// out once, so the two cannot say different things about the same round.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../chat/dock/dock_pill.dart';
import '../chat/run_info.dart' show formatClock;
import '../chat/widgets/live_clock.dart';
import '../common/status_dot.dart' show StatusTone;
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_avatar.dart';
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
    _ when room.paused => (l10n.commonPaused, StatusTone.warn),
    _ => (l10n.botsMemberCount(room.members.length), StatusTone.ok),
  };
  final spoken = [for (final id in progress?.spokenBy ?? const <String>[]) ?team.bot(id)?.name].length;
  // The deck's line: what is happening now, never an idle state.
  final (String? activity, DateTime? since, DsBot? bot) = switch (()) {
    _ when speaker != null => (l10n.botsNamedSpeaking(speaker.name), _since(working, speaker.id), speaker),
    _ when working.isNotEmpty => (
      l10n.botsNamedActivity(
        team.bot(working.first.botId)?.name ?? 'Bot',
        workPhrase(working.first) ?? l10n.botsWorking,
      ),
      working.first.since,
      team.bot(working.first.botId),
    ),
    _ when running => (l10n.botsDiscussing, null, null),
    _ => (null, null, null),
  };
  return (label: label, tone: tone, activity: activity, since: since, bot: bot, spoken: spoken, waiting: waiting);
}

DateTime? _since(List<DsBotWork> working, String botId) {
  for (final work in working) {
    if (work.botId == botId) return work.since;
  }
  return null;
}

/// The deck's status line: a dock slot that is zero high while nobody runs, and
/// rises into place while a member does — the same motion as the todo bar.
class RoomActivityStrip extends StatelessWidget {
  const RoomActivityStrip({super.key, required this.status});

  final RoomStatus status;

  @override
  Widget build(BuildContext context) {
    final activity = status.activity;
    return DockSlot(
      key: const ValueKey('room-activity'),
      child: activity == null ? null : _RoomActivityBar(status: status, text: activity),
    );
  }
}

class _RoomActivityBar extends StatelessWidget {
  const _RoomActivityBar({required this.status, required this.text});

  final RoomStatus status;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bot = status.bot;
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: GlassSurface(
        tier: GlassTier.chrome,
        stadium: true,
        child: DockRow(
          // The member doing it, as its face; the group itself has no face.
          leading: bot == null
              ? DockGlyph.icon(AppIcons.groupChat, color: theme.colorScheme.primary)
              : BotAvatar(bot: bot, size: DockMetrics.glyph),
          content: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: DockText.title(context)),
          accessory: LiveElapsed(
            since: status.since,
            builder: (context, elapsed) => elapsed == null
                ? const SizedBox.shrink()
                : Text(formatClock(elapsed), style: AppType.tabular(DockText.detail(context))),
          ),
        ),
      ),
    );
  }
}
