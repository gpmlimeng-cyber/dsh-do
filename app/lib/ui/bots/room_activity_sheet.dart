import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../common/app_sheet.dart';
import '../common/list_page_row.dart';
import '../common/sheet_title_bar.dart';
import '../theme/theme.dart';
import 'bot_avatar.dart';

/// 用量 for the whole group: every member's turns, context and output speed.
///
/// The Host already keeps these per Session (`run-stats`), so this asks once per
/// member and adds them up — no new endpoint, no server change. A member whose
/// read fails simply shows no figures instead of failing the sheet.
Future<void> showRoomActivitySheet(
  BuildContext context, {
  required DsBotRoom room,
  required DsBotTeam team,
  required DsBotApi api,
}) => showAppSheet<void>(
  context,
  isScrollControlled: true,
  builder: (sheet) => SafeArea(
    top: false,
    child: _RoomActivity(room: room, team: team, api: api),
  ),
);

/// One member's figures, already picked apart the way the sheet shows them.
class _Activity {
  const _Activity({
    required this.turns,
    this.usedTokens,
    this.window,
    this.speed,
    required this.cacheRead,
    required this.inputTokens,
  });

  /// Whole turns this member ran in the group.
  final int turns;

  /// What the session carries now: `projectedTokens` (the next turn's read),
  /// else the measured `pressureTokens`, and the window it sits in.
  final int? usedTokens;
  final int? window;

  /// Output tokens per second: `decodeTokens / (decodeMs / 1000)`.
  final double? speed;

  /// Cache reads against every input token, for the group's hit rate.
  final int cacheRead;
  final int inputTokens;

  double? get contextShare {
    final used = usedTokens;
    final size = window;
    if (used == null || size == null || size <= 0) return null;
    return (used / size).clamp(0.0, 1.0);
  }

  static int? _int(Object? value) => switch (value) {
    final num n => n.round(),
    final String s => int.tryParse(s),
    _ => null,
  };

  static num? _num(Object? value) => switch (value) {
    final num n => n,
    final String s => num.tryParse(s),
    _ => null,
  };

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? {for (final entry in value.entries) '${entry.key}': entry.value} : const {};

  /// Null when the Host answered nothing useful for this member.
  static _Activity? fromJson(Map<String, Object?> json) {
    if (json.isEmpty) return null;
    final stats = _map(json['sessionStats']);
    final pressure = _map(json['contextPressure']);
    final usage = _map(json['tokenUsage']);
    if (stats.isEmpty && pressure.isEmpty && usage.isEmpty) return null;

    final decodeTokens = _num(stats['decodeTokens']);
    final decodeMs = _num(stats['decodeMs']);
    final speed = decodeTokens == null || decodeMs == null || decodeMs <= 0 ? null : decodeTokens / (decodeMs / 1000);

    final cacheRead = _int(usage['cacheReadTokens']) ?? 0;
    final uncached = _int(usage['uncachedInputTokens']) ?? 0;
    final cacheWrite = _int(usage['cacheWriteTokens']) ?? 0;

    return _Activity(
      turns: _int(stats['turns']) ?? 0,
      usedTokens: _int(pressure['projectedTokens']) ?? _int(pressure['pressureTokens']),
      window: _int(pressure['contextWindow']),
      speed: speed,
      cacheRead: cacheRead,
      inputTokens: cacheRead + uncached + cacheWrite,
    );
  }
}

class _RoomActivity extends StatefulWidget {
  const _RoomActivity({required this.room, required this.team, required this.api});

  final DsBotRoom room;
  final DsBotTeam team;
  final DsBotApi api;

  @override
  State<_RoomActivity> createState() => _RoomActivityState();
}

class _RoomActivityState extends State<_RoomActivity> {
  late final Future<List<(DsBot, _Activity?)>> _members = _load();

  Future<(DsBot, _Activity?)> _one(DsBot bot) async {
    try {
      return (bot, _Activity.fromJson(await widget.api.runStats(bot.id)));
    } catch (_) {
      // One member's figures are not worth the whole sheet.
      return (bot, null);
    }
  }

  Future<List<(DsBot, _Activity?)>> _load() async {
    final bots = [for (final id in widget.room.members) widget.team.bot(id)].whereType<DsBot>().toList();
    return Future.wait([for (final bot in bots) _one(bot)]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitleBar(l10n.botsUsage),
          Flexible(
            child: FutureBuilder<List<(DsBot, _Activity?)>>(
              future: _members,
              builder: (context, snapshot) {
                final rows = snapshot.data;
                if (rows == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  );
                }
                var totalTurns = 0;
                var cacheRead = 0;
                var inputTokens = 0;
                DsBot? fullest;
                double fullestShare = -1;
                for (final (bot, activity) in rows) {
                  if (activity == null) continue;
                  totalTurns += activity.turns;
                  cacheRead += activity.cacheRead;
                  inputTokens += activity.inputTokens;
                  final share = activity.contextShare;
                  if (share != null && share > fullestShare) {
                    fullest = bot;
                    fullestShare = share;
                  }
                }
                final hit = inputTokens == 0 ? null : cacheRead / inputTokens;
                return ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  children: [
                    for (final (bot, activity) in rows)
                      ListPageRow(
                        leading: BotAvatar(bot: bot, size: 32),
                        title: bot.name,
                        subtitle: _line(context, activity),
                        subtitleMaxLines: 2,
                        chevron: false,
                      ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        [
                          '${l10n.botsMembers} ${rows.length}',
                          // No ready-made 「N 轮」 string: the count stands on its
                          // own after the label the sheet already has.
                          '${l10n.activityUsageContext} $totalTurns',
                          if (hit != null) '${l10n.activityCacheHit} ${(hit * 100).round()}%',
                          if (fullest != null) '${fullest.name} ${(fullestShare * 100).round()}%',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// One member's line: context share, output speed, turns — whichever the Host
  /// answered. Empty when it answered none of them, so the row is just the name.
  String? _line(BuildContext context, _Activity? activity) {
    if (activity == null) return null;
    final l10n = context.l10n;
    final parts = <String>[];
    final share = activity.contextShare;
    if (share != null) parts.add('${l10n.activityUsageContext} ${(share * 100).round()}%');
    final speed = activity.speed;
    if (speed != null && speed > 0) parts.add('${speed.round()} tok/s');
    if (activity.turns > 0) parts.add('${activity.turns}×');
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
