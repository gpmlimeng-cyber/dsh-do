// 资料卡的「想多久再回」：有档位的模型才出现这一行，选完写回 bot.effort，
// 失败时抽屉不关、给提示。

import 'package:dsh_app/ui/im/im_bot_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bots/support.dart' show FakeDsBotTransport, dsBotOverrides, sampleTeam;
import '../../chat/support/harness.dart' show loadTestFonts, testApp, usePhoneView;

Future<void> frames(WidgetTester tester, [int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 示例团队里 b2 换成指定模型（默认 `deepseek/deepseek-v4-pro`）。
Map<String, Object?> teamWithModel(String model, {String? effort}) {
  final team = sampleTeam();
  final bots = (team['bots']! as List).cast<Map<String, Object?>>();
  final b2 = bots.firstWhere((bot) => bot['id'] == 'b2');
  b2['model'] = model;
  if (effort != null) b2['effort'] = effort;
  return team;
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, FakeDsBotTransport fake) async {
    usePhoneView(tester);
    await tester.pumpWidget(testApp(
      const ImBotProfilePage(botId: 'b2'),
      // dsBotOverrides 自带 testCatalog（deepseek-v4-pro 有 off/low/high/max）。
      overrides: dsBotOverrides(fake),
    ));
    await frames(tester);
  }

  testWidgets('a model with thinking levels shows the row and its current tier', (tester) async {
    await open(tester, FakeDsBotTransport(team: teamWithModel('deepseek/deepseek-v4-pro')));
    expect(find.text('想多久再回'), findsOneWidget);
    // 没存 effort 就是「看情况」。
    expect(find.textContaining('看情况'), findsOneWidget);
  });

  testWidgets('a stored effort shows its tier, not the id', (tester) async {
    await open(tester, FakeDsBotTransport(team: teamWithModel('deepseek/deepseek-v4-pro', effort: 'high')));
    expect(find.textContaining('多想想'), findsOneWidget);
    expect(find.textContaining('high'), findsNothing, reason: '不露档位 id');
  });

  testWidgets('a model without thinking levels hides the row', (tester) async {
    await open(tester, FakeDsBotTransport(team: teamWithModel('deepseek/plain')));
    expect(find.text('想多久再回'), findsNothing);
  });

  testWidgets('picking 多想想 writes effort high and closes', (tester) async {
    final fake = FakeDsBotTransport(team: teamWithModel('deepseek/deepseek-v4-pro'));
    fake.handlers['update-bot'] = (_) => true;
    await open(tester, fake);

    await tester.tap(find.text('想多久再回'));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('reply-pace-thoughtful')));
    await frames(tester);

    final call = fake.calls.firstWhere((entry) => entry.$1 == 'update-bot');
    expect(call.$2['id'], 'b2');
    expect(call.$2['effort'], 'high');
    expect(find.byKey(const ValueKey('reply-pace-thoughtful')), findsNothing, reason: '成功后抽屉关闭');
  });

  testWidgets('看情况 with nothing stored sends no request', (tester) async {
    final fake = FakeDsBotTransport(team: teamWithModel('deepseek/deepseek-v4-pro'));
    fake.handlers['update-bot'] = (_) => true;
    await open(tester, fake);

    await tester.tap(find.text('想多久再回'));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('reply-pace-adaptive')));
    await frames(tester);

    expect(fake.calls.where((entry) => entry.$1 == 'update-bot'), isEmpty);
  });

  testWidgets('a failed save keeps the sheet open and shows the snackbar', (tester) async {
    final fake = FakeDsBotTransport(team: teamWithModel('deepseek/deepseek-v4-pro'));
    fake.handlers['update-bot'] = (_) => throw StateError('boom');
    await open(tester, fake);

    await tester.tap(find.text('想多久再回'));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('reply-pace-deep')));
    await frames(tester);

    expect(find.byKey(const ValueKey('reply-pace-deep')), findsOneWidget, reason: '失败不关抽屉，可重试');
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
