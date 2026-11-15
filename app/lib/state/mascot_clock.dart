// 头像动画的共享时钟：全 App 一个 ticker，所有吉祥物 / 字团从同一个时间算相位。
//
// 为什么：伙伴页一屏 6–8 个头像，每处各自一个 AnimationController 就是 6–8 个
// ticker + 每帧 6–8 次 setState。这里只留一个 ticker；头像把时钟当
// `CustomPainter(repaint:)` 的 Listenable 交给画笔，一帧只重画不重建 widget。
//
// 什么时候走：头像 mount / 重新可见时 acquire，dispose / 不可见时 release，
// 计数归零 ticker 就停。系统「减少动态效果」或 App 自己的减弱动效打开时
// （MediaQuery.disableAnimations），头像不 acquire —— 等于全静态，一帧都不跑。
//
// 时间基准：走 Ticker，帧时间戳就是 SteadyFrameBinding 调整过的那份
// （ui/theme/frame_clock.dart），跳帧不会让头像突然跳一下，和其它动画一致。
//
// 测试：`MascotClockScope(clock: …)` 注入一个不自己走的时钟，用
// `advanceTo()` 推到固定相位，就能断言「同屏多个头像读到同一个值」；
// 真实时钟下 `tester.binding.transientCallbackCount` 应为 1（旧实现是每个头像 1）。
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 头像动画的共享时钟。
///
/// 它自己不会走：真实运行时由 [MascotClockScope] 的 ticker 调 [advanceTo]，
/// 测试里由用例直接调 [advanceTo]。
class MascotClock extends ChangeNotifier {
  MascotClock();

  Duration _elapsed = Duration.zero;
  int _holders = 0;
  bool _disposed = false;

  /// 从第一次 acquire 起累计的动画时间（单调不减）。
  Duration get elapsed => _elapsed;

  /// 现在有几个头像在等这个时钟；0 时 ticker 停。
  int get holders => _holders;

  bool get isDisposed => _disposed;

  /// 一档动作的相位 0..1（按 [period] 循环）。周期由调用方按动作档位给。
  double phaseOf(Duration period) {
    final micros = period.inMicroseconds;
    if (micros <= 0) return 0;
    return (_elapsed.inMicroseconds % micros) / micros;
  }

  /// 头像开始要动画时调用，不再要动画时 [release]。
  void acquire() {
    if (_disposed) return;
    _holders++;
    notifyListeners();
  }

  /// [acquire] 的对应操作；多调不会把计数压到负数。
  void release() {
    if (_disposed || _holders == 0) return;
    _holders--;
    notifyListeners();
  }

  /// 推进到某个时间点。真实时钟每帧给绝对时长；测试给固定值。
  ///
  /// 只往前走：帧时间戳回拨（或测试给了更小的值）不许动画倒放。
  void advanceTo(Duration elapsed) {
    if (_disposed || elapsed == _elapsed) return;
    _elapsed = elapsed < _elapsed ? _elapsed : elapsed;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 把共享时钟放到整棵树上面（`lib/app.dart` 的 `MaterialApp.builder`）。
///
/// 没有 scope 时（单页 widget 测试、独立预览）[maybeOf] 返回 null，头像会退回
/// 自己起 ticker —— 和改造前行为一致，不会因为没接线就静止。
class MascotClockScope extends StatefulWidget {
  const MascotClockScope({super.key, required this.child, this.clock});

  final Widget child;

  /// 测试注入：传了之后不再自己起 ticker，由用例用 [MascotClock.advanceTo] 驱动。
  final MascotClock? clock;

  /// 最近的一个共享时钟；不在 scope 里返回 null。
  static MascotClock? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MascotClockMarker>()?.clock;

  /// 同上，但要求必须存在（只在确定接了 scope 的地方用）。
  static MascotClock of(BuildContext context) {
    final clock = maybeOf(context);
    assert(clock != null, 'MascotClockScope.of() 用在了没有 scope 的子树里');
    return clock!;
  }

  @override
  State<MascotClockScope> createState() => _MascotClockScopeState();
}

class _MascotClockScopeState extends State<MascotClockScope> with SingleTickerProviderStateMixin {
  late final MascotClock _clock = widget.clock ?? MascotClock();
  Ticker? _ticker;

  /// ticker 每次 start 都从 0 算，换算回时钟用的基准；暂停再回来动画从原处继续。
  Duration _base = Duration.zero;

  /// 注入的时钟由测试驱动，不自己起 ticker。
  bool get _driven => widget.clock == null;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _clock.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void didUpdateWidget(MascotClockScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(identical(oldWidget.clock, widget.clock), 'MascotClockScope 的 clock 不支持中途替换');
  }

  void _syncTicker() {
    final ticker = _ticker;
    if (!_driven || ticker == null) return;
    final want = _clock.holders > 0;
    if (want && !ticker.isActive) {
      _base = _clock.elapsed;
      ticker.start();
    } else if (!want && ticker.isActive) {
      ticker.stop();
    }
  }

  void _onTick(Duration elapsed) => _clock.advanceTo(_base + elapsed);

  @override
  void dispose() {
    _clock.removeListener(_syncTicker);
    _ticker?.dispose();
    _ticker = null;
    if (_driven) _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _MascotClockMarker(clock: _clock, child: widget.child);
}

class _MascotClockMarker extends InheritedWidget {
  const _MascotClockMarker({required this.clock, required super.child});

  final MascotClock clock;

  @override
  bool updateShouldNotify(_MascotClockMarker oldWidget) => !identical(oldWidget.clock, clock);
}

/// 眨眼的纯函数：给定共享时钟时间和 seed，这一刻闭不闭眼。
///
/// 周期 2.2–4.8 秒（按 seed 错开），闭眼 110ms；`seed % 100 < 18` 的还会在
/// 160ms 后补一次 90ms 的连眨。和画法无关（哪种眼睛不眨由渲染层决定），
/// painter 和测试共用这一份，别各写一套。
bool mascotBlinkAt(Duration elapsed, int seed) {
  final period = 2200 + (seed % 2600);
  final phase = (elapsed.inMilliseconds + seed) % period;
  if (phase < 110) return true;
  if (seed % 100 < 18) {
    final second = phase - 160;
    return second >= 0 && second < 90;
  }
  return false;
}
