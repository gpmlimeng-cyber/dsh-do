// 表情墙（隐藏调试页）：5 个角色 × 40 个情绪，一次看全。
//
// 入口在「设置 › 关于」的版本号上连点 7 下（`VersionTaps`），不放进任何菜单：
// 它是给设计和真机对照用的，不是用户功能。
//
// 每个格子都是静态帧（`animate:false`），200 个一起也不会起 ticker。
import 'package:flutter/material.dart';

import '../shell/page_frame.dart';
import '../theme/theme.dart';
import 'mascot_avatar.dart';

class MascotGalleryPage extends StatelessWidget {
  const MascotGalleryPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const MascotGalleryPage());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final ids = mascotExpressions.keys.toList()..sort();
    return AppPage.list(
      title: '表情墙',
      subtitle: Text('${MascotCharacter.values.length} 个角色 × ${ids.length} 个情绪，静态帧', style: theme.textTheme.bodySmall),
      children: [
        // 按三档动作编排（空闲态）各渲一行，方便对照 demo 的「动作编排」。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '按动作编排（空闲态）',
            style: theme.textTheme.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ),
        for (final motion in MascotMotion.values)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    motion.zh,
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.textTertiary),
                  ),
                ),
                for (final character in MascotCharacter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: MascotAvatar(
                      spec: MascotSpec(character: character).withPresetMotion(motion),
                      emotion: '02',
                      size: 48,
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        for (final character in MascotCharacter.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Row(
              children: [
                MascotAvatar(spec: MascotSpec(character: character), size: 40),
                const SizedBox(width: 10),
                Text(
                  '${character.zh}  ${character.name}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 4,
              runSpacing: 6,
              children: [
                for (final id in ids)
                  SizedBox(
                    width: 58,
                    child: Column(
                      children: [
                        MascotAvatar(
                          spec: MascotSpec(character: character),
                          emotion: id,
                          size: 48,
                        ),
                        Text(
                          id,
                          style: theme.textTheme.labelSmall?.copyWith(color: colors.textTertiary, height: 1.1),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            '点空白处返回。改渲染后先来这里对一遍官方 demo。',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ),
      ],
    );
  }
}

/// 版本号上连点 7 下的入口（2 秒内算一轮）。不显示任何提示，防误触。
class VersionTaps extends StatefulWidget {
  const VersionTaps({super.key, required this.child});

  final Widget child;

  @override
  State<VersionTaps> createState() => _VersionTapsState();
}

class _VersionTapsState extends State<VersionTaps> {
  int _taps = 0;
  DateTime? _last;

  void _tap() {
    final now = DateTime.now();
    if (_last == null || now.difference(_last!) > const Duration(seconds: 2)) {
      _taps = 0;
    }
    _last = now;
    _taps++;
    if (_taps < 7) return;
    _taps = 0;
    Navigator.of(context, rootNavigator: true).push(MascotGalleryPage.route());
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _tap,
    behavior: HitTestBehavior.opaque,
    child: widget.child,
  );
}
