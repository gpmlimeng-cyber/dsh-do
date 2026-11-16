// 新建 Bot 的默认指令：可视化回复开着才追加一句 dsh-ui 提示；关着不加，
// 用户自己写过 dsh-ui 也不重复加。
import 'package:dsh_app/ui/bots/new_bot_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart' show loadTestFonts, pumpFrames, usePhoneView;
import '../shell/golden_harness.dart' show goldenApp;
import 'support.dart';

void main() {
  setUpAll(loadTestFonts);
/// 创建键在 `_scope` 拿到 api 且 ready 之前是 disabled：点到它什么也不做，
/// 事后只能看到「create-bot 没发出来」。等到它真的可点再点，失败信息也更直接。
Future<void> pumpUntilCreateEnabled(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    final button = tester.widget<FilledButton>(find.byKey(const ValueKey('bot-create')));
    if (button.onPressed != null) return;
  }
  fail('bot-create never became enabled');
}


  test('on: an empty instructions field gets the hint', () {
    final text = newBotInstructions('', visualReplies: true);
    expect(text, isNotNull);
    expect(text, contains('dsh-ui'));
  });

  test('on: the hint follows what the person wrote', () {
    final text = newBotInstructions('画海报', visualReplies: true);
    expect(text, startsWith('画海报'));
    expect(text, contains('dsh-ui'));
  });

  test('on: a person who already said dsh-ui is not told again', () {
    const typed = '回答时用 dsh-ui 出卡片';
    expect(newBotInstructions(typed, visualReplies: true), typed);
  });

  test('off: nothing is added', () {
    expect(newBotInstructions('', visualReplies: false), isNull);
    expect(newBotInstructions('画海报', visualReplies: false), '画海报');
  });

  group('the form follows the setting', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('on: the created Bot carries the hint', (tester) async {
      final fake = FakeDsBotTransport();
      fake.handlers['create-bot'] = (payload) => {'id': 'b9', 'name': payload['name'], 'sessionId': 'b9'};
      usePhoneView(tester);
      await tester.pumpWidget(
        goldenApp(
          home: const NewBotPage(),
          brightness: Brightness.light,
          overrides: [...dsBotOverrides(fake), settingsWith()],
        ),
      );
      await pumpFrames(tester, 8);
      await tester.enterText(find.byKey(const ValueKey('bot-name')), '设计师');
      await pumpUntilCreateEnabled(tester);
      await tester.tap(find.byKey(const ValueKey('bot-create')));
      await pumpFrames(tester, 8);
      final call = fake.calls.firstWhere((c) => c.$1 == 'create-bot');
      expect(call.$2['instructions'], newBotInstructions('', visualReplies: true));
    });

    testWidgets('off: the created Bot is left as typed', (tester) async {
      SharedPreferences.setMockInitialValues({'visual_replies': false});
      final fake = FakeDsBotTransport();
      fake.handlers['create-bot'] = (payload) => {'id': 'b9', 'name': payload['name'], 'sessionId': 'b9'};
      usePhoneView(tester);
      await tester.pumpWidget(
        goldenApp(
          home: const NewBotPage(),
          brightness: Brightness.light,
          overrides: [...dsBotOverrides(fake), settingsWith(visualReplies: false)],
        ),
      );
      await pumpFrames(tester, 8);
      await tester.enterText(find.byKey(const ValueKey('bot-name')), '设计师');
      await pumpUntilCreateEnabled(tester);
      await tester.tap(find.byKey(const ValueKey('bot-create')));
      await pumpFrames(tester, 8);
      final call = fake.calls.firstWhere((c) => c.$1 == 'create-bot');
      expect(call.$2.containsKey('instructions'), isFalse);
    });
  });
}
