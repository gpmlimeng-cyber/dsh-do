// 「新建」: one panel for starting a conversation — a plain one, a Bot, a
// group — and for finding one that already exists by name.
//
// It replaces the drawer's 新对话 key (a plain new chat with no way to reach a
// Bot or a group from there). The search field is the panel's point: type a
// name and the Bot or group it names comes up, or a Bot with that name can be
// made on the spot.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dsh_client/dsh_client.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../../state/drawer_view_state.dart';
import '../../state/sessions_state.dart';
import '../bots/bot_avatar.dart';
import '../bots/bot_chat_page.dart';
import '../bots/bot_format.dart' show shortTime;
import '../bots/new_bot_page.dart';
import '../bots/new_room_sheet.dart';
import '../bots/room_chat_page.dart';
import '../common/app_sheet.dart';
import '../common/brief_notice.dart';
import '../common/list_page_row.dart';
import '../common/sheet_title_bar.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'sessions_drawer.dart' show sessionTitle;

/// Opens the 新建 panel. [onChosen] runs once a conversation was picked or a
/// new one opened (the drawer closes itself; a pushed page keeps it under).
Future<void> showNewPanel(BuildContext context, {VoidCallback? onChosen}) => showAppSheet<void>(
  context,
  isScrollControlled: true,
  builder: (_) => _NewPanel(onChosen: onChosen),
);

class _NewPanel extends ConsumerStatefulWidget {
  const _NewPanel({this.onChosen});

  final VoidCallback? onChosen;

  @override
  ConsumerState<_NewPanel> createState() => _NewPanelState();
}

class _NewPanelState extends ConsumerState<_NewPanel> {
  final _search = TextEditingController();
  final _folderName = TextEditingController();
  final _folderFocus = FocusNode();
  String _query = '';
  bool _naming = false;
  String? _nameError;
  String? _openFolder;
  late final BuildContext _host = context;

  @override
  void dispose() {
    _search.dispose();
    _folderName.dispose();
    _folderFocus.dispose();
    super.dispose();
  }

  /// Closes the panel, then runs [action] with the navigator that had it: this
  /// panel's own context is gone by then.
  void _after(void Function(NavigatorState navigator) action) {
    final navigator = Navigator.of(context);
    navigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => action(navigator));
  }

  void _openSession(String id) {
    ref.read(currentSessionProvider.notifier).select(id);
    widget.onChosen?.call();
    Navigator.of(context).pop();
  }

  Future<void> _createFolder() async {
    final name = _folderName.text.trim();
    if (name.isEmpty) return;
    final taken = ref.read(drawerViewProvider).folders.map((f) => f.name).toSet();
    if (taken.contains(name)) {
      setState(() => _nameError = context.l10n.shellNewFolderTaken);
      return;
    }
    await ref.read(drawerViewProvider.notifier).createFolder(name);
    if (!mounted) return;
    setState(() {
      _naming = false;
      _folderName.clear();
      _nameError = null;
    });
    _folderFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final team = ref.watch(dsBotProvider.select((s) => s.team));
    final folders = ref.watch(drawerViewProvider.select((v) => v.folders));
    final sessions = ref.watch(sessionsProvider).value ?? const <SessionSummary>[];
    final now = DateTime.now();
    final query = _query.trim().toLowerCase();

    final recent = [...sessions]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final bots = [
      for (final bot in team?.bots ?? const <DsBot>[])
        if (query.isEmpty || bot.name.toLowerCase().contains(query)) bot,
    ];
    final rooms = [
      for (final room in team?.rooms ?? const <DsBotRoom>[])
        if (query.isEmpty || room.name.toLowerCase().contains(query)) room,
    ];
    final matchedFolders = [
      for (final folder in folders)
        if (query.isEmpty || folder.name.toLowerCase().contains(query)) folder,
    ];
    final searching = query.isNotEmpty;
    final botNamed = searching && bots.isEmpty ? _search.text.trim() : null;

    Widget row({
      required Widget leading,
      required String title,
      String? subtitle,
      Widget? trailing,
      VoidCallback? onTap,
    }) => ListPageRow(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
    );

    final children = <Widget>[
      if (!searching) ...[
        SheetGroup(
          title: l10n.shellNewPanelStart,
          children: [
            row(
              leading: Icon(AppIcons.newChat, size: 20, color: dsh.textTertiary),
              title: l10n.commonNewChat,
              onTap: () {
                // 先关面板与抽屉，下一帧再切会话：同一帧里既切会话又关面板，
                // 会让 ChatScreen 的重建和关闭动画打架——从左侧栏进来第一次
                // 会留一帧空页（看着是黑屏）。notifier 在这里先取好，回调跑
                // 时这个面板已经销毁，不能再碰 ref。
                final sessions = ref.read(currentSessionProvider.notifier);
                final chosen = widget.onChosen;
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  chosen?.call();
                  sessions.select(null);
                });
              },
            ),
          ],
        ),
        if (recent.isNotEmpty)
          SheetGroup(
            title: l10n.shellNewPanelRecent,
            children: [
              for (final session in recent.take(3))
                row(
                  leading: Icon(AppIcons.chat, size: 20, color: dsh.textTertiary),
                  title: sessionTitle(session),
                  subtitle: shortTime(session.updatedAt, now: now),
                  onTap: () => _openSession(session.sessionId),
                ),
            ],
          ),
        SheetGroup(
          title: l10n.shellNewPanelNew,
          children: [
            row(
              leading: Icon(AppIcons.bot, size: 20, color: dsh.textTertiary),
              title: l10n.botsNewBot,
              onTap: () => _after((navigator) => navigator.push(NewBotPage.route())),
            ),
            row(
              leading: Icon(AppIcons.groupChat, size: 20, color: dsh.textTertiary),
              title: l10n.botsNewGroup,
              onTap: () {
                final bots = team?.bots.length ?? 0;
                if (bots < 2) {
                  _after((_) => showBriefNotice(_host, l10n.botsPickTwoBots));
                  return;
                }
                _after((_) => showNewRoomSheet(_host));
              },
            ),
            if (_naming)
              _FolderNamingRow(
                controller: _folderName,
                focus: _folderFocus,
                error: _nameError,
                onCancel: () => setState(() {
                  _naming = false;
                  _folderName.clear();
                  _nameError = null;
                }),
                onConfirm: _createFolder,
              )
            else
              row(
                leading: Icon(AppIcons.folder, size: 20, color: dsh.textTertiary),
                title: l10n.shellNewFolder,
                onTap: () {
                  setState(() => _naming = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) => _folderFocus.requestFocus());
                },
              ),
          ],
        ),
        if (folders.isNotEmpty)
          SheetGroup(
            title: l10n.shellGroups,
            children: [
              for (final folder in folders)
                row(
                  leading: Icon(AppIcons.folder, size: 20, color: dsh.textTertiary),
                  title: folder.name,
                  subtitle: l10n.shellFolderSessions(folder.sessionIds.length),
                  trailing: Icon(
                    _openFolder == folder.id ? AppIcons.collapse : AppIcons.expand,
                    size: 16,
                    color: dsh.textTertiary,
                  ),
                  onTap: () => setState(() => _openFolder = _openFolder == folder.id ? null : folder.id),
                ),
              if (_openFolder != null)
                for (final id in folders.where((f) => f.id == _openFolder).expand((f) => f.sessionIds))
                  if (sessions.where((s) => s.sessionId == id).firstOrNull case final session?)
                    row(
                      leading: const SizedBox(width: 20),
                      title: sessionTitle(session),
                      onTap: () => _openSession(session.sessionId),
                    ),
            ],
          ),
      ] else ...[
        if (bots.isNotEmpty)
          SheetGroup(
            title: l10n.shellNewPanelBots,
            children: [
              for (final bot in bots)
                row(
                  leading: BotAvatar(bot: bot, size: 20),
                  title: bot.name,
                  onTap: () => _after((navigator) => navigator.push(BotChatPage.route(bot.id))),
                ),
            ],
          ),
        if (rooms.isNotEmpty)
          SheetGroup(
            title: l10n.shellNewPanelGroups,
            children: [
              for (final room in rooms)
                row(
                  leading: Icon(AppIcons.groupChat, size: 20, color: dsh.textTertiary),
                  title: room.name,
                  onTap: () => _after((navigator) => navigator.push(RoomChatPage.route(room.id))),
                ),
            ],
          ),
        if (matchedFolders.isNotEmpty)
          SheetGroup(
            title: l10n.shellGroups,
            children: [
              for (final folder in matchedFolders)
                row(
                  leading: Icon(AppIcons.folder, size: 20, color: dsh.textTertiary),
                  title: folder.name,
                  subtitle: l10n.shellFolderSessions(folder.sessionIds.length),
                ),
            ],
          ),
        if (botNamed != null)
          SheetGroup(
            children: [
              row(
                leading: Icon(AppIcons.bot, size: 20, color: dsh.textTertiary),
                title: l10n.shellNewNamedBot(botNamed),
                onTap: () => _after((navigator) => navigator.push(NewBotPage.route(initialName: botNamed))),
              ),
            ],
          ),
      ],
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitleBar(l10n.shellNewPanelTitle, onClose: () => Navigator.of(context).pop()),
              Padding(
                padding: const EdgeInsets.fromLTRB(kSheetGutter, 0, kSheetGutter, 8),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    key: const ValueKey('new-panel-search'),
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    style: theme.textTheme.bodyMedium,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l10n.shellNewPanelSearch,
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(color: dsh.textTertiary),
                      prefixIcon: Icon(AppIcons.search, size: 18, color: dsh.textTertiary),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                      contentPadding: const EdgeInsets.only(right: 12),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              Flexible(child: SingleChildScrollView(child: Column(children: children))),
            ],
          ),
        ),
      ),
    );
  }
}

/// The folder name taken inline: the row becomes the field, and the panel
/// stays put — a naming sheet over a panel over the drawer is one layer too
/// many.
class _FolderNamingRow extends StatelessWidget {
  const _FolderNamingRow({
    required this.controller,
    required this.focus,
    required this.error,
    required this.onCancel,
    required this.onConfirm,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.folder, size: 20, color: dsh.textTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('new-folder-name'),
                  controller: controller,
                  focusNode: focus,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onConfirm(),
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.l10n.shellNewFolderName,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(color: dsh.textTertiary),
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('new-folder-cancel'),
                onPressed: onCancel,
                icon: Icon(AppIcons.close, size: 18, color: dsh.textTertiary),
              ),
              IconButton(
                key: const ValueKey('new-folder-ok'),
                onPressed: onConfirm,
                icon: Icon(AppIcons.done, size: 18, color: theme.colorScheme.primary),
              ),
            ],
          ),
          if (error case final text?)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 0, 8, 6),
              child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
