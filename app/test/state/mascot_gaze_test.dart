// 注视的纯逻辑：手指方向、死区、多指、抬手回中、没触摸时的自动漂。
//
// 时间只来自共享时钟（MascotClock），所以这些断言不依赖真实计时器。

import 'package:dsh_app/state/mascot_clock.dart';
import 'package:dsh_app/state/mascot_gaze.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = Size(400, 800);

void main() {
  late MascotClock clock;
  late MascotGaze gaze;

  setUp(() {
    clock = MascotClock();
    gaze = MascotGaze(clock);
  });

  tearDown(() => clock.dispose());

  test('a finger off-centre looks that way and clamps at the edge', () {
    gaze.follow(1, Offset.zero, _phone);
    expect(gaze.touched, isTrue);
    expect(gaze.target.dx, closeTo(-1, 1e-9));
    expect(gaze.target.dy, closeTo(-1, 1e-9));
    expect(gaze.resolve(seed: 7), gaze.target);
  });

  test('a finger on the middle does nothing (dead zone)', () {
    gaze.follow(1, Offset(_phone.width / 2 + 4, _phone.height / 2 - 4), _phone);
    expect(gaze.touched, isTrue);
    expect(gaze.target, Offset.zero);
  });

  test('only the first finger drives the look', () {
    gaze.follow(1, const Offset(0, 400), _phone);
    final first = gaze.target;
    gaze.follow(2, const Offset(400, 400), _phone);
    expect(gaze.target, first);
    // 第二根手指抬起也不该松开第一根。
    gaze.release(2);
    expect(gaze.touched, isTrue);
    expect(gaze.target, first);
    gaze.release(1);
    expect(gaze.touched, isFalse);
  });

  test('a released finger eases back to the idle look within 380ms', () {
    gaze.follow(1, const Offset(0, 400), _phone);
    expect(gaze.target.dx, closeTo(-1, 1e-9));
    clock.advanceTo(const Duration(seconds: 2));
    gaze.release(1);

    // 松手当刻还停在原方向。
    expect(gaze.resolveAt(const Duration(seconds: 2), seed: 11).dx, closeTo(-1, 1e-9));
    // 中途在两者之间。
    final middle = gaze.resolveAt(const Duration(milliseconds: 2190), seed: 11).dx;
    expect(middle, greaterThan(-1));
    expect(middle, lessThan(1));
    // 到点就回到自动看向：和一只从没被按过的注视读到的完全一样。
    final idle = MascotGaze(clock);
    expect(
      gaze.resolveAt(const Duration(milliseconds: 2380), seed: 11),
      idle.resolveAt(const Duration(milliseconds: 2380), seed: 11),
    );
  });

  test('without a finger each seed drifts on its own', () {
    final a = gaze.resolveAt(const Duration(seconds: 3), seed: 1);
    final b = gaze.resolveAt(const Duration(seconds: 3), seed: 2);
    expect(a, isNot(b), reason: '不同 seed 不该同步');
    final later = gaze.resolveAt(const Duration(seconds: 6), seed: 1);
    expect(later, isNot(a), reason: '没触摸时也会慢慢漂');
    // 幅度在需求给的范围内（|x| ≤ 0.35，|y| ≤ 0.18）。
    for (var i = 0; i < 20; i++) {
      final look = gaze.resolveAt(Duration(milliseconds: i * 700), seed: 5);
      expect(look.dx.abs(), lessThanOrEqualTo(0.35 + 1e-9));
      expect(look.dy.abs(), lessThanOrEqualTo(0.18 + 1e-9));
    }
  });

  test('a finger wins over the idle drift', () {
    gaze.follow(1, const Offset(400, 400), _phone);
    final at = gaze.resolveAt(const Duration(seconds: 5), seed: 3);
    expect(at.dx, closeTo(1, 1e-9));
    expect(at.dy, closeTo(0, 1e-9));
  });
}
