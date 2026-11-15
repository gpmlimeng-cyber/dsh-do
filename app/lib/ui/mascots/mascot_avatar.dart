// 吉祥物头像：把 lively-mascot（MIT）的 5 个角色用 Flutter 原生重绘。
//
// 为什么不内嵌：它是 CSS/SVG 的 Web 引擎，列表里几十个 WebView 会卡；这里一个
// CustomPainter 画完，列表用 `animate: false` 时不起 ticker。
//
// 形状对照（lively-mascot dist/characters/*.css）：
//   sprout 碗 + 顶上一片叶子；cat 圆身 + 双耳；robot 圆角方身 + 天线；
//   ghost 圆顶 + 波浪底；jelly 半球 + 果冻光泽。
// 3D：径向渐变 + 底部内阴影 + 高光，**不描边**（用户要求）。
//
// 动画三档：活泼（弹跳）/ 安静（呼吸）/ 好奇（侧头看）。
// 参数化：角色 5、五官 3、预设色 6、动作 3；`MascotSpec.random` 给「随机换一个」。
//
// 文案随本地双语表（本机生成不了 l10n gen），键名对齐将来的 arb。
// l10n:keep-begin 吉祥物本地名称（迁移到 arb 前不参与扫描）
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 5 个角色，顺序即选择器里的顺序。
enum MascotCharacter {
  sprout('芽团', 'Sprout'),
  cat('猫团', 'Cat'),
  robot('机团', 'Robot'),
  ghost('幽团', 'Ghost'),
  jelly('果冻', 'Jelly');

  const MascotCharacter(this.zh, this.en);
  final String zh;
  final String en;
}

/// 3 种五官。
enum MascotFace {
  gentle('温和', 'Gentle'),
  curious('机灵', 'Curious'),
  happy('呆萌', 'Happy');

  const MascotFace(this.zh, this.en);
  final String zh;
  final String en;
}

/// 3 档动作。
enum MascotMotion {
  lively('活泼', 'Lively', '轻快、有弹性'),
  quiet('安静', 'Quiet', '缓慢、克制'),
  curious('好奇', 'Curious', '目光先行');

  const MascotMotion(this.zh, this.en, this.hintZh);
  final String zh;
  final String en;
  final String hintZh;
}

/// 6 个预设色（名字与 Miffan 对齐：经典 / 抹茶 / 樱花 / 月光 / 海盐 / 墨玉）。
enum MascotColor {
  classic('经典', 'Classic', Color(0xFFE8833A)),
  matcha('抹茶', 'Matcha', Color(0xFF7BA05B)),
  sakura('樱花', 'Sakura', Color(0xFFE48093)),
  moonlight('月光', 'Moonlight', Color(0xFF5B5E8C)),
  seasalt('海盐', 'Sea salt', Color(0xFF4A9E9E)),
  inkJade('墨玉', 'Ink jade', Color(0xFF2F5D50));

  const MascotColor(this.zh, this.en, this.ink);
  final String zh;
  final String en;

  /// 身体的主色；渐变和高光都从这里推。
  final Color ink;

  /// 跟着 App 主题走时用它（`MascotSpec.followAppColor`）。
  static Color fromTheme(ColorScheme scheme) => scheme.primary;

  /// 写进宿主 `bot.color` 的名字：宿主只认色名白名单，不收 hex（架构核过
  /// `ds-bot/src/host/constants.js`）。只影响文字头像底色和其他端，吉祥物自身
  /// 用 [ink] 画。
  String get hostName => switch (this) {
    MascotColor.classic => 'orange',
    MascotColor.matcha => 'green',
    MascotColor.sakura => 'magenta',
    MascotColor.moonlight => 'violet',
    MascotColor.seasalt => 'cyan',
    MascotColor.inkJade => 'deepseek',
  };
}

/// 头像的全部可配置项。序列化用 [toJson]/[fromJson]（键名对应架构定的本地配置）。
class MascotSpec {
  const MascotSpec({
    this.character = MascotCharacter.sprout,
    this.face = MascotFace.gentle,
    this.motion = MascotMotion.lively,
    this.color = MascotColor.classic,
    this.followAppColor = false,
    this.seed = 0,
  });

  final MascotCharacter character;
  final MascotFace face;
  final MascotMotion motion;
  final MascotColor color;

  /// 跟着 App 主题色/深浅色变（Miffan 的「跟着 App 换颜色」）。
  final bool followAppColor;

  /// 「随机换一个」用的种子：存下来就能复现同一个随机样子。
  final int seed;

  MascotSpec copyWith({
    MascotCharacter? character,
    MascotFace? face,
    MascotMotion? motion,
    MascotColor? color,
    bool? followAppColor,
    int? seed,
  }) => MascotSpec(
    character: character ?? this.character,
    face: face ?? this.face,
    motion: motion ?? this.motion,
    color: color ?? this.color,
    followAppColor: followAppColor ?? this.followAppColor,
    seed: seed ?? this.seed,
  );

  /// 「芽团 · 月光 · 好奇」。
  String get caption => '${character.zh} · ${color.zh} · ${motion.zh}';

  Map<String, Object?> toJson() => {
    'character': character.name,
    'face': face.name,
    'motion': motion.name,
    'color': color.name,
    'followAppColor': followAppColor,
    'seed': seed,
  };

  factory MascotSpec.fromJson(Object? json) {
    if (json is! Map) return const MascotSpec();
    return MascotSpec(
      character: _byName(MascotCharacter.values, json['character'], MascotCharacter.sprout),
      face: _byName(MascotFace.values, json['face'], MascotFace.gentle),
      motion: _byName(MascotMotion.values, json['motion'], MascotMotion.lively),
      color: _byName(MascotColor.values, json['color'], MascotColor.classic),
      followAppColor: json['followAppColor'] == true,
      seed: json['seed'] is int ? json['seed'] as int : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MascotSpec &&
      other.character == character &&
      other.face == face &&
      other.motion == motion &&
      other.color == color &&
      other.followAppColor == followAppColor &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(character, face, motion, color, followAppColor, seed);

  /// Miffan 的「随机换一个」：角色和颜色都换掉，动作随机（五官不动），
  /// 种子存下来可以复现。与 `random` 的区别是「整组不同」不够——只换动作也算
  /// 不同，这里按产品规则必须换角色和颜色。
  factory MascotSpec.randomDifferent(MascotSpec avoid, math.Random random) {
    final seed = random.nextInt(1 << 31);
    final r = math.Random(seed);
    // 角色：从另外 4 只里挑。
    final others = [for (final c in MascotCharacter.values) if (c != avoid.character) c];
    // 颜色：从另外 6 色里挑。
    final colors = [for (final c in MascotColor.values) if (c != avoid.color) c];
    return MascotSpec(
      character: others[r.nextInt(others.length)],
      face: avoid.face,
      motion: MascotMotion.values[r.nextInt(MascotMotion.values.length)],
      color: colors[r.nextInt(colors.length)],
      seed: seed,
    );
  }

  /// 「随机换一个」：用种子生成，存下 [seed] 就能复现。
  factory MascotSpec.random(math.Random random, {int? seed}) {
    final s = seed ?? random.nextInt(1 << 31);
    final r = math.Random(s);
    return MascotSpec(
      character: MascotCharacter.values[r.nextInt(MascotCharacter.values.length)],
      face: MascotFace.values[r.nextInt(MascotFace.values.length)],
      motion: MascotMotion.values[r.nextInt(MascotMotion.values.length)],
      color: MascotColor.values[r.nextInt(MascotColor.values.length)],
      seed: s,
    );
  }
}

/// 一条情绪配方：lively-mascot `LivelyEmotionRecipes` 的绘制意图。
/// 状态到情绪的映射归 `state/`（架构的 `emotionFor`）；这里只认 id 和怎么画。
class MascotExpression {
  const MascotExpression(this.eyes, this.mouth, this.top, this.body, {this.effect});
  final String eyes;
  final String mouth;
  final String top;
  final String body;
  final String? effect;
}

/// 40 条，键就是 lively-mascot 的两位 id。
const mascotExpressions = <String, MascotExpression>{
  '00': MascotExpression('closed', 'flat', 'droop', 'rest', effect: 'sleep'),
  '01': MascotExpression('wide', 'open', 'perk', 'wake'),
  '02': MascotExpression('open', 'neutral', 'idle', 'idle'),
  '03': MascotExpression('open', 'neutral', 'idle', 'breathe'),
  '04': MascotExpression('open', 'neutral', 'perk', 'breathe'),
  '05': MascotExpression('sad', 'flat', 'droop', 'rest'),
  '06': MascotExpression('open', 'neutral', 'work', 'refresh'),
  '07': MascotExpression('sad', 'frown', 'droop', 'dim'),
  '08': MascotExpression('closed', 'flat', 'droop', 'dim'),
  '09': MascotExpression('wide', 'open', 'perk', 'wake'),
  '10': MascotExpression('happy', 'smile', 'perk', 'bounce', effect: 'sparkles'),
  '11': MascotExpression('wide', 'open', 'perk', 'work'),
  '12': MascotExpression('sad', 'frown', 'droop', 'dim'),
  '13': MascotExpression('angry', 'frown', 'shake', 'shake'),
  '14': MascotExpression('wide', 'open', 'perk', 'wake'),
  '15': MascotExpression('sad', 'smile', 'droop', 'work'),
  '16': MascotExpression('love', 'smile', 'perk', 'pulse', effect: 'hearts'),
  '17': MascotExpression('sad', 'frown', 'work', 'work'),
  '18': MascotExpression('open', 'smile', 'perk', 'idle'),
  '19': MascotExpression('open', 'smile', 'perk', 'work'),
  '20': MascotExpression('thinking', 'flat', 'work', 'work'),
  '21': MascotExpression('open', 'neutral', 'listen', 'work'),
  '22': MascotExpression('open', 'talk', 'work', 'work'),
  '23': MascotExpression('open', 'neutral', 'work', 'work'),
  '24': MascotExpression('thinking', 'smile', 'work', 'work'),
  '25': MascotExpression('thinking', 'neutral', 'work', 'work'),
  '26': MascotExpression('thinking', 'flat', 'work', 'work'),
  '27': MascotExpression('happy', 'smile', 'work', 'work'),
  '28': MascotExpression('thinking', 'flat', 'idle', 'bounce', effect: 'loading'),
  '29': MascotExpression('thinking', 'flat', 'work', 'work'),
  '30': MascotExpression('happy', 'smile', 'perk', 'bounce', effect: 'sparkles'),
  '31': MascotExpression('closed', 'frown', 'shake', 'shake'),
  '32': MascotExpression('happy', 'smile', 'perk', 'pulse', effect: 'hearts'),
  '33': MascotExpression('thinking', 'neutral', 'work', 'work'),
  '34': MascotExpression('sad', 'frown', 'droop', 'rest'),
  '35': MascotExpression('cry', 'frown', 'droop', 'dim'),
  '36': MascotExpression('bored', 'flat', 'droop', 'rest'),
  '37': MascotExpression('sad', 'neutral', 'shake', 'shake'),
  '38': MascotExpression('wide', 'smile', 'perk', 'bounce', effect: 'sparkles'),
  '39': MascotExpression('open', 'flat', 'idle', 'work'),
};

/// 用户的「五官三选」与情绪 id 的兜底：没有情绪时按 spec.face 画。
MascotExpression expressionFor(MascotSpec spec) => switch (spec.face) {
  MascotFace.gentle => const MascotExpression('open', 'smile', 'idle', 'idle'),
  MascotFace.curious => const MascotExpression('wide', 'open', 'perk', 'breathe'),
  MascotFace.happy => const MascotExpression('happy', 'smile', 'perk', 'bounce'),
};

/// 一个吉祥物头像。
///
/// [animate] 为 false 时是纯静态一帧（列表、消息行用），不创建 ticker；
/// 预览区和自定义页才传 true。
class MascotAvatar extends StatefulWidget {
  const MascotAvatar({super.key, required this.spec, this.emotion, this.size = 48, this.animate = false});

  final MascotSpec spec;

  /// 会话状态对应的情绪 id（`mascotExpressions` 的键，如 `'20'`）；null 时按
  /// spec.face 画。列表里只画这一帧，不跑动画。
  final String? emotion;
  final double size;
  final bool animate;

  @override
  State<MascotAvatar> createState() => _MascotAvatarState();
}

class _MascotAvatarState extends State<MascotAvatar> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _start();
  }

  @override
  void didUpdateWidget(MascotAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && _controller == null) _start();
    if (!widget.animate && _controller != null) _stop();
    if (widget.animate && _controller != null && oldWidget.spec.motion != widget.spec.motion) {
      _controller!.duration = _durationOf(widget.spec.motion);
      _controller!
        ..reset()
        ..repeat();
    }
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = widget.spec.followAppColor ? MascotColor.fromTheme(scheme) : widget.spec.color.ink;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.square(
      dimension: widget.size,
      child: _controller == null
          ? CustomPaint(painter: MascotPainter(spec: widget.spec, emotion: widget.emotion, body: body, phase: 0.35, dark: dark), size: Size.square(widget.size))
          : AnimatedBuilder(
              animation: _controller!,
              builder: (context, _) => CustomPaint(
                painter: MascotPainter(spec: widget.spec, emotion: widget.emotion, body: body, phase: _controller!.value, dark: dark),
                size: Size.square(widget.size),
              ),
            ),
    );
  }
}

/// 画一帧。[phase] 0..1 是按 [MascotSpec.motion] 走的时间。
class MascotPainter extends CustomPainter {
  const MascotPainter({required this.spec, required this.body, required this.phase, this.dark = false, this.emotion});

  final MascotSpec spec;
  final String? emotion;
  final Color body;
  final double phase;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final t = phase * 2 * math.pi;
    final expression = emotion == null ? expressionFor(spec) : (mascotExpressions[emotion] ?? expressionFor(spec));

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

    final rect = Rect.fromLTWH(s * 0.10, s * 0.20, s * 0.80, s * 0.70);
    final top = _lighten(body, 0.34);
    final bottom = _darken(body, 0.30);

    // 身体底色：径向渐变（光从左上）。
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.45, -0.6),
        radius: 1.1,
        colors: [top, body, bottom],
        stops: const [0, 0.55, 1],
      ).createShader(rect);

    final path = switch (spec.character) {
      MascotCharacter.sprout => _bowl(rect),
      MascotCharacter.cat => _cat(rect),
      MascotCharacter.robot => _robot(rect),
      MascotCharacter.ghost => _ghost(rect),
      MascotCharacter.jelly => _jelly(rect),
    };
    canvas.drawPath(path, bodyPaint);

    // 底部内阴影：让身体看上去是立体的。
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
    // 高光：左上角一小块弧形。
    canvas.drawOval(
      Rect.fromCenter(center: Offset(rect.left + rect.width * 0.30, rect.top + rect.height * 0.22), width: rect.width * 0.34, height: rect.height * 0.20),
      Paint()..color = Colors.white.withValues(alpha: dark ? 0.22 : 0.38),
    );
    canvas.restore();

    // 角色专属零件（叶子/耳朵/天线/呆毛）。
    _charParts(canvas, size, rect, t, expression.top);

    // 五官。
    _face(canvas, rect, t, expression.eyes, expression.mouth);

    canvas.restore();
  }

  // ── 身体形状 ──

  Path _bowl(Rect r) {
    // 陶碗：上宽下窄，碗口一圈亮边。
    final path = Path()
      ..moveTo(r.left + r.width * 0.06, r.top + r.height * 0.18)
      ..quadraticBezierTo(r.center.dx, r.top + r.height * 0.02, r.right - r.width * 0.06, r.top + r.height * 0.18)
      ..quadraticBezierTo(r.right + r.width * 0.02, r.center.dy + r.height * 0.10, r.center.dx + r.width * 0.34, r.bottom - r.height * 0.04)
      ..quadraticBezierTo(r.center.dx, r.bottom + r.height * 0.06, r.center.dx - r.width * 0.34, r.bottom - r.height * 0.04)
      ..quadraticBezierTo(r.left - r.width * 0.02, r.center.dy + r.height * 0.10, r.left + r.width * 0.06, r.top + r.height * 0.18)
      ..close();
    return path;
  }

  Path _cat(Rect r) {
    final path = Path()..addOval(r.deflate(0));
    // 两只三角形耳朵。
    for (final left in [true, false]) {
      final x = left ? r.left + r.width * 0.16 : r.right - r.width * 0.16;
      final dir = left ? -1.0 : 1.0;
      final ear = Path()
        ..moveTo(x, r.top + r.height * 0.10)
        ..lineTo(x + dir * r.width * 0.12, r.top - r.height * 0.16)
        ..lineTo(x + dir * r.width * 0.26, r.top + r.height * 0.04)
        ..close();
      path.addPath(ear, Offset.zero);
    }
    return path;
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

  // ── 角色专属零件 ──

  void _charParts(Canvas canvas, Size size, Rect r, double t, String top) {
    switch (spec.character) {
      case MascotCharacter.sprout:
        // 茎 + 叶，随动作轻摆。
        final sway = switch (top) {
          'perk' => math.sin(t) * 0.10,
          'listen' => math.sin(t * 0.6) * 0.14,
          'work' => math.sin(t * 1.4) * 0.06,
          'shake' => math.sin(t * 6) * 0.05,
          'droop' => 0.28 + math.sin(t * 0.5) * 0.03,
          _ => math.sin(t) * 0.05,
        };
        canvas.save();
        canvas.translate(r.center.dx, r.top + r.height * 0.16);
        canvas.rotate(sway);
        final stem = Paint()
          ..color = _darken(body, 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.018
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset.zero, Offset(0, -r.height * 0.20), stem);
        final leaf = Path()
          ..moveTo(0, -r.height * 0.16)
          ..quadraticBezierTo(r.width * 0.20, -r.height * 0.34, r.width * 0.02, -r.height * 0.40)
          ..quadraticBezierTo(-r.width * 0.06, -r.height * 0.26, 0, -r.height * 0.16)
          ..close();
        canvas.drawPath(leaf, Paint()..color = _lighten(body, 0.10));
        canvas.restore();
      case MascotCharacter.cat:
        // 耳朵内圈。
        for (final left in [true, false]) {
          final x = left ? r.left + r.width * 0.20 : r.right - r.width * 0.20;
          final dir = left ? -1.0 : 1.0;
          final inner = Path()
            ..moveTo(x, r.top + r.height * 0.08)
            ..lineTo(x + dir * r.width * 0.07, r.top - r.height * 0.08)
            ..lineTo(x + dir * r.width * 0.16, r.top + r.height * 0.04)
            ..close();
          canvas.drawPath(inner, Paint()..color = _lighten(body, 0.22).withValues(alpha: 0.85));
        }
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
    }
  }

  // ── 五官 ──

  /// [eyes]/[mouth] 是情绪配方里的词（open/closed/wide/happy/sad/thinking/
  /// angry/love/cry/bored；neutral/smile/open/flat/frown/talk）。
  void _face(Canvas canvas, Rect r, double t, String eyes, String mouth) {
    final gaze = spec.motion == MascotMotion.curious ? math.sin(t) * r.width * 0.035 : 0.0;
    final eyeY = r.top + r.height * 0.44;
    final lx = r.center.dx - r.width * 0.18 + gaze;
    final rx = r.center.dx + r.width * 0.18 + gaze;
    final ink = _darken(body, 0.62);
    final white = Paint()..color = Colors.white.withValues(alpha: 0.92);
    final dark = Paint()..color = ink;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = r.width * 0.024
      ..strokeCap = StrokeCap.round;

    void roundEye(double x, double radius, {double dx = 0, double dy = 0}) {
      canvas.drawCircle(Offset(x, eyeY), radius, dark);
      canvas.drawCircle(Offset(x - radius * 0.35 + dx, eyeY - radius * 0.35 + dy), radius * 0.34, white);
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

    for (final (x, left) in [(lx, true), (rx, false)]) {
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
    switch (mouth) {
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
        // neutral
        canvas.drawLine(
          Offset(r.center.dx - r.width * 0.03, mouthY),
          Offset(r.center.dx + r.width * 0.03, mouthY),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(MascotPainter oldDelegate) =>
      oldDelegate.spec != spec || oldDelegate.emotion != emotion || oldDelegate.body != body || oldDelegate.phase != phase || oldDelegate.dark != dark;
}

/// 按 enum 的 `name` 取值；未知/缺失回落到 [fallback]。
T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

Color _lighten(Color color, double amount) => Color.lerp(color, Colors.white, amount)!;
Color _darken(Color color, double amount) => Color.lerp(color, Colors.black, amount)!;
// l10n:keep-end
