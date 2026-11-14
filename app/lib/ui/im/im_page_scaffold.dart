// 轻松模式的页面框：大标题 + 右侧玻璃圆键 + 内容。
//
// 为什么不用现成的 `AppPage`：它的顶栏固定画返回键（`page_frame.dart:217-224`），
// 四个 Tab 的根页不该有返回键；大标题左右也是 24，IM 列表要贴 16。
// 这里只复用它的高度、阅读宽和背景。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/side_insets.dart';
import '../../l10n/l10n.dart';
import '../shell/page_frame.dart' show AppPage, GlassIconButton;
import '../theme/app_icons.dart';
import '../theme/theme.dart';

class ImPageScaffold extends StatelessWidget {
  const ImPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.back = false,
    this.padding = const EdgeInsets.only(top: 4),
    required this.child,
  });

  /// 大标题（`headlineLarge`，与 `AppPage` 同一档）。
  final String title;

  /// 标题下的一行小字。
  final String? subtitle;

  /// 顶栏右侧的玻璃圆键，最多 2 个。
  final List<Widget> actions;

  /// 从 Tab 里推进来的页面（资料卡等）为 true；Tab 根页为 false。
  final bool back;

  /// 内容自己的内边距；横向留白由本框架给。
  final EdgeInsetsGeometry padding;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safe = MediaQuery.paddingOf(context);
    final side = AppPage.sideFor(MediaQuery.sizeOf(context).width, inset: sideInsetFor(safe));
    final l10n = context.l10n;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dshSystemOverlay(theme.brightness),
      child: AppBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppPage.contentWidth),
              child: Padding(
                padding: EdgeInsets.only(left: side, right: side),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(back ? 8 : 16, safe.top + 8, 10, 8),
                      child: Row(
                        children: [
                          if (back) ...[
                            GlassIconButton(
                              icon: AppIcons.back,
                              tooltip: l10n.commonBack,
                              size: 36,
                              // 这里没有 BackdropGroup：单独一块玻璃就不分组采样。
                              grouped: false,
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.headlineLarge,
                                  ),
                                  if (subtitle case final subtitle? when subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ...actions,
                        ],
                      ),
                    ),
                    Expanded(child: Padding(padding: padding, child: child)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
