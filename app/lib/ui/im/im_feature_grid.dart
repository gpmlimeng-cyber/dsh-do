// 发现页的图标网格：4 列、每格 76 高、图标 24 + 一行 12.5 字。
//
// 不用 `TileGrid`：它是「全部功能」那种 2 列大卡片，IM 里一屏放不下。
import 'package:flutter/material.dart';

import '../theme/theme.dart';

class ImFeatureGrid extends StatelessWidget {
  const ImFeatureGrid({super.key, required this.cells, this.columns = 4});

  final List<Widget> cells;
  final int columns;

  /// 一格的格子高度。
  static const cellHeight = 76.0;

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: cellHeight,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      children: cells,
    );
  }
}

class ImFeatureCell extends StatelessWidget {
  const ImFeatureCell({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.onDisabledTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 需要会话上下文、现在不能进的格子。
  final bool enabled;

  /// 禁用时点一下给的提示（toast）。
  final VoidCallback? onDisabledTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final ink = enabled ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppShape.radiusMd,
        onTap: enabled ? onTap : onDisabledTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: ink),
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 12.5,
                  height: 1.2,
                  color: enabled ? colors.textTertiary : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
