// 吉祥物模型：角色、配色、五官、动作、视图与存档序列化。
//
// 渲染（CustomPainter、配色解析 mascotSkinOf、MascotAvatar）留在
// ui/mascots/mascot_avatar.dart；那边 export 本文件，原来的 import 不用改。
// 状态层（如 bot_avatar_state.dart）只依赖这里，不依赖 ui/。

import 'dart:math' as math;
import 'dart:ui' show Color;

import '../l10n/l10n.dart';

// l10n:keep-begin 吉祥物本地名称（迁移到 arb 前不参与扫描）

/// 12 个角色，顺序即选择器里的顺序（顺序是选择器顺序，存档按名字读写）。
enum MascotCharacter {
  // 银团（App 图标那颗银灰石）排第一：它是主 Bot 的默认形象，
  // 选择器和新 Bot 的预览都按枚举顺序取第一个。
  pebble('银团', 'Pebble'),
  robot('机团', 'Robot'),
  ghost('幽团', 'Ghost'),
  jelly('果冻', 'Jelly'),
  orb('圆团', 'Orb'),
  star('星团', 'Star'),
  triangle('角团', 'Triangle'),
  onigiri('饭团', 'Rice ball'),
  potato('芋团', 'Potato'),
  orange('橘团', 'Orange'),
  pear('梨团', 'Pear'),
  mango('芒团', 'Mango');

  const MascotCharacter(this.zh, this.en);
  final String zh;
  String get label => AppLocale.isEnglish ? en : zh;
  final String en;

  /// 角色自己的默认配色（demo 每个角色自带 skin），新 Bot 的模板和派生用得上。
  MascotSkin get skin => switch (this) {
    MascotCharacter.robot => const MascotSkin(Color(0xFF6F879B), Color(0xFF162332), Color(0xFF74E5FF)),
    MascotCharacter.ghost => const MascotSkin(Color(0xFFBDEEF2), Color(0xFF23434D), Color(0xFFA9D9FF)),
    MascotCharacter.jelly => const MascotSkin(Color(0xFFF29CC2), Color(0xFF5A243E), Color(0xFFFFE0A8)),
    MascotCharacter.orb => const MascotSkin(Color(0xFFFFD66B), Color(0xFF6B4E00), Color(0xFFFF9FB6)),
    MascotCharacter.star => const MascotSkin(Color(0xFFFFC93C), Color(0xFF5C4300), Color(0xFFFFE9A8)),
    MascotCharacter.triangle => const MascotSkin(Color(0xFF8FE3C8), Color(0xFF1F4A3F), Color(0xFFFFB7C5)),
    MascotCharacter.onigiri => const MascotSkin(Color(0xFFF7F1E3), Color(0xFF3A342A), Color(0xFFF19CA0)),
    MascotCharacter.potato => const MascotSkin(Color(0xFFC8A165), Color(0xFF4A3A1C), Color(0xFFE8C98F)),
    MascotCharacter.orange => const MascotSkin(Color(0xFFF5811F), Color(0xFF934D13), Color(0xFFFFD7A0)),
    MascotCharacter.pear => const MascotSkin(Color(0xFFC7D96B), Color(0xFF778240), Color(0xFFF0EFC9)),
    MascotCharacter.mango => const MascotSkin(Color(0xFFEFA13F), Color(0xFF8F6126), Color(0xFFFFE1A8)),
    // 银团：App 图标那颗银灰磨砂石（灰度取自 brand-icon-source.jpg）。
    MascotCharacter.pebble => const MascotSkin(Color(0xFFC9CED5), Color(0xFF1A2230), Color(0xFFA8C6DA)),
  };

  /// 写进宿主 `bot.color` 的色名（model 时按角色映射，架构给的对照表）。
  String get hostColor => switch (this) {
    MascotCharacter.robot => 'gray',
    MascotCharacter.ghost => 'cyan',
    MascotCharacter.jelly => 'rose',
    MascotCharacter.orb => 'tangerine',
    MascotCharacter.star => 'yellow',
    MascotCharacter.triangle => 'cyan',
    MascotCharacter.onigiri => 'gray',
    MascotCharacter.potato => 'brown',
    MascotCharacter.orange => 'orange',
    MascotCharacter.pear => 'yellow',
    MascotCharacter.mango => 'tangerine',
    MascotCharacter.pebble => 'gray',
  };
}

/// 一个角色/一次配置落到画面上的三种颜色。
class MascotSkin {
  const MascotSkin(this.body, this.ink, this.accent);
  final Color body;
  final Color ink;
  final Color accent;
}

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
  lively('活泼', 'Lively', '轻快、有弹性', 'Light and springy'),
  quiet('安静', 'Quiet', '缓慢、克制', 'Slow and steady'),
  curious('好奇', 'Curious', '目光先行', 'Looks around first');

  const MascotMotion(this.zh, this.en, this.hintZh, this.hintEn);
  final String zh;
  String get label => AppLocale.isEnglish ? en : zh;
  final String en;
  final String hintZh;
  final String hintEn;

  /// 卡片上的一句说明。
  String get hint => AppLocale.isEnglish ? hintEn : hintZh;
}

/// 9 个 demo 预设 + 6 个 Miffan 预设 + 1 个品牌银灰；「跟随角色默认」已下线，颜色只认具体色值。
enum MascotColor {
  mint('薄荷绿', 'Mint', Color(0xFF48FF42), Color(0xFF080808), Color(0xFFFF9FB6)),
  sky('天空蓝', 'Sky blue', Color(0xFF6EC7FF), Color(0xFF0B1E3A), Color(0xFFFF9FB6)),
  peach('蜜桃橙', 'Peach', Color(0xFFFFB37A), Color(0xFF5C2A12), Color(0xFFFF9FB6)),
  lavender('薰衣草紫', 'Lavender', Color(0xFFC9A6FF), Color(0xFF2E1A4D), Color(0xFFFF9FB6)),
  rose('玫瑰粉', 'Rose', Color(0xFFFF9FB6), Color(0xFF5C1F33), Color(0xFFFFE0A8)),
  lemon('柠檬黄', 'Lemon', Color(0xFFFFE066), Color(0xFF4D3D00), Color(0xFFFF9FB6)),
  cream('奶油白', 'Cream', Color(0xFFF1E7D8), Color(0xFF463A2E), Color(0xFFFF9FB6)),
  steel('钢蓝', 'Steel blue', Color(0xFF6F879B), Color(0xFF162332), Color(0xFF74E5FF)),
  paleCyan('浅青', 'Pale cyan', Color(0xFFBDEEF2), Color(0xFF23434D), Color(0xFFA9D9FF)),

  // Miffan 的 6 个预设色（`MiffanPalette`）：描边色由身体色压暗 40% 算得，不用纯黑。
  // key 带 `miffan` 前缀，避免和旧存档别名（classic/matcha/… → 旧色）撞名。
  miffanClassic('经典', 'Miffan classic', Color(0xFFC76644), Color(0xFF773D29), Color(0xFFFFE8A9)),
  miffanMatcha('抹茶', 'Miffan matcha', Color(0xFF5F7F50), Color(0xFF394C30), Color(0xFFE8F0B4)),
  miffanSakura('樱花', 'Miffan sakura', Color(0xFFC86F83), Color(0xFF78434F), Color(0xFFFFE5D7)),
  miffanMoonlight('月光', 'Miffan moonlight', Color(0xFF5A5F91), Color(0xFF363957), Color(0xFFE2DCF8)),
  miffanSeaSalt('海盐', 'Miffan sea salt', Color(0xFF3E8391), Color(0xFF254F57), Color(0xFFDCF1E8)),
  miffanInkJade('墨玉', 'Miffan ink jade', Color(0xFF354947), Color(0xFF202C2B), Color(0xFF9EDBC3)),

  /// 银灰：App 图标那颗石头的本色（数据取自 brand-icon-source.jpg），
  /// 和银团的默认 skin 是同一组颜色。
  silver('银灰', 'Silver', Color(0xFFC9CED5), Color(0xFF4A525E), Color(0xFFA8C6DA));

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

  /// 写进宿主 `bot.color` 的名字（宿主只认色名白名单，不收 hex）。
  String get hostName => switch (this) {
    MascotColor.mint => 'green',
    MascotColor.sky => 'sky',
    MascotColor.peach => 'tangerine',
    MascotColor.lavender => 'violet',
    MascotColor.rose => 'rose',
    MascotColor.lemon => 'yellow',
    MascotColor.cream => 'gray',
    MascotColor.steel => 'cobalt',
    MascotColor.paleCyan => 'cyan',
    MascotColor.miffanClassic => 'tangerine',
    MascotColor.miffanMatcha => 'green',
    MascotColor.miffanSakura => 'rose',
    MascotColor.miffanMoonlight => 'violet',
    MascotColor.miffanSeaSalt => 'cyan',
    MascotColor.miffanInkJade => 'charcoal',
    MascotColor.silver => 'gray',
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
    this.character = MascotCharacter.pebble,
    this.face = MascotFace.standard,
    this.motion = MascotMotion.lively,
    this.color = MascotColor.mint,
    this.view = MascotView.flat,
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
      character: _byName(MascotCharacter.values, json['character'], MascotCharacter.pebble),
      face: _faceOf(json['face']),
      motion: _byName(MascotMotion.values, json['motion'], MascotMotion.lively),
      color: _colorOf(json['color']),
      // 视图：默认 2D；存过 three 的旧存档保持 3D。边框仍固定不显示。
      view: _byName(MascotView.values, json['view'], MascotView.flat, wire: true),
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
    // 颜色：除当前外的 15 个；角色和颜色必换。
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
  MascotMotion.lively => (body: 'bounce', eyes: 'open', mouth: 'smile'),
  MascotMotion.quiet => (body: 'breathe', eyes: 'open', mouth: 'flat'),
  MascotMotion.curious => (body: 'work', eyes: 'wide', mouth: 'open'),
};

/// 没有情绪时的默认表情：只看三档预设（动作编排细项已取消，旧存档里的值不再生效）。
/// 情绪态永远压过这套。
MascotExpression expressionFor(MascotSpec spec) {
  final preset = motionPreset(spec.motion);
  return MascotExpression(preset.eyes, preset.mouth, 'idle', preset.body);
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
  'inkJade' => MascotColor.miffanInkJade,
  _ => _byName(MascotColor.values, value, MascotColor.mint),
};
// l10n:keep-end
