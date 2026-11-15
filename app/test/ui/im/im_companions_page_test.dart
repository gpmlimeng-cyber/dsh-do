// The partners tab in P0: one contact row per Bot — the row opens the profile,
// only its message key opens the timeline — the two states it draws, and the
// empty state that offers creating a Bot.

import 'package:dsh_app/ui/bots/bot_avatar.dart';
import 'package:dsh_app/ui/bots/new_bot_page.dart';
import 'package:dsh_app/ui/im/im_bot_profile_page.dart';
import 'package:dsh_app/ui/im/im_companions_page.dart';
import 'package:dsh_app/ui/im/im_partner_templates.dart';
import 'package:dsh_app/ui/im/im_strings.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bots/support.dart' show FakeDsBotTransport, dsBotOverrides, sampleTeam;
import '../../chat/support/harness.dart' show loadTestFonts, testApp, usePhoneView;
import 'support/im_fixtures.dart';

Future<void> frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, FakeDsBotTransport transport, {ValueChanged<String>? onOpenBot}) async {
    usePhoneView(tester);
    await tester.pumpWidget(testApp(
      ImCompanionsPage(onOpenBot: onOpenBot ?? (_) {}),
      overrides: dsBotOverrides(transport),
    ));
    await frames(tester);
  }

  test('the waiting fixture really carries a question for b2', () {
    final state = approvalAndWorkTransport().handlers['state']!(<String, Object?>{}) as Map<String, Object?>;
    final team = DsBotTeam.fromJson(state);
    final bot = team.bot('b2')!;
    expect(team.questionOf(bot), isNotNull);
    expect(team.questions, isNotEmpty);
  });

  testWidgets('every Bot gets one contact row with a 56 avatar', (tester) async {
    await open(tester, FakeDsBotTransport());
    for (final name in ['Chief', 'Writer', 'Coder']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    final avatars = tester.widgetList<BotAvatar>(find.byType(BotAvatar));
    expect(avatars.every((avatar) => avatar.size == 56), isTrue);
  });

  testWidgets('tapping a row opens the profile, not the timeline', (tester) async {
    String? opened;
    await open(tester, FakeDsBotTransport(), onOpenBot: (id) => opened = id);
    await tester.tap(find.text('Chief'));
    await frames(tester);
    expect(find.byType(ImBotProfilePage), findsOneWidget);
    final avatar = find.byKey(const ValueKey('im-profile-avatar'));
    expect(avatar, findsOneWidget);
    final face = tester.widget<BotAvatar>(
      find.descendant(of: avatar, matching: find.byType(BotAvatar)),
    );
    expect(face.size, 112);
    expect(face.animate, isTrue, reason: 'the profile face animates');
    expect(opened, isNull);
  });

  testWidgets('the message key opens the timeline', (tester) async {
    String? opened;
    await open(tester, FakeDsBotTransport(), onOpenBot: (id) => opened = id);
    await tester.tap(find.byKey(const ValueKey('companion-message-b2')));
    await frames(tester);
    expect(opened, 'b2');
    expect(find.byType(ImBotProfilePage), findsNothing);
  });

  // 三种状态各用一个 testWidgets：同一个测试里连续 pumpWidget 会复用
  // ProviderScope，Riverpod 只在容器创建时捕获 override，第二次的 transport
  // 读不到。
  testWidgets('a working Bot row says it is busy', (tester) async {
    await open(tester, FakeDsBotTransport());
    expect(find.text(ImStrings.companionBusy), findsOneWidget);
  });

  testWidgets('waiting beats busy for the same Bot', (tester) async {
    await open(tester, approvalAndWorkTransport());
    expect(find.text(ImStrings.companionWaiting), findsOneWidget);
    expect(find.text(ImStrings.companionBusy), findsNothing);
  });

  testWidgets('an idle Bot shows no status text', (tester) async {
    await open(tester, FakeDsBotTransport(team: sampleTeam(working: false)));
    expect(find.text(ImStrings.companionWaiting), findsNothing);
    expect(find.text(ImStrings.companionBusy), findsNothing);
  });

  testWidgets('no Bot offers the create entry', (tester) async {
    await open(tester, emptyTeamTransport());
    expect(find.text(ImStrings.emptyBotsTitle), findsOneWidget);
    await tester.tap(find.text(ImStrings.emptyBotsCreate));
    await frames(tester);
    expect(find.byType(NewBotPage), findsOneWidget);
  });

  testWidgets('the template strip comes after the last Bot row', (tester) async {
    await open(tester, FakeDsBotTransport());
    final card = find.byKey(ValueKey('template-card-${featuredPartnerTemplates.first.id}'));
    expect(card, findsOneWidget, reason: '模板横滑区应该在页面上');
    // Coder 是示例团队里最后一个伙伴，模板区要整体落在它下面。
    final lastRowBottom = tester.getBottomLeft(find.text('Coder')).dy;
    final stripTop = tester.getTopLeft(card).dy;
    expect(stripTop, greaterThan(lastRowBottom), reason: '模板区要移到伙伴列表之后，不在顶部');
  });
}
