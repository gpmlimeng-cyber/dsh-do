// Measured checks for a brand lockup (`BrandLockup`), shared by the drawer, the
// share card and the brand tests: the glyph's visual centre on the word's
// x-height centre (cap-height centre for capitals), measured on the ink of the
// font actually drawn; the glyph's height and the gap fixed shares of the word's
// drawn size, the same in every lockup.

import 'dart:ui' as ui;

import 'package:dsh_app/ui/shell/brand_mark.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show MediaQuery;
import 'package:flutter_test/flutter_test.dart';

/// Top and bottom of [char]'s ink, from the top of its line box, drawn in
/// [style] with [scaler] (rendered at 8× and read at half coverage). Any word in
/// the same style puts its glyphs on the same baseline in its box, so this is
/// the band the word's lowercase (or capitals) occupy on screen.
Future<(double, double, double)> inkBand(WidgetTester tester, TextStyle style, TextScaler scaler, String char) async {
  const k = 8.0;
  final painter = TextPainter(
    text: TextSpan(
      text: char,
      style: style.copyWith(color: const Color(0xFF000000)),
    ),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  final w = (painter.width * k).ceil();
  final h = (painter.height * k).ceil();
  // 这个字自己那一行的行框高：整词的行框可能因为它回退到了别的字体而更高，
  // 两者的行框顶不是同一个原点。
  final lineHeight = painter.height;
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder)..scale(k), Offset.zero);
  painter.dispose();
  final picture = recorder.endRecording();
  final data = await tester.runAsync(() async {
    final image = await picture.toImage(w, h);
    final bytes = await image.toByteData();
    image.dispose();
    return bytes;
  });
  picture.dispose();
  final bytes = data!.buffer.asUint8List();
  bool inked(int y) {
    for (var x = 0; x < w; x++) {
      if (bytes[(y * w + x) * 4 + 3] >= 128) return true;
    }
    return false;
  }

  var top = 0;
  while (top < h && !inked(top)) {
    top++;
  }
  var bottom = h - 1;
  while (bottom > top && !inked(bottom)) {
    bottom--;
  }
  if (top >= h) throw StateError('no ink for $char');
  return (top / k, (bottom + 1) / k, lineHeight);
}

/// The lockup found by [lockup] is built to the rules (see [BrandLockup]).
/// Returns the word's rect.
Future<Rect> expectBrandLockup(WidgetTester tester, Finder lockup) async {
  final label = tester.widget<BrandLockup>(lockup).label;
  final glyph = tester.getRect(find.descendant(of: lockup, matching: find.byType(BrandMark)));
  final wordFinder = find.descendant(of: lockup, matching: find.text(label));
  final word = tester.getRect(wordFinder);
  final paragraph = tester.renderObject<RenderParagraph>(wordFinder);
  final style = (paragraph.text as TextSpan).style!;
  // 锁排自己那层的缩放：外层（抽屉、分享卡）会对锁排单独缩放，段落上报的
  // `textScaler` 不是它——用后者算出来的期望值会比实际画出来的大 1/dy。
  final lockupScaler = MediaQuery.textScalerOf(tester.element(lockup));
  final drawn = lockupScaler.scale(style.fontSize!);
  final lowercase = label.contains(RegExp('[a-z]'));
  final (top, bottom, lineHeight) = await inkBand(tester, style, lockupScaler, lowercase ? 'x' : 'H');
  // 单字的行框与整词的行框不一定同高（整词可能回退到别的字体）；按比例把墨带
  // 落回整词自己的行框，否则差的是行框原点，不是字形。
  final dy = word.height / lineHeight;
  final band = (word.top + top * dy, word.top + bottom * dy);
  final centre = glyph.top + BrandMark.visualCentre.dy * glyph.height;
  printOnFailure(
    '「$label」 band=$band centre=$centre wordHeight=${word.height} lineHeight=$lineHeight dy=$dy',
  );

  expect(
    centre,
    // 3% of the word's size: the band is the test font's, the lockup is built
    // on the system sans' proportions (BrandLockup.xHeight / capHeight).
    closeTo((band.$1 + band.$2) / 2, drawn * 0.03),
    reason: '「$label」: the glyph\'s visual centre on the ${lowercase ? 'x' : 'cap'}-height centre',
  );
  expect(glyph.height, closeTo(drawn * BrandLockup.glyphScale, 0.01), reason: '「$label」: glyph size');
  expect(glyph.width, closeTo(glyph.height * BrandMark.aspect, 0.01));
  expect(word.left - glyph.right, closeTo(drawn * BrandLockup.gapScale, 0.01), reason: '「$label」: gap');
  return word;
}
