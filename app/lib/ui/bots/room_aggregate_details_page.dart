import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../../state/chat_state.dart';
import '../../state/session_detail_state.dart';
import '../../state/usage_state.dart';
import '../common/list_page_row.dart';
import '../chat/diff_page.dart' show ChangeDiffPage;
import '../chat/turn_summary.dart' show FileChange, fileChangesOf;
import '../chat/turn_usage.dart' show TurnUsageCard;
import '../chat/usage_sheet.dart' show SessionUsageSections, formatTokens;
import '../chat/widgets/change_card.dart' show DiffCounts;
import '../common/page_hero.dart';
import '../chat/widgets/activity_strip.dart' show TodoProgress;
import '../session/session_detail_page.dart' show GlassSegments, TrajectoryTab;
import '../session/session_tab.dart';
import '../session/workspace_files.dart' show WorkspaceFilesTab;
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/semantic_colors.dart' show DshColors;
import 'bot_action_scope.dart';
import 'bot_format.dart' show workPhrase;
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
    // The group's Sessions join the key: a member's first word here adds one, and
    // the totals must switch from their own chat to it without reopening the page.
    final sessions = [for (final id in room.members) '${id}:${room.sessions[id] ?? ''}'].join(',');
    final key = '${room.id}|${room.members.join(',')}|$sessions|$api';
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
      // The tab bar says what the page is; the hero below keeps the group's
      // name, so the group is still what the page is about.
      title: l10n.hubSessionDetails,
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
              _RoomTrajectoryTab(room: room, team: team, roomSession: roomSession),
              _RoomChangesTab(room: room, team: team, roomSession: roomSession),
              _RoomFilesTab(room: room, team: team, roomSession: roomSession),
              _RoomProgressTab(room: room, team: team, roomSession: roomSession),
              _RoomContextTab(room: room, activity: activity, roomSession: roomSession),
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

/// 轨迹 for a group: one trajectory, chosen from the group Session or a member.
///
/// The group Session shows every relay, but not what each member did inside
/// their own Session, so the chips above the list switch which Session the
/// single-conversation trajectory reads: the group first, then the members in
/// the order the group states them. A member who has not spoken here yet falls
/// back to their own conversation (see [memberSessionFor]) — its turns are then
/// shown, and nothing says they happened in this group.
class _RoomTrajectoryTab extends ConsumerStatefulWidget {
  const _RoomTrajectoryTab({required this.room, required this.team, required this.roomSession});

  final DsBotRoom room;
  final DsBotTeam team;
  final String? roomSession;

  @override
  State<_RoomTrajectoryTab> createState() => _RoomTrajectoryTabState();
}

class _RoomTrajectoryTabState extends ConsumerState<_RoomTrajectoryTab> {
  /// The member whose Session is on screen; null is the group's own. Kept as an
  /// id, not as a Session: the group's runs in another Session after a part
  /// change, and the page follows it without being reopened.
  String? _memberId;

  @override
  void didUpdateWidget(_RoomTrajectoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another group: back to its own Session.
    if (oldWidget.room.id != widget.room.id) {
      _memberId = null;
      return;
    }
    // The member was removed from the group: fall back to the group's Session.
    if (_memberId case final id? when !widget.room.members.contains(id)) _memberId = null;
  }

  /// The Session the chips point at: the group's own, or a member's for this
  /// group. Null means there is nothing to read — a group without a Session of
  /// its own, or a member the team no longer has.
  String? _sessionFor(DsBotRoom room) {
    if (_memberId case final id?) {
      final bot = widget.team.bot(id);
      return bot == null ? null : memberSessionFor(room, bot);
    }
    return widget.roomSession;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final room = widget.room;
    // Members are filtered like the files tab does it: an id that no longer
    // resolves to a Bot is skipped rather than drawn as a nameless chip.
    final members = [
      for (final id in room.members) widget.team.bot(id),
    ].whereType<DsBot>().toList();
    final sessionId = _sessionFor(room);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              _Chip(
                key: const ValueKey('room-trajectory-group'),
                label: l10n.botsGroupChat,
                selected: _memberId == null,
                onTap: () => setState(() => _memberId = null),
              ),
              for (final member in members) ...[
                const SizedBox(width: 8),
                _Chip(
                  key: ValueKey('room-trajectory-${member.id}'),
                  label: member.name,
                  avatar: BotAvatar(bot: member, size: 20),
                  selected: _memberId == member.id,
                  onTap: () => setState(() => _memberId = member.id),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: sessionId == null
              ? const _Empty()
              : TrajectoryTab(key: ValueKey('room-trajectory-session-$sessionId'), sessionId: sessionId),
        ),
      ],
    );
  }
}

/// 改动 for a group.
///
/// A group's own Session barely changes files: the work happens in each member's
/// Session for this group. So every member's tool calls are read where they
/// happened and shown as one block per member — the same path twice stays two
/// rows, because "who changed it" is the point here.
class _RoomChangesTab extends ConsumerWidget {
  const _RoomChangesTab({required this.room, required this.team, required this.roomSession});

  final DsBotRoom room;
  final DsBotTeam team;
  final String? roomSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    // The group's own Session first, then each member's Session for this group;
    // one Session is read once even if two rows name it.
    final sessions = <String, DsBot?>{};
    if (roomSession != null && roomSession!.isNotEmpty) sessions[roomSession!] = null;
    for (final id in room.members) {
      final bot = team.bot(id);
      if (bot == null) continue;
      final sessionId = memberSessionFor(room, bot);
      if (sessionId != null && sessionId.isNotEmpty) sessions[sessionId] = bot;
    }
    final blocks = <(DsBot?, List<FileChange>)>[];
    for (final entry in sessions.entries) {
      final items = ref.watch(chatProvider(entry.key).select((s) => s.items));
      final files = fileChangesOf(items.whereType<ToolChatItem>());
      if (files.isNotEmpty) blocks.add((entry.value, files));
    }
    if (blocks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            l10n.hubSessionNoChanges,
            style: theme.textTheme.bodyMedium?.copyWith(color: dsh.textTertiary),
          ),
        ),
      );
    }
    final total = blocks.fold<int>(0, (sum, block) => sum + block.$2.length);
    final added = blocks.fold<int>(0, (sum, block) => sum + block.$2.fold<int>(0, (s, f) => s + f.added));
    final removed = blocks.fold<int>(0, (sum, block) => sum + block.$2.fold<int>(0, (s, f) => s + f.removed));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              Text(
                l10n.hubSessionFileCount(total),
                style: theme.textTheme.labelLarge?.copyWith(color: dsh.textTertiary),
              ),
              const Spacer(),
              DiffCounts(added: added, removed: removed),
            ],
          ),
        ),
        for (final (bot, files) in blocks) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                if (bot != null) ...[BotAvatar(bot: bot, size: 20), const SizedBox(width: 8)],
                Text(
                  bot?.name ?? l10n.botsGroupChat,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.hubSessionFileCount(files.length),
                  style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary),
                ),
                const Spacer(),
                DiffCounts(
                  added: files.fold<int>(0, (s, f) => s + f.added),
                  removed: files.fold<int>(0, (s, f) => s + f.removed),
                ),
              ],
            ),
          ),
          ListPageCard(
            children: [
              for (final (i, file) in files.indexed)
                ListPageRow(
                  icon: file.created ? Icons.note_add_outlined : Icons.description_outlined,
                  title: file.fileName,
                  subtitle: [
                    if (file.directory.isNotEmpty) file.directory,
                    if (file.edits > 1) l10n.hubSessionEditCount(file.edits),
                  ].join(' · '),
                  trailing: DiffCounts(added: file.added, removed: file.removed),
                  chevron: true,
                  onTap: () => Navigator.of(context).push(
                    ChangeDiffPage.route(files, initialIndex: i, title: l10n.hubSessionChanges),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
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
    final admin = widget.team.bot(widget.room.admin);
    if (admin == null) return widget.roomSession;
    return memberSessionFor(widget.room, admin) ?? widget.roomSession;
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
                  selected: sessionId == memberSessionFor(widget.room, admin),
                  onTap: () => setState(() => _sessionId = memberSessionFor(widget.room, admin)),
                ),
                const SizedBox(width: 8),
              ],
              for (final bot in others) ...[
                _Chip(
                  key: ValueKey('room-files-${bot.id}'),
                  label: bot.name,
                  avatar: BotAvatar(bot: bot, size: 20),
                  selected: sessionId == memberSessionFor(widget.room, bot),
                  onTap: () => setState(() => _sessionId = memberSessionFor(widget.room, bot)),
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

/// The Session that holds a member's work in this group: `room.sessions` when the
/// Host sends it (plugin 0.2.7+), the Bot's own Session otherwise — an older Host
/// has no group Session to name, and a member who has not spoken here yet has none.
String? memberSessionFor(DsBotRoom room, DsBot bot) {
  final inRoom = room.sessions[bot.id];
  return inRoom == null || inRoom.isEmpty ? bot.sessionId : inRoom;
}

/// One member's figures, as the two summed tabs show them.
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

  int? get contextTokens => projectedTokens ?? pressureTokens;

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
    if (usedTokens == null || size == null || size <= 0) return;
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

/// 进度 for a group: what is still open here.
///
/// A group Session rarely has a todo list of its own — each member keeps theirs —
/// so this states the group's live situation first, then every member's open items
/// with their own progress, and finally the group Session's own goal and todos
/// when it has any.
class _RoomProgressTab extends ConsumerWidget {
  const _RoomProgressTab({required this.room, required this.team, required this.roomSession});

  final DsBotRoom room;
  final DsBotTeam team;
  final String? roomSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final status = ref.watch(dsBotProvider);

    // 1. The group's live situation.
    final working = status.live.rooms[room.id] ?? const <DsBotWork>[];
    final approvals = [
      for (final approval in status.live.approvals)
        if (approval.roomId == room.id && approval.answerable) approval,
    ];

    // 2. Each member's open todos, from their Session for this group.
    final openByBot = <(DsBot, List<TodoItem>, int)>[];
    final seen = <String>{};
    for (final id in room.members) {
      final bot = team.bot(id);
      if (bot == null) continue;
      final sessionId = memberSessionFor(room, bot);
      if (sessionId == null || sessionId.isEmpty || !seen.add(sessionId)) continue;
      final panels = ref.watch(sessionPanelsProvider(sessionId));
      final logged = ref.watch(chatProvider(sessionId).select((s) => s.todos));
      final todos = panels.todos ?? logged ?? const <TodoItem>[];
      final open = [for (final todo in todos) if (todo.status != 'completed') todo];
      if (open.isNotEmpty) openByBot.add((bot, open, todos.length));
    }

    // 3. The group Session's own goal and todos, when it has them.
    final groupPanels = roomSession == null ? null : ref.watch(sessionPanelsProvider(roomSession!));
    final goal = groupPanels?.goal;
    final groupTodos = roomSession == null
        ? const <TodoItem>[]
        : (groupPanels?.todos ?? ref.watch(chatProvider(roomSession!).select((s) => s.todos)) ?? const <TodoItem>[]);
    final groupDone = groupTodos.where((todo) => todo.status == 'completed').length;

    if (working.isEmpty &&
        approvals.isEmpty &&
        !room.paused &&
        openByBot.isEmpty &&
        goal == null &&
        groupTodos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.hubSessionNoGoal, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 6),
              Text(
                l10n.hubSessionGoalHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    final phaseText = switch (goal?.phase) {
      'complete' => l10n.commonCompleted,
      'blocked' => l10n.hubSessionBlocked,
      'paused' => l10n.commonPaused,
      _ => l10n.commonInProgress,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (working.isNotEmpty || approvals.isNotEmpty || room.paused)
          ListPageCard(
            title: l10n.hubTabProgress,
            children: [
              if (room.paused)
                ListPageRow(
                  key: const ValueKey('room-progress-paused'),
                  icon: AppIcons.paused,
                  title: l10n.commonPaused,
                  chevron: false,
                ),
              for (final work in working)
                if (team.bot(work.botId) case final bot?)
                  ListPageRow(
                    key: ValueKey('room-progress-work-${bot.id}'),
                    leading: BotAvatar(bot: bot, size: 28),
                    title: bot.name,
                    subtitle: workPhrase(work, team: team) ?? l10n.botsWorking,
                    subtitleMaxLines: 1,
                    chevron: false,
                  ),
              for (final approval in approvals)
                if (team.bot(approval.botId) case final bot?)
                  ListPageRow(
                    key: ValueKey('room-progress-approval-${bot.id}'),
                    leading: BotAvatar(bot: bot, size: 28),
                    title: bot.name,
                    subtitle: l10n.botsMemberNeedsApproval,
                    subtitleMaxLines: 1,
                    chevron: false,
                  ),
            ],
          ),
        for (final (bot, open, total) in openByBot) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                BotAvatar(bot: bot, size: 20),
                const SizedBox(width: 8),
                Text(bot.name, style: theme.textTheme.labelLarge),
                const Spacer(),
                Text(
                  '${total - open.length}/$total',
                  style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary),
                ),
                const SizedBox(width: 8),
                TodoProgress(done: total - open.length, total: total, barWidth: 56, showLabel: false),
              ],
            ),
          ),
          ListPageCard(
            children: [
              for (final (i, todo) in open.indexed)
                ListPageRow(
                  key: ValueKey('room-todo-${bot.id}-$i'),
                  icon: AppIcons.todo,
                  title: todo.content,
                  subtitleMaxLines: 2,
                  chevron: false,
                ),
            ],
          ),
        ],
        if (goal != null) ...[
          const SizedBox(height: 16),
          ListPageCard(
            title: l10n.hubSessionGoal,
            children: [
              ListPageRow(
                key: const ValueKey('room-goal-objective'),
                icon: AppIcons.goal,
                title: goal.objective,
                subtitleMaxLines: 3,
                chevron: false,
              ),
              ListPageRow(
                key: const ValueKey('room-goal-state'),
                title: phaseText,
                meta: goal.maxRounds == null
                    ? l10n.hubSessionTurn(goal.roundsStarted)
                    : l10n.hubSessionTurnOf(goal.roundsStarted, goal.maxRounds!),
                chevron: false,
              ),
            ],
          ),
        ],
        if (groupTodos.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                Text(l10n.hubSessionTodos, style: theme.textTheme.labelLarge?.copyWith(color: dsh.textTertiary)),
                const Spacer(),
                TodoProgress(done: groupDone, total: groupTodos.length, barWidth: 56, showLabel: false),
              ],
            ),
          ),
          ListPageCard(
            children: [
              for (final (i, todo) in groupTodos.indexed)
                ListPageRow(
                  key: ValueKey('room-group-todo-$i'),
                  icon: todo.status == 'completed' ? AppIcons.done : AppIcons.todo,
                  title: todo.content,
                  subtitleMaxLines: 2,
                  chevron: false,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 上下文 for a group: what the whole group is spending, then the detail.
///
/// The two top cards add up the group's own Session and every member's Session
/// *in this group*, so they state the group's real spend — the group Session
/// alone runs almost no model. The last turns are the group Session's, because
/// member turns only come as sums. The member rows below are the detail: a
/// member without a Session here keeps its row but counts as nothing.
class _RoomContextTab extends ConsumerWidget {
  const _RoomContextTab({required this.room, required this.activity, required this.roomSession});

  final DsBotRoom room;
  final Future<RoomMembersActivity> activity;
  final String? roomSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final sessionId = roomSession;
    final usage = sessionId == null ? null : ref.watch(sessionUsageProvider(sessionId));
    final turns = sessionId == null
        ? const <TurnTrace>[]
        : ref.watch(chatProvider(sessionId).select((s) => s.turns));
    return FutureBuilder<RoomMembersActivity>(
      future: activity,
      builder: (context, snapshot) {
        final total = snapshot.data;
        // Both top cards are totals, so they wait for the members' figures: drawn
        // first, the group Session's own zero would flash before them.
        if (total == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        final share = total.maxContextShare;
        final fullest = total.fullest;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // The group's own Session and every member's Session in this group,
            // added up; the members' rows below are the detail. No price: the
            // members may run different models, so one pricing does not hold.
            SessionUsageSections(usage: roomUsageTotal(usage ?? SessionUsage.empty, total), pricing: null),
            // The group Session's last turns, as the single-conversation page
            // draws them. Member turns only come as sums, so they are not
            // plotted here.
            TurnUsageCard(turns: turns),
            const SizedBox(height: 8),
            Text(
              l10n.activityUsageContext,
              style: theme.textTheme.labelMedium?.copyWith(color: dsh.textTertiary),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  share == null ? '—' : '${(share * 100).round()}% · ${formatTokens(total.contextTokens)}',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                if (fullest != null) ...[
                  Text(
                    fullest.bot.name,
                    style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  '${l10n.activityCacheHit} ${(total.cacheHit * 100).round()}%',
                  style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              // 合计 = N 位成员 + 群会话, as the page states it.
              '${l10n.botsMembers} ${total.members.length} + ${l10n.botsGroupChat}',
              style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary),
            ),
            const SizedBox(height: 8),
            for (final member in total.members)
              ListPageRow(
                key: ValueKey('member-context-${member.bot.id}'),
                leading: BotAvatar(bot: member.bot, size: 32),
                title: member.bot.name,
                subtitle: [
                  if (member.contextShare != null) '${(member.contextShare! * 100).round()}%',
                  if (member.contextTokens != null) formatTokens(member.contextTokens!),
                  if (member.turns > 0) '${member.turns}×',
                  if (member.speed != null) '${member.speed!.round()} tok/s',
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
