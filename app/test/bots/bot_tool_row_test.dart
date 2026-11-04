// 工具行：说动作（「查看文件」），不报工具名；运行中 / 失败各有状态。
import 'package:dsh_app/ui/bots/bot_chat_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart' show testApp;

void main() {
  test('a tool name maps to the action it performs', () {
    expect(botToolKind('bash'), BotToolKind.run);
    expect(botToolKind('read_file'), BotToolKind.read);
    expect(botToolKind('list_files'), BotToolKind.read);
    expect(botToolKind('write_file'), BotToolKind.edit);
    expect(botToolKind('edit'), BotToolKind.edit);
    expect(botToolKind('grep'), BotToolKind.search);
    expect(botToolKind('web_search'), BotToolKind.search);
    expect(botToolKind('web_fetch'), BotToolKind.browse);
    expect(botToolKind('send_message'), BotToolKind.message);
    expect(botToolKind('ask_user'), BotToolKind.ask);
    // A write verb that is not a file: 待办 stays 干活.
    expect(botToolKind('todo_write'), BotToolKind.work);
    expect(botToolKind('something_new'), BotToolKind.work);
  });

  testWidgets('a running tool says what it is doing', (tester) async {
    await tester.pumpWidget(testApp(const Scaffold(body: BotToolRow(name: 'read_file', status: 'running'))));
    expect(find.text('正在查看文件'), findsOneWidget);
    expect(find.text('read_file'), findsNothing);
  });

  testWidgets('a finished tool says what it did', (tester) async {
    await tester.pumpWidget(testApp(const Scaffold(body: BotToolRow(name: 'read_file', status: 'done'))));
    expect(find.text('查看文件'), findsOneWidget);
    expect(find.text('正在查看文件'), findsNothing);
    expect(find.text('read_file'), findsNothing);
  });

  testWidgets('a failed tool says so', (tester) async {
    await tester.pumpWidget(testApp(const Scaffold(body: BotToolRow(name: 'bash', status: 'failed'))));
    expect(find.text('运行命令'), findsOneWidget);
    expect(find.text('失败'), findsOneWidget);
  });
}
