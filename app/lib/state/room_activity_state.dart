// The group's member figures: what each member spent in this group, and the
// totals the group's details page and the composer's context ring share. One
// provider, so a ring and a page never read `run-stats` twice for the same
// state.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bots_state.dart';
import 'connection_state.dart';
import 'usage_state.dart' show SessionUsage;

/// One member's figures, as the group's summed cards show them.
class RoomMemberActivity {
  const RoomMemberActivity({
    required this.bot,
    this.turns = 0,
    this.pressureTokens,
    this.projectedTokens,
    this.window,
    this.speed,
    this.decodeMs = 0,
    this.cacheRead = 0,
    this.uncachedInput = 0,
    this.cacheWrite = 0,
    this.output = 0,
    this.llmMs = 0,
    this.toolMs = 0,
    this.inGroup = false,
  });

  final DsBot bot;
  final int turns;

  /// Tokens the member's last request occupied, and the estimate for the next
  /// one. The group's totals prefer the measured value, like the group Session.
  final int? pressureTokens;
  final int? projectedTokens;
  final int? window;

  /// Output tokens per second: `decodeTokens / (decodeMs / 1000)`.
  final double? speed;
  final num decodeMs;
  final int cacheRead;
  final int uncachedInput;
  final int cacheWrite;
  final int output;
  final int llmMs;
  final int toolMs;

  /// Whether the member has a Session *in this group* (`room.sessions`): only
  /// those add up into the group's totals. A member read from their own
  /// conversation keeps its figures on its row but stays out of the sum.
  final bool inGroup;

  int? get contextTokens {
    final used = projectedTokens ?? pressureTokens;
    // Zero is not a measurement: a request's prompt is never empty, so a 0 here
    // means the figure is missing. Keeping it would add a window with no use.
    return used == null || used <= 0 ? null : used;
  }

  double? get contextShare {
    final used = contextTokens;
    final size = window;
    if (used == null || size == null || size <= 0) return null;
    return (used / size).clamp(0.0, 1.0);
  }
}

/// Every member's figures, summed the way the group's pages state them.
class RoomMembersActivity {
  const RoomMembersActivity({required this.members});

  final List<RoomMemberActivity> members;

  int get turns => members.fold(0, (sum, m) => sum + m.turns);
  int get contextTokens => members.fold(0, (sum, m) => sum + (m.contextTokens ?? 0));
  int get cacheRead => members.fold(0, (sum, m) => sum + m.cacheRead);
  int get inputTokens => members.fold(0, (sum, m) => sum + m.cacheRead + m.uncachedInput + m.cacheWrite);
  num get decodeMs => members.fold<num>(0, (sum, m) => sum + m.decodeMs);

  /// The largest share of a member's own window: "who is closest to full".
  double? get maxContextShare {
    double? best;
    for (final member in members) {
      final share = member.contextShare;
      if (share != null && (best == null || share > best)) best = share;
    }
    return best;
  }

  RoomMemberActivity? get fullest {
    RoomMemberActivity? best;
    double? bestShare;
    for (final member in members) {
      final share = member.contextShare;
      if (share != null && (bestShare == null || share > bestShare)) {
        best = member;
        bestShare = share;
      }
    }
    return best;
  }

  /// Total output tokens over total decode time, so slow members weigh in.
  double? get speed {
    var tokens = 0.0;
    var ms = 0.0;
    for (final member in members) {
      final rate = member.speed;
      if (rate == null || rate <= 0) continue;
      tokens += rate * (member.decodeMs / 1000);
      ms += member.decodeMs.toDouble();
    }
    return ms <= 0 ? null : tokens / (ms / 1000);
  }

  double get cacheHit => inputTokens == 0 ? 0 : cacheRead / inputTokens;
}

/// The group's two top cards: its own Session plus every member's Session *in
/// this group*. A member without one counts as nothing — a private
/// conversation's spend is not the group's.
///
/// The window pair takes only Sessions that report both numbers: a missing
/// window would shrink the total and read as a fuller context than there is.
/// The system/tools/messages split is left out — `run-stats` does not return
/// it, so it stays hidden rather than borrowing the group Session's.
SessionUsage roomUsageTotal(SessionUsage group, RoomMembersActivity activity) {
  var uncachedInput = group.uncachedInput;
  var output = group.output;
  var cacheRead = group.cacheRead;
  var cacheWrite = group.cacheWrite;
  var turns = group.turns ?? 0;
  var llmMs = group.llmMs ?? 0;
  var toolMs = group.toolMs ?? 0;
  var used = 0;
  var window = 0;
  void addWindow(int? usedTokens, int? size) {
    // Only a measured pair adds a window: an unknown (or 0) use with a known
    // window would read as "empty" rather than "nobody knows", which is the
    // 0 %-while-idle bug the ring had.
    if (usedTokens == null || usedTokens <= 0 || size == null || size <= 0) return;
    used += usedTokens;
    window += size;
  }

  addWindow(group.pressureTokens ?? group.projectedTokens, group.contextWindow);
  for (final member in activity.members) {
    if (!member.inGroup) continue;
    uncachedInput += member.uncachedInput;
    output += member.output;
    cacheRead += member.cacheRead;
    cacheWrite += member.cacheWrite;
    turns += member.turns;
    llmMs += member.llmMs;
    toolMs += member.toolMs;
    addWindow(member.pressureTokens ?? member.projectedTokens, member.window);
  }
  return SessionUsage(
    uncachedInput: uncachedInput,
    output: output,
    cacheRead: cacheRead,
    cacheWrite: cacheWrite,
    pressureTokens: window > 0 ? used : null,
    contextWindow: window > 0 ? window : null,
    turns: turns,
    llmMs: llmMs,
    toolMs: toolMs,
  );
}

/// What the members' read depends on: the group and each member's Session in it.
/// Selecting on exactly these keeps the live feed — which changes on every
/// turn — from re-reading every member's `run-stats`.
typedef RoomActivityKey = ({bool present, String members, String sessions});

final roomActivityKeyProvider = Provider.autoDispose.family<RoomActivityKey, String>((ref, roomId) {
  return ref.watch(
    dsBotProvider.select((state) {
      final room = state.team?.room(roomId);
      return (
        present: room != null,
        members: room?.members.join(',') ?? '',
        sessions: [
          for (final id in room?.members ?? const <String>[]) '$id:${room?.sessions[id] ?? ''}',
        ].join(','),
      );
    }),
  );
});

/// Every member's figures, read once per [roomActivityKeyProvider] change. The
/// group's details page and the composer's context ring share this: a refresh
/// keeps the previous figures (`AsyncValue`), so numbers swap in place instead
/// of vanishing behind a spinner.
final roomMembersActivityProvider = FutureProvider.autoDispose.family<RoomMembersActivity, String>((
  ref,
  roomId,
) async {
  ref.watch(roomActivityKeyProvider(roomId));
  // The API belongs to the connection, not to the room.
  ref.watch(activeConnectionProvider);
  final state = ref.read(dsBotProvider);
  final team = state.team;
  final room = team?.room(roomId);
  if (team == null || room == null) return const RoomMembersActivity(members: []);
  return loadRoomMembersActivity(ref.read(dsBotProvider.notifier).api, room, team);
});

/// Reads every member's `run-stats`, one per member. A member the Host cannot
/// answer keeps a row with no figures; the page never fails as a whole.
Future<RoomMembersActivity> loadRoomMembersActivity(DsBotApi? api, DsBotRoom room, DsBotTeam team) async {
  final bots = [for (final id in room.members) team.bot(id)].whereType<DsBot>().toList();
  if (api == null) return RoomMembersActivity(members: [for (final bot in bots) RoomMemberActivity(bot: bot)]);
  final read = await Future.wait([
    for (final bot in bots)
      () async {
        final inGroup = room.sessions[bot.id];
        try {
          // A member's figures are the ones from their Session *in this group*
          // when the Host names it; the Bot's own Session is the fallback, and
          // `inGroup` keeps that fallback out of the group's totals.
          return _member(bot, await api.runStats(bot.id, sessionId: inGroup), inGroupSession: inGroup);
        } catch (_) {
          return RoomMemberActivity(bot: bot);
        }
      }(),
  ]);
  return RoomMembersActivity(members: read);
}

int? _int(Object? value) => switch (value) {
  final num n => n.round(),
  final String s => int.tryParse(s),
  _ => null,
};

num? _num(Object? value) => switch (value) {
  final num n => n,
  final String s => num.tryParse(s),
  _ => null,
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? {for (final entry in value.entries) '${entry.key}': entry.value} : const {};

RoomMemberActivity _member(DsBot bot, Map<String, Object?> json, {String? inGroupSession}) {
  final stats = _map(json['sessionStats']);
  final pressure = _map(json['contextPressure']);
  final usage = _map(json['tokenUsage']);
  final decodeTokens = _num(stats['decodeTokens']);
  final decodeMs = _num(stats['decodeMs']);
  final speed = decodeTokens == null || decodeMs == null || decodeMs <= 0 ? null : decodeTokens / (decodeMs / 1000);
  final cacheRead = _int(usage['cacheReadTokens']) ?? 0;
  final uncached = _int(usage['uncachedInputTokens']) ?? 0;
  final cacheWrite = _int(usage['cacheWriteTokens']) ?? 0;
  return RoomMemberActivity(
    bot: bot,
    turns: _int(stats['turns']) ?? 0,
    pressureTokens: _int(pressure['pressureTokens']),
    projectedTokens: _int(pressure['projectedTokens']),
    window: _int(pressure['contextWindow']),
    speed: speed,
    decodeMs: decodeMs ?? 0,
    cacheRead: cacheRead,
    uncachedInput: uncached,
    cacheWrite: cacheWrite,
    output: _int(usage['outputTokens']) ?? 0,
    llmMs: _int(stats['llmMs']) ?? 0,
    toolMs: _int(stats['toolMs']) ?? 0,
    inGroup: (inGroupSession ?? '').isNotEmpty,
  );
}
