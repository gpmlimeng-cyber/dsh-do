// 轻松模式的外壳：四个 Tab（消息 / 伙伴 / 发现 / 我）+ 底栏。
//
// 挂载点：`ui/web/mode_home.dart` 在 InterfaceMode.light 时 early return
// `const ImShell()`。必须保持 const 构造，否则那边编译不过。
//
// 返回键：不在「消息」时先回「消息」，在「消息」再退 App。
// 页面各自带 `ImPageScaffold`（含 AppBackdrop），所以这里不重复画背景。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/bots_state.dart';
import '../bots/bot_chat_page.dart';
import '../bots/room_chat_page.dart';
import 'im_companions_page.dart';
import 'im_discover_page.dart';
import 'im_me_page.dart';
import 'im_messages_page.dart';
import 'im_tab_bar.dart';

class ImShell extends ConsumerStatefulWidget {
  const ImShell({super.key});

  @override
  ConsumerState<ImShell> createState() => ImShellState();
}

class ImShellState extends ConsumerState<ImShell> {
  ImTab _tab = ImTab.messages;

  void _select(ImTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
  }

  void _openBot(String botId) {
    unawaited(Navigator.of(context).push(BotChatPage.route(botId)));
  }

  void _openRoom(String roomId) {
    unawaited(Navigator.of(context).push(RoomChatPage.route(roomId)));
  }

  @override
  Widget build(BuildContext context) {
    // 底栏「消息」上的一颗未读点：内存计数，冷启动清零。
    final unread = ref.watch(dsBotInboxProvider.select((inbox) => inbox.total > 0));
    return PopScope(
      canPop: _tab == ImTab.messages,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _tab = ImTab.messages);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: _tab.index,
          children: [
            ImMessagesPage(
              onOpenBot: _openBot,
              onOpenRoom: _openRoom,
              onGoDiscover: () => _select(ImTab.discover),
            ),
            ImCompanionsPage(onOpenBot: _openBot),
            const ImDiscoverPage(),
            const ImMePage(),
          ],
        ),
        bottomNavigationBar: ImTabBar(current: _tab, onSelect: _select, unread: unread),
      ),
    );
  }
}
