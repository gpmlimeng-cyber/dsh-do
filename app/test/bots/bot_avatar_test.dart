// A Bot without a photo or a saved look now draws a mascot derived from its id
// (role / colour / motion from the seed) — 字团 went away. Old `kind=text`
// archives still draw the letter mascot; nothing new picks it.

import 'package:dsh_app/state/bot_avatar_state.dart';
import 'package:dsh_app/ui/bots/bot_avatar.dart';
import 'package:dsh_app/ui/mascots/mascot_avatar.dart';
import 'package:dsh_app/ui/mascots/mascot_letter_avatar.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart' show loadTestFonts, testApp;
import 'support.dart' show FakeDsBotTransport, dsBotOverrides;

/// 没配置时的派生角色：seed 对角色池（12）取模。颜色池和动作档同一条 seed。
MascotCharacter derivedCharacterOf(String botId) =>
    MascotCharacter.values[stableSeedOf(botId) % MascotCharacter.values.length];

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a Bot without a look draws a derived mascot, not 字团', (tester) async {
    const bot = DsBot(id: 'b2', name: 'Writer', role: '写手');
    await tester.pumpWidget(testApp(const Center(child: BotAvatar(bot: bot, size: 48))));
    final face = tester.widget<MascotAvatar>(find.byType(MascotAvatar));
    expect(face.size, 48);
    expect(face.spec.character, derivedCharacterOf('b2'));
    expect(find.byType(MascotLetterAvatar), findsNothing, reason: '字团不再是兜底');
    expect(find.byType(BotMonogram), findsNothing);
  });

  testWidgets('the same Bot gets the same look every time', (tester) async {
    const bot = DsBot(id: 'b2', name: 'Writer');
    await tester.pumpWidget(testApp(const Center(child: BotAvatar(bot: bot, size: 48))));
    final first = tester.widget<MascotAvatar>(find.byType(MascotAvatar)).spec;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(const Center(child: BotAvatar(bot: bot, size: 48))));
    final second = tester.widget<MascotAvatar>(find.byType(MascotAvatar)).spec;
    expect(second, first);
  });

  testWidgets('two Bots get different looks, and the look is not random', (tester) async {
    final specs = <String, MascotSpec>{};
    for (final id in ['b1', 'b2', 'b3', 'b4', 'b5']) {
      await tester.pumpWidget(testApp(Center(child: BotAvatar(bot: DsBot(id: id, name: id), size: 40))));
      specs[id] = tester.widget<MascotAvatar>(find.byType(MascotAvatar)).spec;
    }
    expect(specs.values.toSet().length, greaterThan(1));
    for (final id in ['b1', 'b2', 'b3']) {
      expect(specs[id]!.character, derivedCharacterOf(id), reason: id);
    }
  });

  testWidgets('the derived mascot draws at list, chat and profile sizes', (tester) async {
    for (final size in [40.0, 56.0, 96.0]) {
      await tester.pumpWidget(testApp(Center(
        child: BotAvatar(bot: const DsBot(id: 'b2', name: '测试'), size: size),
      )));
      expect(tester.takeException(), isNull, reason: 'size $size');
      expect(tester.widget<MascotAvatar>(find.byType(MascotAvatar)).size, size);
    }
  });

  testWidgets('an old 字团 archive still draws the letter mascot, even over a photo', (tester) async {
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
    // 字团 is a mascot body with the name's letter where the face would be.
    expect(tester.widget<MascotAvatar>(find.byType(MascotAvatar)).letter, 'C');
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('an old 字团 archive keeps the whole grapheme as the letter', (tester) async {
    await tester.pumpWidget(testApp(
      const Center(child: BotAvatar(bot: DsBot(id: 'b3', name: '👨‍👩‍👧'), size: 48)),
      overrides: [botAvatarProvider.overrideWith(_TextLookStore.new)],
    ));
    await tester.pump();
    expect(tester.widget<MascotLetterAvatar>(find.byType(MascotLetterAvatar)).letter, '👨‍👩‍👧');
  });
}

/// A store that says 「this Bot still uses 字团」, like an archive saved before it went away.
class _TextLookStore extends BotAvatarStore {
  @override
  Map<String, BotAvatarConfig> build() => const {'b3': BotAvatarConfig.text()};
}
