// The customizer's preview is live: every pick rebuilds the preview's spec on
// the same frame, and the preview animates while the person picks.
//
// 角色 / 颜色 / 五官 three tabs; motion (活泼/安静/好奇) lives on the 五官 tab as
// three cards; 字团 and the old body/eyes/mouth controls are gone.

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/ui/mascots/mascot_avatar.dart';
import 'package:dsh_app/ui/mascots/mascot_customizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/support/harness.dart' show loadTestFonts, testApp, usePhoneView;

void main() {
  setUpAll(loadTestFonts);

  Future<void> open(WidgetTester tester) async {
    usePhoneView(tester);
    // 一整屏放下预览 + 三个 tab 的内容，省得对懒加载的下半截做滚动断言。
    tester.view.physicalSize = const Size(780, 2400);
    await tester.pumpWidget(testApp(const MascotCustomizer(initial: MascotSpec())));
    await tester.pump();
  }

  testWidgets('the character tab shows the thirteen roles and no 字团', (tester) async {
    await open(tester);
    final grid = find.byType(GridView);
    expect(grid, findsOneWidget);
    for (final character in MascotCharacter.values) {
      expect(find.descendant(of: grid, matching: find.text(character.label)), findsOneWidget, reason: character.name);
    }
    expect(find.text('字团'), findsNothing, reason: '字团已下线，选择器里不再有入口');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the colour tab shows every colour option', (tester) async {
    await open(tester);
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
    await open(tester);
    for (final label in ['身体动作', '眼睛状态', '嘴巴状态', '快速眨眼', '动作编排']) {
      expect(find.text(label), findsNothing, reason: 'old control "$label" must be gone');
    }
    // 动作不再留在角色页。
    for (final motion in MascotMotion.values) {
      expect(find.byKey(ValueKey('mascot-motion-${motion.name}')), findsNothing, reason: '角色页不该有动作卡');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the face tab holds the three motion cards, and picking one switches the look', (tester) async {
    await open(tester);
    MascotSpec previewSpec() => tester.widget<MascotPreview>(find.byType(MascotPreview)).spec;

    await tester.tap(find.text('五官'));
    await tester.pump();
    for (final motion in MascotMotion.values) {
      expect(find.byKey(ValueKey('mascot-motion-${motion.name}')), findsOneWidget, reason: motion.name);
    }

    await tester.tap(find.byKey(ValueKey('mascot-motion-${MascotMotion.quiet.name}')));
    await tester.pump();
    expect(previewSpec().motion, MascotMotion.quiet);
    expect(previewSpec().caption, contains(MascotMotion.quiet.label), reason: '标题第三段跟着换');

    // 重进保持：把选好的 spec 再交给自定义页，动作仍是安静。
    final kept = previewSpec();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(MascotCustomizer(initial: kept)));
    await tester.pump();
    await tester.tap(find.text('五官'));
    await tester.pump();
    expect(tester.widget<MascotPreview>(find.byType(MascotPreview)).spec.motion, MascotMotion.quiet);

    // 回到角色页，角色格还在，动作卡不在了。
    await tester.tap(find.text('角色'));
    await tester.pump();
    expect(find.byKey(ValueKey('mascot-motion-${MascotMotion.quiet.name}')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('every pick rebuilds the animated preview immediately', (tester) async {
    await open(tester);

    MascotSpec previewSpec() => tester.widget<MascotPreview>(find.byType(MascotPreview)).spec;
    final previewAvatar = find.descendant(of: find.byType(MascotPreview), matching: find.byType(MascotAvatar));
    expect(tester.widget<MascotAvatar>(previewAvatar).animate, isTrue, reason: 'the preview must animate');

    // Character: the preview shows the picked one on this frame.
    await tester.tap(find.text(MascotCharacter.jelly.label));
    await tester.pump();
    expect(previewSpec().character, MascotCharacter.jelly);

    // Colour.
    await tester.tap(find.text('颜色'));
    await tester.pump();
    await tester.tap(find.text(MascotColor.lavender.label));
    await tester.pump();
    expect(previewSpec().color, MascotColor.lavender);

    // Face, view and motion all live on the 五官 tab.
    await tester.tap(find.text('五官'));
    await tester.pump();
    await tester.tap(find.text(MascotFace.values[1].label));
    await tester.pump();
    expect(previewSpec().face, MascotFace.values[1]);

    expect(previewSpec().view, MascotView.flat);
    await tester.tap(find.byKey(const ValueKey('mascot-view-three')));
    await tester.pump();
    expect(previewSpec().view, MascotView.three);
    await tester.tap(find.byKey(const ValueKey('mascot-view-flat')));
    await tester.pump();
    expect(previewSpec().view, MascotView.flat);

    await tester.tap(find.byKey(ValueKey('mascot-motion-${MascotMotion.quiet.name}')));
    await tester.pump();
    expect(previewSpec().motion, MascotMotion.quiet);

    // The preview keeps animating after the last pick, then the ticker is released.
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
