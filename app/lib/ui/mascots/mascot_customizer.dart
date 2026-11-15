// 「换个样子」：吉祥物自定义页（照 demo：角色 / 颜色 / 五官，动作在角色下面）。
//
// 视图固定 3D、边框固定隐藏（用户定），所以界面不给这两个开关；字段仍在存档里。
// 只在新建 Bot 页/资料卡用；返回选好的 [MascotChoice]，取消返回 null。
// l10n:keep-begin 本地双语表（迁移到 arb 前不参与扫描）
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/theme.dart';
import 'mascot_avatar.dart';

String _t(String zh, String en) => AppLocale.current.languageCode == 'zh' ? zh : en;

/// 用户选的结果：继续用文字头像，还是换成这只吉祥物。
class MascotChoice {
  const MascotChoice({required this.spec, required this.text});

  final MascotSpec spec;
  final bool text;
}

/// 打开自定义页；返回 null 表示取消。
Future<MascotChoice?> openMascotCustomizer(
  BuildContext context, {
  required MascotSpec initial,
  bool text = false,
}) => Navigator.of(context).push<MascotChoice>(
  MaterialPageRoute(builder: (_) => MascotCustomizer(initial: initial, text: text)),
);

/// 预览圆：浅色圆底 + 会动的吉祥物。
class MascotPreview extends StatelessWidget {
  const MascotPreview({super.key, required this.spec, this.emotion = '02', this.size = 132});

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
  const MascotCustomizer({super.key, required this.initial, this.text = false});

  final MascotSpec initial;

  /// 进来时是「文字头像」。
  final bool text;

  @override
  State<MascotCustomizer> createState() => _MascotCustomizerState();
}

enum _Tab { character, color, face }

class _MascotCustomizerState extends State<MascotCustomizer> {
  late MascotSpec _spec = widget.initial;
  late bool _text = widget.text;
  _Tab _tab = _Tab.character;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 预览随选中的动作播；文字头像时预览仍显示吉祥物（文字头像在角色格第一格）。
    final preview = _text ? _spec : _spec;
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
                      _PreviewCard(spec: preview, text: _text),
                      const SizedBox(height: 14),
                      _TabBar(current: _tab, onSelect: (tab) => setState(() => _tab = tab)),
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
                              const SizedBox(height: 16),
                              _MotionList(spec: _spec, onPick: (m) => setState(() => _spec = _spec.withPresetMotion(m))),
                              const SizedBox(height: 12),
                              _ActionComposer(
                                spec: _spec,
                                onChanged: (next) => setState(() => _spec = next),
                              ),
                            ],
                          ),
                        _Tab.color => _ColorGrid(
                            spec: _spec,
                            onPick: (c) => setState(() {
                              _text = false;
                              _spec = _spec.copyWith(color: c, followAppColor: false);
                            }),
                          ),
                        _Tab.face => _FaceList(spec: _spec, onPick: (f) => setState(() => _spec = _spec.copyWith(face: f))),
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
  const _PreviewCard({required this.spec, this.text = false});

  final MascotSpec spec;
  final bool text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = text
        ? '${_t('文字头像', 'Text')} · ${spec.color.label} · ${spec.motion.label}'
        : spec.caption;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: ShapeDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        shape: const RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(AppShape.xl))),
      ),
      child: Column(
        children: [
          MascotPreview(spec: spec, emotion: '02'),
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
            label: character.label,
            hint: _t(_hints[character]!, _hints[character]!),
            selected: !text && spec.character == character,
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

/// 文字头像的预览：名字首字占位 + 当前颜色。
class _TextFace extends StatelessWidget {
  const _TextFace({required this.spec, required this.size});

  final MascotSpec spec;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final skin = mascotSkinOf(spec, theme.colorScheme);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: skin.body.withValues(alpha: dark ? 0.30 : 0.18)),
      child: Center(
        child: Text(
          _t('字', 'A'),
          style: theme.textTheme.titleMedium?.copyWith(
            color: skin.body,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.38,
          ),
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
    final theme = Theme.of(context);
    return GridView.count(
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
                      color: spec.color == color && !spec.followAppColor
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 1.6,
                    ),
                  ),
                  child: MascotAvatar(
                    spec: spec.copyWith(color: color, followAppColor: false),
                    emotion: '02',
                    size: 56,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  color == MascotColor.model ? _t('默认色', 'Model') : color.label,
                  maxLines: 1,
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FaceList extends StatelessWidget {
  const _FaceList({required this.spec, required this.onPick});

  final MascotSpec spec;
  final ValueChanged<MascotFace> onPick;

  static const _hints = {
    MascotFace.standard: '眼白 + 瞳孔 + 高光',
    MascotFace.simple: '两笔竖胶囊',
    MascotFace.dot: '两个圆点',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
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
                    MascotAvatar(spec: spec.copyWith(face: face), emotion: '02', size: 46),
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
                          Text(motion.label, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            motion.hintZh,
                            style: theme.textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      spec.motion == motion ? Icons.radio_button_checked : Icons.radio_button_unchecked,
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

/// 「动作编排」：demo 那页的三组 + 快速眨眼；改任一项就成「自定义」，只在空闲态生效。
class _ActionComposer extends StatelessWidget {
  const _ActionComposer({required this.spec, required this.onChanged});

  final MascotSpec spec;
  final ValueChanged<MascotSpec> onChanged;

  MascotSpec _set({String? body, String? eyes, String? mouth, bool? blink, bool clearBody = false, bool clearEyes = false, bool clearMouth = false}) => MascotSpec(
    character: spec.character,
    face: spec.face,
    motion: spec.motion,
    color: spec.color,
    view: spec.view,
    outline: spec.outline,
    body: clearBody ? null : (body ?? spec.body),
    eyes: clearEyes ? null : (eyes ?? spec.eyes),
    mouth: clearMouth ? null : (mouth ?? spec.mouth),
    blink: blink ?? spec.blink,
    followAppColor: spec.followAppColor,
    seed: spec.seed,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = DshColors.of(context).textTertiary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: ShapeDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
        shape: const RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(AppShape.lg))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_t('动作编排', 'Choreography'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (spec.motionCustom)
                Text(
                  _t('自定义', 'Custom'),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                ),
              const Spacer(),
              Text(_t('只在空闲时生效', 'Idle only'), style: theme.textTheme.labelSmall?.copyWith(color: muted)),
            ],
          ),
          const SizedBox(height: 10),
          _Group(
            title: _t('身体动作', 'Body'),
            values: mascotBodyActions,
            current: spec.body,
            onPick: (v) => onChanged(v == null ? _set(clearBody: true) : _set(body: v)),
          ),
          const SizedBox(height: 8),
          _Group(
            title: _t('眼睛状态', 'Eyes'),
            values: mascotEyeStates,
            current: spec.eyes,
            onPick: (v) => onChanged(v == null ? _set(clearEyes: true) : _set(eyes: v)),
          ),
          const SizedBox(height: 8),
          _Group(
            title: _t('嘴巴状态', 'Mouth'),
            values: mascotMouthStates,
            current: spec.mouth,
            onPick: (v) => onChanged(v == null ? _set(clearMouth: true) : _set(mouth: v)),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            value: spec.blink,
            onChanged: (on) => onChanged(_set(blink: on)),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(_t('快速眨眼', 'Quick blink'), style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.values, required this.current, required this.onPick});

  final String title;
  final List<String> values;
  final String? current;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelSmall?.copyWith(color: DshColors.of(context).textTertiary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip(context, _t('跟随情绪', 'Auto'), current == null, () => onPick(null)),
            for (final value in values) _chip(context, value, current == value, () => onPick(value)),
          ],
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, bool selected, VoidCallback onTap) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.quick),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: ShapeDecoration(
          color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : theme.colorScheme.surface,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppShape.sm)),
            side: BorderSide(
              color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 1.4 : 0.8,
            ),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected ? theme.colorScheme.primary : DshColors.of(context).textTertiary,
          ),
        ),
      ),
    );
  }
}
