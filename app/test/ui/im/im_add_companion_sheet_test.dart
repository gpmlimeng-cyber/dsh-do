// 伙伴页「+」打开的高抽屉（Miffan 那种）：高度够高，已添加的行不可点，
// 点「添加」进的是预填好的新建页——不直接建 Bot。

import 'package:dsh_app/ui/bots/new_bot_page.dart';
import 'package:dsh_app/ui/common/sheet_title_bar.dart';
import 'package:dsh_app/ui/im/im_companions_page.dart';
import 'package:dsh_app/ui/im/im_partner_templates.dart';
import 'package:dsh_app/ui/im/im_partner_templates_page.dart' show templateName;
import 'package:dsh_app/ui/im/im_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bots/support.dart' show FakeDsBotTransport, dsBotOverrides, sampleTeam;
import '../../chat/support/harness.dart' show loadTestFonts, testApp, usePhoneView;

Future<void> frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 团队里有一个 Bot 就叫这个模板的名字（中文名），用来造「已添加」。
Map<String, Object?> teamWithBotNamed(PartnerTemplate template) {
  final team = sampleTeam();
  final bots = (team['bots']! as List).cast<Map<String, Object?>>();
  bots.first['name'] = template.nameZh;
  return team;
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openDrawer(WidgetTester tester, FakeDsBotTransport fake) async {
    usePhoneView(tester);
    await tester.pumpWidget(testApp(
      ImCompanionsPage(onOpenBot: (_) {}),
      overrides: dsBotOverrides(fake),
    ));
    await frames(tester);
    await tester.tap(find.byTooltip(ImStrings.newBot));
    await frames(tester);
  }

  testWidgets('the add sheet is at least 80% of the screen tall', (tester) async {
    await openDrawer(tester, FakeDsBotTransport());
    expect(find.text(ImStrings.addCompanion), findsOneWidget);
    expect(find.text(ImStrings.templateStart), findsOneWidget);

    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final boxes = tester.widgetList<SizedBox>(
      find.ancestor(of: find.byType(SheetTitleBar), matching: find.byType(SizedBox)),
    );
    final tall = boxes.where((box) => (box.height ?? 0) >= screenHeight * 0.8).toList();
    expect(tall, isNotEmpty, reason: '抽屉高度要 ≥ 屏高 80%，现在的实现是 heightFactor: 0.86');
    expect(
      tester.getRect(find.byWidget(tall.first)).height,
      greaterThanOrEqualTo(screenHeight * 0.8),
    );
  });

  testWidgets('a template already in the team shows 已添加 and its row does nothing', (tester) async {
    final added = featuredPartnerTemplates.first;
    await openDrawer(tester, FakeDsBotTransport(team: teamWithBotNamed(added)));

    final row = find.byKey(ValueKey('template-add-${added.id}'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text(ImStrings.templateAdded)), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text(ImStrings.templateAdd)), findsNothing);

    await tester.tap(row);
    await frames(tester);
    // 抽屉还在，也没进新建页。
    expect(find.text(ImStrings.addCompanion), findsOneWidget);
    expect(find.byType(NewBotPage), findsNothing);
  });

  testWidgets('tapping 添加 opens the new-Bot page prefilled, and creates nothing yet', (tester) async {
    final template = featuredPartnerTemplates.elementAt(1);
    final fake = FakeDsBotTransport();
    await openDrawer(tester, fake);

    final row = find.byKey(ValueKey('template-add-${template.id}'));
    await tester.tap(find.descendant(of: row, matching: find.text(ImStrings.templateAdd)));
    await frames(tester);

    expect(find.byType(NewBotPage), findsOneWidget);
    expect(fake.calls.where((call) => call.$1 == 'create-bot'), isEmpty, reason: '选模板只预填，不直接建');

    String textOf(String key) =>
        tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
    expect(textOf('bot-name'), templateName(template));
    expect(textOf('bot-role'), template.role);
    expect(textOf('bot-instructions'), template.instructions);
  });
}
