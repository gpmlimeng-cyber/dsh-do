// 思考一行：同一回合只留最后一条，正文/工具出现或回合结束后收掉。
import 'package:dsh_app/ui/bots/bot_chat_kit.dart';
import 'package:dsh_app/ui/bots/bot_chat_page.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart' show loadTestFonts, usePhoneView;
import '../shell/golden_harness.dart' show goldenApp;
import 'support.dart';

DsBotItem _thinking(int minute) =>
    DsBotItem(kind: DsBotItemKind.thinking, time: DateTime(2026, 1, 1, 10, minute));

DsBotItem _bot(String text, int minute) =>
    DsBotItem(kind: DsBotItemKind.bot, text: text, time: DateTime(2026, 1, 1, 10, minute));

DsBotItem _tool(String name, int minute) => DsBotItem(
  kind: DsBotItemKind.tool,
  toolName: name,
  toolStatus: 'running',
  time: DateTime(2026, 1, 1, 10, minute),
);

Future<void> _frames(WidgetTester tester, [int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the newest thinking stays while the turn runs', () {
    final items = botTranscriptItems([_bot('先说说', 1), _thinking(2)], running: true);
    expect(items.length, 2);
    expect(items.last.kind, DsBotItemKind.thinking);
  });

  test('a finished turn keeps no thinking', () {
    final items = botTranscriptItems([_bot('先说说', 1), _thinking(2)], running: false);
    expect(items.map((item) => item.kind), [DsBotItemKind.bot]);
  });

  test('thinking followed by a reply or a tool row is over', () {
    expect(botTranscriptItems([_thinking(1), _bot('答复', 2)], running: true), hasLength(1));
    expect(botTranscriptItems([_thinking(1), _tool('read_file', 2)], running: true), hasLength(1));
  });

  test('several steps of one turn make one line', () {
    final items = botTranscriptItems(
      [_thinking(1), _tool('read_file', 2), _thinking(3), _tool('bash', 4), _thinking(5)],
      running: true,
    );
    expect(items.where((item) => item.kind == DsBotItemKind.thinking), hasLength(1));
    expect(items.last.kind, DsBotItemKind.thinking);
  });

  test('a history page without a running turn adds nothing', () {
    expect(botTranscriptItems([_bot('旧消息', 1), _thinking(2)], running: false).single.kind, DsBotItemKind.bot);
  });

  testWidgets('a thinking line draws under the Bot name while it runs', (tester) async {
    final fake = FakeDsBotTransport()
      ..chatItems = [
        {'kind': 'bot', 'text': '我来看看', 'time': DateTime(2026, 1, 1, 10).millisecondsSinceEpoch},
        {'kind': 'thinking', 'time': DateTime(2026, 1, 1, 10, 1).millisecondsSinceEpoch},
      ];
    usePhoneView(tester);
    await tester.pumpWidget(
      goldenApp(
        home: const BotChatPage(botId: 'm1'),
        brightness: Brightness.light,
        overrides: dsBotOverrides(fake),
      ),
    );
    await _frames(tester);
    expect(find.byType(BotTypingLine), findsOneWidget);
    expect(find.text('Chief · 正在思考'), findsOneWidget);
  });

  testWidgets('a finished turn draws no thinking line', (tester) async {
    final fake = FakeDsBotTransport(team: sampleTeam(working: false))
      ..chatItems = [
        {'kind': 'bot', 'text': '我来看看', 'time': DateTime(2026, 1, 1, 10).millisecondsSinceEpoch},
        {'kind': 'thinking', 'time': DateTime(2026, 1, 1, 10, 1).millisecondsSinceEpoch},
      ];
    usePhoneView(tester);
    await tester.pumpWidget(
      goldenApp(
        home: const BotChatPage(botId: 'm1'),
        brightness: Brightness.light,
        overrides: dsBotOverrides(fake),
      ),
    );
    await _frames(tester);
    expect(find.byType(BotTypingLine), findsNothing);
  });
}
