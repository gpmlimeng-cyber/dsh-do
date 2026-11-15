// The mascot renderer's table and its still path: every emotion id has a full
// recipe and draws one frame without a ticker, and every face, character and
// colour renders too.

import 'package:dsh_app/ui/mascots/mascot_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/support/harness.dart' show loadTestFonts, testApp;

void main() {
  setUpAll(loadTestFonts);

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
