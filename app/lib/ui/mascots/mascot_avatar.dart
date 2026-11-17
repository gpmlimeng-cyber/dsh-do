// 吉祥物头像：把 lively-mascot（MIT）的 5 个角色用 Flutter 原生重绘。
//
// 为什么不内嵌：它是 CSS/SVG 的 Web 引擎，列表里几十个 WebView 会卡；这里一个
// CustomPainter 画完，列表用 `animate: false` 时不起 ticker。
//
// 形状对照（lively-mascot dist/characters/*.css）：
//   pebble 磨砂银石 + 凹陷五官；robot 圆角方身 + 天线；
//   ghost 圆顶 + 波浪底；jelly 半球 + 果冻光泽。
// 3D：径向渐变 + 底部内阴影 + 高光，**不描边**（用户要求）。
//
// 动画三档：活泼（弹跳）/ 安静（呼吸）/ 好奇（侧头看）。
// 参数化：角色 5、五官 3、预设色 6、动作 3；`MascotSpec.random` 给「随机换一个」。
//
// 文案随本地双语表（本机生成不了 l10n gen），键名对齐将来的 arb。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/mascot_clock.dart';
import '../../state/mascot_gaze.dart';
import '../../state/mascot_spec.dart';

export '../../state/mascot_spec.dart';

/// 解析实际配色：model → 角色 skin；跟主题 → 主题色；其余用预设色。
MascotSkin mascotSkinOf(MascotSpec spec, ColorScheme scheme) {
  if (spec.followAppColor) {
    final body = scheme.primary;
    return MascotSkin(body, Color.lerp(body, Colors.black, 0.86)!, Color.lerp(body, const Color(0xFFFF6E8A), 0.62)!);
  }
  if (spec.color == MascotColor.model) return spec.character.skin;
  return MascotSkin(spec.color.ink, spec.color.outlineInk, spec.color.accent);
}

/// `bot.color` 的色名：model 跟随角色，其余用预设映射。
String hostColorOf(MascotSpec spec) =>
    spec.color == MascotColor.model ? spec.character.hostColor : spec.color.hostName;

/// 一个吉祥物头像。
///
/// [animate] 为 false 时是纯静态一帧（列表、消息行用），不创建 ticker；
/// 预览区和自定义页才传 true。
class MascotAvatar extends StatefulWidget {
  const MascotAvatar({super.key, required this.spec, this.emotion, this.size = 48, this.animate = false, this.letter});

  final MascotSpec spec;

  /// 会话状态对应的情绪 id（`mascotExpressions` 的键，如 `'20'`）；null 时按
  /// spec.face 画。列表里只画这一帧，不跑动画。
  final String? emotion;
  final double size;
  final bool animate;

  /// 字团：给了字就把五官位置换成这个字（[emotion] 不再影响脸）。
  final String? letter;

  @override
  State<MascotAvatar> createState() => _MascotAvatarState();
}

class _MascotAvatarState extends State<MascotAvatar> with SingleTickerProviderStateMixin {
  /// 共享时钟：有 scope 时用它，一屏多个头像共用一个 ticker。
  MascotClock? _clock;

  /// 全 App 的注视状态（没有 scope 时不做注视）。
  MascotGaze? _gaze;
  bool _holding = false;

  /// 没有共享时钟时（单页测试/独立预览）退回本地控制器。
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // clock / reduce-motion / TickerMode 都在这三个依赖里，变化时重跑。
    _syncAnimation();
  }

  @override
  void didUpdateWidget(MascotAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
    if (_controller != null && oldWidget.spec.motion != widget.spec.motion) {
      _controller!.duration = _durationOf(widget.spec.motion);
      _controller!
        ..reset()
        ..repeat();
    }
  }

  /// 只决定「要不要动」：共享时钟 acquire/release，没有时钟才起本地控制器。
  void _syncAnimation() {
    final clock = MascotClockScope.maybeOf(context);
    _gaze = MascotGazeScope.maybeOf(context);
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final active = widget.animate && !reduced && TickerMode.valuesOf(context).enabled;

    if (!identical(clock, _clock)) {
      if (_holding) {
        _clock?.release();
        _holding = false;
      }
      _clock = clock;
    }
    if (clock != null) {
      // 共享时钟：只在翻转时 acquire / release，别每帧调。
      _stop();
      if (active && !_holding) {
        clock.acquire();
        _holding = true;
      } else if (!active && _holding) {
        clock.release();
        _holding = false;
      }
      return;
    }
    if (!active && _holding) {
      _clock?.release();
      _holding = false;
    }
    if (active && _controller == null) _start();
    if (!active && _controller != null) _stop();
  }

  void _start() {
    _controller = AnimationController(vsync: this, duration: _durationOf(widget.spec.motion))..repeat();
  }

  void _stop() {
    _controller?.dispose();
    _controller = null;
  }

  static Duration _durationOf(MascotMotion motion) => switch (motion) {
    MascotMotion.lively => const Duration(milliseconds: 1100),
    MascotMotion.quiet => const Duration(milliseconds: 3200),
    MascotMotion.curious => const Duration(milliseconds: 2400),
  };

  @override
  void dispose() {
    if (_holding) {
      _clock?.release();
      _holding = false;
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final skin = mascotSkinOf(widget.spec, scheme);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.animate && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) && TickerMode.valuesOf(context).enabled;
    final clock = active ? _clock : null;

    MascotPainter frame({double phase = 0.35, MascotClock? clock, Duration? period}) => MascotPainter(
      spec: widget.spec,
      emotion: widget.emotion,
      letter: widget.letter,
      body: skin.body,
      ink: skin.ink,
      accent: skin.accent,
      phase: phase,
      dark: dark,
      clock: clock,
      period: period ?? _durationOf(widget.spec.motion),
      gaze: active ? _gaze : null,
    );

    // 共享时钟：把时钟当 repaint 交给画笔，一帧只重画、不重建 widget。
    if (clock != null) {
      return SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(painter: frame(clock: clock), size: Size.square(widget.size)),
      );
    }
    // 没有共享时钟（单页测试 / 独立预览）：本地控制器兜底。
    if (active && _controller != null) {
      return SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller!,
          builder: (context, _) => CustomPaint(painter: frame(phase: _controller!.value), size: Size.square(widget.size)),
        ),
      );
    }
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: frame(), size: Size.square(widget.size)),
    );
  }
}

/// 画一帧。[phase] 0..1 是按 [MascotSpec.motion] 走的时间。
class MascotPainter extends CustomPainter {
  const MascotPainter({
    required this.spec,
    required this.body,
    required this.ink,
    required this.accent,
    required this.phase,
    this.dark = false,
    this.emotion,
    this.letter,
    this.clock,
    this.period = const Duration(milliseconds: 1100),
    this.gaze,
  }) : super(repaint: clock);

  final MascotSpec spec;
  final String? emotion;

  /// 共享时钟：非空时每帧从它算相位（`repaint` 也挂在它上面）。
  final MascotClock? clock;

  /// 这一档动作的周期；共享时钟按它取模。
  final Duration period;

  /// 全 App 的注视状态；null 时不做注视（静态帧、独立预览）。
  final MascotGaze? gaze;

  /// 同一副形象用同一个 seed：眼睛自动漂和眨眼都按它错开。
  int get gazeSeed => spec.seed != 0
      ? spec.seed
      : Object.hash(spec.character, spec.color, spec.motion);

  /// 字团用：非空时在五官位置画这个字，不画眼睛/嘴/腮红。
  final String? letter;
  final Color body;
  final Color ink;
  final Color accent;
  final double phase;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final phase = clock?.phaseOf(period) ?? this.phase;
    final t = phase * 2 * math.pi;
    final expression = emotion == null ? expressionFor(spec) : (mascotExpressions[emotion] ?? expressionFor(spec));
    // 注视与眨眼：都只读共享时钟，不另起计时器。
    final look = gaze?.resolve(seed: gazeSeed) ?? Offset.zero;
    final blinking = _blinkingNow();
    // 动作：先按情绪的身体意图，再用用户选的动作兜底。
    var dy = 0.0;
    var scaleY = 1.0;
    var tilt = 0.0;
    var shake = 0.0;
    switch (expression.body) {
      case 'bounce':
        dy = -0.030 * s * math.sin(t).abs();
        scaleY = 1 + 0.022 * math.sin(t);
      case 'breathe':
        scaleY = 1 + 0.012 * math.sin(t);
      case 'pulse':
        scaleY = 1 + 0.030 * math.sin(t);
      case 'shake':
        shake = 0.012 * s * math.sin(t * 6);
      case 'rest' || 'dim':
        break;
      case 'wake':
        dy = -0.010 * s * (1 - math.sin(t).abs());
      default:
        switch (spec.motion) {
          case MascotMotion.lively:
            dy = -0.012 * s * math.sin(t).abs();
          case MascotMotion.quiet:
            scaleY = 1 + 0.008 * math.sin(t);
          case MascotMotion.curious:
            tilt = 0.030 * math.sin(t);
        }
    }

    canvas.save();
    // 旋转与缩放都绕中心，再整体上下位移。
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(tilt);
    canvas.scale(1, scaleY);
    canvas.translate(-size.width / 2 + shake, -size.height / 2 + dy);

    final three = spec.view == MascotView.three;
    if (three) {
      // 3D 的「远近」：z 呼吸 + 随注视轻微转头（侧转时补一点体积，别变窄）。
      final breath = 0.98 + 0.02 * (0.5 + 0.5 * math.sin(t * 0.9));
      final yaw = look.dx * 9.4;
      canvas.translate(size.width / 2, size.height * 0.55);
      canvas.rotate(look.dx * 0.06);
      canvas.scale(breath * (1 - yaw.abs() * 0.0025), breath);
      canvas.translate(-size.width / 2, -size.height * 0.55);
    }

    // 角团下宽上尖，重心压在底部：整体上移一点，视觉重心才落在画布中央。
    // 其余角色按原矩形画，不动。
    final lift = spec.character == MascotCharacter.triangle ? s * 0.08 : 0.0;
    final rect = Rect.fromLTWH(s * 0.10, s * 0.20 - lift, s * 0.80, s * 0.70);
    final top = _lighten(body, 0.34);
    final bottom = _darken(body, 0.30);

    // 身体底色：3D 用径向渐变（光从左上），2D 是纯色贴纸。
    final bodyPaint = three
        ? (Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.45, -0.6),
              radius: 1.1,
              colors: [top, body, bottom],
              stops: const [0, 0.55, 1],
            ).createShader(rect))
        : (Paint()..color = body);

    final path = switch (spec.character) {
      MascotCharacter.robot => _robot(rect),
      MascotCharacter.ghost => _ghost(rect),
      MascotCharacter.jelly => _jelly(rect),
      MascotCharacter.orb => _orb(rect),
      MascotCharacter.star => _starBody(rect),
      MascotCharacter.triangle => _triangle(rect),
      MascotCharacter.onigiri => _onigiri(rect),
      MascotCharacter.potato => _potato(rect),
      MascotCharacter.orange => _orange(rect),
      MascotCharacter.pear => _pear(rect),
      MascotCharacter.mango => _mango(rect),
      MascotCharacter.pebble => _pebble(rect),
    };
    canvas.drawPath(path, bodyPaint);

    // 3D 才有底部内阴影和左上高光；2D 保持纯色。
    if (three) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.transparent, _darken(body, 0.38).withValues(alpha: 0.55)],
            stops: const [0, 0.62, 1],
          ).createShader(rect),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            rect.left + rect.width * (0.30 + look.dx * 0.05),
            rect.top + rect.height * (0.22 + look.dy * 0.04),
          ),
          width: rect.width * 0.34,
          height: rect.height * 0.20,
        ),
        Paint()..color = Colors.white.withValues(alpha: dark ? 0.22 : 0.38),
      );
      canvas.restore();
    }

    // 角色专属零件（叶子/耳朵/天线/呆毛）。
    _charParts(canvas, size, rect, t, expression.top, three: three);

    // 五官；字团时把五官位置换成名字的首字。
    if (letter case final glyph?) {
      _glyph(canvas, rect, glyph);
    } else {
      _face(canvas, rect, t, expression.eyes, expression.mouth, three: three, look: look, blinking: blinking);
    }

    canvas.restore();
    _drawEffect(canvas, size, expression.effect, t, head: Offset(size.width / 2, 0.10 * s));
  }

  // ── 身体形状 ──

  /// 五官的颜色：深色身体上用白色，浅色身体上按本色压暗，保证看得清。
  /// 银团的五官是磨在金属上的凹槽，始终走深色，和图标一样。
  Color get _featureInk {
    if (spec.character == MascotCharacter.pebble) {
      return body.computeLuminance() < 0.30 ? Colors.white.withValues(alpha: 0.92) : _darken(body, 0.80);
    }
    return body.computeLuminance() < 0.42 ? Colors.white.withValues(alpha: 0.95) : _darken(body, 0.62);
  }

  Path _robot(Rect r) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(r.deflate(r.width * 0.02), Radius.circular(r.width * 0.26)));
    return path;
  }

  Path _ghost(Rect r) {
    final path = Path()
      ..moveTo(r.left + r.width * 0.12, r.top + r.height * 0.30)
      ..quadraticBezierTo(r.left + r.width * 0.12, r.top, r.center.dx, r.top)
      ..quadraticBezierTo(r.right - r.width * 0.12, r.top, r.right - r.width * 0.12, r.top + r.height * 0.30)
      ..lineTo(r.right - r.width * 0.12, r.bottom - r.height * 0.12);
    // 波浪底：三个小拱。
    final w = r.width * 0.76 / 3;
    for (var i = 0; i < 3; i++) {
      final x0 = r.right - r.width * 0.12 - i * w;
      path.quadraticBezierTo(x0 - w * 0.25, r.bottom + r.height * 0.06, x0 - w * 0.5, r.bottom - r.height * 0.12);
      path.quadraticBezierTo(x0 - w * 0.75, r.bottom - r.height * 0.02, x0 - w, r.bottom - r.height * 0.12);
    }
    path.lineTo(r.left + r.width * 0.12, r.top + r.height * 0.30);
    return path..close();
  }

  Path _jelly(Rect r) {
    final path = Path()
      ..moveTo(r.left + r.width * 0.10, r.center.dy + r.height * 0.18)
      ..quadraticBezierTo(r.left + r.width * 0.10, r.top, r.center.dx, r.top)
      ..quadraticBezierTo(r.right - r.width * 0.10, r.top, r.right - r.width * 0.10, r.center.dy + r.height * 0.18)
      ..quadraticBezierTo(r.center.dx, r.bottom + r.height * 0.02, r.left + r.width * 0.10, r.center.dy + r.height * 0.18)
      ..close();
    return path;
  }

  // 圆团：纯球，没有顶饰。
  /// 圆团是正圆：身体矩形是 0.80×0.70 的扁椭圆，这里取短边作直径，
  /// 免得它跟着身体框被拉宽。
  Path _orb(Rect r) =>
      Path()..addOval(Rect.fromCircle(center: r.center, radius: r.shortestSide / 2));

  /// 四角星：特效用的，和星团的海星形状无关。
  void _sparkleStar(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final r = i.isEven ? radius : radius * 0.38;
      final a = -math.pi / 2 + i * math.pi / 4;
      final p = center + Offset(math.cos(a) * r, math.sin(a) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  // 星团：五角海星，角是圆的，中间略鼓。
  Path _starBody(Rect r) {
    final c = r.center;
    final outer = r.width * 0.52;
    final inner = outer * 0.48;
    final points = <Offset>[];
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final radius = i.isEven ? outer : inner;
      final squash = i.isEven ? 1.0 : 1.06;
      points.add(Offset(c.dx + math.cos(angle) * radius, c.dy + math.sin(angle) * radius * squash));
    }
    return _roundedPolygon(points);
  }

  // 三角：软糖那种圆润三角，顶点不尖。
  Path _triangle(Rect r) {
    final points = [
      Offset(r.center.dx, r.top - r.height * 0.04),
      Offset(r.right + r.width * 0.04, r.bottom - r.height * 0.02),
      Offset(r.left - r.width * 0.04, r.bottom - r.height * 0.02),
    ];
    return _roundedPolygon(points);
  }

  // 饭团：圆顶、平底的奶白饭团（海苔在 _charParts 里画）。
  Path _onigiri(Rect r) => Path()
    ..addRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(r.left + r.width * 0.02, r.top, r.width * 0.96, r.height),
        topLeft: Radius.circular(r.width * 0.46),
        topRight: Radius.circular(r.width * 0.46),
        bottomLeft: Radius.circular(r.width * 0.18),
        bottomRight: Radius.circular(r.width * 0.18),
      ),
    );

  // 土豆：不规则扁椭圆，轮廓带几处起伏。
  Path _potato(Rect r) {
    final c = r.center;
    final w = r.width;
    final h = r.height;
    final path = Path()..moveTo(c.dx - w * 0.46, c.dy + h * 0.06);
    path.cubicTo(c.dx - w * 0.50, c.dy - h * 0.30, c.dx - w * 0.16, c.dy - h * 0.52, c.dx + w * 0.16, c.dy - h * 0.48);
    path.cubicTo(c.dx + w * 0.48, c.dy - h * 0.44, c.dx + w * 0.52, c.dy - h * 0.06, c.dx + w * 0.44, c.dy + h * 0.22);
    path.cubicTo(c.dx + w * 0.36, c.dy + h * 0.50, c.dx - w * 0.10, c.dy + h * 0.54, c.dx - w * 0.34, c.dy + h * 0.44);
    path.cubicTo(c.dx - w * 0.46, c.dy + h * 0.34, c.dx - w * 0.46, c.dy + h * 0.20, c.dx - w * 0.46, c.dy + h * 0.06);
    return path..close();
  }

  // 瓜团：绿皮圆球（条纹在 _charParts 里画）。
  // 橘团：略扁的橙色圆球。
  Path _orange(Rect r) => Path()
    ..addOval(
      Rect.fromCenter(center: r.center.translate(0, r.height * 0.03), width: r.width, height: r.height * 0.90),
    );

  // 梨团：上窄下圆的梨形。
  Path _pear(Rect r) {
    final path = Path()..moveTo(r.center.dx, r.top);
    path.cubicTo(r.center.dx - r.width * 0.10, r.top + r.height * 0.18, r.left + r.width * 0.02, r.top + r.height * 0.38,
        r.left + r.width * 0.05, r.center.dy + r.height * 0.10);
    path.cubicTo(r.left, r.bottom + r.height * 0.02, r.right, r.bottom + r.height * 0.02,
        r.right - r.width * 0.05, r.center.dy + r.height * 0.10);
    path.cubicTo(r.right - r.width * 0.02, r.top + r.height * 0.38, r.center.dx + r.width * 0.10, r.top + r.height * 0.18,
        r.center.dx, r.top);
    return path..close();
  }

  // 芒团：歪椭圆，右上角略尖。
  Path _mango(Rect r) {
    final path = Path()..moveTo(r.left + r.width * 0.16, r.top + r.height * 0.30);
    path.cubicTo(r.left + r.width * 0.30, r.top - r.height * 0.02, r.right - r.width * 0.06, r.top + r.height * 0.10,
        r.right, r.top + r.height * 0.34);
    path.cubicTo(r.right + r.width * 0.02, r.center.dy + r.height * 0.14, r.right - r.width * 0.12, r.bottom,
        r.center.dx - r.width * 0.12, r.bottom);
    path.cubicTo(r.left + r.width * 0.02, r.bottom - r.height * 0.02, r.left, r.center.dy - r.height * 0.10,
        r.left + r.width * 0.16, r.top + r.height * 0.30);
    return path..close();
  }

  // 银团：App 图标那颗银灰磨砂石——软方的鹅卵形，四角半径各不相同才不呆板。
  Path _pebble(Rect r) {
    final base = math.min(r.width, r.height);
    return Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          r,
          topLeft: Radius.circular(base * 0.46),
          topRight: Radius.circular(base * 0.53),
          bottomRight: Radius.circular(base * 0.50),
          bottomLeft: Radius.circular(base * 0.44),
        ),
      );
  }

  /// 顶点之间用二次贝塞尔过点，得到「圆角多边形」。
  Path _roundedPolygon(List<Offset> points) {
    final path = Path();
    final n = points.length;
    Offset mid(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final start = mid(points[n - 1], points[0]);
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < n; i++) {
      final current = points[i];
      final next = mid(current, points[(i + 1) % n]);
      path.quadraticBezierTo(current.dx, current.dy, next.dx, next.dy);
    }
    return path..close();
  }

  // ── 角色专属零件 ──

  void _charParts(Canvas canvas, Size size, Rect r, double t, String top, {required bool three}) {
    switch (spec.character) {
      case MascotCharacter.robot:
        // 天线 + 两侧耳钉。
        final antenna = Paint()
          ..color = _darken(body, 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.016
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(r.center.dx, r.top), Offset(r.center.dx, r.top - r.height * 0.14), antenna);
        canvas.drawCircle(Offset(r.center.dx, r.top - r.height * 0.17), size.width * 0.026, Paint()..color = _lighten(body, 0.30));
        for (final left in [true, false]) {
          final x = left ? r.left : r.right;
          canvas.drawCircle(Offset(x, r.center.dy), size.width * 0.020, Paint()..color = _darken(body, 0.22));
        }
      case MascotCharacter.ghost:
        // 幽灵的腮红两点。
        for (final left in [true, false]) {
          final x = left ? r.left + r.width * 0.24 : r.right - r.width * 0.24;
          canvas.drawCircle(Offset(x, r.center.dy + r.height * 0.10), size.width * 0.030, Paint()..color = _lighten(body, 0.30).withValues(alpha: 0.45));
        }
      case MascotCharacter.jelly:
        // 果冻的亮点。
        canvas.drawCircle(Offset(r.left + r.width * 0.26, r.top + r.height * 0.26), size.width * 0.030, Paint()..color = Colors.white.withValues(alpha: 0.55));
        canvas.drawCircle(Offset(r.left + r.width * 0.38, r.top + r.height * 0.18), size.width * 0.016, Paint()..color = Colors.white.withValues(alpha: 0.45));
      case MascotCharacter.onigiri:
        // 底部一条海苔（Miffan 的饭团）；顶角一点米粒高光。
        final nori = RRect.fromRectAndCorners(
          Rect.fromLTWH(r.center.dx - r.width * 0.19, r.top + r.height * 0.66, r.width * 0.38, r.height * 0.34),
          topLeft: Radius.circular(r.width * 0.03),
          topRight: Radius.circular(r.width * 0.03),
          bottomLeft: Radius.circular(r.width * 0.14),
          bottomRight: Radius.circular(r.width * 0.14),
        );
        canvas.drawRRect(nori, Paint()..color = const Color(0xFF2F3B2F));
        canvas.drawCircle(Offset(r.left + r.width * 0.30, r.top + r.height * 0.20), size.width * 0.014, Paint()..color = Colors.white.withValues(alpha: 0.55));
        // 腮红（Miffan 的饭团有）。
        for (final left in [true, false]) {
          final x = left ? r.left + r.width * 0.24 : r.right - r.width * 0.24;
          canvas.drawOval(
            Rect.fromCenter(center: Offset(x, r.top + r.height * 0.57), width: r.width * 0.13, height: r.height * 0.055),
            Paint()..color = accent.withValues(alpha: 0.75),
          );
        }
      case MascotCharacter.potato:
        // 土豆斑点：outline 降透明度点几颗。
        final spot = Paint()..color = _darken(body, 0.52).withValues(alpha: 0.45);
        canvas.drawOval(Rect.fromCenter(center: Offset(r.left + r.width * 0.26, r.top + r.height * 0.30), width: size.width * 0.050, height: size.width * 0.034), spot);
        canvas.drawOval(Rect.fromCenter(center: Offset(r.right - r.width * 0.24, r.center.dy + r.height * 0.06), width: size.width * 0.040, height: size.width * 0.028), spot);
        canvas.drawOval(Rect.fromCenter(center: Offset(r.center.dx - r.width * 0.06, r.bottom - r.height * 0.16), width: size.width * 0.030, height: size.width * 0.022), spot);
      case MascotCharacter.orange:
        // 橘团：短蒂 + 一片小绿叶 + 表皮几颗低透明深点。
        final stem = Paint()
          ..color = _darken(body, 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.018
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(r.center.dx, r.top + r.height * 0.06), Offset(r.center.dx + r.width * 0.01, r.top - r.height * 0.07), stem);
        canvas.save();
        canvas.translate(r.center.dx + r.width * 0.09, r.top - r.height * 0.10);
        canvas.rotate(-0.35);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r.width * 0.16, height: r.height * 0.085),
          Paint()..color = const Color(0xFF4F8A3C),
        );
        canvas.restore();
        for (final spot in [Offset(0.30, 0.34), Offset(0.68, 0.52)]) {
          canvas.drawCircle(
            Offset(r.left + r.width * spot.dx, r.top + r.height * spot.dy),
            size.width * 0.010,
            Paint()..color = _darken(body, 0.42).withValues(alpha: 0.45),
          );
        }
      case MascotCharacter.pear:
        // 梨团：短梗 + 小叶 + 侧面几点果斑。
        final stem = Paint()
          ..color = const Color(0xFF6B5A2E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.018
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(r.center.dx, r.top + r.height * 0.05), Offset(r.center.dx + r.width * 0.02, r.top - r.height * 0.08), stem);
        canvas.save();
        canvas.translate(r.center.dx + r.width * 0.10, r.top - r.height * 0.09);
        canvas.rotate(-0.4);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r.width * 0.14, height: r.height * 0.075),
          Paint()..color = const Color(0xFF5E8A3E),
        );
        canvas.restore();
        for (final spot in [Offset(0.36, 0.52), Offset(0.62, 0.66), Offset(0.50, 0.78)]) {
          canvas.drawCircle(
            Offset(r.left + r.width * spot.dx, r.top + r.height * spot.dy),
            size.width * 0.009,
            Paint()..color = _darken(body, 0.40).withValues(alpha: 0.40),
          );
        }
      case MascotCharacter.mango:
        // 芒团：斜向高光 + 少量深色斑点。
        canvas.drawOval(
          Rect.fromCenter(center: Offset(r.left + r.width * 0.34, r.top + r.height * 0.26), width: r.width * 0.30, height: r.height * 0.14),
          Paint()..color = const Color(0xFFFFD98A).withValues(alpha: 0.55),
        );
        for (final spot in [Offset(0.62, 0.44), Offset(0.44, 0.66)]) {
          canvas.drawCircle(
            Offset(r.left + r.width * spot.dx, r.top + r.height * spot.dy),
            size.width * 0.010,
            Paint()..color = _darken(body, 0.40).withValues(alpha: 0.40),
          );
        }
      case MascotCharacter.orb:
      case MascotCharacter.star:
      case MascotCharacter.triangle:
        // 圆团/星团/三角没有额外顶饰。
        break;
      case MascotCharacter.pebble:
        // 银团：3D 时左上有一道斜向磨砂高光（和图标一样的金属反光）；
        // 2D 是纯色贴纸，不加。
        if (three) {
          canvas.save();
          canvas.clipPath(_pebble(r));
          canvas.translate(r.left + r.width * 0.33, r.top + r.height * 0.21);
          canvas.rotate(-0.55);
          canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: r.width * 0.56, height: r.height * 0.24),
            Paint()..color = Colors.white.withValues(alpha: 0.20),
          );
          canvas.restore();
        }
    }
  }

  // ── 五官 ──

  /// [eyes]/[mouth] 是情绪配方里的词（open/closed/wide/happy/sad/thinking/
  /// angry/love/cry/bored；neutral/smile/open/flat/frown/talk）。
  /// 用共享时钟算眨眼：周期 2.2–4.8s（按 seed 错开），闭眼 110ms；
  /// `seed % 100 < 18` 的还会在 160ms 后补一次 90ms 的连眨。
  /// 眨眼节奏见 `state/mascot_clock.dart` 的 [mascotBlinkAt]（纯函数，测试同一份）。
  bool _blinkingNow() {
    final now = gaze?.clock.elapsed ?? clock?.elapsed;
    if (now == null) return false;
    return mascotBlinkAt(now, gazeSeed);
  }

  /// 字团的脸：身体中间一个字；深底白字、浅底深字，按身体明度挑。
  void _glyph(Canvas canvas, Rect r, String glyph) {
    final glyphInk = body.computeLuminance() < 0.42 ? Colors.white.withValues(alpha: 0.94) : _darken(body, 0.62);
    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          color: glyphInk,
          fontSize: r.width * 0.46,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final center = Offset(r.center.dx - painter.width / 2, r.top + r.height * 0.46 - painter.height / 2);
    painter.paint(canvas, center);
  }

  void _face(
    Canvas canvas,
    Rect r,
    double t,
    String eyes,
    String mouth, {
    required bool three,
    Offset look = Offset.zero,
    bool blinking = false,
  }) {
    // 好奇档自带的左右看，叠加在注视方向之上。
    final drift = spec.motion == MascotMotion.curious ? math.sin(t) * r.width * 0.035 : 0.0;
    // 注视：瞳孔最多 ±8/±6（100 制），眼球轻微放大压扁；2D 脸转 5°、3D 3.4°。
    final gx = look.dx * 8 * (r.width / 80);
    final gy = look.dy * 6 * (r.height / 70);
    final pivot = Offset(r.center.dx, r.top + r.height * 0.5);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(look.dx * (three ? 0.06 : 0.087));
    canvas.scale(1 + look.dx.abs() * 0.035 * (r.width / 80), 1 - look.dx.abs() * 0.1 * (r.width / 80));
    canvas.translate(-pivot.dx, -pivot.dy);
    // 角团下宽上尖，五官放在几何中线会显得偏高，往下压一点更顺眼。
    final faceDrop = spec.character == MascotCharacter.triangle ? r.height * 0.10 : 0.0;
    final eyeY = r.top + r.height * 0.44 + gy + faceDrop;
    final lx = r.center.dx - r.width * 0.18 + drift + gx;
    final rx = r.center.dx + r.width * 0.18 + drift + gx;
    final ink = _featureInk;
    // 银团的五官是凹进去的槽（图标那两处），不是贴上去的白眼球。
    final recessed = spec.character == MascotCharacter.pebble;
    final white = Paint()..color = Colors.white.withValues(alpha: 0.92);
    final dark = Paint()..color = ink;
    // 眼白描边、瞳孔固定用深色：跟着 `ink` 走的话，深色身体上连瞳孔都会被
    // 涂成白色，眼睛就剩两团白（炭灰、钢蓝和六个 Miffan 色都是这样）。
    final eyeInk = _darken(body, 0.72);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = r.width * 0.024
      ..strokeCap = StrokeCap.round;

    void roundEye(double x, double radius, {double dx = 0, double dy = 0}) {
      if (recessed) {
        // 银团：深色椭圆槽 + 外侧一圈被磨起的亮边 + 一点反光，和图标同一个意思。
        final socket = Rect.fromCenter(center: Offset(x, eyeY), width: radius * 2.9, height: radius * 2.8);
        canvas.drawOval(socket, Paint()..color = eyeInk.withValues(alpha: 0.94));
        canvas.drawOval(
          socket.inflate(radius * 0.20),
          Paint()
            ..color = _lighten(body, 0.62).withValues(alpha: 0.50)
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * 0.24,
        );
        canvas.drawCircle(
          Offset(x - radius * 0.32 + dx, eyeY - radius * 0.36 + dy),
          radius * 0.28,
          Paint()..color = Colors.white.withValues(alpha: 0.45),
        );
        return;
      }
      // 默认五官对齐 lively-mascot：白眼球 + 深色描边 + 大瞳孔 + 高光。
      // 2D 也这么画，否则「默认」在小缩略图上和「圆点」分不出来。
      final eye = Rect.fromCenter(center: Offset(x, eyeY), width: radius * 2.8, height: radius * 3.1);
      canvas.drawOval(eye, white);
      canvas.drawOval(
        eye,
        Paint()
          ..color = eyeInk
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.30,
      );
      canvas.drawCircle(Offset(x + radius * 0.12 + dx, eyeY + radius * 0.10 + dy), radius * 0.82, Paint()..color = eyeInk);
      canvas.drawCircle(Offset(x - radius * 0.34 + dx, eyeY - radius * 0.42 + dy), radius * 0.30, white);
    }

    void closedEye(double x) {
      canvas.drawPath(
        Path()
          ..moveTo(x - r.width * 0.050, eyeY)
          ..quadraticBezierTo(x, eyeY + r.height * 0.030, x + r.width * 0.050, eyeY),
        stroke,
      );
    }

    void happyEye(double x) {
      canvas.drawPath(
        Path()
          ..moveTo(x - r.width * 0.055, eyeY + r.height * 0.020)
          ..quadraticBezierTo(x, eyeY - r.height * 0.060, x + r.width * 0.055, eyeY + r.height * 0.020),
        stroke,
      );
    }

    void sadEye(double x) {
      canvas.drawPath(
        Path()
          ..moveTo(x - r.width * 0.050, eyeY + r.height * 0.020)
          ..quadraticBezierTo(x, eyeY - r.height * 0.030, x + r.width * 0.050, eyeY + r.height * 0.020),
        stroke,
      );
    }

    void angledEye(double x, bool left) {
      final dir = left ? 1.0 : -1.0;
      canvas.drawLine(
        Offset(x - dir * r.width * 0.045, eyeY - r.height * 0.020),
        Offset(x + dir * r.width * 0.045, eyeY + r.height * 0.020),
        stroke,
      );
    }

    void loveEye(double x) {
      final h = Path()
        ..moveTo(x, eyeY + r.height * 0.030)
        ..quadraticBezierTo(x - r.width * 0.060, eyeY - r.height * 0.040, x - r.width * 0.018, eyeY - r.height * 0.030)
        ..quadraticBezierTo(x, eyeY - r.height * 0.014, x, eyeY + r.height * 0.004)
        ..quadraticBezierTo(x, eyeY - r.height * 0.014, x + r.width * 0.018, eyeY - r.height * 0.030)
        ..quadraticBezierTo(x + r.width * 0.060, eyeY - r.height * 0.040, x, eyeY + r.height * 0.030)
        ..close();
      canvas.drawPath(h, dark);
    }

    // 五官三档对每个角色都生效：简约＝竖条眼，圆点＝小圆眼；
    // 「开心」仍画弧线，免得情绪全被档位吃掉。
    // 五官档位优先于情绪：选简约/圆点后眼睛形状固定，情绪只走嘴和特效。
    final fixedFace = spec.face != MascotFace.standard;
    void simpleEye(double x) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, eyeY), width: r.width * 0.11, height: r.height * 0.20),
        Radius.circular(r.width * 0.055),
      ),
      dark,
    );
    void dotEye(double x) => canvas.drawCircle(Offset(x, eyeY), r.width * 0.048, dark);

    for (final (x, left) in [(lx, true), (rx, false)]) {
      // 自动眨眼：眼白类才眨，弧线/爱心/生气保持原样。
      if (blinking && !fixedFace && !const {'happy', 'closed', 'love', 'angry', 'cry'}.contains(eyes)) {
        closedEye(x);
        continue;
      }
      if (fixedFace) {
        if (spec.face == MascotFace.simple) {
          simpleEye(x);
        } else {
          dotEye(x);
        }
        continue;
      }
      switch (eyes) {
        case 'closed':
          closedEye(x);
        case 'happy':
          happyEye(x);
        case 'sad':
          sadEye(x);
        case 'wide':
          roundEye(x, r.width * 0.060);
        case 'thinking':
          roundEye(x, r.width * 0.048, dx: -r.width * 0.010, dy: -r.height * 0.014);
        case 'angry':
          angledEye(x, left);
        case 'love':
          loveEye(x);
        case 'cry':
          closedEye(x);
          canvas.drawCircle(Offset(x, eyeY + r.height * 0.075), r.width * 0.016, Paint()..color = const Color(0xFF7FB8E6));
        case 'bored':
          canvas.drawLine(Offset(x - r.width * 0.045, eyeY), Offset(x + r.width * 0.045, eyeY), stroke);
        default:
          roundEye(x, r.width * 0.045);
      }
    }

    final mouthY = eyeY + r.height * 0.16;
    // 银团的嘴也是磨出来的槽：多数情绪是一枚横胶囊（图标里那枚），
    // 只有皱眉/哭这种需要弧线的才画线。
    void pillMouth({double width = 0.115, double height = 0.045}) {
      final pill = Rect.fromCenter(
        center: Offset(r.center.dx, mouthY + r.height * 0.005),
        width: r.width * width,
        height: r.height * height,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(pill, Radius.circular(pill.height / 2)), dark);
    }

    switch (mouth) {
      case 'smile' when recessed:
      case 'flat' when recessed:
        pillMouth();
      case 'open' when recessed:
        pillMouth(width: 0.10, height: 0.075);
      case 'talk' when recessed:
        pillMouth(width: 0.09, height: 0.060);
      case 'smile':
        canvas.drawPath(
          Path()
            ..moveTo(r.center.dx - r.width * 0.05, mouthY)
            ..quadraticBezierTo(r.center.dx, mouthY + r.height * 0.06, r.center.dx + r.width * 0.05, mouthY),
          stroke,
        );
      case 'open':
        canvas.drawOval(
          Rect.fromCenter(center: Offset(r.center.dx, mouthY + r.height * 0.02), width: r.width * 0.07, height: r.height * 0.07),
          dark,
        );
      case 'talk':
        canvas.drawOval(
          Rect.fromCenter(center: Offset(r.center.dx, mouthY + r.height * 0.02), width: r.width * 0.06, height: r.height * 0.05),
          dark,
        );
      case 'flat':
        canvas.drawLine(
          Offset(r.center.dx - r.width * 0.04, mouthY),
          Offset(r.center.dx + r.width * 0.04, mouthY),
          stroke,
        );
      case 'frown':
        canvas.drawPath(
          Path()
            ..moveTo(r.center.dx - r.width * 0.05, mouthY + r.height * 0.02)
            ..quadraticBezierTo(r.center.dx, mouthY - r.height * 0.02, r.center.dx + r.width * 0.05, mouthY + r.height * 0.02),
          stroke,
        );
      default:
        if (recessed) {
          pillMouth(width: 0.085, height: 0.042);
        } else {
          // neutral
          canvas.drawLine(
            Offset(r.center.dx - r.width * 0.03, mouthY),
            Offset(r.center.dx + r.width * 0.03, mouthY),
            stroke,
          );
        }
    }
    canvas.restore();
  }

  // ── 特效：星空/爱心/睡眠/加载环（锚点按引擎的 head/face/body） ─────────
  void _drawEffect(Canvas canvas, Size size, String? effect, double t, {required Offset head}) {
    final s = size.shortestSide;
    switch (effect) {
      case 'sparkles':
        // 头顶一圈金色四角星，闪烁。
        const gold = Color(0xFFFFD76A);
        for (var i = 0; i < 4; i++) {
          final angle = -math.pi / 2 + (i - 1.5) * 0.55 + math.sin(t + i) * 0.05;
          final radius = s * (0.24 + 0.03 * math.sin(t * 2 + i));
          final center = head + Offset(math.cos(angle) * radius, math.sin(angle) * radius * 0.7);
          final twinkle = 0.55 + 0.45 * math.sin(t * 2 + i * 1.3).abs();
          _sparkleStar(canvas, center, s * 0.045 * twinkle, gold.withValues(alpha: 0.55 + 0.45 * twinkle));
        }
      case 'hearts':
        const pink = Color(0xFFFF7B9C);
        for (var i = 0; i < 3; i++) {
          final rise = ((t / (2 * math.pi)) + i / 3) % 1;
          final center = head + Offset((i - 1) * s * 0.10 + math.sin(t * 2 + i) * s * 0.01, -rise * s * 0.22);
          _heart(canvas, center, s * 0.045, pink.withValues(alpha: (1 - rise).clamp(0.0, 1.0)));
        }
      case 'sleep':
        const ink = Color(0xFF8FA6C2);
        for (var i = 0; i < 2; i++) {
          final rise = ((t / (2 * math.pi)) + i / 2) % 1;
          final center = head + Offset(s * (0.10 + i * 0.05), -rise * s * 0.20 - s * 0.02);
          _zed(canvas, center, s * (0.05 + i * 0.012), ink.withValues(alpha: (1 - rise).clamp(0.0, 1.0)));
        }
      case 'loading':
        // 身体周围一圈转动的弧。
        final rect = Rect.fromCircle(center: Offset(size.width / 2, size.height * 0.66), radius: s * 0.52);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.035
          ..strokeCap = StrokeCap.round
          ..color = accent.withValues(alpha: 0.85);
        canvas.drawArc(rect, t, math.pi * 0.5, false, paint);
        canvas.drawArc(rect, t + math.pi, math.pi * 0.35, false, paint..color = accent.withValues(alpha: 0.35));
    }
  }


  void _heart(Canvas canvas, Offset center, double r, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy + r)
      ..cubicTo(center.dx - r * 2, center.dy - r * 0.5, center.dx - r * 1.0, center.dy - r * 2.0, center.dx, center.dy - r * 0.6)
      ..cubicTo(center.dx + r * 1.0, center.dy - r * 2.0, center.dx + r * 2, center.dy - r * 0.5, center.dx, center.dy + r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _zed(Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - size * 0.5, center.dy - size * 0.5)
        ..lineTo(center.dx + size * 0.5, center.dy - size * 0.5)
        ..lineTo(center.dx - size * 0.5, center.dy + size * 0.5)
        ..lineTo(center.dx + size * 0.5, center.dy + size * 0.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(MascotPainter oldDelegate) =>
      oldDelegate.spec != spec ||
      oldDelegate.emotion != emotion ||
      oldDelegate.letter != letter ||
      oldDelegate.clock != clock ||
      oldDelegate.period != period ||
      oldDelegate.gaze != gaze ||
      oldDelegate.body != body ||
      oldDelegate.phase != phase ||
      oldDelegate.dark != dark;
}

Color _lighten(Color color, double amount) => Color.lerp(color, Colors.white, amount)!;
Color _darken(Color color, double amount) => Color.lerp(color, Colors.black, amount)!;
