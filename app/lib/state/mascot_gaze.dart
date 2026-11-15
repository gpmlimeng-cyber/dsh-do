// 吉祥物的注视输入：全 App 一个 [MascotGaze]，手指按在哪、头像就往哪看。
//
// 为什么放状态层：注视是「输入 → 归一化方向」这一件事，所有头像读到同一个值；
// 每页各建一份会让同一屏里的头像各看各的。
//
// 输入源：根节点一层 `Listener`。它不拦手势（不是手势识别器，只是旁听指针事件），
// 所以滚动、点击、长按照旧；只跟第一根按下的手指，多指时其余忽略，免得方向跳。
//
// 抬手之后不是硬归零：从松手那一刻的方向按 easeOutCubic 淡回「自动看向」，
// 时间用共享时钟算，不额外起 ticker、不自己 setState。
//
// 没有触摸时每个头像按自己的 seed 慢慢漂（两只正弦，周期几秒），所以「偶尔看看
// 左右」不需要定时器，也不需要可复现的随机数。
//
// 系统「减少动态效果」时不做注视：头像那边本来就是静态帧（不 acquire 时钟），
// 这里也直接不跟手，读数恒为 0。
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'mascot_clock.dart';

/// 全 App 共用的注视状态。自己不走时间：时间来自 [MascotClock]。
class MascotGaze {
  MascotGaze(this.clock);

  /// 松手后淡回自动看向的时长。
  static const returnEase = Duration(milliseconds: 380);

  /// 死区：手指在中线附近不动眼睛，避免轻微抖动。
  static const deadZone = 0.08;

  final MascotClock clock;

  Offset _target = Offset.zero;
  Offset _releasedFrom = Offset.zero;
  Duration? _releasedAt;
  bool _touched = false;
  int? _pointer;

  /// 现在有没有手指按着（按住时 [target] 就是注视方向）。
  bool get touched => _touched;

  /// 归一化后的注视方向，[-1, 1]；没按着时是零。
  Offset get target => _target;

  /// 按下一根手指（或它移动）。[global] 是屏幕坐标，[viewport] 用来归一化。
  void follow(int pointer, Offset global, Size viewport) {
    if (_pointer != null && _pointer != pointer) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;
    _pointer = pointer;
    _touched = true;
    _releasedAt = null;
    final nx = ((global.dx - viewport.width / 2) / (viewport.width / 2)).clamp(-1.0, 1.0);
    final ny = ((global.dy - viewport.height / 2) / (viewport.height / 2)).clamp(-1.0, 1.0);
    final next = Offset(nx, ny);
    _target = next.distance < deadZone ? Offset.zero : next;
  }

  /// 这根手指抬起 / 被取消：从这里淡回自动看向。
  void release(int pointer) {
    if (_pointer != null && _pointer != pointer) return;
    _pointer = null;
    _touched = false;
    _releasedFrom = _target;
    _releasedAt = clock.elapsed;
    _target = Offset.zero;
  }

  /// 某一时刻的画面方向：按住就看手指，松手后淡出，其余时间按 seed 自动漂。
  Offset resolveAt(Duration now, {required int seed}) {
    final idle = _idleLook(now, seed);
    if (_touched) return _target;
    final released = _releasedAt;
    if (released == null) return idle;
    final elapsed = now - released;
    if (elapsed >= returnEase) return idle;
    final t = Curves.easeOutCubic.transform(elapsed.inMicroseconds / returnEase.inMicroseconds);
    return Offset.lerp(_releasedFrom, idle, t) ?? idle;
  }

  /// 现在这一刻的方向（painter 用）。
  Offset resolve({required int seed}) => resolveAt(clock.elapsed, seed: seed);

  /// 自动看向：两条不同周期的正弦，seed 决定起始相位，所以每只头像不同步。
  static Offset _idleLook(Duration now, int seed) {
    final t = now.inMilliseconds / 1000;
    final phase = (seed % 628) / 100;
    return Offset(
      math.sin(t * 0.42 + phase) * 0.35,
      math.sin(t * 0.27 + phase * 1.7) * 0.18,
    );
  }
}

/// 把注视挂到整棵树上（`lib/app.dart`，和 [MascotClockScope] 一起）。
///
/// 没有 scope 时（单页测试、独立预览）[maybeOf] 返回 null，头像不做注视。
class MascotGazeScope extends StatefulWidget {
  const MascotGazeScope({super.key, required this.child, this.gaze});

  final Widget child;

  /// 测试注入：直接给一个自己驱动的 [MascotGaze]，不再旁听指针。
  final MascotGaze? gaze;

  /// 最近的注视状态；不在 scope 里返回 null。
  static MascotGaze? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MascotGazeMarker>()?.gaze;

  @override
  State<MascotGazeScope> createState() => _MascotGazeScopeState();
}

class _MascotGazeScopeState extends State<MascotGazeScope> {
  MascotGaze? _own;
  MascotGaze? _gaze;

  /// 系统「减少动态效果」：建的时候缓存，指针回调里不再查 context。
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final injected = widget.gaze;
    if (injected != null) {
      _gaze = injected;
      return;
    }
    final clock = MascotClockScope.maybeOf(context);
    // 没有共享时钟就没有时间基准：不做注视（头像也画静态帧）。
    _gaze = clock == null ? null : (_own ??= MascotGaze(clock));
  }

  void _down(PointerDownEvent event) {
    if (_reduced) return;
    _gaze?.follow(event.pointer, event.position, MediaQuery.sizeOf(context));
  }

  void _move(PointerMoveEvent event) {
    if (_reduced) return;
    _gaze?.follow(event.pointer, event.position, MediaQuery.sizeOf(context));
  }

  void _up(PointerEvent event) {
    if (_reduced) return;
    _gaze?.release(event.pointer);
  }

  @override
  Widget build(BuildContext context) {
    final gaze = _gaze;
    // Listenable 不在这里通知：注视每帧只被 repaint 读，不触发 widget 重建。
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: _MascotGazeMarker(gaze: gaze, child: widget.child),
    );
  }
}

class _MascotGazeMarker extends InheritedWidget {
  const _MascotGazeMarker({required this.gaze, required super.child});

  final MascotGaze? gaze;

  @override
  bool updateShouldNotify(_MascotGazeMarker oldWidget) => !identical(oldWidget.gaze, gaze);
}
