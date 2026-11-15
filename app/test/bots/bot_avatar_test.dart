// A Bot without a photo or a saved look draws 字团: the mascot's body with the
// name's first letter where the face would be. The old circle monogram stays
// only for a member that has no Bot (bot_chat_kit), never for kind=text.

import 'package:dsh_app/state/bot_avatar_state.dart';
import 'package:dsh_app/ui/bots/bot_avatar.dart';
import 'package:dsh_app/ui/mascots/mascot_letter_avatar.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart' show loadTestFonts, testApp;
import 'support.dart' show FakeDsBotTransport, dsBotOverrides;

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a Bot without a look draws the letter mascot, not the old circle', (tester) async {
    const bot = DsBot(id: 'b2', name: 'Writer', role: '写手');
    await tester.pumpWidget(testApp(const Center(child: BotAvatar(bot: bot, size: 48))));
    final letter = tester.widget<MascotLetterAvatar>(find.byType(MascotLetterAvatar));
    expect(letter.letter, 'W');
    expect(letter.size, 48);
    expect(find.byType(BotMonogram), findsNothing);
  });

  testWidgets('the same Bot gets the same body every time', (tester) async {
    const bot = DsBot(id: 'b2', name: 'Writer');
    await tester.pumpWidget(testApp(const Center(child: BotAvatar(bot: bot, size: 48))));
    final first = tester.widget<MascotLetterAvatar>(find.byType(MascotLetterAvatar)).spec;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(const Center(child: BotAvatar(bot: bot, size: 48))));
    final second = tester.widget<MascotLetterAvatar>(find.byType(MascotLetterAvatar)).spec;
    expect(second, first);
  });

  testWidgets('the letter mascot draws at list, chat and profile sizes', (tester) async {
    for (final size in [40.0, 56.0, 96.0]) {
      await tester.pumpWidget(testApp(Center(
        child: BotAvatar(bot: const DsBot(id: 'b2', name: '测试'), size: size),
      )));
      expect(tester.takeException(), isNull, reason: 'size $size');
      final widget = tester.widget<MascotLetterAvatar>(find.byType(MascotLetterAvatar));
      expect(widget.size, size);
      expect(widget.letter, '测');
    }
  });

  testWidgets('an explicit 字团 choice wins over the host photo', (tester) async {
    const bot = DsBot(id: 'b3', name: 'Coder', imageRef: 'abc123');
    await tester.pumpWidget(testApp(
      const Center(child: BotAvatar(bot: bot, size: 48)),
      overrides: [
        botAvatarProvider.overrideWith(_TextLookStore.new),
        ...dsBotOverrides(FakeDsBotTransport()),
      ],
    ));
    await tester.pump();
    expect(find.byType(MascotLetterAvatar), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('an emoji name keeps the whole grapheme as the letter', (tester) async {
    await tester.pumpWidget(testApp(const Center(
      child: BotAvatar(bot: DsBot(id: 'b3', name: '👨‍👩‍👧'), size: 48),
    )));
    expect(tester.widget<MascotLetterAvatar>(find.byType(MascotLetterAvatar)).letter, '👨‍👩‍👧');
  });
}

/// A store that says 「this Bot uses 字团」 regardless of what is saved.
class _TextLookStore extends BotAvatarStore {
  @override
  Map<String, BotAvatarConfig> build() => const {'b3': BotAvatarConfig.text()};
}
