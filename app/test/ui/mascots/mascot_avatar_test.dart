// The mascot renderer's table and its still path: every emotion id has a full
// recipe and draws one frame without a ticker, and every face, character and
// colour renders too.

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/ui/mascots/mascot_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/support/harness.dart' show loadTestFonts, testApp;

void main() {
  setUpAll(loadTestFonts);

  test('every enum label follows the app language', () {
    addTearDown(() => AppLocale.use(AppLocale.zhCN));
    AppLocale.use(AppLocale.zhCN);
    for (final character in MascotCharacter.values) {
      expect(character.label, character.zh);
    }
    for (final face in MascotFace.values) {
      expect(face.label, face.zh);
    }
    for (final motion in MascotMotion.values) {
      expect(motion.label, motion.zh);
    }
    for (final color in MascotColor.values) {
      expect(color.label, color.zh);
    }

    AppLocale.use(AppLocale.en);
    for (final character in MascotCharacter.values) {
      expect(character.label, character.en);
    }
    for (final face in MascotFace.values) {
      expect(face.label, face.en);
    }
    for (final motion in MascotMotion.values) {
      expect(motion.label, motion.en);
    }
    for (final color in MascotColor.values) {
      expect(color.label, color.en);
    }
  });

  test('every emotion id has a full recipe', () {
    expect(mascotExpressions.length, 40);
    for (var i = 0; i < 40; i++) {
      final id = i.toString().padLeft(2, '0');
      final recipe = mascotExpressions[id];
      expect(recipe, isNotNull, reason: 'missing recipe $id');
      expect(recipe!.eyes, isNotEmpty, reason: 'eyes $id');
      expect(recipe.mouth, isNotEmpty, reason: 'mouth $id');
      expect(recipe.top, isNotEmpty, reason: 'top $id');
      expect(recipe.body, isNotEmpty, reason: 'body $id');
    }
  });

  test('the four effects are all used and no unknown effect appears', () {
    const known = {'hearts', 'sparkles', 'sleep', 'loading'};
    final used = <String>{};
    for (final recipe in mascotExpressions.values) {
      final effect = recipe.effect;
      if (effect != null) used.add(effect);
    }
    expect(used, containsAll(known));
    expect(used.difference(known), isEmpty);
  });

  testWidgets('every emotion id draws a still frame', (tester) async {
    for (var i = 0; i < 40; i++) {
      final id = i.toString().padLeft(2, '0');
      await tester.pumpWidget(testApp(Center(
        child: MascotAvatar(spec: const MascotSpec(), emotion: id, size: 48),
      )));
      expect(tester.takeException(), isNull, reason: 'emotion $id');
    }
  });

  test('there are thirteen characters with distinct names and host colours', () {
    expect(MascotCharacter.values.length, 13);
    expect({for (final character in MascotCharacter.values) character.name}.length, 13);
    expect({for (final character in MascotCharacter.values) character.zh}.length, 13);
    // The host accepts only these colour names; every role's default colour must be one.
    const hostColours = {
      'deepseek', 'blue', 'violet', 'orange', 'green', 'magenta', 'cyan', 'red', 'yellow',
      'brown', 'gray', 'black', 'aurora', 'charcoal', 'graphite', 'rose', 'sky', 'tangerine', 'cobalt',
    };
    for (final character in MascotCharacter.values) {
      expect(hostColours, contains(character.hostColor), reason: character.name);
    }
  });

  test('the fruit roles and the brand pebble are appended after potato with their final colours', () {
    // Order is the save index: existing roles first, the fruits and the pebble
    // only appended. cat and watermelon were removed with the 字团 cut.
    expect([for (final character in MascotCharacter.values.take(9)) character.name],
        ['sprout', 'robot', 'ghost', 'jelly', 'orb', 'star', 'triangle', 'onigiri', 'potato']);
    expect([for (final character in MascotCharacter.values.skip(9)) character.name],
        ['orange', 'pear', 'mango', 'pebble']);

    // body, outline (body × 0.6), accent and the host colour, from the agreed table.
    const table = {
      'orange': (0xFFF5811F, 0xFF934D13, 0xFFFFD7A0, 'orange'),
      'pear': (0xFFC7D96B, 0xFF778240, 0xFFF0EFC9, 'yellow'),
      'mango': (0xFFEFA13F, 0xFF8F6126, 0xFFFFE1A8, 'tangerine'),
      // 银团 = App 图标那颗银灰石，灰度按 brand-icon-source.jpg 取。
      'pebble': (0xFFC9CED5, 0xFF1A2230, 0xFFA8C6DA, 'gray'),
    };
    for (final MapEntry(key: name, value: expected) in table.entries) {
      final character = MascotCharacter.values.firstWhere((character) => character.name == name);
      expect(character.skin.body, Color(expected.$1), reason: '$name body');
      expect(character.skin.ink, Color(expected.$2), reason: '$name outline');
      expect(character.skin.accent, Color(expected.$3), reason: '$name accent');
      expect(character.hostColor, expected.$4, reason: '$name host');
    }
  });

  testWidgets('every character draws every emotion', (tester) async {
    for (final character in MascotCharacter.values) {
      for (var i = 0; i < 40; i++) {
        final id = i.toString().padLeft(2, '0');
        await tester.pumpWidget(testApp(Center(
          child: MascotAvatar(spec: MascotSpec(character: character), emotion: id, size: 32),
        )));
        expect(tester.takeException(), isNull, reason: '${character.name}/$id');
      }
    }
  });

  testWidgets('every character draws in both the flat and the 3D view', (tester) async {
    for (final character in MascotCharacter.values) {
      for (final view in MascotView.values) {
        await tester.pumpWidget(testApp(Center(
          child: MascotAvatar(spec: MascotSpec(character: character, view: view), emotion: '02', size: 40),
        )));
        expect(tester.takeException(), isNull, reason: '${character.name}/${view.name}');
      }
    }
  });

  testWidgets('every face, character and colour renders still', (tester) async {
    for (final character in MascotCharacter.values) {
      for (final face in MascotFace.values) {
        for (final color in MascotColor.values) {
          await tester.pumpWidget(testApp(Center(
            child: MascotAvatar(
              spec: MascotSpec(character: character, face: face, color: color),
              size: 40,
            ),
          )));
          expect(tester.takeException(), isNull, reason: '${character.name}/${face.name}/${color.name}');
        }
      }
    }
  });
}
