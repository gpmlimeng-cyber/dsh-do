// 「切换会话」: which conversation the group's chat page shows, and the filters
// that only apply to the group chat. Navigation and filtering sit in two
// sections, and the filter switch changes the member rows' shape, so one never
// reads as the other.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

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
    required this.onTarget,
    required this.onMode,
  });

  final DsBotRoom room;
  final DsBotTeam team;
  final RoomChatTarget target;
  final RoomMessageMode mode;
  final List<DsBotItem> items;
  final ValueChanged<RoomChatTarget> onTarget;
  final ValueChanged<RoomMessageMode> onMode;

  @override
  State<_RoomSessionSheet> createState() => _RoomSessionSheetState();
}

class _RoomSessionSheetState extends State<_RoomSessionSheet> {
  late RoomChatTarget _target = widget.target;
  late RoomMessageMode _mode = widget.mode;
  final _membersScroll = ScrollController();
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
    _membersScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Newest line per member, read from the group's own messages: no extra RPC.
  Map<String, DateTime> get _lastSpoken {
    final out = <String, DateTime>{};
    for (final item in widget.items) {
      final id = item.botId;
      final time = item.time;
      if (id == null || time == null) continue;
      final seen = out[id];
      if (seen == null || time.isAfter(seen)) out[id] = time;
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
      return bt.compareTo(at);
    });
    return matched;
  }

  int get _memberCount => widget.room.members.length;

  void _revealCurrent() {
    if (!mounted || !_membersScroll.hasClients) return;
    final index = _orderedMembers.indexWhere((bot) => bot.id == widget.target.memberId);
    if (index < 0) return;
    const rowHeight = 52.0;
    final position = _membersScroll.position;
    _membersScroll.jumpTo((index * rowHeight).clamp(0.0, position.maxScrollExtent));
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

  void _toggleRelevant() {
    if (!_filtersEnabled) return;
    _setMode(_mode.isRelevant ? RoomMessageMode.all : RoomMessageMode.relevant);
  }

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

    Widget memberRow(DsBot bot) {
      final time = spoken[bot.id];
      final selected = filtering ? _mode.memberId == bot.id : _target.memberId == bot.id;
      return ListPageRow(
        key: ValueKey('room-member-${bot.id}'),
        leading: BotAvatar(bot: bot, size: 24),
        title: bot.name,
        subtitle: time == null ? l10n.botsRoomNeverSpoke : shortTime(time, now: now),
        subtitleColor: time == null ? dsh.textTertiary : null,
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

    return SafeArea(
      top: false,
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
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
                  child: ListView.builder(
                    key: const ValueKey('room-member-list'),
                    controller: _membersScroll,
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (context, index) => memberRow(members[index]),
                  ),
                ),
            ],
          ),
          SheetGroup(
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
                key: const ValueKey('room-filter-relevant'),
                title: l10n.botsMessageModeRelevant,
                trailing: Switch(
                  value: _mode.isRelevant,
                  onChanged: filtersEnabled ? (_) => _toggleRelevant() : null,
                ),
                onTap: filtersEnabled ? _toggleRelevant : null,
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
          ),
        ],
      ),
    );
  }
}
