// 轻松模式的底栏：4 个 Tab，玻璃/实底 + 顶部发丝线，图标与标签同色。
//
// 选中态不用 Fill 变体：`robot` / `dotsNine` 在 `DshGlyphs` 里没有 Fill，
// 补一个要重生成图标字体（`app/tool/make_icon_font.py`），MVP 不值。
// 用「主色 + 底部 4dp 圆点」在 4 个图标上统一。
import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'im_strings.dart';

/// 轻松模式的四个 Tab，顺序即底栏顺序。
enum ImTab { messages, companions, discover, me }

class ImTabBar extends StatelessWidget {
  const ImTabBar({super.key, required this.current, required this.onSelect, this.unread = false});

  final ImTab current;
  final ValueChanged<ImTab> onSelect;

  /// 「消息」上有没有未读（一颗小点）。
  final bool unread;

  /// 图标区高度（不含系统手势条）。
  static const height = 56.0;

  static IconData iconOf(ImTab tab) => switch (tab) {
    ImTab.messages => AppIcons.chat,
    ImTab.companions => AppIcons.bot,
    ImTab.discover => AppIcons.allFeatures,
    ImTab.me => AppIcons.profile,
  };

  static String labelOf(ImTab tab) => switch (tab) {
    ImTab.messages => ImStrings.tabMessages,
    ImTab.companions => ImStrings.tabCompanions,
    ImTab.discover => ImStrings.tabDiscover,
    ImTab.me => ImStrings.tabMe,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final surfaces = DshSurfaces.of(context);
    final insets = MediaQuery.paddingOf(context);
    final selected = theme.colorScheme.primary;
    final idle = dsh.textTertiary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.backdropTop,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5), width: 0.5),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: insets.bottom),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (final tab in ImTab.values)
                Expanded(
                  child: _ImTabKey(
                    tab: tab,
                    selected: tab == current,
                    unread: tab == ImTab.messages && unread,
                    iconColor: tab == current ? selected : idle,
                    labelColor: tab == current ? selected : idle,
                    onTap: () => onSelect(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImTabKey extends StatelessWidget {
  const _ImTabKey({
    required this.tab,
    required this.selected,
    required this.unread,
    required this.iconColor,
    required this.labelColor,
    required this.onTap,
  });

  final ImTab tab;
  final bool selected;
  final bool unread;
  final Color iconColor;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = ImTabBar.labelOf(tab);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 26,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(ImTabBar.iconOf(tab), size: 24, color: iconColor),
                  if (unread)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: DshSurfaces.of(context).backdropTop, width: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: labelColor,
                height: 1.2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.quick),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? theme.colorScheme.primary : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
