// The single chat page's light look: the leading key goes back to the messages
// list instead of opening the professional conversation drawer, and a part
// divider carries the light wording. Pumped on its own page, since that is the
// surface the user sees.

import 'package:dsh_app/ui/bots/bot_chat_kit.dart';
import 'package:dsh_app/ui/bots/bot_chat_page.dart';
import 'package:dsh_app/ui/im/im_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bots/support.dart' show dsBotOverrides;
import '../../chat/support/harness.dart' show loadTestFonts, usePhoneView;
import '../../shell/golden_harness.dart' show goldenApp;
import 'support/im_fixtures.dart';

Future<void> frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('light leading goes back to the messages list', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    usePhoneView(tester);
    await tester.pumpWidget(goldenApp(
      brightness: Brightness.light,
      home: const BotChatPage(botId: 'b2', look: BotChatLook.light),
      overrides: dsBotOverrides(dividerTransport()),
    ));
    await frames(tester);
    // The leading key is a rounded key with a Semantics label, not a Tooltip.
    expect(find.bySemanticsLabel(ImStrings.backToMessages), findsOneWidget);
  });

  testWidgets('light draws the light wording on a part boundary', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(goldenApp(
      brightness: Brightness.light,
      home: const BotChatPage(botId: 'b2', look: BotChatLook.light),
      overrides: dsBotOverrides(dividerTransport()),
    ));
    await frames(tester);
    // The divider row is a rich text (its icon is a WidgetSpan), so match inside it.
    expect(find.textContaining(ImStrings.segmentDivider, findRichText: true), findsOneWidget);
  });
}
