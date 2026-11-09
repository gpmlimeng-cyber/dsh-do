// 「切换会话」: which conversation the group's chat page shows, and the filters
// that only apply to the group chat. Navigation and filtering sit in two
// sections, and the filter switch changes the member rows' shape, so one never
// reads as the other.

import 'package:dsh_client/dsh_client.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/room_chat_target.dart';
import '../../state/room_message_mode.dart';
import '../common/app_sheet.dart';
import '../common/list_page_row.dart';
import '../common/sheet_title_bar.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_avatar.dart';
import 'bot_format.dart' show shortTime;

Future<void> showRoomSessionSheet(
  BuildContext context, {
  required DsBotRoom room,
  required DsBotTeam team,
  required RoomChatTarget target,
  required RoomMessageMode mode,
  required List<DsBotItem> items,
  required String? Function(DsBotItem item) speakerOf,
  required ValueChanged<RoomChatTarget> onTarget,
  required ValueChanged<RoomMessageMode> onMode,
}) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) => _RoomSessionSheet(
      room: room,
      team: team,
      target: target,
      mode: mode,
      items: items,
      speakerOf: speakerOf,
      onTarget: onTarget,
      onMode: onMode,
    ),
  );
}

class _RoomSessionSheet extends StatefulWidget {
  const _RoomSessionSheet({
    required this.room,
    required this.team,
    required this.target,
    required this.mode,
    required this.items,
    required this.speakerOf,
    required this.onTarget,
    required this.onMode,
  });

  final DsBotRoom room;
  final DsBotTeam team;
  final RoomChatTarget target;
  final RoomMessageMode mode;
  final List<DsBotItem> items;

  /// Which member a line came from (the Bot id it carries, or its name).
  final String? Function(DsBotItem item) speakerOf;
  final ValueChanged<RoomChatTarget> onTarget;
  final ValueChanged<RoomMessageMode> onMode;

  @override
  State<_RoomSessionSheet> createState() => _RoomSessionSheetState();
}

class _RoomSessionSheetState extends State<_RoomSessionSheet> {
  late RoomChatTarget _target = widget.target;
  late RoomMessageMode _mode = widget.mode;
  final _scroll = ScrollController();
  final _search = TextEditingController();
  String _query = '';

  /// The member rows pick a filter only while the group chat is on screen: in a
  /// member's conversation the filters do not apply, so the rows navigate.
  bool get _filtering => _target.isAll && _mode.memberId != null;

  bool get _filtersEnabled => _target.isAll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// When each member last spoke in this group, read from the messages on
  /// screen: no extra RPC. A line's presence is what says the member has
  /// spoken — `room.log` lines carry no time at all, so the row shows a time
  /// only when the host sends one.
  Map<String, ({DateTime? time, int at})> get _lastSpoken {
    final out = <String, ({DateTime? time, int at})>{};
    var index = 0;
    for (final item in widget.items) {
      final id = widget.speakerOf(item);
      final time = item.time;
      index++;
      if (id == null) continue;
      final seen = out[id];
      if (seen == null || (time != null && (seen.time == null || time.isAfter(seen.time!)))) {
        out[id] = (time: time, at: index);
      }
    }
    return out;
  }

  /// Members with a line in this group first, newest first; those who have not
  /// spoken keep the group's own member order and sink to the bottom.
  List<DsBot> get _orderedMembers {
    final spoken = _lastSpoken;
    final bots = <DsBot>[];
    for (final id in widget.room.members) {
      final bot = widget.team.bot(id);
      if (bot != null) bots.add(bot);
    }
    final query = _query.trim().toLowerCase();
    final matched = <DsBot>[
      for (final bot in bots)
        if (query.isEmpty || bot.name.toLowerCase().contains(query)) bot,
    ];
    matched.sort((a, b) {
      final at = spoken[a.id];
      final bt = spoken[b.id];
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      // Times answer it finely; without them the newest line wins, which is
      // what the order of the messages already says.
      if (at.time != null && bt.time != null) return bt.time!.compareTo(at.time!);
      return bt.at.compareTo(at.at);
    });
    return matched;
  }

  int get _memberCount => widget.room.members.length;

  void _revealCurrent() {
    if (!mounted || !_scroll.hasClients) return;
    final index = _orderedMembers.indexWhere((bot) => bot.id == widget.target.memberId);
    if (index < 0) return;
    // Title bar, the group row and the member section's own title above it.
    const above = 56.0 + 64.0 + 24.0;
    final position = _scroll.position;
    _scroll.jumpTo((above + index * 52.0).clamp(0.0, position.maxScrollExtent));
  }

  void _pickTarget(RoomChatTarget next) {
    if (next == _target) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _target = next);
    widget.onTarget(next);
    Navigator.of(context).pop();
  }

  void _setMode(RoomMessageMode next) {
    if (next == _mode) return;
    setState(() => _mode = next);
    widget.onMode(next);
  }

  void _pickFilterMember(String id) => _setMode(RoomMessageMode.member(id));

  void _toggleMemberOnly() {
    if (!_filtersEnabled) return;
    if (_mode.memberId != null) {
      _setMode(RoomMessageMode.all);
      return;
    }
    final members = _orderedMembers;
    if (members.isEmpty) return;
    _setMode(RoomMessageMode.member(members.first.id));
  }

  Widget _searchField(L10n l10n, ThemeData theme, DshColors dsh) => SizedBox(
    height: 36,
    child: TextField(
      key: const ValueKey('room-member-search'),
      controller: _search,
      onChanged: (value) => setState(() => _query = value),
      style: theme.textTheme.bodyMedium,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        isDense: true,
        hintText: l10n.botsRoomSearchMembers,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(color: dsh.textTertiary),
        prefixIcon: Icon(AppIcons.search, size: 18, color: dsh.textTertiary),
        prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 36),
        contentPadding: const EdgeInsets.only(right: 12),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final scheme = theme.colorScheme;
    final members = _orderedMembers;
    final spoken = _lastSpoken;
    final now = DateTime.now();
    final filtering = _filtering;
    final filtersEnabled = _filtersEnabled;
    final searchable = _memberCount >= 8;
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);
    final available = size.height - insets.top - insets.bottom;
    // A short window (a phone on its side) cannot keep the filters fixed at the
    // bottom: everything scrolls together there, or they are cut off.
    final compact = available < 420;

    Widget memberRow(DsBot bot) {
      final spokenAt = spoken[bot.id];
      final time = spokenAt?.time;
      final selected = filtering ? _mode.memberId == bot.id : _target.memberId == bot.id;
      return ListPageRow(
        key: ValueKey('room-member-${bot.id}'),
        leading: BotAvatar(bot: bot, size: 24),
        title: bot.name,
        subtitle: time != null ? shortTime(time, now: now) : (spokenAt == null ? l10n.botsRoomNeverSpoke : null),
        subtitleColor: spokenAt == null ? dsh.textTertiary : null,
        meta: !filtering && selected ? l10n.botsRoomWatching : null,
        trailing: filtering
            ? Icon(
                selected ? AppIcons.radioOn : AppIcons.radioOff,
                size: 20,
                color: selected ? scheme.primary : dsh.textTertiary,
              )
            : null,
        chevron: filtering ? false : !selected,
        onTap: () => filtering ? _pickFilterMember(bot.id) : _pickTarget(RoomChatTarget.member(bot.id)),
      );
    }

    final middle = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetGroup(
          children: [
            ListPageRow(
              key: const ValueKey('room-target-all'),
              icon: AppIcons.groupChat,
              title: l10n.botsGroupChat,
              meta: _target.isAll ? l10n.botsRoomWatching : null,
              chevron: !_target.isAll,
              onTap: () => _pickTarget(RoomChatTarget.all),
            ),
          ],
        ),
        SheetGroup(
          title: filtering ? l10n.botsRoomOnlyWhose : l10n.botsRoomMemberChats,
          children: [
            if (members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  l10n.botsRoomNeverSpoke,
                  style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
                ),
              )
            else
              // One scroll region for the panel: the member rows are plain
              // children here, not a second list with a height of its own.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final bot in members) memberRow(bot)],
              ),
          ],
        ),
      ],
    );

    final filters = SheetGroup(
      title: l10n.botsRoomFilter,
      children: [
        if (!filtersEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              l10n.botsRoomFilterGroupOnly,
              style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
            ),
          ),
        ListPageRow(
          key: const ValueKey('room-filter-member'),
          title: l10n.botsRoomOnlyThisMember,
          subtitle: filtersEnabled ? null : l10n.botsRoomFilterGroupOnly,
          subtitleColor: dsh.textTertiary,
          trailing: Switch(
            value: _mode.memberId != null,
            onChanged: filtersEnabled ? (_) => _toggleMemberOnly() : null,
          ),
          onTap: filtersEnabled ? _toggleMemberOnly : null,
        ),
      ],
    );

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          // The panel never grows past the window: the title stays, the middle
          // takes what is left, and the filters stay reachable.
          constraints: BoxConstraints(maxHeight: math.max(0, available * 0.9), maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitleBar(l10n.botsRoomSwitchChat),
              if (searchable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(SheetTitleBar.inset, 0, SheetTitleBar.inset, 8),
                  child: _searchField(l10n, theme, dsh),
                ),
              if (compact)
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [middle, filters],
                    ),
                  ),
                )
              else ...[
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(controller: _scroll, child: middle),
                ),
                filters,
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 「只看谁的发言」: the scope one group chat shows. The chip in the group chat
/// clears it; this is where it is set. The old session sheet also switched
/// conversations and needs the chat's live items, which a details row does not
/// have — so the scope gets this small sheet of its own.
Future<void> showMessageScopeSheet(
  BuildContext context,
  WidgetRef ref, {
  required DsBotRoom room,
  required DsBotTeam team,
}) {
  final ids = [
    if (room.admin != null) room.admin!,
    ...room.members.where((id) => id != room.admin),
  ];
  final bots = [for (final id in ids) ?team.bot(id)];
  final current = ref.read(roomMessageModeProvider(room.id));
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) {
      final l10n = sheet.l10n;
      final dsh = DshColors.of(sheet);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitleBar(l10n.botsRoomOnlyWhose),
          for (final bot in bots)
            ListPageRow(
              key: ValueKey('scope-${bot.id}'),
              leading: BotAvatar(bot: bot, size: 32),
              title: bot.name,
              trailing: current.memberId == bot.id ? Icon(AppIcons.done, size: 20, color: dsh.info) : null,
              chevron: false,
              onTap: () {
                ref.read(roomMessageModesProvider.notifier).set(room.id, RoomMessageMode.member(bot.id));
                Navigator.of(sheet).maybePop();
              },
            ),
          const SizedBox(height: 12),
        ],
      );
    },
  );
}
