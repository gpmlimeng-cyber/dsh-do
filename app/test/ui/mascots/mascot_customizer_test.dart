// The customizer's preview is live: every pick rebuilds the preview's spec on
// the same frame, and the preview animates while the person picks. The caption
// is 角色 · 颜色 · 表情 (五官·动作), or 「自定义」 once the action is customised.

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/ui/mascots/mascot_avatar.dart';
import 'package:dsh_app/ui/mascots/mascot_customizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/support/harness.dart' show loadTestFonts, testApp, usePhoneView;

void main() {
  setUpAll(loadTestFonts);

  testWidgets('the colour tab shows all twelve options', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(testApp(const MascotCustomizer(initial: MascotSpec())));
    await tester.pump();
    await tester.tap(find.text('颜色'));
    await tester.pump();
    final grid = find.byType(GridView);
    expect(grid, findsOneWidget);
    for (final color in MascotColor.values) {
      final label = color == MascotColor.model ? (AppLocale.isEnglish ? 'Model' : '默认色') : color.label;
      // The preview caption also names the selected colour, so count inside the grid only.
      expect(find.descendant(of: grid, matching: find.text(label)), findsOneWidget, reason: color.name);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the body, eyes, mouth and blink controls are gone', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(testApp(const MascotCustomizer(initial: MascotSpec())));
    await tester.pump();
    for (final label in ['身体动作', '眼睛状态', '嘴巴状态', '快速眨眼', '动作编排']) {
      expect(find.text(label), findsNothing, reason: 'old control "$label" must be gone');
    }
    // The three presets stay.
    for (final motion in MascotMotion.values) {
      expect(find.text(motion.label), findsOneWidget, reason: motion.name);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('every pick rebuilds the animated preview immediately', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(testApp(const MascotCustomizer(initial: MascotSpec())));
    await tester.pump();

    MascotSpec previewSpec() => tester.widget<MascotPreview>(find.byType(MascotPreview)).spec;
    final previewAvatar = find.descendant(of: find.byType(MascotPreview), matching: find.byType(MascotAvatar));
    expect(tester.widget<MascotAvatar>(previewAvatar).animate, isTrue, reason: 'the preview must animate');

    // Character: the preview shows the picked one on this frame.
    await tester.tap(find.text(MascotCharacter.cat.label));
    await tester.pump();
    expect(previewSpec().character, MascotCharacter.cat);

    // Colour.
    await tester.tap(find.text('颜色'));
    await tester.pump();
    await tester.tap(find.text(MascotColor.lavender.label));
    await tester.pump();
    expect(previewSpec().color, MascotColor.lavender);

    // Face.
    await tester.tap(find.text('五官'));
    await tester.pump();
    await tester.tap(find.text(MascotFace.values[1].label));
    await tester.pump();
    expect(previewSpec().face, MascotFace.values[1]);

    // View: 2D by default, switching to 3D reaches the preview on this frame.
    expect(previewSpec().view, MascotView.flat);
    await tester.tap(find.byKey(const ValueKey('mascot-view-three')));
    await tester.pump();
    expect(previewSpec().view, MascotView.three);
    await tester.tap(find.byKey(const ValueKey('mascot-view-flat')));
    await tester.pump();
    expect(previewSpec().view, MascotView.flat);

    // Motion preset: choosing it clears any custom action.
    await tester.tap(find.text('角色'));
    await tester.pump();
    await tester.tap(find.text(MascotMotion.quiet.label));
    await tester.pump();
    expect(previewSpec().motion, MascotMotion.quiet);

    // The preview keeps animating after the last pick, then the ticker is released.
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
