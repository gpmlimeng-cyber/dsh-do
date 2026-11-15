// The template path: the featured six, the all-templates page (search and a
// coming-soon row), and creating from a template — the prefill reaches the host
// verbatim and a double tap only creates once.

import 'package:dsh_app/ui/bots/new_bot_page.dart';
import 'package:dsh_app/ui/im/im_partner_templates.dart';
import 'package:dsh_app/ui/im/im_partner_templates_page.dart';
import 'package:dsh_app/ui/im/im_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bots/support.dart' show FakeDsBotTransport, dsBotOverrides;
import '../../chat/support/harness.dart' show loadTestFonts, usePhoneView;
import '../../shell/golden_harness.dart' show goldenApp;

Future<void> frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final featured = featuredPartnerTemplates;
  final reviewer = partnerTemplateOf('grok.pr-reviewer')!;
  final unavailable = partnerTemplates.firstWhere((template) => !template.available);

  test('the home sheet has six featured templates from six categories', () {
    expect(featured.length, 6);
    expect(featured.every((template) => template.available), isTrue);
    expect({for (final template in featured) template.category}.length, 6);
  });

  testWidgets('the all-templates page searches by name', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(goldenApp(home: const ImPartnerTemplatesPage(), brightness: Brightness.light));
    await frames(tester);
    expect(find.text(reviewer.nameZh), findsOneWidget);

    // 只搜名字的一个片段：输入框里出现的是片段，整名只可能来自结果行。
    // （搜整名时输入框自己也带这个词，find.text 会命中两次。）
    final fragment = reviewer.nameZh.substring(0, 2);
    await tester.enterText(find.byKey(const ValueKey('template-search')), fragment);
    await frames(tester);
    expect(find.text(reviewer.nameZh), findsOneWidget);
  });

  testWidgets('a coming-soon template shows the disabled create key', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(goldenApp(
      home: ImPartnerTemplateDetailPage(template: unavailable),
      brightness: Brightness.light,
    ));
    await frames(tester);
    final button = tester.widget<FilledButton>(find.byKey(const ValueKey('template-create')));
    expect(button.onPressed, isNull);
    expect(find.text(ImStrings.templateComingSoon), findsWidgets);
  });

  testWidgets('a template prefills the form and sends its instructions verbatim', (tester) async {
    usePhoneView(tester);
    final fake = FakeDsBotTransport();
    fake.handlers['create-bot'] = (payload) => {'id': 'b9', 'name': payload['name'], 'sessionId': 'b9'};
    await tester.pumpWidget(goldenApp(
      home: NewBotPage(template: reviewer),
      brightness: Brightness.light,
      overrides: dsBotOverrides(fake),
    ));
    await frames(tester);

    await tester.tap(find.byKey(const ValueKey('bot-create')));
    await frames(tester);

    final call = fake.calls.firstWhere((entry) => entry.$1 == 'create-bot');
    expect(call.$2['name'], reviewer.nameZh);
    expect(call.$2['role'], reviewer.role);
    expect(call.$2['instructions'], reviewer.instructions);
  });

  testWidgets('a double tap on create only creates one Bot', (tester) async {
    usePhoneView(tester);
    final fake = FakeDsBotTransport();
    fake.handlers['create-bot'] = (payload) => {'id': 'b9', 'name': payload['name'], 'sessionId': 'b9'};
    await tester.pumpWidget(goldenApp(
      home: NewBotPage(template: reviewer),
      brightness: Brightness.light,
      overrides: dsBotOverrides(fake),
    ));
    await frames(tester);

    await tester.tap(find.byKey(const ValueKey('bot-create')));
    await tester.tap(find.byKey(const ValueKey('bot-create')));
    await frames(tester);
    expect(fake.calls.where((entry) => entry.$1 == 'create-bot').length, 1);
  });
}
