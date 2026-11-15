// 「换个样子」：吉祥物自定义页（照 demo：角色 / 颜色 / 五官，动作在角色下面）。
//
// 视图固定 3D、边框固定隐藏（用户定），所以界面不给这两个开关；字段仍在存档里。
// 只在新建 Bot 页/资料卡用；返回选好的 [MascotChoice]，取消返回 null。
// l10n:keep-begin 本地双语表（迁移到 arb 前不参与扫描）
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'mascot_avatar.dart';

String _t(String zh, String en) => AppLocale.current.languageCode == 'zh' ? zh : en;

/// 用户选的结果：换成这只吉祥物（字团已下线，不再有第二种结果）。
class MascotChoice {
  const MascotChoice({required this.spec});

  final MascotSpec spec;
}

/// 打开自定义页；返回 null 表示取消。
Future<MascotChoice?> openMascotCustomizer(
  BuildContext context, {
  required MascotSpec initial,
}) => Navigator.of(context).push<MascotChoice>(
  MaterialPageRoute(builder: (_) => MascotCustomizer(initial: initial)),
);

/// 预览圆：浅色圆底 + 会动的吉祥物。
///
/// [emotion] 留空＝按当前配置画：五官、动作预设、自定义编排都直接反映，
/// 这就是用户说的「实时看到当前配置」。
class MascotPreview extends StatelessWidget {
  const MascotPreview({super.key, required this.spec, this.emotion, this.size = 132});

  final MascotSpec spec;
  final String? emotion;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size * 1.42,
      height: size * 1.42,
      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primary.withValues(alpha: 0.10)),
      child: Center(child: MascotAvatar(spec: spec, emotion: emotion, size: size, animate: true)),
    );
  }
}

class MascotCustomizer extends StatefulWidget {
  const MascotCustomizer({super.key, required this.initial});

  final MascotSpec initial;

  @override
  State<MascotCustomizer> createState() => _MascotCustomizerState();
}

enum _Tab { character, color, face }

class _MascotCustomizerState extends State<MascotCustomizer> {
  late MascotSpec _spec = widget.initial;
  _Tab _tab = _Tab.character;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 预览随选中的动作播。
    final preview = _spec;
    return AnnotatedRegion(
      value: dshSystemOverlay(theme.brightness),
      child: AppBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                  child: Row(
                    children: [
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(_t('取消', 'Cancel'))),
                      Expanded(
                        child: Text(
                          _t('换个样子', 'Change the look'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(MascotChoice(spec: _spec)),
                        child: Text(_t('完成', 'Done')),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      _PreviewCard(spec: preview),
                      const SizedBox(height: 14),
                      _TabBar(current: _tab, onSelect: (tab) => setState(() => _tab = tab)),
                      const SizedBox(height: 14),
                      switch (_tab) {
                        _Tab.character => Column(
                            children: [
                              _CharacterGrid(
                                spec: _spec,
                                onPick: (c) => setState(() => _spec = _spec.copyWith(character: c)),
                              ),
                            ],
                          ),
                        _Tab.color => _ColorGrid(
                            spec: _spec,
                            onPick: (c) => setState(() => _spec = _spec.copyWith(color: c, followAppColor: false)),
                          ),
                        _Tab.face => _FaceList(
                            spec: _spec,
                            onPick: (f) => setState(() => _spec = _spec.copyWith(face: f)),
                            onView: (v) => setState(() => _spec = _spec.copyWith(view: v)),
                            onMotion: (m) => setState(() => _spec = _spec.withPresetMotion(m)),
                          ),
                      },
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.spec});

  final MascotSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = spec.caption;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: ShapeDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        shape: const RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(AppShape.xl))),
      ),
      child: Column(
        children: [
          MascotPreview(spec: spec),
          const SizedBox(height: 10),
          Text(caption, style: theme.textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary)),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onSelect});

  final _Tab current;
  final ValueChanged<_Tab> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = [_t('角色', 'Character'), _t('颜色', 'Color'), _t('五官', 'Face')];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.05), shape: const StadiumBorder()),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(_Tab.values[i]),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: AppMotion.of(context, AppMotion.quick),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: ShapeDecoration(
                    color: current == _Tab.values[i] ? theme.colorScheme.surface : Colors.transparent,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: current == _Tab.values[i] ? FontWeight.w600 : FontWeight.w400,
                      color: current == _Tab.values[i] ? theme.colorScheme.onSurface : DshColors.of(context).textTertiary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CharacterGrid extends StatelessWidget {
  const _CharacterGrid({required this.spec, required this.onPick});

  final MascotSpec spec;
  final ValueChanged<MascotCharacter> onPick;

  static const _hints = {
    MascotCharacter.sprout: '摇叶倾听 · 刻纹陶碗',
    MascotCharacter.robot: '天线轻闪 · 圆角铁壳',
    MascotCharacter.ghost: '漂浮无声 · 波浪尾巴',
    MascotCharacter.jelly: '轻晃光泽 · 弹性半球',
    MascotCharacter.orb: '纯圆小球 · 没有顶饰',
    MascotCharacter.star: '五角圆润 · 中间略鼓',
    MascotCharacter.triangle: '软糖角团 · 圆角',
    MascotCharacter.onigiri: '奶白圆身 · 底部海苔',
    MascotCharacter.potato: '不规则椭圆 · 带斑点',
    MascotCharacter.orange: '略扁橙球 · 顶小叶',
    MascotCharacter.pear: '梨形小蛮腰 · 果斑',
    MascotCharacter.mango: '歪椭圆 · 一头略尖',
  };

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 8,
      childAspectRatio: 0.92,
      children: [
        for (final character in MascotCharacter.values)
          _CharacterCell(
            label: character.label,
            hint: _t(_hints[character]!, _hints[character]!),
            selected: spec.character == character,
            onTap: () => onPick(character),
            avatar: MascotAvatar(spec: spec.copyWith(character: character), emotion: '02', size: 44),
          ),
      ],
    );
  }
}

class _CharacterCell extends StatelessWidget {
  const _CharacterCell({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
    required this.avatar,
  });

  final String label;
  final String hint;
  final Widget avatar;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.quick),
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
        decoration: ShapeDecoration(
          color: selected ? theme.colorScheme.primary.withValues(alpha: 0.10) : theme.colorScheme.surface,
          shape: RoundedSuperellipseBorder(
            borderRadius: const BorderRadius.all(Radius.circular(AppShape.md)),
            side: BorderSide(
              color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 1.6 : 0.8,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            avatar,
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              hint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: DshColors.of(context).textTertiary, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorGrid extends StatelessWidget {
  const _ColorGrid({required this.spec, required this.onPick});

  final MascotSpec spec;
  final ValueChanged<MascotColor> onPick;

  @override
  Widget build(BuildContext context) {
    // 紧凑网格：4 列、18 格（17 个预设 + 「跟随默认」），5 行一屏看全。
    // 格子高度按内容算（头像 58 + 标签 + 内边距），换屏幕宽度也不会溢出。
    const columns = 4;
    const gap = 8.0;
    const cellHeight = 98.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: gap,
          childAspectRatio: cellWidth / cellHeight,
          children: [
            for (final color in MascotColor.values)
              _ColorCell(
                spec: spec,
                color: color,
                selected: spec.color == color && !spec.followAppColor,
                onTap: () => onPick(color),
              ),
          ],
        );
      },
    );
  }
}

class _ColorCell extends StatelessWidget {
  const _ColorCell({required this.spec, required this.color, required this.selected, required this.onTap});

  final MascotSpec spec;
  final MascotColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.quick),
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
        decoration: ShapeDecoration(
          color: selected ? theme.colorScheme.primary.withValues(alpha: 0.08) : Colors.transparent,
          shape: RoundedSuperellipseBorder(
            borderRadius: const BorderRadius.all(Radius.circular(AppShape.md)),
            side: BorderSide(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              width: 1.4,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  MascotAvatar(
                    spec: spec.copyWith(color: color, followAppColor: false),
                    emotion: '02',
                    size: 58,
                  ),
                  // 选中只靠格子本身的底色 + 主色描边，不盖对钩。
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              color == MascotColor.model ? _t('默认色', 'Model') : color.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceList extends StatelessWidget {
  const _FaceList({required this.spec, required this.onPick, required this.onView, required this.onMotion});

  final MascotSpec spec;
  final ValueChanged<MascotFace> onPick;
  final ValueChanged<MascotView> onView;
  final ValueChanged<MascotMotion> onMotion;

  static const _hints = {
    MascotFace.standard: '眼白 + 瞳孔 + 高光',
    MascotFace.simple: '两笔竖胶囊',
    MascotFace.dot: '两个圆点',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ViewToggle(view: spec.view, onPick: onView),
        const SizedBox(height: 12),
        Row(
      children: [
        for (final face in MascotFace.values) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => onPick(face),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                key: ValueKey('mascot-face-${face.wire}'),
                duration: AppMotion.of(context, AppMotion.quick),
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
                decoration: ShapeDecoration(
                  color: spec.face == face ? theme.colorScheme.primary.withValues(alpha: 0.10) : theme.colorScheme.surface,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(AppShape.md)),
                    side: BorderSide(
                      color: spec.face == face ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                      width: spec.face == face ? 1.6 : 0.8,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // 卡片里画「这个档位的静态五官」：带情绪会变成笑脸弧线，
                    // 和「眼白 + 瞳孔 + 高光」这类说明对不上。
                    MascotAvatar(spec: spec.copyWith(face: face), size: 52),
                    const SizedBox(height: 8),
                    Text(face.label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      _hints[face] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: DshColors.of(context).textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (face != MascotFace.values.last) const SizedBox(width: 8),
        ],
      ],
        ),
        const SizedBox(height: 16),
        _MotionCards(spec: spec, onPick: onMotion),
      ],
    );
  }
}

/// 动作三档：和五官卡同一套卡片样式，点一下预览当帧换动作。
class _MotionCards extends StatelessWidget {
  const _MotionCards({required this.spec, required this.onPick});

  final MascotSpec spec;
  final ValueChanged<MascotMotion> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = DshColors.of(context).textTertiary;
    return Row(
      children: [
        for (final motion in MascotMotion.values) ...[
          Expanded(
            child: GestureDetector(
              key: ValueKey('mascot-motion-${motion.name}'),
              onTap: () => onPick(motion),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: AppMotion.of(context, AppMotion.quick),
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
                decoration: ShapeDecoration(
                  color: spec.motion == motion ? theme.colorScheme.primary.withValues(alpha: 0.10) : theme.colorScheme.surface,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: AppShape.radiusMd,
                    side: BorderSide(
                      color: spec.motion == motion ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                      width: spec.motion == motion ? 1.6 : 0.8,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    MascotAvatar(spec: spec.copyWith(motion: motion), emotion: '02', size: 52),
                    const SizedBox(height: 8),
                    Text(motion.label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      motion.hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (motion != MascotMotion.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// 「视图」2D / 3D：默认 2D；切了预览立刻变。
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onPick});

  final MascotView view;
  final ValueChanged<MascotView> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = DshColors.of(context).textTertiary;
    return Row(
      children: [
        Text(_t('视图', 'View'), style: theme.textTheme.labelMedium?.copyWith(color: muted)),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: ShapeDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
              shape: const StadiumBorder(),
            ),
            child: Row(
              children: [
                for (final option in MascotView.values)
                  Expanded(
                    child: GestureDetector(
                      key: ValueKey('mascot-view-${option.wire}'),
                      onTap: () => onPick(option),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: AppMotion.of(context, AppMotion.quick),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: ShapeDecoration(
                          color: view == option ? theme.colorScheme.surface : Colors.transparent,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          option.label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: view == option ? FontWeight.w600 : FontWeight.w400,
                            color: view == option ? theme.colorScheme.onSurface : muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// l10n:keep-end
