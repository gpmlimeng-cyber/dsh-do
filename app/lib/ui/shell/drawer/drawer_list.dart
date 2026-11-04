// The drawer's conversation list once it has loaded:
// DS Bot's row, 置顶, the folders (opening and closing in place), then the
// rest by day; or, under a status filter, just the matches. Loading, error
// and empty-host states stay with the drawer (sessions_drawer.dart).

import 'package:dsh_client/dsh_client.dart' show SessionSummary;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../state/drawer_view_state.dart';
import '../../../state/session_attention_state.dart';
import '../../../state/session_created_state.dart';
import '../../../state/bots_state.dart';
import '../../../state/sessions_state.dart';
import '../../../state/workspaces_state.dart';
import '../../common/empty_view.dart';
import '../../theme/app_icons.dart';
import '../../bots/bot_avatar.dart';
import '../../bots/bot_format.dart' show shortTime, workPhrase;
import '../../theme/theme.dart';
import '../../bots/bot_chat_page.dart';
import '../../bots/room_chat_page.dart';
import '../sessions_drawer.dart' show sessionTitle;
import 'drawer_actions.dart';
import 'folder_header.dart';
import 'session_tile.dart';

class DrawerConversationList extends ConsumerWidget {
  const DrawerConversationList({
    super.key,
    required this.onOpen,
    required this.onLongPress,
    this.onNewChat,
    this.leading,
    required this.onClose,
    this.now,
    this.readOnly = false,
  });

  /// Opens a conversation (and closes the drawer).
  final ValueChanged<String> onOpen;

  /// Closes the drawer after choosing a folder for a new conversation.
  final VoidCallback? onNewChat;

  /// Drawn above the list (a Bot row, upstream's 1.0.10 addition); null hides it.
  final Widget? leading;

  /// A conversation's actions.
  final void Function(SessionSummary session) onLongPress;

  /// Closes the drawer once a Bot's chat covers it.
  final VoidCallback onClose;

  /// Clock override for the day groups (tests).
  final DateTime? now;
  final bool readOnly;

  /// The list's padding: rows' edges on the drawer's 10 line.
  static const padding = EdgeInsets.fromLTRB(10, 4, 10, 16);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final blocks = watchDrawerBlocks(ref, now: now);
    if (blocks == null) return const SizedBox.shrink();
    final selection = ref.watch(drawerSelectionProvider);
    final selecting = !readOnly && selection != null;
    final filter = ref.watch(drawerFilterProvider);
    final current = ref.watch(currentSessionProvider);
    // A Bot's or a group's chat is a pushed page, not a Session here: its row
    // lights up from the page that is showing it.
    final viewing = ref.watch(dsBotViewingProvider);
    final pending = ref.watch(pendingInteractionsProvider);
    final unread = ref.watch(unreadSessionIdsProvider);
    final pinned = ref.watch(workspacesProvider.select((s) => s.pinnedSessionIds)).toSet();
    final sort = ref.watch(drawerViewProvider.select((v) => v.sort));
    if (!readOnly && sort == DrawerSort.created) {
      final ids = [
        for (final block in blocks)
          for (final row in block.items)
            if (row is SessionRow) row.id,
      ];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ref.read(sessionCreatedProvider.notifier).ensure(ids);
      });
    }
    final selectionNotifier = ref.read(drawerSelectionProvider.notifier);

    Widget tile(SessionSummary s, {bool inFolder = false}) {
      final id = s.sessionId;
      return SessionTile(
        key: ValueKey('session-$id'),
        title: sessionTitle(s),
        running: s.running,
        current: id == current,
        pending: readOnly ? null : pending[id],
        unread: !readOnly && unread.contains(id),
        pinned: inFolder && pinned.contains(id),
        indent: inFolder ? SessionTile.folderIndent : 0,
        selecting: selecting,
        selected: selection?.contains(id) ?? false,
        onTap: selecting ? () => selectionNotifier.toggle(id) : () => onOpen(id),
        onLongPress: readOnly
            ? null
            : selecting
            ? () => selectionNotifier.toggle(id)
            : () => onLongPress(s),
      );
    }

    // Keep only builders for off-screen rows: preparing a title and a tile for
    // every conversation makes even a selection change scale with the history.
    final rows = <({Key key, WidgetBuilder builder})>[];
    void add(Key key, WidgetBuilder builder) => rows.add((key: key, builder: builder));
    // A Bot's own chat or a group chat: same row, its own chat page. Never
    // selectable, and its only long-press action is the folder.
    final bots = ref.watch(dsBotProvider);
    final team = bots.team;
    final clock = now ?? ref.watch(drawerClockProvider)();
    Widget botTile(BotDrawerRow row, {bool inFolder = false}) => SessionTile(
      key: ValueKey('bot-${row.id}'),
      title: row.title,
      running: row.running,
      current: viewing == row.id,
      pending: readOnly ? null : row.pending,
      unread: !readOnly && row.unread,
      pinned: false,
      badge: row.badge,
      note: botRowNote(bots, row, clock),
      // A face is what tells these rows from the conversations beside them.
      leading: switch ((row.bot, row.room, team)) {
        (final bot?, _, _) => BotAvatar(bot: bot, size: 22),
        (_, final room?, final team?) => RoomAvatar(room: room, team: team, size: 22),
        _ => null,
      },
      indent: inFolder ? SessionTile.folderIndent : 0,
      selecting: selecting,
      selected: false,
      onTap: selecting
          ? () {}
          : () {
              Navigator.of(
                context,
              ).push(row.isRoom ? RoomChatPage.route(row.id) : BotChatPage.route(row.id));
              // Close once the page covers us, so "back" lands on the chat.
              Future<void>.delayed(AppMotion.slow, onClose);
            },
      onLongPress: readOnly || selecting ? null : () => moveToFolderFlow(context, ref, [row.id]),
    );

    void addRows(List<DrawerRow> items) {
      for (final row in items) {
        switch (row) {
          case SessionRow(:final session):
            add(ValueKey('session-${row.id}'), (_) => tile(session));
          case BotDrawerRow():
            add(ValueKey('bot-${row.id}'), (_) => botTile(row));
        }
      }
    }
    var foldersLabelled = false;
    for (final block in blocks) {
      switch (block) {
        case FilteredBlock(filter: final matching, :final items) when items.isEmpty:
          const key = ValueKey('filter-empty');
          add(key, (_) => _FilterEmpty(matching, key: key));
        case FilteredBlock(:final items):
          addRows(items);
        case PinnedBlock(:final items):
          const key = ValueKey('pinned-label');
          add(key, (_) => DrawerEyebrow(l10n.commonPin, key: key));
          addRows(items);
        case FolderBlock(:final folder, :final items):
          if (!foldersLabelled) {
            foldersLabelled = true;
            const key = ValueKey('folders-label');
            add(key, (_) => DrawerEyebrow(l10n.shellFolders, key: key));
          }
          final headerKey = ValueKey('folder-${folder.id}');
          add(
            headerKey,
            (_) => DrawerFolderHeader(
              key: headerKey,
              folder: folder,
              count: items.length,
              onTap: () => ref.read(drawerViewProvider.notifier).toggleCollapsed(folder.id),
              onLongPress: () {
                if (!readOnly) folderActionsFlow(context, ref, folder, onNewChat: onNewChat);
              },
            ),
          );
          final bodyKey = ValueKey('folder-body-${folder.id}');
          add(
            bodyKey,
            (_) => DrawerFolderBody(
              key: bodyKey,
              open: !folder.collapsed,
              childrenBuilder: () => [
                for (final row in items)
                  if (row is SessionRow)
                    tile(row.session, inFolder: true)
                  else if (row is BotDrawerRow)
                    botTile(row, inFolder: true),
              ],
            ),
          );
        case DayBlock(:final day, :final items):
          final key = ValueKey('day-${day.name}');
          add(key, (_) => DrawerEyebrow(sessionDayLabels[day]!, key: key));
          addRows(items);
      }
    }
    // Preserve keyed row/folder state when pinning, sorting or hiding the
    // leading row changes indices. A new filter still starts at the top.
    final indices = {for (var i = 0; i < rows.length; i++) rows[i].key: i};
    return ListView.builder(
      key: ValueKey(filter),
      padding: padding,
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index].builder(context),
      findChildIndexCallback: (key) => indices[key],
    );
  }
}

/// A status filter with no matches.
class _FilterEmpty extends StatelessWidget {
  const _FilterEmpty(this.filter, {super.key});

  final DrawerFilter filter;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, title) = switch (filter) {
      DrawerFilter.running => (AppIcons.running, l10n.shellNoRunningChats),
      DrawerFilter.pending => (AppIcons.toConfirm, l10n.shellNoPendingChats),
      DrawerFilter.unread => (AppIcons.allRead, l10n.shellNoUnreadChats),
      DrawerFilter.all => (AppIcons.chat, l10n.shellNoChatsYet),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: EmptyView(compact: true, icon: icon, title: title),
    );
  }
}

/// What a Bot or group row says on its right: what it is doing now, or when it
/// last moved. Null when there is nothing to say — and while it waits for an
/// answer, where the marker already says 待回答 / 待确认.
String? botRowNote(DsBotStatus status, BotDrawerRow row, DateTime now) {
  if (row.pending != null) return null;
  if (row.isRoom) {
    final works = status.live.rooms[row.id];
    if (works != null && works.isNotEmpty) return appL10n.botsRoomWorkingCount(works.length);
  } else {
    final activity = status.live.activity[row.id];
    if (row.running || activity == 'thinking') {
      return workPhrase(status.live.bots[row.id], activity: activity, team: status.team);
    }
  }
  if (!row.activity) return null;
  return shortTime(row.updatedAt, now: now);
}
