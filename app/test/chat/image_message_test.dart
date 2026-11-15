// The shared user bubble's image path: an older host that only counts images
// keeps the 「［图片］」 placeholder. The refs → bytes path (parse `imageRefs`,
// call `image`, cache) gets its own cases once the client lands it.

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/ui/bots/bot_chat_kit.dart';
import 'package:dsh_app/ui/bots/bot_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bots/support.dart' show dsBotOverrides;
import '../shell/golden_harness.dart' show goldenApp;
import 'support/harness.dart' show loadTestFonts, usePhoneView;
import 'support/image_fixtures.dart';

Future<void> frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a counted image with no refs keeps the placeholder', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(goldenApp(
      brightness: Brightness.light,
      home: const BotChatPage(botId: 'b2', look: BotChatLook.light),
      overrides: dsBotOverrides(imageCountOnlyTransport()),
    ));
    await frames(tester);
    final l10n = tester.element(find.byType(BotChatPage)).l10n;
    expect(find.text(l10n.botsImagePlaceholder), findsOneWidget);
  });
}
