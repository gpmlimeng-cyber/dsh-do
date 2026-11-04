import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../../state/usage_state.dart';
import '../common/list_page_row.dart';
import '../chat/usage_sheet.dart' show formatTokens;
import '../common/page_hero.dart';
import '../session/session_detail_page.dart' show ChangesTab, GlassSegments, ProgressTab, TrajectoryTab;
import '../session/session_tab.dart';
import '../session/workspace_files.dart' show WorkspaceFilesTab;
import '../shell/page_frame.dart';
import 'bot_action_scope.dart';
import 'bot_avatar.dart';

/// 对话详情 for a group.
///
/// The tabs are a single conversation's, because the group's own Session is one:
/// its trajectory shows every relay and every member's reply. What differs is the
/// numbers — context and usage add up each member's own figures (`run-stats` per
/// member), since the group Session never carries what a member spent. The group
/// Session itself is stated on the page so the totals are not read as the whole
/// story.
class RoomAggregateDetailsPage extends ConsumerStatefulWidget {
  const RoomAggregateDetailsPage({super.key, required this.roomId});

  final String roomId;

  static Route<void> route(String roomId) =>
      MaterialPageRoute<void>(builder: (_) => RoomAggregateDetailsPage(roomId: roomId));

  @override
  ConsumerState<RoomAggregateDetailsPage> createState() => _RoomAggregateDetailsPageState();
}

class _RoomAggregateDetailsPageState extends ConsumerState<RoomAggregateDetailsPage>
    with TickerProviderStateMixin {
  late final TabController _controller = TabController(length: 5, vsync: this);

  /// One read per room, not one per build: `run-stats` is a round trip per
  /// member, and the page rebuilds on every scroll and tab change.
  Future<RoomMembersActivity>? _activity;
  String? _activityKey;

  Future<RoomMembersActivity> _activityFor(DsBotApi? api, DsBotRoom room, DsBotTeam team) {
    final key = '${room.id}|${room.members.join(',')}|${api == null}';
    if (_activity == null || _activityKey != key) {
      _activityKey = key;
      _activity = loadRoomMembersActivity(api, room, team);
    }
    return _activity!;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(dsBotProvider);
    final team = status.team;
    final room = team?.room(widget.roomId);
    if (team == null || room == null) {
      return AppPage(
        title: l10n.botsGroupChat,
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: Text(l10n.botsRoomGone, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
        ],
      );
    }
    final api = BotActionScope(ref, roomId: room.id).api;
    final roomSession = room.sessionId;
    final activity = _activityFor(api, room, team);
    final labels = [
      SessionTab.trajectory.label,
      SessionTab.changes.label,
      SessionTab.files.label,
      SessionTab.progress.label,
      SessionTab.context.label,
    ];
    return AppPage(
      title: room.name,
      hero: PageHero(
        leading: RoomAvatar(room: room, team: team, size: 56),
        title: room.name,
        subtitle: Text(
          // 合计 = N 位成员 + 群会话, in the app's own words.
          '${l10n.botsMembers} ${room.members.length} + ${l10n.botsGroupChat}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: GlassSegments(controller: _controller, labels: labels),
          ),
        ),
        SliverFillRemaining(
          child: TabBarView(
            controller: _controller,
            children: [
              // The group's own conversation: relays, replies, tools and steps,
              // exactly as the single-conversation page draws them.
              if (roomSession != null) TrajectoryTab(sessionId: roomSession) else const _Empty(),
              if (roomSession != null) ChangesTab(sessionId: roomSession) else const _Empty(),
              _RoomFilesTab(room: room, team: team, roomSession: roomSession),
              if (roomSession != null) ProgressTab(sessionId: roomSession) else const _Empty(),
              _MemberContextTab(room: room, activity: activity, roomSession: roomSession),
            ],
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Text(
        context.l10n.commonNotSet,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

/// 文件 for a group.
///
/// A shared directory makes the group's own Session the right one to read, so the
/// single-conversation tab is used as is. Without one, the real files live in the
/// members' own directories: the strip switches the Session the tab reads, and
/// starts on the admin — the directory the group usually writes to.
class _RoomFilesTab extends StatefulWidget {
  const _RoomFilesTab({required this.room, required this.team, required this.roomSession});

  final DsBotRoom room;
  final DsBotTeam team;
  final String? roomSession;

  @override
  State<_RoomFilesTab> createState() => _RoomFilesTabState();
}

class _RoomFilesTabState extends State<_RoomFilesTab> {
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = _initial();
  }

  @override
  void didUpdateWidget(_RoomFilesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) _sessionId = _initial();
  }

  bool get _shared => (widget.room.workDir ?? '').isNotEmpty;

  /// A shared directory: the group's own Session. Otherwise the admin's, whose
  /// directory the group writes to by default.
  String? _initial() {
    if (_shared) return widget.roomSession;
    return widget.team.bot(widget.room.admin)?.sessionId ?? widget.roomSession;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sessionId = _sessionId;
    if (sessionId == null) return const _Empty();
    final browser = WorkspaceFilesTab(key: ValueKey('room-files-$sessionId'), sessionId: sessionId);
    if (_shared) return browser;
    final admin = widget.team.bot(widget.room.admin);
    final others = [
      for (final id in widget.room.members)
        if (id != admin?.id) widget.team.bot(id),
    ].whereType<DsBot>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: browser),
        // Which directory is on screen. Only without a shared directory: there is
        // nothing to choose between otherwise. Admin first, then the members,
        // then the group itself.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              if (admin != null) ...[
                _Chip(
                  key: const ValueKey('room-files-admin'),
                  label: admin.name,
                  avatar: BotAvatar(bot: admin, size: 20),
                  selected: sessionId == admin.sessionId,
                  onTap: () => setState(() => _sessionId = admin.sessionId),
                ),
                const SizedBox(width: 8),
              ],
              for (final bot in others) ...[
                _Chip(
                  key: ValueKey('room-files-${bot.id}'),
                  label: bot.name,
                  avatar: BotAvatar(bot: bot, size: 20),
                  selected: sessionId == bot.sessionId,
                  onTap: () => setState(() => _sessionId = bot.sessionId),
                ),
                const SizedBox(width: 8),
              ],
              _Chip(
                key: const ValueKey('room-files-group'),
                label: l10n.botsGroupChat,
                selected: sessionId == widget.roomSession,
                onTap: () => setState(() => _sessionId = widget.roomSession),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.selected, required this.onTap, this.avatar});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: selected ? colors.secondaryContainer : Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (avatar != null) ...[avatar!, const SizedBox(width: 6)],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? colors.onSecondaryContainer : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One member's figures, as the two summed tabs show them.
class RoomMemberActivity {
  const RoomMemberActivity({
    required this.bot,
    this.turns = 0,
    this.contextTokens,
    this.window,
    this.speed,
    this.decodeMs = 0,
    this.cacheRead = 0,
    this.inputTokens = 0,
  });

  final DsBot bot;
  final int turns;
  final int? contextTokens;
  final int? window;

  /// Output tokens per second: `decodeTokens / (decodeMs / 1000)`.
  final double? speed;
  final num decodeMs;
  final int cacheRead;
  final int inputTokens;

  double? get contextShare {
    final used = contextTokens;
    final size = window;
    if (used == null || size == null || size <= 0) return null;
    return (used / size).clamp(0.0, 1.0);
  }
}

/// Every member's figures, summed the way the page states them.
class RoomMembersActivity {
  const RoomMembersActivity({required this.members});

  final List<RoomMemberActivity> members;

  int get turns => members.fold(0, (sum, m) => sum + m.turns);
  int get contextTokens => members.fold(0, (sum, m) => sum + (m.contextTokens ?? 0));
  int get cacheRead => members.fold(0, (sum, m) => sum + m.cacheRead);
  int get inputTokens => members.fold(0, (sum, m) => sum + m.inputTokens);
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

/// Reads every member's `run-stats`, one per member. A member the Host cannot
/// answer keeps a row with no figures; the page never fails as a whole.
Future<RoomMembersActivity> loadRoomMembersActivity(DsBotApi? api, DsBotRoom room, DsBotTeam team) async {
  final bots = [for (final id in room.members) team.bot(id)].whereType<DsBot>().toList();
  if (api == null) return RoomMembersActivity(members: [for (final bot in bots) RoomMemberActivity(bot: bot)]);
  final read = await Future.wait([
    for (final bot in bots)
      () async {
        try {
          return _member(bot, await api.runStats(bot.id));
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

RoomMemberActivity _member(DsBot bot, Map<String, Object?> json) {
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
    // `projectedTokens` is what the next turn would carry; fall back to the
    // measured pressure when the Host only sends that.
    contextTokens: _int(pressure['projectedTokens']) ?? _int(pressure['pressureTokens']),
    window: _int(pressure['contextWindow']),
    speed: speed,
    decodeMs: decodeMs ?? 0,
    cacheRead: cacheRead,
    inputTokens: cacheRead + uncached + cacheWrite,
  );
}

class _MemberContextTab extends ConsumerWidget {
  const _MemberContextTab({required this.room, required this.activity, required this.roomSession});

  final DsBotRoom room;
  final Future<RoomMembersActivity> activity;
  final String? roomSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final group = roomSession == null ? null : ref.watch(sessionUsageProvider(roomSession!));
    final groupShare = group?.contextFraction;
    return FutureBuilder<RoomMembersActivity>(
      future: activity,
      builder: (context, snapshot) {
        final total = snapshot.data;
        if (total == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        final share = total.maxContextShare;
        final fullest = total.fullest;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                Text(
                  l10n.activityUsageContext,
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  share == null
                      ? '—'
                      : '${(share * 100).round()}% · ${formatTokens(total.contextTokens)}',
                  style: theme.textTheme.titleMedium,
                ),
                if (fullest != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    fullest.bot.name,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              // 合计 = N 位成员 + 群会话, as the page states it.
              '${l10n.botsMembers} ${total.members.length} + ${l10n.botsGroupChat}',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // The group's own Session: the relays' context, the one figure it has.
            if (groupShare != null)
              ListPageRow(
                key: const ValueKey('member-context-group'),
                icon: Icons.groups_outlined,
                title: l10n.botsGroupChat,
                subtitle: '${(groupShare * 100).round()}%',
                subtitleMaxLines: 1,
                chevron: false,
              ),
            for (final member in total.members)
              ListPageRow(
                key: ValueKey('member-context-${member.bot.id}'),
                leading: BotAvatar(bot: member.bot, size: 32),
                title: member.bot.name,
                subtitle: [
                  if (member.contextShare != null) '${(member.contextShare! * 100).round()}%',
                  if (member.contextTokens != null) formatTokens(member.contextTokens!),
                  if (member.turns > 0) '${member.turns}×',
                ].join(' · '),
                subtitleMaxLines: 1,
                chevron: false,
              ),
          ],
        );
      },
    );
  }
}
