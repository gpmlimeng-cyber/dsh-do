// 时间分隔：时刻两侧各一条细线，和原生聊天的时间分隔观感一致。
import 'package:dsh_app/ui/bots/bot_chat_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart' show testApp;

void main() {
  testWidgets('a time line says when, between two hairlines', (tester) async {
    await tester.pumpWidget(testApp(Scaffold(body: BotTimeLine(DateTime.now()))));
    // 「刚刚」 for a time this close: the wording stays shortTime's, unchanged.
    expect(find.text('刚刚'), findsOneWidget);
    expect(find.byKey(const ValueKey('time-line-left')), findsOneWidget);
    expect(find.byKey(const ValueKey('time-line-right')), findsOneWidget);
  });
}
