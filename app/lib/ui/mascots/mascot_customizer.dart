// 「换个样子」：吉祥物的自定义页（照 Miffan 的 角色 / 颜色 / 动作 三 Tab）。
//
// 只在新建 Bot 页和资料卡里用；返回选好的 [MascotSpec]，取消返回 null。
// 文案先本地双语（本机生成不了 l10n gen），键名对齐将来的 arb。
// l10n:keep-begin 本地双语表（迁移到 arb 前不参与扫描）
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'mascot_avatar.dart';

String _t(String zh, String en) => AppLocale.current.languageCode == 'zh' ? zh : en;

/// 预览圆：浅色圆底 + 会动的吉祥物。
class MascotPreview extends StatelessWidget {
  const MascotPreview({super.key, required this.spec, this.size = 132});

  final MascotSpec spec;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size * 1.42,
      height: size * 1.42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
      ),
      child: Center(child: MascotAvatar(spec: spec, size: size, animate: true)),
    );
  }
}

/// 用户选的结果：继续用文字头像，还是换成这只吉祥物。
class MascotChoice {
  const MascotChoice({required this.spec, required this.text});

  final MascotSpec spec;
  final bool text;

  MascotChoice copyWith({MascotSpec? spec, bool? text}) => MascotChoice(spec: spec ?? this.spec, text: text ?? this.text);
}

/// 打开自定义页；返回 null 表示取消。
Future<MascotChoice?> openMascotCustomizer(
  BuildContext context, {
  required MascotSpec initial,
  bool text = false,
}) => Navigator.of(context).push<MascotChoice>(
  MaterialPageRoute(builder: (_) => MascotCustomizer(initial: initial, text: text)),
);

class MascotCustomizer extends StatefulWidget {
  const MascotCustomizer({super.key, required this.initial, this.text = false});

  final MascotSpec initial;

  /// 进来时是「文字头像」。
  final bool text;

  @override
  State<MascotCustomizer> createState() => _MascotCustomizerState();
}

enum _Tab { character, color, motion }

class _MascotCustomizerState extends State<MascotCustomizer> {
  late MascotSpec _spec = widget.initial;
  late bool _text = widget.text;
  _Tab _tab = _Tab.character;
  void _update(MascotSpec next) => setState(() => _spec = next);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                        onPressed: () => Navigator.of(context).pop(MascotChoice(spec: _spec, text: _text)),
                        child: Text(_t('完成', 'Done')),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      _PreviewCard(spec: _spec),
                      const SizedBox(height: 14),
                      _TabBar(
                        current: _tab,
                        onSelect: (tab) => setState(() => _tab = tab),
                      ),
                      const SizedBox(height: 14),
                      switch (_tab) {
                        _Tab.character => Column(
                            children: [
                              _CharacterGrid(
                                spec: _spec,
                                text: _text,
                                onText: () => setState(() => _text = true),
                                onPick: (c) => setState(() {
                                  _text = false;
                                  _spec = _spec.copyWith(character: c);
                                }),
                              ),
                              const SizedBox(height: 14),
                              _FaceRow(
                                spec: _spec,
                                onPick: (f) => _update(_spec.copyWith(face: f)),
                              ),
                            ],
                          ),
                        _Tab.color => _ColorGrid(
                            spec: _spec,
                            onPick: (c) => _update(_spec.copyWith(color: c, followAppColor: false)),
                            onFollowApp: (on) => _update(_spec.copyWith(followAppColor: on)),
                          ),
                        _Tab.motion => _MotionList(spec: _spec, onPick: (m) => _update(_spec.copyWith(motion: m))),
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
          Text(
            spec.caption,
            style: theme.textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
          ),
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
    final labels = [_t('角色', 'Character'), _t('颜色', 'Color'), _t('动作', 'Motion')];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        shape: const StadiumBorder(),
      ),
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
  const _CharacterGrid({required this.spec, required this.text, required this.onText, required this.onPick});

  final MascotSpec spec;
  final bool text;
  final VoidCallback onText;
  final ValueChanged<MascotCharacter> onPick;

  static const _hints = {
    MascotCharacter.sprout: '摇叶倾听 · 刻纹陶碗',
    MascotCharacter.cat: '竖耳警觉 · 毛绒圆身',
    MascotCharacter.robot: '天线轻闪 · 圆角铁壳',
    MascotCharacter.ghost: '漂浮无声 · 波浪尾巴',
    MascotCharacter.jelly: '轻晃光泽 · 弹性半球',
  };

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.92,
      children: [
        _CharacterCell(
          label: _t('文字头像', 'Text'),
          hint: _t('名字的首字', 'First letter'),
          selected: text,
          onTap: onText,
          avatar: _TextFace(spec: spec, size: 44),
        ),
        for (final character in MascotCharacter.values)
          _CharacterCell(
            label: character.zh,
            hint: _t(_hints[character]!, _hints[character]!),
            selected: !text && spec.character == character,
            onTap: () => onPick(character),
            avatar: MascotAvatar(spec: spec.copyWith(character: character), size: 44),
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

/// 文字头像的预览：名字首字占位 + 当前颜色。
class _TextFace extends StatelessWidget {
  const _TextFace({required this.spec, required this.size});

  final MascotSpec spec;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: spec.color.ink.withValues(alpha: dark ? 0.30 : 0.18)),
      child: Center(
        child: Text(
          _t('字', 'A'),
          style: theme.textTheme.titleMedium?.copyWith(
            color: spec.color.ink,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.38,
          ),
        ),
      ),
    );
  }
}

/// 五官三档。
class _FaceRow extends StatelessWidget {
  const _FaceRow({required this.spec, required this.onPick});

  final MascotSpec spec;
  final ValueChanged<MascotFace> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_t('五官', 'Face'), style: theme.textTheme.labelMedium?.copyWith(color: DshColors.of(context).textTertiary)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final face in MascotFace.values) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => onPick(face),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: AppMotion.of(context, AppMotion.quick),
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                        MascotAvatar(spec: spec.copyWith(face: face), size: 34),
                        const SizedBox(height: 4),
                        Text(face.zh, style: theme.textTheme.labelMedium),
                      ],
                    ),
                  ),
                ),
              ),
              if (face != MascotFace.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _ColorGrid extends StatelessWidget {
  const _ColorGrid({required this.spec, required this.onPick, required this.onFollowApp});

  final MascotSpec spec;
  final ValueChanged<MascotColor> onPick;
  final ValueChanged<bool> onFollowApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
          children: [
            for (final color in MascotColor.values)
              GestureDetector(
                onTap: () => onPick(color),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: spec.color == color && !spec.followAppColor ? theme.colorScheme.primary : Colors.transparent,
                          width: 1.6,
                        ),
                      ),
                      child: MascotAvatar(spec: spec.copyWith(color: color, followAppColor: false), size: 56),
                    ),
                    const SizedBox(height: 4),
                    Text(color.zh, style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: spec.followAppColor,
          onChanged: onFollowApp,
          contentPadding: EdgeInsets.zero,
          title: Text(_t('跟着 App 换颜色', 'Follow the app color')),
          subtitle: Text(
            _t('App 换主题色、深浅色时，它也跟着变', 'Changes with the app theme and light/dark'),
            style: theme.textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
          ),
        ),
      ],
    );
  }
}

class _MotionList extends StatelessWidget {
  const _MotionList({required this.spec, required this.onPick});

  final MascotSpec spec;
  final ValueChanged<MascotMotion> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final motion in MascotMotion.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => onPick(motion),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: AppMotion.of(context, AppMotion.quick),
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                decoration: ShapeDecoration(
                  color: spec.motion == motion ? theme.colorScheme.primary.withValues(alpha: 0.08) : theme.colorScheme.surface,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(AppShape.md)),
                    side: BorderSide(
                      color: spec.motion == motion ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                      width: spec.motion == motion ? 1.6 : 0.8,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(motion.zh, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            motion.hintZh,
                            style: theme.textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      spec.motion == motion ? AppIcons.radioOn : AppIcons.radioOff,
                      color: spec.motion == motion ? theme.colorScheme.primary : theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          _t('上面的预览会按选中的样子动起来。', 'The preview above moves the way you pick.'),
          style: theme.textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
        ),
      ],
    );
  }
}
// l10n:keep-end
