// A Bot's face before the mascot exists: no photo and no mascot config keeps the
// text avatar (the initial on the Bot's colour). That is the fallback the mascot
// avatar must keep for old Bots and for hosts that store no avatar config.

import 'package:dsh_app/ui/bots/bot_avatar.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart' show loadTestFonts, testApp;

void main() {
  setUpAll(loadTestFonts);

  testWidgets('a Bot without avatar config keeps its text face', (tester) async {
    const bot = DsBot(id: 'b2', name: 'Writer', role: '写手');
    await tester.pumpWidget(testApp(const Center(child: BotAvatar(bot: bot, size: 48))));
    expect(find.byType(BotMonogram), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
  });

  testWidgets('the text face scales with the asked size', (tester) async {
    const bot = DsBot(id: 'b2', name: 'Writer');
    await tester.pumpWidget(testApp(const Center(child: BotAvatar(bot: bot, size: 96))));
    final face = tester.getSize(find.byType(BotMonogram));
    expect(face, const Size(96, 96));
  });
}
