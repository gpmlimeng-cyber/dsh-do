// The Bot avatar store's contract: what a stored look means, what a missing or
// broken entry falls back to, that a random look is reproducible and actually
// differs, and that each Host keeps its own entries.

import 'dart:convert';
import 'dart:math';

import 'package:dsh_app/state/bot_avatar_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/ui/mascots/mascot_avatar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(ProviderContainer container) async {
  for (var i = 0; i < 20 && !container.read(botAvatarProvider.notifier).restored; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<ProviderContainer> open() async {
  final container = ProviderContainer();
  container.read(botAvatarProvider);
  await settle(container);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const cat = MascotSpec(
    character: MascotCharacter.cat,
    face: MascotFace.curious,
    motion: MascotMotion.quiet,
    color: MascotColor.moonlight,
    followAppColor: true,
    seed: 123,
  );

  group('serialisation', () {
    test('a mascot survives the JSON round trip', () {
      const config = BotAvatarConfig.mascot(cat);
      final back = BotAvatarConfig.fromJson(jsonDecode(jsonEncode(config.toJson())));
      expect(back, config);
      expect(back.isMascot, isTrue);
      expect(back.mascot, cat);
    });

    test('text, photo and emoji keep their kind', () {
      for (final config in const [BotAvatarConfig.text(), BotAvatarConfig.photo(), BotAvatarConfig.emoji('🙂')]) {
        final back = BotAvatarConfig.fromJson(jsonDecode(jsonEncode(config.toJson())));
        expect(back, config);
      }
    });

    test('missing or unknown entries fall back to the text avatar', () {
      expect(BotAvatarConfig.fromJson(null).kind, BotAvatarKind.text);
      expect(BotAvatarConfig.fromJson(<String, Object?>{}).kind, BotAvatarKind.text);
      expect(BotAvatarConfig.fromJson(<String, Object?>{'kind': 'nope'}).kind, BotAvatarKind.text);
    });

    test('a broken mascot falls back field by field', () {
      final config = BotAvatarConfig.fromJson({
        'kind': 'mascot',
        'mascot': {'character': 'dragon', 'face': 7, 'motion': null, 'color': 'plaid', 'seed': 'x'},
      });
      expect(config.isMascot, isTrue);
      expect(config.mascot!.character, MascotCharacter.sprout);
      expect(config.mascot!.face, MascotFace.gentle);
      expect(config.mascot!.motion, MascotMotion.lively);
      expect(config.mascot!.color, MascotColor.classic);
      expect(config.mascot!.seed, 0);
    });

    test('a mascot whose whole payload is not a map falls back to the defaults', () {
      final config = BotAvatarConfig.fromJson({'kind': 'mascot', 'mascot': 'cat'});
      expect(config.isMascot, isTrue);
      expect(config.mascot, const MascotSpec());
    });
  });

  group('random looks', () {
    test('the same seed gives the same look', () {
      expect(BotAvatarConfig.randomMascot(seed: 7), BotAvatarConfig.randomMascot(seed: 7));
    });

    test('a re-roll never returns the look it was asked to avoid', () {
      final first = BotAvatarConfig.randomMascot(seed: 7).mascot!;
      final next = BotAvatarConfig.randomMascot(seed: 7, avoid: first).mascot!;
      final same = next.character == first.character &&
          next.face == first.face &&
          next.motion == first.motion &&
          next.color == first.color;
      expect(same, isFalse);
    });

    test('the caption names character, colour and motion', () {
      expect(cat.caption, '猫团 · 月光 · 安静');
    });

    test('a random seed is kept so the look can be reproduced', () {
      final spec = MascotSpec.random(Random(5));
      final again = MascotSpec.random(Random(999), seed: spec.seed);
      expect(again, spec);
    });
  });

  group('store', () {
    test('a Bot with no entry has no config and is not "unread"', () async {
      final container = await open();
      addTearDown(container.dispose);
      expect(container.read(botAvatarProvider.notifier).restored, isTrue);
      expect(container.read(botAvatarProvider.notifier).of('b1'), isNull);
      expect(container.read(botAvatarProvider), isEmpty);
    });

    test('a set look is still there on the next launch', () async {
      final first = await open();
      addTearDown(first.dispose);
      await first.read(botAvatarProvider.notifier).set('b1', const BotAvatarConfig.mascot(cat));

      final again = await open();
      addTearDown(again.dispose);
      expect(again.read(botAvatarProvider.notifier).of('b1'), const BotAvatarConfig.mascot(cat));
    });

    test('clearing brings the Bot back to its old avatar', () async {
      final container = await open();
      addTearDown(container.dispose);
      await container.read(botAvatarProvider.notifier).set('b1', const BotAvatarConfig.mascot(cat));
      await container.read(botAvatarProvider.notifier).clear('b1');
      expect(container.read(botAvatarProvider.notifier).of('b1'), isNull);
    });

    test('the same Bot keeps its own look per Host', () async {
      final container = await open();
      addTearDown(container.dispose);
      await container.read(botAvatarProvider.notifier).set('b1', const BotAvatarConfig.emoji('🙂'));

      container.read(activeHostProvider.notifier).select(const HostRef.ssh('second'));
      await settle(container);
      expect(container.read(botAvatarProvider.notifier).of('b1'), isNull);
      await container.read(botAvatarProvider.notifier).set('b1', const BotAvatarConfig.text());

      container.read(activeHostProvider.notifier).select(HostRef.local);
      await settle(container);
      expect(container.read(botAvatarProvider.notifier).of('b1'), const BotAvatarConfig.emoji('🙂'));
    });

    test('one Host keeps at most 200 entries, dropping the oldest', () async {
      final container = await open();
      addTearDown(container.dispose);
      final store = container.read(botAvatarProvider.notifier);
      for (var i = 0; i < BotAvatarStore.maxPerHost + 1; i++) {
        await store.set('bot$i', const BotAvatarConfig.emoji('🙂'));
      }
      expect(container.read(botAvatarProvider).length, BotAvatarStore.maxPerHost);
      expect(store.of('bot0'), isNull);
      expect(store.of('bot${BotAvatarStore.maxPerHost}'), isNotNull);
    });
  });
}
