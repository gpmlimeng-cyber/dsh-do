// The group chat's status line in the deck above the composer: who is running
// what, with the clock ticking beside it, in the same kind of pill the todo and
// goal bars use. It shows only while a member runs — an idle group keeps the
// header's own line (已说 N / 待批准 / 成员数), so the same words never appear
// twice on one screen.
//
// The header and this line read the same state; [roomStatusOf] works the words
// out once, so the two cannot say different things about the same round.

import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/run_pulse.dart';

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

/// The deck's status line: a dock slot that is zero high while nobody runs, and
/// rises into place while a member does — the same motion as the todo bar.
class RoomActivityStrip extends StatelessWidget {
  const RoomActivityStrip({super.key, required this.status, this.onTap});

  final RoomStatus status;

  /// A tap opens the group's own activity figures. Null leaves the line quiet —
  /// the header and the details page still carry them.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visible = status.activity != null || status.waiting;
    return DockSlot(
      key: const ValueKey('room-activity'),
      child: visible ? _RoomActivityBar(status: status, onTap: onTap) : null,
    );
  }
}

class _RoomActivityBar extends ConsumerStatefulWidget {
  const _RoomActivityBar({required this.status, this.onTap});

  final RoomStatus status;

  final VoidCallback? onTap;

  @override
  ConsumerState<_RoomActivityBar> createState() => _RoomActivityBarState();
}

class _RoomActivityBarState extends ConsumerState<_RoomActivityBar> {
  /// How long the step's figures stay up, as the single chat's strip does.
  static const statsFor = Duration(seconds: 4);

  Timer? _stats;

  @override
  void dispose() {
    _stats?.cancel();
    super.dispose();
  }

  void _showStats() {
    HapticFeedback.selectionClick();
    _stats?.cancel();
    _stats = Timer(statsFor, () {
      if (mounted) setState(() => _stats = null);
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final waiting = status.waiting;
    final bot = status.bot;
    final sessionId = status.sessionId;
    final pulse = sessionId == null ? null : ref.watch(runPulseProvider(sessionId));
    final ink = waiting ? DshColors.of(context).warning : null;
    final showStats = _stats != null && !waiting;

    final TextSpan line;
    if (waiting) {
      line = TextSpan(text: l10n.botsMemberNeedsApproval, style: DockText.title(context, color: ink));
    } else if (showStats) {
      final speed = pulse?.tokensPerSecond;
      line = TextSpan(
        text: speed == null ? l10n.botsWorking : '${speed.round()} tok/s',
        style: AppType.tabular(DockText.detail(context, color: colors.onSurface)),
      );
    } else {
      final target = status.work?.target;
      line = TextSpan(
        children: [
          TextSpan(
            text: bot == null ? l10n.botsGroupChat : bot.name,
            style: DockText.title(context, color: ink),
          ),
          TextSpan(
            text: '  ${workPhrase(status.work) ?? l10n.botsWorking}',
            style: DockText.detail(context, color: ink),
          ),
          if (target != null && target.isNotEmpty)
            TextSpan(
              text: '  $target',
              style: AppType.tabular(DockText.detail(context, color: DshColors.of(context).textTertiary)),
            ),
        ],
      );
    }

    return Semantics(
      liveRegion: true,
      label: status.activity ?? (waiting ? l10n.botsMemberNeedsApproval : ''),
      excludeSemantics: true,
      child: GlassSurface(
        tier: GlassTier.chrome,
        stadium: true,
        onTap: widget.onTap,
        onLongPress: waiting ? null : _showStats,
        child: DockRow(
          // The member doing it, as its face; the group itself has no face, and
          // a round with several members running stacks their faces instead of
          // summing them up as 「+N」.
          leading: _RoomActivityFaces(status: status, waiting: waiting, ink: ink),
          content: Text.rich(line, maxLines: 1, overflow: TextOverflow.ellipsis),
          accessory: showStats || waiting
              ? (showStats && status.since != null
                  ? LiveElapsed(
                      since: status.since,
                      builder: (context, elapsed) => elapsed == null
                          ? const SizedBox.shrink()
                          : Text(formatClock(elapsed), style: AppType.tabular(DockText.detail(context))),
                    )
                  : null)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // How far the round has got, as the header says it, so the
                    // line carries a number and not just a name.
                    if (status.spoken > 0 && status.members > 0) ...[
                      Text(
                        '${l10n.botsAlreadySpoke} ${status.spoken}/${status.members}',
                        style: AppType.tabular(DockText.detail(context)),
                      ),
                      const SizedBox(width: 6),
                    ] else if (status.others > 0) ...[
                      Text('+${status.others}', style: AppType.tabular(DockText.detail(context))),
                      const SizedBox(width: 6),
                    ],
                    LiveElapsed(
                      since: status.since,
                      builder: (context, elapsed) => elapsed == null
                          ? const SizedBox.shrink()
                          : Text(formatClock(elapsed), style: AppType.tabular(DockText.detail(context))),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The line's leading: the group's glyph, one member's face, or the faces of the
/// members running now, overlapping so the row stays one glyph wide plus a sliver.
class _RoomActivityFaces extends StatelessWidget {
  const _RoomActivityFaces({required this.status, required this.waiting, this.ink});

  final RoomStatus status;
  final bool waiting;
  final Color? ink;

  /// How much of each face the next one covers.
  static const _overlap = 6.0;

  @override
  Widget build(BuildContext context) {
    final bot = status.bot;
    final primary = Theme.of(context).colorScheme.primary;
    if (bot == null) {
      return DockGlyph.icon(AppIcons.groupChat, color: waiting ? (ink ?? primary) : primary);
    }
    final more = status.otherBots.take(2).toList();
    if (more.isEmpty) return BotAvatar(bot: bot, size: DockMetrics.glyph);
    final step = DockMetrics.glyph - _overlap;
    return SizedBox(
      width: DockMetrics.glyph + step * more.length,
      height: DockMetrics.glyph,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = more.length; i > 0; i--)
            Positioned(
              left: DockMetrics.glyph + step * (i - 1),
              child: BotAvatar(bot: more[i - 1], size: DockMetrics.glyph),
            ),
          Positioned(left: 0, child: BotAvatar(bot: bot, size: DockMetrics.glyph)),
        ],
      ),
    );
  }
}
