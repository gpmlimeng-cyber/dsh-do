// The Bot avatar store's contract: what a stored look means, what a missing or
// broken entry falls back to, how the 12 colour names map, that a random look is
// reproducible and actually differs, and that each Host keeps its own entries.

import 'dart:convert';
import 'dart:math';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/bot_avatar_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/ui/mascots/mascot_avatar.dart';
import 'package:flutter/material.dart';
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

  // A non-default look on every axis, so a dropped field fails a round trip.
  final cat = MascotSpec(
    character: MascotCharacter.cat,
    face: MascotFace.values[1],
    motion: MascotMotion.quiet,
    color: MascotColor.lavender,
    view: MascotView.three,
    outline: false,
    followAppColor: true,
    seed: 123,
  );

  group('serialisation', () {
    test('a mascot survives the JSON round trip', () {
      final config = BotAvatarConfig.mascot(cat);
      final wire = jsonDecode(jsonEncode(config.toJson())) as Map<String, Object?>;
      final look = wire['mascot']! as Map<String, Object?>;
      expect(look['character'], 'cat');
      expect(look['face'], cat.face.wire);
      expect(look['motion'], 'quiet');
      expect(look['color'], 'lavender');
      expect(look['view'], 'three');
      expect(look['outline'], false);

      final back = BotAvatarConfig.fromJson(wire);
      expect(back, config);
      expect(back.isMascot, isTrue);
      expect(back.mascot!.face, cat.face);
      expect(back.mascot!.color, MascotColor.lavender);
      expect(back.mascot!.view, MascotView.three);
      expect(back.mascot!.outline, isFalse);
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
        'mascot': {'character': 'dragon', 'face': 7, 'motion': null, 'color': 'plaid', 'view': '2d', 'seed': 'x'},
      });
      expect(config.isMascot, isTrue);
      expect(config.mascot!.character, MascotCharacter.sprout);
      expect(config.mascot!.face, MascotFace.standard);
      expect(config.mascot!.motion, MascotMotion.lively);
      expect(config.mascot!.color, MascotColor.mint);
      expect(config.mascot!.view, MascotView.three);
      expect(config.mascot!.outline, isFalse);
      expect(config.mascot!.seed, 0);
    });

    test('missing view and outline read as 3D without the outline', () {
      final config = BotAvatarConfig.fromJson({
        'kind': 'mascot',
        'mascot': {'character': 'cat', 'face': 'default', 'color': 'mint'},
      });
      expect(config.mascot!.view, MascotView.three);
      expect(config.mascot!.outline, isFalse);
    });

    test('a mascot whose whole payload is not a map falls back to the defaults', () {
      final config = BotAvatarConfig.fromJson({'kind': 'mascot', 'mascot': 'cat'});
      expect(config.isMascot, isTrue);
      expect(config.mascot, const MascotSpec());
    });
  });

  group('old saves', () {
    test('the old face names read as the default face', () {
      for (final old in ['gentle', 'curious', 'happy']) {
        final config = BotAvatarConfig.fromJson({
          'kind': 'mascot',
          'mascot': {'face': old},
        });
        expect(config.mascot!.face, MascotFace.standard, reason: 'old face "$old"');
      }
    });

    test('the old colour names map to their nearest preset', () {
      const mapping = {
        'classic': MascotColor.peach,
        'matcha': MascotColor.mint,
        'sakura': MascotColor.rose,
        'moonlight': MascotColor.lavender,
        'seasalt': MascotColor.paleCyan,
        'inkJade': MascotColor.charcoal,
      };
      for (final MapEntry(key: old, value: expected) in mapping.entries) {
        final config = BotAvatarConfig.fromJson({
          'kind': 'mascot',
          'mascot': {'color': old},
        });
        expect(config.mascot!.color, expected, reason: 'old colour "$old"');
      }
    });
  });

  group('colours', () {
    test('there are 11 presets plus the model default', () {
      expect(MascotColor.values.length, 12);
      expect(MascotColor.values, contains(MascotColor.model));
      expect(MascotColor.values.where((color) => color != MascotColor.model).length, 11);
    });

    test('every colour name survives the spec JSON round trip', () {
      for (final color in MascotColor.values) {
        final spec = MascotSpec(color: color);
        final wire = jsonDecode(jsonEncode(spec.toJson())) as Map<String, Object?>;
        expect(wire['color'], color.name);
        expect(MascotSpec.fromJson(wire).color, color);
      }
    });

    test('the preset hex values are the demo ones', () {
      expect(MascotColor.mint.ink, const Color(0xFF48FF42));
      expect(MascotColor.paleCyan.ink, const Color(0xFFBDEEF2));
      expect(MascotColor.charcoal.ink, const Color(0xFF3D4852));
      expect(MascotColor.berry.ink, const Color(0xFFF29CC2));
    });

    test('the model default draws each character\'s own skin', () {
      for (final character in MascotCharacter.values) {
        final skin = mascotSkinOf(
          MascotSpec(character: character, color: MascotColor.model),
          const ColorScheme.light(),
        );
        expect(skin.body, character.skin.body, reason: character.name);
      }
    });

    test('bot.color names stay inside the host whitelist', () {
      const presets = {
        MascotColor.mint: 'green',
        MascotColor.sky: 'sky',
        MascotColor.peach: 'tangerine',
        MascotColor.lavender: 'violet',
        MascotColor.rose: 'rose',
        MascotColor.lemon: 'yellow',
        MascotColor.charcoal: 'graphite',
        MascotColor.cream: 'gray',
        MascotColor.steel: 'cobalt',
        MascotColor.paleCyan: 'cyan',
        MascotColor.berry: 'magenta',
      };
      for (final MapEntry(key: color, value: name) in presets.entries) {
        expect(hostColorOf(MascotSpec(color: color)), name);
      }
      const models = {
        MascotCharacter.sprout: 'green',
        MascotCharacter.cat: 'charcoal',
        MascotCharacter.robot: 'gray',
        MascotCharacter.ghost: 'cyan',
        MascotCharacter.jelly: 'rose',
      };
      for (final MapEntry(key: character, value: name) in models.entries) {
        expect(hostColorOf(MascotSpec(character: character, color: MascotColor.model)), name);
      }
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

    test('randomDifferent changes the character and colour and keeps the rest', () {
      final before = cat;
      final next = MascotSpec.randomDifferent(before, Random(7));
      expect(next.character, isNot(before.character));
      expect(next.color, isNot(before.color));
      expect(next.face, before.face);
      expect(next.view, before.view);
      expect(next.outline, before.outline);
      expect(next.followAppColor, before.followAppColor);
    });


    test('a random seed is kept so the look can be reproduced', () {
      final spec = MascotSpec.random(Random(5));
      final again = MascotSpec.random(Random(999), seed: spec.seed);
      expect(again, spec);
    });
  });

  group('motion presets', () {
    test('each preset expands to its body, eyes and mouth', () {
      expect(motionPreset(MascotMotion.lively), (body: 'bounce', eyes: 'happy', mouth: 'smile'));
      expect(motionPreset(MascotMotion.quiet), (body: 'breathe', eyes: 'open', mouth: 'flat'));
      expect(motionPreset(MascotMotion.curious), (body: 'work', eyes: 'wide', mouth: 'open'));
    });

    test('an old blink or motion value reads without breaking', () {
      expect(MascotSpec.fromJson(const <String, Object?>{}).blink, isTrue);
      expect(MascotSpec.fromJson({'blink': false}).blink, isFalse);
      // Old saves may still carry custom motion values; reading them must not throw.
      final old = MascotSpec.fromJson({'body': 'bounce', 'eyes': 'happy', 'mouth': 'smile', 'blink': false});
      expect(old.blink, isFalse);
    });

    test('the caption is 角色 · 颜色 · 表情 in both languages', () {
      addTearDown(() => AppLocale.use(AppLocale.zhCN));
      AppLocale.use(AppLocale.zhCN);
      expect(cat.caption,
          '${MascotCharacter.cat.zh} · ${MascotColor.lavender.zh} · ${cat.face.zh}·${cat.motion.zh}');

      AppLocale.use(AppLocale.en);
      expect(cat.caption,
          '${MascotCharacter.cat.en} · ${MascotColor.lavender.en} · ${cat.face.en}·${cat.motion.en}');
      // No Chinese left in the English caption (G7).
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(cat.caption), isFalse);
    });

    test('a preset caption follows the app language too', () {
      addTearDown(() => AppLocale.use(AppLocale.zhCN));
      final preset = MascotSpec(character: MascotCharacter.sprout, color: MascotColor.mint);
      AppLocale.use(AppLocale.en);
      expect(preset.caption,
          '${MascotCharacter.sprout.en} · ${MascotColor.mint.en} · ${MascotFace.standard.en}·${MascotMotion.lively.en}');
      AppLocale.use(AppLocale.zhCN);
      expect(preset.caption,
          '${MascotCharacter.sprout.zh} · ${MascotColor.mint.zh} · ${MascotFace.standard.zh}·${MascotMotion.lively.zh}');
    });
  });

  group('letter mascot', () {
    test('the seed is stable FNV-1a', () {
      expect(stableSeedOf('b1'), 2351703228);
      expect(stableSeedOf('猫团'), 1725553031);
      expect(stableSeedOf('b1'), stableSeedOf('b1'));
    });

    test('a Bot without a look derives one from its id', () {
      // The character pool grows with the enum, so b1's derived body changes when a
      // role is added; every other Bot keeps its id-derived stability.
      final seed = stableSeedOf('b1');
      final colors = [for (final color in MascotColor.values) if (color != MascotColor.model) color];
      final derived = letterMascotOf(null, 'b1');
      expect(derived.character, MascotCharacter.values[seed % MascotCharacter.values.length]);
      expect(derived.color, colors[(seed ~/ 7) % colors.length]);
      expect(derived.motion, MascotMotion.values[(seed ~/ 13) % MascotMotion.values.length]);
      expect(letterMascotOf(null, 'b1'), derived);
    });

    test('the ten-role derivation table is stable', () {
      // Indices follow the enum order (new roles appended after jelly); the colour
      // pool is the 11 presets, model excluded, and motion is the 3 presets.
      final colors = [for (final color in MascotColor.values) if (color != MascotColor.model) color];
      const table = [
        ('b1', 8, 4, 2),
        ('b3', 6, 7, 1),
        ('bot-1', 2, 1, 2),
        ('猫团', 1, 6, 1),
      ];
      for (final (id, character, color, motion) in table) {
        final derived = letterMascotOf(null, id);
        expect(derived.character, MascotCharacter.values[character], reason: '$id character');
        expect(derived.color, colors[color], reason: '$id colour');
        expect(derived.motion, MascotMotion.values[motion], reason: '$id motion');
      }
    });

    test('different Bots do not all get the same body', () {
      final looks = {for (final id in ['a', 'b', 'c', 'd', 'e']) letterMascotOf(null, id)};
      expect(looks.length, greaterThan(1));
    });

    test('a text config with a body keeps that body', () {
      final config = BotAvatarConfig.text(cat);
      expect(letterMascotOf(config, 'b1'), cat);
    });

    test('the kept body survives the JSON round trip', () {
      final config = BotAvatarConfig.text(cat);
      final wire = jsonDecode(jsonEncode(config.toJson())) as Map<String, Object?>;
      expect(wire['kind'], 'text');
      expect(wire['mascot'], isNotNull);
      final back = BotAvatarConfig.fromJson(wire);
      expect(back, config);
      expect(back.kind, BotAvatarKind.text);
      expect(back.mascot, cat);
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
      await first.read(botAvatarProvider.notifier).set('b1', BotAvatarConfig.mascot(cat));

      final again = await open();
      addTearDown(again.dispose);
      expect(again.read(botAvatarProvider.notifier).of('b1'), BotAvatarConfig.mascot(cat));
    });

    test('clearing brings the Bot back to its old avatar', () async {
      final container = await open();
      addTearDown(container.dispose);
      await container.read(botAvatarProvider.notifier).set('b1', BotAvatarConfig.mascot(cat));
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
