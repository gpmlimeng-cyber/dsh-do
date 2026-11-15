// 头像读注视：painter 拿到的是注入的同一个 MascotGaze，手指一按全屏头像一起看过去，
// 松手回中；系统「减少动态效果」时指针不生效、时钟也不跑。

import 'package:dsh_app/state/mascot_clock.dart';
import 'package:dsh_app/state/mascot_gaze.dart';
import 'package:dsh_app/ui/mascots/mascot_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/support/harness.dart' show loadTestFonts, testApp;

MascotPainter painterOf(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<MascotPainter>()
    .first;

Widget scopeFor(MascotClock clock, MascotGaze gaze, {bool reduced = false}) {
  Widget page = MascotClockScope(
    clock: clock,
    child: MascotGazeScope(
      gaze: gaze,
      child: const SizedBox.expand(
        child: Center(child: MascotAvatar(spec: MascotSpec(), animate: true, size: 64)),
      ),
    ),
  );
  if (!reduced) return page;
  // 系统「减少动态效果」：包一层 MediaQuery，继承当前的尺寸等其它字段。
  return Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: page,
    ),
  );
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('the avatar paints from the injected gaze instance', (tester) async {
    final clock = MascotClock();
    final gaze = MascotGaze(clock);
    addTearDown(clock.dispose);
    await tester.pumpWidget(testApp(scopeFor(clock, gaze)));
    await tester.pump();
    expect(identical(painterOf(tester).gaze, gaze), isTrue, reason: 'painter 要读同一个注视实例');
    expect(clock.holders, 1);
  });

  testWidgets('a finger on the screen turns the avatar and letting go releases it', (tester) async {
    final clock = MascotClock();
    final gaze = MascotGaze(clock);
    addTearDown(clock.dispose);
    await tester.pumpWidget(testApp(scopeFor(clock, gaze)));
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(24, 400));
    await tester.pump();
    expect(gaze.touched, isTrue);
    expect(gaze.target.dx, lessThan(0), reason: '按在左边，应该看左边');

    await gesture.up();
    await tester.pump();
    expect(gaze.touched, isFalse);
  });

  testWidgets('reduced motion ignores the pointer and stops the clock', (tester) async {
    final clock = MascotClock();
    final gaze = MascotGaze(clock);
    addTearDown(clock.dispose);
    await tester.pumpWidget(testApp(scopeFor(clock, gaze, reduced: true)));
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(24, 400));
    await tester.pump();
    expect(gaze.touched, isFalse, reason: '减少动态效果时不跟手');
    expect(gaze.target, Offset.zero);
    expect(clock.holders, 0, reason: '静态帧不挂时钟');
    await gesture.up();
    await tester.pump();
  });
}
