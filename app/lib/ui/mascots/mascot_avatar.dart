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

import '../../l10n/l10n.dart';

/// 10 个角色，顺序即选择器里的顺序（新角色只能加在末尾：顺序是存档索引）。
enum MascotCharacter {
  sprout('芽团', 'Sprout'),
  cat('猫团', 'Cat'),
  robot('机团', 'Robot'),
  ghost('幽团', 'Ghost'),
  jelly('果冻', 'Jelly'),
  orb('圆团', 'Orb'),
  star('星团', 'Star'),
  triangle('角团', 'Triangle'),
  onigiri('饭团', 'Rice ball'),
  potato('芋团', 'Potato');

  const MascotCharacter(this.zh, this.en);
  final String zh;
  String get label => AppLocale.isEnglish ? en : zh;
  final String en;

  /// 角色默认配色（demo 每个角色自带 skin；「跟随默认」用它）。
  MascotSkin get skin => switch (this) {
    MascotCharacter.sprout => const MascotSkin(Color(0xFF48FF42), Color(0xFF080808), Color(0xFFFF9FB6)),
    MascotCharacter.cat => const MascotSkin(Color(0xFF3D4852), Color(0xFF131A20), Color(0xFFEEB3C1)),
    MascotCharacter.robot => const MascotSkin(Color(0xFF6F879B), Color(0xFF162332), Color(0xFF74E5FF)),
    MascotCharacter.ghost => const MascotSkin(Color(0xFFBDEEF2), Color(0xFF23434D), Color(0xFFA9D9FF)),
    MascotCharacter.jelly => const MascotSkin(Color(0xFFF29CC2), Color(0xFF5A243E), Color(0xFFFFE0A8)),
    MascotCharacter.orb => const MascotSkin(Color(0xFFFFD66B), Color(0xFF6B4E00), Color(0xFFFF9FB6)),
    MascotCharacter.star => const MascotSkin(Color(0xFFFFC93C), Color(0xFF5C4300), Color(0xFFFFE9A8)),
    MascotCharacter.triangle => const MascotSkin(Color(0xFF8FE3C8), Color(0xFF1F4A3F), Color(0xFFFFB7C5)),
    MascotCharacter.onigiri => const MascotSkin(Color(0xFFF7F1E3), Color(0xFF3A342A), Color(0xFFF19CA0)),
    MascotCharacter.potato => const MascotSkin(Color(0xFFC8A165), Color(0xFF4A3A1C), Color(0xFFE8C98F)),
  };

  /// 写进宿主 `bot.color` 的色名（model 时按角色映射，架构给的对照表）。
  String get hostColor => switch (this) {
    MascotCharacter.sprout => 'green',
    MascotCharacter.cat => 'charcoal',
    MascotCharacter.robot => 'gray',
    MascotCharacter.ghost => 'cyan',
    MascotCharacter.jelly => 'rose',
    MascotCharacter.orb => 'tangerine',
    MascotCharacter.star => 'yellow',
    MascotCharacter.triangle => 'cyan',
    MascotCharacter.onigiri => 'gray',
    MascotCharacter.potato => 'brown',
  };
}

/// 一个角色/一次配置落到画面上的三种颜色。
class MascotSkin {
  const MascotSkin(this.body, this.ink, this.accent);
  final Color body;
  final Color ink;
  final Color accent;
}

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

/// 五官三档：默认（眼白+瞳孔+高光）/ 简约（竖胶囊）/ 圆点。
/// `wire` 是存储用的名字，照 demo 的 default/minimal/dots。
enum MascotFace {
  standard('default', '默认', 'Default'),
  simple('simple', '简约', 'Simple'),
  dot('dot', '圆点', 'Dot');

  const MascotFace(this.wire, this.zh, this.en);
  final String wire;
  final String zh;
  String get label => AppLocale.isEnglish ? en : zh;
  final String en;
}

/// 3 档动作（动画等级）。
enum MascotMotion {
  lively('活泼', 'Lively', '轻快、有弹性'),
  quiet('安静', 'Quiet', '缓慢、克制'),
  curious('好奇', 'Curious', '目光先行');

  const MascotMotion(this.zh, this.en, this.hintZh);
  final String zh;
  String get label => AppLocale.isEnglish ? en : zh;
  final String en;
  final String hintZh;
}

/// 11 个 demo 预设 + 6 个 Miffan 预设，最后一项「跟随角色默认」按角色 skin 画、不存色值。
enum MascotColor {
  mint('薄荷绿', 'Mint', Color(0xFF48FF42), Color(0xFF080808), Color(0xFFFF9FB6)),
  sky('天空蓝', 'Sky blue', Color(0xFF6EC7FF), Color(0xFF0B1E3A), Color(0xFFFF9FB6)),
  peach('蜜桃橙', 'Peach', Color(0xFFFFB37A), Color(0xFF5C2A12), Color(0xFFFF9FB6)),
  lavender('薰衣草紫', 'Lavender', Color(0xFFC9A6FF), Color(0xFF2E1A4D), Color(0xFFFF9FB6)),
  rose('玫瑰粉', 'Rose', Color(0xFFFF9FB6), Color(0xFF5C1F33), Color(0xFFFFE0A8)),
  lemon('柠檬黄', 'Lemon', Color(0xFFFFE066), Color(0xFF4D3D00), Color(0xFFFF9FB6)),
  charcoal('炭灰', 'Charcoal', Color(0xFF3D4852), Color(0xFF131A20), Color(0xFFEEB3C1)),
  cream('奶油白', 'Cream', Color(0xFFF1E7D8), Color(0xFF463A2E), Color(0xFFFF9FB6)),
  steel('钢蓝', 'Steel blue', Color(0xFF6F879B), Color(0xFF162332), Color(0xFF74E5FF)),
  paleCyan('浅青', 'Pale cyan', Color(0xFFBDEEF2), Color(0xFF23434D), Color(0xFFA9D9FF)),
  berry('莓果粉', 'Berry pink', Color(0xFFF29CC2), Color(0xFF5A243E), Color(0xFFFFE0A8)),

  // Miffan 的 6 个预设色（`MiffanPalette`）：描边色由身体色压暗 40% 算得，不用纯黑。
  // key 带 `miffan` 前缀，避免和旧存档别名（classic/matcha/… → 旧色）撞名。
  miffanClassic('经典', 'Miffan classic', Color(0xFFC76644), Color(0xFF773D29), Color(0xFFFFE8A9)),
  miffanMatcha('抹茶', 'Miffan matcha', Color(0xFF5F7F50), Color(0xFF394C30), Color(0xFFE8F0B4)),
  miffanSakura('樱花', 'Miffan sakura', Color(0xFFC86F83), Color(0xFF78434F), Color(0xFFFFE5D7)),
  miffanMoonlight('月光', 'Miffan moonlight', Color(0xFF5A5F91), Color(0xFF363957), Color(0xFFE2DCF8)),
  miffanSeaSalt('海盐', 'Miffan sea salt', Color(0xFF3E8391), Color(0xFF254F57), Color(0xFFDCF1E8)),
  miffanInkJade('墨玉', 'Miffan ink jade', Color(0xFF354947), Color(0xFF202C2B), Color(0xFF9EDBC3)),

  /// 最后一项「跟随角色默认色」：能存能恢复；实际颜色按角色 skin 取
  /// （`mascotSkinOf`），这里的 hex 只是占位。
  model('跟随默认', 'Model default', Color(0xFF48FF42), Color(0xFF080808), Color(0xFFFF9FB6));

  const MascotColor(this.zh, this.en, this.ink, this.outlineInk, this.accent);
  final String zh;

  /// 界面上的名字：跟随 App 语言。
  String get label => AppLocale.isEnglish ? en : zh;
  final String en;

  /// 身体主色；渐变和高光都从这里推。
  final Color ink;

  /// 这一色的深色（demo 每个预设带自己的 outline）。
  final Color outlineInk;

  /// 腮红/点缀色。
  final Color accent;

  /// 跟着 App 主题走（旧字段，界面不再给入口）。
  static Color fromTheme(ColorScheme scheme) => scheme.primary;

  /// 写进宿主 `bot.color` 的名字（宿主只认色名白名单，不收 hex）。
  String get hostName => switch (this) {
    MascotColor.mint => 'green',
    MascotColor.sky => 'sky',
    MascotColor.peach => 'tangerine',
    MascotColor.lavender => 'violet',
    MascotColor.rose => 'rose',
    MascotColor.lemon => 'yellow',
    MascotColor.charcoal => 'graphite',
    MascotColor.cream => 'gray',
    MascotColor.steel => 'cobalt',
    MascotColor.paleCyan => 'cyan',
    MascotColor.berry => 'magenta',
    MascotColor.miffanClassic => 'tangerine',
    MascotColor.miffanMatcha => 'green',
    MascotColor.miffanSakura => 'rose',
    MascotColor.miffanMoonlight => 'violet',
    MascotColor.miffanSeaSalt => 'cyan',
    MascotColor.miffanInkJade => 'charcoal',
    // model 要看角色，用 `hostColorOf(spec)`。
    MascotColor.model => 'green',
  };
}

/// 视图：2D 扁平 / 3D 渐变 + 内阴影（demo 默认 3D）。
enum MascotView {
  flat('flat', '2D'),
  three('three', '3D');

  const MascotView(this.wire, this.label);
  final String wire;
  final String label;
}

/// 头像的全部可配置项。序列化用 [toJson]/[fromJson]（键名对应架构定的本地配置）。
class MascotSpec {
  const MascotSpec({
    this.character = MascotCharacter.sprout,
    this.face = MascotFace.standard,
    this.motion = MascotMotion.lively,
    this.color = MascotColor.mint,
    this.view = MascotView.three,
    this.outline = false,
    this.body,
    this.eyes,
    this.mouth,
    this.blink = true,
    this.followAppColor = false,
    this.seed = 0,
  });

  final MascotCharacter character;
  final MascotFace face;
  final MascotMotion motion;
  final MascotColor color;

  /// 2D / 3D：3D 有渐变高光与内阴影，2D 是扁平贴纸。
  final MascotView view;

  /// 描边 + 投影（demo 默认开；用户要求默认关，五官的线条始终保留）。
  final bool outline;

  /// 自定义动作编排（demo 那页的三组）：null = 跟随情绪。只在空闲态生效。
  final String? body;
  final String? eyes;
  final String? mouth;

  /// 快速眨眼（默认开）。
  final bool blink;

  /// 选三档预设：清掉自定义编排回到预设组合。
  MascotSpec withPresetMotion(MascotMotion motion) => MascotSpec(
    character: character,
    face: face,
    motion: motion,
    color: color,
    view: view,
    outline: outline,
    blink: blink,
    followAppColor: followAppColor,
    seed: seed,
  );

  /// 动作编排细项已取消：`body/eyes/mouth` 只留着读旧存档，
  /// 渲染和标签都按三档预设走，所以这里恒为 false。
  bool get motionCustom => false;

  /// 跟着 App 主题色/深浅色变（旧字段，界面不再给入口）。
  final bool followAppColor;

  /// 「随机换一个」用的种子：存下来就能复现同一个随机样子。
  final int seed;

  MascotSpec copyWith({
    MascotCharacter? character,
    MascotFace? face,
    MascotMotion? motion,
    MascotColor? color,
    MascotView? view,
    bool? outline,
    String? body,
    String? eyes,
    String? mouth,
    bool? blink,
    bool? followAppColor,
    int? seed,
  }) => MascotSpec(
    character: character ?? this.character,
    face: face ?? this.face,
    motion: motion ?? this.motion,
    color: color ?? this.color,
    view: view ?? this.view,
    outline: outline ?? this.outline,
    body: body ?? this.body,
    eyes: eyes ?? this.eyes,
    mouth: mouth ?? this.mouth,
    blink: blink ?? this.blink,
    followAppColor: followAppColor ?? this.followAppColor,
    seed: seed ?? this.seed,
  );

  /// 三段＝角色 · 颜色 · 表情（五官 · 动作预设）。
  String get caption => '${character.label} · ${color.label} · ${face.label}·${motion.label}';

  Map<String, Object?> toJson() => {
    'character': character.name,
    'face': face.wire,
    'motion': motion.name,
    'color': color.name,
    'view': view.wire,
    'outline': outline,
    // 只有自定义过才写；默认值不写进存档，旧样例断言不受影响。
    if (body != null) 'body': body,
    if (eyes != null) 'eyes': eyes,
    if (mouth != null) 'mouth': mouth,
    if (!blink) 'blink': false,
    'followAppColor': followAppColor,
    'seed': seed,
  };

  factory MascotSpec.fromJson(Object? json) {
    if (json is! Map) return const MascotSpec();
    return MascotSpec(
      character: _byName(MascotCharacter.values, json['character'], MascotCharacter.sprout),
      face: _faceOf(json['face']),
      motion: _byName(MascotMotion.values, json['motion'], MascotMotion.lively),
      color: _colorOf(json['color']),
      // 视图/边框固定：用户定死 3D、不显示外框，读到别的值也按这个跑。
      view: MascotView.three,
      outline: false,
      body: _choiceOf(json['body'], mascotBodyActions),
      eyes: _choiceOf(json['eyes'], mascotEyeStates),
      mouth: _choiceOf(json['mouth'], mascotMouthStates),
      blink: json['blink'] != false,
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
      other.view == view &&
      other.outline == outline &&
      other.body == body &&
      other.eyes == eyes &&
      other.mouth == mouth &&
      other.blink == blink &&
      other.followAppColor == followAppColor &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(character, face, motion, color, view, outline,
      body, eyes, mouth, blink, followAppColor, seed);

  /// Miffan 的「随机换一个」：角色和颜色都换掉，动作随机（五官不动），
  /// 种子存下来可以复现。与 `random` 的区别是「整组不同」不够——只换动作也算
  /// 不同，这里按产品规则必须换角色和颜色。
  factory MascotSpec.randomDifferent(MascotSpec avoid, math.Random random) {
    final seed = random.nextInt(1 << 31);
    final r = math.Random(seed);
    // 角色：从另外 9 只里挑。
    final others = [for (final c in MascotCharacter.values) if (c != avoid.character) c];
    // 颜色：除当前外的 17 个（含 model）；角色和颜色必换。
    final colors = [for (final c in MascotColor.values) if (c != avoid.color) c];
    return MascotSpec(
      character: others[r.nextInt(others.length)],
      face: avoid.face,
      motion: MascotMotion.values[r.nextInt(MascotMotion.values.length)],
      color: colors[r.nextInt(colors.length)],
      view: avoid.view,
      outline: avoid.outline,
      followAppColor: avoid.followAppColor,
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
/// demo「动作编排」页的三组可选值（名字照原文）。
const mascotBodyActions = ['idle', 'breathe', 'wake', 'rest', 'bounce', 'shake', 'pulse', 'work', 'dim', 'refresh'];
const mascotEyeStates = ['open', 'closed', 'happy', 'wide', 'sad', 'angry', 'love', 'thinking', 'bored', 'cry'];
const mascotMouthStates = ['neutral', 'smile', 'open', 'flat', 'frown', 'talk'];

String? _choiceOf(Object? value, List<String> allowed) =>
    value is String && allowed.contains(value) ? value : null;

/// 三档动画等级各自展开成一组身体/眼/嘴（一键预设）。
({String body, String eyes, String mouth}) motionPreset(MascotMotion motion) => switch (motion) {
  MascotMotion.lively => (body: 'bounce', eyes: 'happy', mouth: 'smile'),
  MascotMotion.quiet => (body: 'breathe', eyes: 'open', mouth: 'flat'),
  MascotMotion.curious => (body: 'work', eyes: 'wide', mouth: 'open'),
};

/// 没有情绪时的默认表情：只看三档预设（动作编排细项已取消，旧存档里的值不再生效）。
/// 情绪态永远压过这套。
MascotExpression expressionFor(MascotSpec spec) {
  final preset = motionPreset(spec.motion);
  return MascotExpression(preset.eyes, preset.mouth, 'idle', preset.body);
}

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
    final skin = mascotSkinOf(widget.spec, scheme);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.square(
      dimension: widget.size,
      child: _controller == null
          ? CustomPaint(painter: MascotPainter(spec: widget.spec, emotion: widget.emotion, letter: widget.letter, body: skin.body, ink: skin.ink, accent: skin.accent, phase: 0.35, dark: dark), size: Size.square(widget.size))
          : AnimatedBuilder(
              animation: _controller!,
              builder: (context, _) => CustomPaint(
                painter: MascotPainter(spec: widget.spec, emotion: widget.emotion, letter: widget.letter, body: skin.body, ink: skin.ink, accent: skin.accent, phase: _controller!.value, dark: dark),
                size: Size.square(widget.size),
              ),
            ),
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
  });

  final MascotSpec spec;
  final String? emotion;

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
    final t = phase * 2 * math.pi;
    final expression = emotion == null ? expressionFor(spec) : (mascotExpressions[emotion] ?? expressionFor(spec));
    if (spec.character == MascotCharacter.sprout) {
      _paintSprout(canvas, size, expression, t, letter);
      return;
    }

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
      MascotCharacter.orb => _orb(rect),
      MascotCharacter.star => _star(rect),
      MascotCharacter.triangle => _triangle(rect),
      MascotCharacter.onigiri => _onigiri(rect),
      MascotCharacter.potato => _potato(rect),
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

    // 五官；字团时把五官位置换成名字的首字。
    if (letter case final glyph?) {
      _glyph(canvas, rect, glyph);
    } else {
      _face(canvas, rect, t, expression.eyes, expression.mouth);
    }

    canvas.restore();
    _drawEffect(canvas, size, expression.effect, t, head: Offset(size.width / 2, 0.10 * s));
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

  // 圆团：纯球，没有顶饰。
  Path _orb(Rect r) => Path()..addOval(Rect.fromLTWH(r.left, r.top, r.width, r.height));

  // 星团：五角海星，角是圆的，中间略鼓。
  Path _star(Rect r) {
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
      case MascotCharacter.orb:
      case MascotCharacter.star:
      case MascotCharacter.triangle:
        // 圆团/星团/三角没有额外顶饰。
        break;
    }
  }

  // ── 五官 ──

  /// [eyes]/[mouth] 是情绪配方里的词（open/closed/wide/happy/sad/thinking/
  /// angry/love/cry/bored；neutral/smile/open/flat/frown/talk）。
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

  // ── 芽团（sprout）：按 lively-mascot 的数值 1:1 重画 ────────────────────
  //
  // 坐标系：内容 100 宽 × 148 高——叶子 6..46、身体 40..140、脚 132..148。
  // 数值来源：src/lively-mascot.css（body 圆角/3D 渐变/内阴影/face inset 4/
  // 眼坐标 34,43 与 66,43、眼白 rx10 ry11.5、瞳孔 r6.2、腮红 20/80,57）、
  // src/characters/sprout.model.css|js（border-radius 50% 50% 46% 49%、叶子
  // 37×40 在 top -34、脚的 22×16 椭圆）。
  void _paintSprout(Canvas canvas, Size size, MascotExpression expr, double t, String? letter) {
    const contentW = 100.0;
    const bodyTop = 40.0;
    const contentH = 148.0;
    final s = size.shortestSide;
    final scale = s / contentH;
    final dx = (s - contentW * scale) / 2;
    Offset p(double x, double y) => Offset(dx + x * scale, y * scale);
    // 视图固定 3D、边框固定关（用户定；字段留在存档里互认，这里不读）。
    final three = true;
    final showOutline = false;

    // 身体漂浮：绕 (50, 132) 呼吸，2D 下幅度很小。
    final origin = p(50, 132);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    final breathe = 1 + (expr.body == 'bounce' ? 0.02 : 0.006) * math.sin(t);
    canvas.scale(1.0, breathe);
    canvas.translate(-origin.dx, -origin.dy);

    final bodyRect = Rect.fromLTWH(dx, bodyTop * scale, contentW * scale, 100 * scale);
    final shape = RRect.fromRectAndCorners(
      bodyRect,
      topLeft: Radius.elliptical(50 * scale, 50 * scale),
      topRight: Radius.elliptical(50 * scale, 50 * scale),
      bottomRight: Radius.elliptical(46 * scale, 46 * scale),
      bottomLeft: Radius.elliptical(49 * scale, 49 * scale),
    );

    // 脚：两个深色椭圆（22×16 的 viewBox，left 18 / 60，贴身体底）。
    for (final left in [18.0, 60.0]) {
      canvas.drawOval(
        Rect.fromLTWH(dx + left * scale, 132 * scale, 22 * scale, 16 * scale),
        Paint()..color = ink,
      );
    }

    // 描边/投影（demo 默认开、用户默认关）：2D 硬投影，3D 柔和落影。
    if (showOutline) {
      if (three) {
        canvas.drawRRect(
          shape.shift(Offset(0, 4 * scale)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.18)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * scale),
        );
      } else {
        canvas.drawRRect(shape.shift(Offset(3 * scale, 3 * scale)), Paint()..color = ink.withValues(alpha: 0.55));
      }
    }

    // 身体底色：3D 用渐变 + 三层高光 + 内阴影；2D 是扁平贴纸。
    if (!three) {
      canvas.drawRRect(shape, Paint()..color = body);
    } else {
      canvas.drawRRect(
        shape,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_lighten(body, 0.06), body, _darken(body, 0.10)],
            stops: const [0, 0.55, 1],
          ).createShader(bodyRect),
      );
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawRect(
        bodyRect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.5, -0.64),
            radius: 0.62,
            colors: [Colors.white.withValues(alpha: 0.34), Colors.white.withValues(alpha: 0.17), Colors.white.withValues(alpha: 0)],
            stops: const [0, 0.16, 0.43],
          ).createShader(bodyRect),
      );
      canvas.drawRect(
        bodyRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0.13), Colors.white.withValues(alpha: 0), Colors.black.withValues(alpha: 0.20)],
            stops: const [0, 0.43, 1],
          ).createShader(bodyRect),
      );
      // 内阴影：底部/右下压暗一圈（CSS inset -12 -14 22 / 7 7 14 的近似）。
      canvas.drawRRect(
        shape.deflate(3 * scale),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14 * scale
          ..color = _darken(body, 0.55).withValues(alpha: 0.30)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * scale),
      );
      canvas.restore();
    }
    if (showOutline) {
      canvas.drawRRect(
        shape.deflate(1 * scale),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * scale
          ..color = ink,
      );
    }

    // 五官坐标：face wrap 是身体 inset 4、viewBox 100。
    const faceInset = 4.0;
    const faceScale = 0.92;
    Offset f(double x, double y) => p(faceInset + x * faceScale, bodyTop + faceInset + y * faceScale);
    final u = scale * faceScale;

    _sproutLeaf(canvas, p, scale, expr.top, t);
    if (letter case final glyph?) {
      // 字团：五官位置换成名字首字，不画眼/嘴/腮红。
      _sproutGlyph(canvas, f, u, glyph);
    } else {
      // 腮红。
      for (final cx in [20.0, 80.0]) {
        canvas.drawOval(
          Rect.fromCenter(center: f(cx, 57), width: 14 * u, height: 8 * u),
          Paint()..color = accent.withValues(alpha: 0.75),
        );
      }
      _sproutEyes(canvas, f, u, expr.eyes, t, spec.face, math.sin(t) > 0.997);
      _sproutMouth(canvas, f, u, expr.mouth);
    }
    canvas.restore();
    // 特效锚点在角色头上（engine 的 head 锚点 50,14；按身体比例折算）。
    _drawEffect(canvas, size, expr.effect, t, head: Offset(size.width / 2, 0.16 * size.shortestSide));
  }

  void _sproutGlyph(Canvas canvas, Offset Function(double, double) f, double u, String glyph) {
    final glyphInk = body.computeLuminance() < 0.42 ? Colors.white.withValues(alpha: 0.94) : _darken(body, 0.62);
    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(color: glyphInk, fontSize: 46 * u, fontWeight: FontWeight.w700, height: 1),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final center = f(50, 50);
    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy - painter.height / 2));
  }

  void _sproutEyes(Canvas canvas, Offset Function(double, double) f, double u, String style, double t, MascotFace face, bool blinking) {
    final white = Paint()..color = Colors.white;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final pupilOffset = style == 'thinking' ? Offset(-1.4 * u, -2.0 * u) : Offset.zero;

    for (final cx in [34.0, 66.0]) {
      final center = f(cx, 43);
      if (blinking && face == MascotFace.standard && style != 'happy' && style != 'closed') {
        canvas.drawLine(Offset(center.dx - 8 * u, center.dy), Offset(center.dx + 8 * u, center.dy), line);
        continue;
      }
      // 简约 / 圆点：形状固定，情绪只做轻微姿势（开心变弧线）。
      if (face == MascotFace.simple && style != 'happy') {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: 9 * u, height: 24 * u),
            Radius.circular(4.5 * u),
          ),
          Paint()..color = ink,
        );
        continue;
      }
      if (face == MascotFace.dot && style != 'happy') {
        canvas.drawCircle(center, 5.5 * u, Paint()..color = ink);
        continue;
      }
      switch (style) {
        case 'happy':
          canvas.drawPath(
            Path()
              ..moveTo(center.dx - 8 * u, center.dy + 2.5 * u)
              ..quadraticBezierTo(center.dx, center.dy - 8.5 * u, center.dx + 8 * u, center.dy + 2.5 * u),
            line,
          );
        case 'closed':
          canvas.drawLine(Offset(center.dx - 8 * u, center.dy), Offset(center.dx + 8 * u, center.dy), line);
        case 'sad':
          canvas.drawLine(Offset(center.dx - 8 * u, center.dy + 1 * u), Offset(center.dx + 8 * u, center.dy - 2 * u), line);
        case 'bored':
          canvas.drawPath(
            Path()
              ..moveTo(center.dx - 9 * u, center.dy - 3 * u)
              ..lineTo(center.dx + 9 * u, center.dy - 3 * u)
              ..cubicTo(center.dx + 8 * u, center.dy + 4.5 * u, center.dx + 4 * u, center.dy + 8 * u, center.dx, center.dy + 8 * u)
              ..cubicTo(center.dx - 4 * u, center.dy + 8 * u, center.dx - 8 * u, center.dy + 4.5 * u, center.dx - 9 * u, center.dy - 3 * u)
              ..close(),
            Paint()..color = Colors.white,
          );
        case 'angry':
          canvas.drawOval(Rect.fromCenter(center: center, width: 20 * u, height: 23 * u), white);
          canvas.drawOval(Rect.fromCenter(center: center, width: 20 * u, height: 23 * u), line);
          canvas.drawLine(Offset(center.dx - 9 * u, center.dy - 8 * u), Offset(center.dx + 8 * u, center.dy - 12 * u), line);
        case 'love':
          final heart = Path()
            ..moveTo(center.dx, center.dy + 6 * u)
            ..cubicTo(center.dx - 12 * u, center.dy - 3 * u, center.dx - 6 * u, center.dy - 12 * u, center.dx, center.dy - 4 * u)
            ..cubicTo(center.dx + 6 * u, center.dy - 12 * u, center.dx + 12 * u, center.dy - 3 * u, center.dx, center.dy + 6 * u)
            ..close();
          canvas.drawPath(heart, Paint()..color = ink);
        case 'cry':
          canvas.drawLine(Offset(center.dx - 8 * u, center.dy), Offset(center.dx + 8 * u, center.dy), line);
          canvas.drawCircle(Offset(center.dx, center.dy + 12 * u), 2.4 * u, Paint()..color = const Color(0xFF7FB8E6));
        case 'wide':
          canvas.drawOval(Rect.fromCenter(center: center, width: 22 * u, height: 25 * u), white);
          canvas.drawOval(Rect.fromCenter(center: center, width: 22 * u, height: 25 * u), line);
          canvas.drawCircle(center + pupilOffset, 6.8 * u, Paint()..color = ink);
          canvas.drawCircle(center + pupilOffset + Offset(2.2 * u, -2.4 * u), 2.1 * u, Paint()..color = Colors.white);
        default:
          // open / thinking：眼白 + 瞳孔 + 两处高光（官方 face SVG 同款）。
          canvas.drawOval(Rect.fromCenter(center: center, width: 20 * u, height: 23 * u), white);
          canvas.drawOval(Rect.fromCenter(center: center, width: 20 * u, height: 23 * u), line);
          final pupil = center + pupilOffset;
          canvas.drawCircle(pupil, 6.2 * u, Paint()..color = ink);
          canvas.drawCircle(pupil + Offset(2.2 * u, -2.4 * u), 2.1 * u, Paint()..color = Colors.white);
          canvas.drawCircle(pupil + Offset(-2.2 * u, 2.1 * u), 1.0 * u, Paint()..color = Colors.white.withValues(alpha: 0.82));
      }
    }
  }

  void _sproutMouth(Canvas canvas, Offset Function(double, double) f, double u, String mouth) {
    final ink = _darken(body, 0.86);
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (mouth) {
      case 'open':
      case 'talk':
        final rx = mouth == 'talk' ? 4.0 : 5.0;
        final ry = mouth == 'talk' ? 5.0 : 6.0;
        canvas.drawOval(
          Rect.fromCenter(center: f(50, 65), width: rx * 2 * u, height: ry * 2 * u),
          Paint()..color = ink,
        );
      case 'flat':
        canvas.drawLine(f(43, 65), f(57, 65), line);
      case 'frown':
        canvas.drawPath(
          Path()
            ..moveTo(f(43, 67).dx, f(43, 67).dy)
            ..quadraticBezierTo(f(50, 62).dx, f(50, 62).dy, f(57, 67).dx, f(57, 67).dy),
          line,
        );
      default:
        // smile / neutral：官方默认嘴。
        canvas.drawPath(
          Path()
            ..moveTo(f(42, 63).dx, f(42, 63).dy)
            ..quadraticBezierTo(f(50, 70).dx, f(50, 70).dy, f(58, 63).dx, f(58, 63).dy),
          line,
        );
    }
  }

  void _sproutLeaf(Canvas canvas, Offset Function(double, double) p, double scale, String top, double t) {
    // 叶子 37×40 在 top -34（相对身体）；viewBox 52×56。
    const leafX = 31.5;
    const leafY = 6.0;
    final k = scale * (37 / 52);
    Offset q(double x, double y) => Offset(p(leafX + x * (37 / 52), leafY + y * (40 / 56)).dx, p(leafX + x * (37 / 52), leafY + y * (40 / 56)).dy);
    final sway = switch (top) {
      'perk' => math.sin(t) * 0.10,
      'listen' => math.sin(t * 0.6) * 0.14,
      'work' => math.sin(t * 1.4) * 0.05,
      'shake' => math.sin(t * 6) * 0.05,
      'droop' => 0.30,
      _ => math.sin(t) * 0.04,
    };
    final stemPoint = q(26, 52);
    canvas.save();
    canvas.translate(stemPoint.dx, stemPoint.dy);
    canvas.rotate(sway);
    canvas.translate(-stemPoint.dx, -stemPoint.dy);

    final ink = _darken(body, 0.86);
    final leafFill = Paint()..color = body;
    final leafStroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * k
      ..strokeJoin = StrokeJoin.round;
    final stem = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * k
      ..strokeCap = StrokeCap.round;

    // 茎
    canvas.drawPath(
      Path()
        ..moveTo(q(26, 52).dx, q(26, 52).dy)
        ..cubicTo(q(26, 42).dx, q(26, 42).dy, q(26, 34).dx, q(26, 34).dy, q(26, 27).dx, q(26, 27).dy),
      stem,
    );
    // 两片叶
    for (final left in [true, false]) {
      final path = Path();
      if (left) {
        path.moveTo(q(26, 28).dx, q(26, 28).dy);
        path.cubicTo(q(22, 15).dx, q(22, 15).dy, q(14, 9).dx, q(14, 9).dy, q(6, 12).dx, q(6, 12).dy);
        path.cubicTo(q(5, 20).dx, q(5, 20).dy, q(12, 29).dx, q(12, 29).dy, q(26, 28).dx, q(26, 28).dy);
      } else {
        path.moveTo(q(26, 28).dx, q(26, 28).dy);
        path.cubicTo(q(30, 15).dx, q(30, 15).dy, q(38, 9).dx, q(38, 9).dy, q(46, 12).dx, q(46, 12).dy);
        path.cubicTo(q(47, 20).dx, q(47, 20).dy, q(40, 29).dx, q(40, 29).dy, q(26, 28).dx, q(26, 28).dy);
      }
      path.close();
      canvas.drawPath(path, leafFill);
      canvas.drawPath(path, leafStroke);
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
          _star(canvas, center, s * 0.045 * twinkle, gold.withValues(alpha: 0.55 + 0.45 * twinkle));
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

  void _star(Canvas canvas, Offset center, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isEven ? r : r * 0.38;
      final angle = -math.pi / 2 + i * math.pi / 4;
      final point = center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
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
      oldDelegate.spec != spec || oldDelegate.emotion != emotion || oldDelegate.letter != letter || oldDelegate.body != body || oldDelegate.phase != phase || oldDelegate.dark != dark;
}

/// 按 enum 的 `name`（或 `wire`）取值；未知/缺失回落到 [fallback]。
T _byName<T extends Enum>(List<T> values, Object? name, T fallback, {bool wire = false}) {
  for (final value in values) {
    final key = wire && value is MascotView ? value.wire : value.name;
    if (key == name) return value;
  }
  return fallback;
}

/// 五官：demo 的 default/minimal/dots；旧存档的 gentle/curious/happy 都算 default。
MascotFace _faceOf(Object? value) {
  for (final face in MascotFace.values) {
    if (face.wire == value) return face;
  }
  return MascotFace.standard;
}

/// 颜色：新名；旧存档的六个名字按最近色映射，未知回落薄荷绿。
MascotColor _colorOf(Object? value) => switch (value) {
  'classic' => MascotColor.peach,
  'matcha' => MascotColor.mint,
  'sakura' => MascotColor.rose,
  'moonlight' => MascotColor.lavender,
  'seasalt' => MascotColor.paleCyan,
  'inkJade' => MascotColor.charcoal,
  _ => _byName(MascotColor.values, value, MascotColor.mint),
};

Color _lighten(Color color, double amount) => Color.lerp(color, Colors.white, amount)!;
Color _darken(Color color, double amount) => Color.lerp(color, Colors.black, amount)!;
// l10n:keep-end
