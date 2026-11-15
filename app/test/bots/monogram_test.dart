// The letter a text avatar shows: one grapheme cluster, so an emoji — even a
// flag or a family made of several code points — stays whole; Latin is
// upper-cased; a blank name falls back to '?'.

import 'package:dsh_app/ui/bots/bot_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a name keeps one letter', () {
    expect(monogramOf('Writer'), 'W');
    expect(monogramOf('测试'), '测');
    expect(monogramOf('42'), '4');
  });

  test('an emoji is one letter, even a composed one', () {
    expect(monogramOf('😀abc'), '😀');
    expect(monogramOf('🇨🇳'), '🇨🇳');
    expect(monogramOf('👨‍👩‍👧'), '👨‍👩‍👧');
  });

  test('blank names fall back to ?', () {
    expect(monogramOf(''), '?');
    expect(monogramOf('   '), '?');
  });
}
