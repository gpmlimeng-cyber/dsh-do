// 工具行：S 档只有「工具名 + 状态」，没有可展开的内容。
import 'package:dsh_app/ui/bots/bot_chat_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart' show testApp;

void main() {
  testWidgets('a running tool says what it is and that it is running', (tester) async {
    await tester.pumpWidget(testApp(const Scaffold(body: BotToolRow(name: 'read_file', status: 'running'))));
    expect(find.text('read_file'), findsOneWidget);
    expect(find.text('正在执行…'), findsOneWidget);
  });

  testWidgets('a finished tool keeps its name and drops the status', (tester) async {
    await tester.pumpWidget(testApp(const Scaffold(body: BotToolRow(name: 'read_file', status: 'done'))));
    expect(find.text('read_file'), findsOneWidget);
    expect(find.text('正在执行…'), findsNothing);
  });

  testWidgets('a failed tool says so', (tester) async {
    await tester.pumpWidget(testApp(const Scaffold(body: BotToolRow(name: 'read_file', status: 'failed'))));
    expect(find.text('失败'), findsOneWidget);
  });
}
