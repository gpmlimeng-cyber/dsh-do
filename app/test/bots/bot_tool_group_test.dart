// 连续工具行到 3 条才合并成一组；运行中展开、结束后折叠。
import 'package:dsh_app/ui/bots/bot_chat_kit.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart' show pumpFrames, testApp;

DsBotItem _tool(String name, {String status = 'done'}) =>
    DsBotItem(kind: DsBotItemKind.tool, toolName: name, toolStatus: status);

List<BotRow> _rows(List<DsBotItem> items) => groupToolRows(transcriptRows(items));

void main() {
  test('two calls in a row stay as two lines', () {
    final rows = _rows([_tool('read_file'), _tool('bash')]);
    expect(rows.whereType<BotToolGroupRow>(), isEmpty);
    expect(rows.whereType<BotItemRow>().length, 2);
  });

  test('three calls in a row fold into one group, in order', () {
    final rows = _rows([_tool('read_file'), _tool('bash'), _tool('web_search', status: 'failed')]);
    final group = rows.whereType<BotToolGroupRow>().single;
    expect(group.items.map((item) => item.toolName), ['read_file', 'bash', 'web_search']);
    expect(group.items.last.toolStatus, 'failed');
  });

  test('a message between calls keeps two runs apart', () {
    final rows = _rows([
      _tool('a'), _tool('b'), _tool('c'),
      DsBotItem(kind: DsBotItemKind.bot, text: '中间说一句'),
      _tool('d'), _tool('e'), _tool('f'),
    ]);
    expect(rows.whereType<BotToolGroupRow>().length, 2);
  });

  testWidgets('a running group is open; a finished one is folded', (tester) async {
    final running = [_tool('read_file', status: 'running'), _tool('bash'), _tool('web_search')];
    await tester.pumpWidget(testApp(Scaffold(body: BotToolGroup(items: running))));
    expect(find.text('read_file'), findsOneWidget);
    expect(find.text('bash'), findsOneWidget);

    final finished = [_tool('read_file'), _tool('bash'), _tool('web_search')];
    await tester.pumpWidget(testApp(Scaffold(body: BotToolGroup(items: finished))));
    await pumpFrames(tester, 2);
    expect(find.text('read_file'), findsNothing);
    expect(find.text('bash'), findsNothing);
  });

  testWidgets('tapping the group opens and closes it', (tester) async {
    await tester.pumpWidget(
      testApp(Scaffold(body: BotToolGroup(items: [_tool('read_file'), _tool('bash'), _tool('web_search')]))),
    );
    await tester.tap(find.textContaining('工具'));
    await pumpFrames(tester, 2);
    expect(find.text('read_file'), findsOneWidget);
    await tester.tap(find.textContaining('工具'));
    await pumpFrames(tester, 2);
    expect(find.text('read_file'), findsNothing);
  });
}
