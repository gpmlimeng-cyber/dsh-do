// The pieces a Bot chat and a group chat share: the floating header, the page
// frame (list under glass, cards and the composer at the bottom), the rows of
// the transcript, and the cards a Bot leaves for the person (a question, a
// view, a model to pick). Messages draw with the chat's own widgets
// (`MarkdownBody`, `UserBubble`).

import 'dart:math' as math;

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/artifacts.dart' show TurnArtifacts;
import '../../state/bots_state.dart';
import '../../state/settings_state.dart';
import '../chat/render/markdown_body.dart';
import '../chat/render/message_mentions.dart';
import '../chat/run_info.dart' show formatSpan;
import '../chat/usage_sheet.dart' show formatTokens;
import '../chat/widgets/chat_card.dart';
import '../chat/dsh_ui/dsh_ui.dart';
import '../chat/secret_mask.dart';
import '../chat/widgets/message_actions.dart';
import '../share/share_entry.dart' show shareText;
import '../chat/widgets/notice_row.dart';
import '../chat/widgets/thinking_pill.dart';
import '../chat/widgets/user_bubble.dart';
import '../common/capsule_chip.dart';
import '../common/side_insets.dart';
import '../common/smooth_size.dart';
import '../common/status_dot.dart';
import '../common/typing_indicator.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_avatar.dart';
import 'bot_memory_notice.dart';
import 'bot_format.dart';
import 'bots_page.dart' show BotTag;

// ── Header ───────────────────────────────────────────────────────────────────

/// Three floating chrome-glass pieces, like the chat's own header: back, a
/// title pill (the face, the name, one line of status), details.
///
/// ```
/// (‹) ( ◉ Chief           )             (ⓘ)
///     (   ● 正在运行命令  )
/// ```
class BotChatHeader extends StatelessWidget {
  const BotChatHeader({
    this.showLeading = true,
    super.key,
    required this.face,
    required this.title,
    required this.status,
    required this.tone,
    required this.onDetails,
    this.onLeading,
    this.leadingTooltip,
    this.scrolledUnder,
    this.chip,
    this.onInfo,
    this.onMenu,
    this.menuController,
    this.menuChildren,
    this.action,
    this.onMessages,
    this.messagesIcon,
    this.messagesTooltip,
    this.titleHint,
    this.infoTooltip,
    this.infoGreyed = false,
    this.trailing,
    this.trailingExpand = false,
    this.titleCompact = false,
  }) : assert(
         (menuChildren == null) == (menuController == null),
         'menuChildren 与 menuController 要成对给',
       );

  final Widget face;
  final String title;
  final String status;
  final StatusTone tone;
  final VoidCallback onDetails;

  /// What the header's first key does; the default steps back.
  final VoidCallback? onLeading;

  /// What that key says: 返回 on a phone; folding the sidebar on a wide window.
  final String? leadingTooltip;
  final ValueNotifier<double>? scrolledUnder;

  /// The leading key (back, or the chats button). Off in a three-column
  /// layout: the rail already has that button, and two of them read wrong.
  final bool showLeading;

  /// The model this Bot runs on, before the details key.
  final Widget? chip;

  /// The right key: 对话详情 (trajectory, files, progress). Without it the key
  /// opens the same place as the title capsule.
  final VoidCallback? onInfo;

  /// When set, the last key is ⋯ and [onMenu] opens the page's menu instead of
  /// going straight to details; a long press still runs [onInfo]. Null keeps
  /// the details key.
  final VoidCallback? onMenu;

  /// 锚定下拉菜单的控制器：给了 [menuChildren] 时，⋯ 就是菜单的锚点，菜单
  /// 从它下方展开，不再弹底部抽屉。页面持有它，是为了返回键与点外面都能收起。
  final MenuController? menuController;

  /// ⋯ 下拉菜单的内容。行由页面给（图标 + 文字），这里只管锚点、卡片与
  /// 开合；每行自己负责点完关掉菜单。
  final List<Widget> Function(BuildContext menuContext, MenuController controller)? menuChildren;

  /// The page's own situation key, drawn after ⋯ (the row's last): stop while
  /// something runs, a warning when offline or read-only. The most important
  /// thing never hides inside a menu.
  final ({IconData icon, String tooltip, VoidCallback? onTap, Color? color})? action;

  /// 消息模式: only a group passes it, and the key sits left of the details one.
  final VoidCallback? onMessages;

  /// What the messages key draws instead of its default glyph: the conversation
  /// it opens (the group's icon, or a member's face in a ring), so where you are
  /// reads at a glance. Give it a key per target — the key swaps with a 120 ms
  /// fade and 0.92 → 1 scale, no bounce.
  final Widget? messagesIcon;

  /// The messages key's words; the page names the mode in them.
  final String? messagesTooltip;

  /// What the title capsule does, for screen readers. The default says
  /// 查看详情; a page whose capsule switches conversations says that instead.
  final String? titleHint;

  /// The right key's words; null keeps 「详情」. A disabled key also says why.
  final String? infoTooltip;

  /// Greys the right key's glyph when there is nothing it can open; the key
  /// keeps its tap area and says why in [infoTooltip] when tapped.
  final bool infoGreyed;

  /// A widget between the title capsule and the right keys: a group's goal pill.
  final Widget? trailing;

  /// The trailing widget takes the row's spare width (a goal pill that fills
  /// the header on a narrow screen); the title makes do with its own face.
  final bool trailingExpand;

  /// The title capsule shrinks to its face alone (圆形) so the goal pill beside
  /// it can carry the group's name instead.
  final bool titleCompact;

  static const barHeight = 56.0;
  static const key44 = 44.0;

  /// The face sits in the pill's left end with the same air all round.
  static const faceSize = 32.0;

  /// [barHeight], taller when a large text size needs it for the title and
  /// status lines.
  static double barHeightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final small = Theme.of(context).textTheme.labelSmall!.fontSize!;
    return math.max(barHeight, scaler.scale(15) * 1.3 + scaler.scale(small) * 1.25 + 12);
  }

  static double heightOf(BuildContext context) => MediaQuery.paddingOf(context).top + barHeightOf(context) + 8;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final faceInset = (key44 - faceSize) / 2;
    final titlePill = Align(
                      alignment: Alignment.centerLeft,
                      // 收缩到内容宽度：撑满态里剩下的宽度要留给目标胶囊。
                      widthFactor: 1,
                      child: Semantics(
                        button: true,
                        hint: titleHint ?? l10n.botsViewDetails,
                        child: GlassSurface(
                          key: const ValueKey('bot-title'),
                          tier: GlassTier.chrome,
                          stadium: true,
                          grouped: true,
                          onTap: onDetails,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: key44),
                            child: Padding(
                              padding: EdgeInsets.only(left: faceInset, right: titleCompact ? faceInset : 16),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox.square(key: const ValueKey('bot-face'), dimension: faceSize, child: face),
                                  if (!titleCompact) ...[
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: SmoothSize(
                                      duration: AppMotion.of(context, AppMotion.standard),
                                      curve: AppMotion.std,
                                      alignment: Alignment.centerLeft,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall?.copyWith(fontSize: 15, height: 1.3),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              StatusDot(tone: tone, size: 6),
                                              const SizedBox(width: 5),
                                              Flexible(
                                                child: Text(
                                                  status,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: theme.textTheme.labelSmall?.copyWith(
                                                    color: tone == StatusTone.warn ? dsh.warning : dsh.textTertiary,
                                                    height: 1.25,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The bar's own plate: the page's backdrop again, a little see-through,
        // so the conversation scrolls under the buttons instead of being cut.
        // It must be positioned: a bare infinite CustomPaint in the stack pushes
        // the buttons off the bar.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          // The native chat's own numbers, so the two plates are one size.
          child: TopFade(height: top + barHeightOf(context) + 12),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(12, top, 12, 0),
          child: BackdropGroup(
            child: SizedBox(
              height: barHeightOf(context),
              child: Row(
                children: [
                  if (showLeading)
                  _RoundKey(
                    key: const ValueKey('bot-back'),
                    icon: onLeading == null ? AppIcons.back : AppIcons.menu,
                    tooltip: onLeading == null ? l10n.commonBack : (leadingTooltip ?? l10n.chatChats),
                    onTap: onLeading ?? () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  // 展开态：标题只剩一颗圆头像，占自己的内容宽，不再参与
                  // 弹性分配——否则它和胶囊各拿一半自由宽，那半截没用完就留在
                  // 行尾，最右那颗键贴不到右边。其余时候标题吃掉剩余宽度。
                  if (trailingExpand) titlePill else Expanded(child: titlePill),
                  if (trailing case final trailing?) ...[
                    const SizedBox(width: 4),
                    // 撑满态（窄屏的完整胶囊）占满剩下的宽度；其余时候它只是
                    // 一颗定宽的小球/胶囊，不参与弹性，否则它那一半没吃完的
                    // 宽度会留在 Row 尾部，最右那颗键就贴不到右边。
                    if (trailingExpand) Expanded(child: trailing) else trailing,
                  ],
                  if (onMessages case final onMessages?) ...[
                    const SizedBox(width: 8),
                    _RoundKey(
                      key: const ValueKey('bot-messages'),
                      icon: AppIcons.chat,
                      iconWidget: messagesIcon,
                      tooltip: messagesTooltip ?? l10n.botsMessageMode,
                      onTap: onMessages,
                    ),
                  ],
                  if (chip case final chip?) ...[
                    const SizedBox(width: 8),
                    chip,
                  ],
                  const SizedBox(width: 8),
                  if (onMenu != null || menuChildren != null) ...[
                    if (menuChildren case final menuChildren?)
                      _AnchoredMenu(
                        controller: menuController!,
                        children: menuChildren,
                        onLongPress: onInfo,
                      )
                    else
                      _RoundKey(
                        key: const ValueKey('bot-menu-key'),
                        icon: AppIcons.more,
                        tooltip: l10n.commonMore,
                        onTap: onMenu,
                        // One more way in, not a second menu: the details key is
                        // still one long press away.
                        onLongPress: onInfo,
                      ),
                    if (action != null) const SizedBox(width: 8),
                  ],
                  if (action case final action?)
                    _RoundKey(
                      key: const ValueKey('bot-action-key'),
                      icon: action.icon,
                      tooltip: action.tooltip,
                      onTap: action.onTap,
                      iconColor: action.color,
                    )
                  else if (onMenu == null && menuChildren == null)
                    _RoundKey(
                      key: const ValueKey('bot-details'),
                      icon: AppIcons.info,
                      tooltip: infoTooltip ?? l10n.commonDetails,
                      onTap: onInfo ?? onDetails,
                      iconColor: infoGreyed ? DshColors.of(context).textTertiary : null,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundKey extends StatelessWidget {
  const _RoundKey({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.onLongPress,
    this.iconWidget,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;

  /// A second way in that the key's tooltip does not need to name.
  final VoidCallback? onLongPress;

  /// Null disables the key: it still says what it would do, but does nothing.
  final VoidCallback? onTap;

  final Color? iconColor;

  /// Drawn instead of [icon]: 消息模式's own key shows the mode, not one glyph.
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: SizedBox.square(
      dimension: BotChatHeader.key44,
      child: GlassSurface(
        tier: GlassTier.chrome,
        circle: true,
        grouped: true,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Tooltip(
          message: tooltip,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: AnimatedSwitcher(
                  // A pick lands: fade in and grow a hair, no bounce, no slide.
                  duration: const Duration(milliseconds: 120),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                      child: child,
                    ),
                  ),
                  child: iconWidget ??
                      Icon(icon, size: 22, color: iconColor ?? Theme.of(context).colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// ⋯ 的下拉菜单：键本身就是锚点，卡片从它下方展开、右边缘与键的右边缘对齐
/// （网页那种从按钮长出来的菜单，不是底部抽屉）。点外面或返回就收起。
class _AnchoredMenu extends StatelessWidget {
  const _AnchoredMenu({required this.controller, required this.children, this.onLongPress});

  final MenuController controller;

  /// 菜单里的一行行，由页面给：图标 + 文字，行高与卡片留白跟其他菜单一套。
  final List<Widget> Function(BuildContext menuContext, MenuController controller) children;

  /// 长按仍是另一条路（页面拿它开详情）。
  final VoidCallback? onLongPress;

  /// 卡片宽度：行按这个宽铺满（行自己带 16 的左右留白），高 52。
  static const double _width = 208;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return MenuAnchor(
      controller: controller,
      // 行是带 Expanded 的列表行：宽度必须先定死，不能让菜单按内容宽去量
      // （那样行会拿到无界宽度）。
      crossAxisUnconstrained: false,
      // 右边缘贴住键的右边缘、挂在它下面；8 的缝，不贴着键。
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomEnd,
        backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
        minimumSize: const WidgetStatePropertyAll(Size(_width, 0)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      ),
      alignmentOffset: const Offset(0, 8),
      menuChildren: [
        for (final row in children(context, controller)) SizedBox(width: _width, child: row),
      ],
      // 开合时 MenuAnchor 自己重建这颗键：PopScope 挂在它上面，返回键先收菜单。
      builder: (context, menu, child) => PopScope(
        canPop: !menu.isOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && menu.isOpen) menu.close();
        },
        child: _RoundKey(
          key: const ValueKey('bot-menu-key'),
          icon: AppIcons.more,
          tooltip: l10n.commonMore,
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          onLongPress: onLongPress,
        ),
      ),
    );
  }
}

// ── Frame ────────────────────────────────────────────────────────────────────

/// The page: the transcript fills the space between the header (floating
/// over it) and the bottom column (cards, error, composer).
class BotChatFrame extends StatefulWidget {
  const BotChatFrame({super.key, required this.header, required this.body, required this.bottom});

  final Widget header;
  final Widget body;
  final List<Widget> bottom;

  @override
  State<BotChatFrame> createState() => _BotChatFrameState();
}

class _BotChatFrameState extends State<BotChatFrame> {
  /// As the native chat's `_ChatLayout.overlap`: the list reaches this far into
  /// the composer, and the plate's solid part starts this far below its top —
  /// the top 6px of the composer area belongs to the feather, not the slab.
  static const _overlap = 6.0;
  /// The composer's measured height: the box it occupies, and the room the
  /// transcript keeps clear of. Written after layout (no animation, so the
  /// first frame that has it is the frame it takes effect).
  final _composer = ValueNotifier<double>(0);

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.header;
    final body = widget.body;
    final bottom = widget.bottom;
    final frame = AnnotatedRegion<SystemUiOverlayStyle>(
      value: dshSystemOverlay(Theme.of(context).brightness),
      child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          // A phone on its side: clear of the cutout on both sides.
          body: SideSafeArea(
            child: Stack(
              children: [
                // The transcript keeps clear of the composer's measured height:
                // the last row stops above it instead of running under it.
                // The transcript runs to the bottom of the screen: its last rows
                // slide under the composer's plate and show faintly through the
                // ramp instead of being cut at the plate's edge. It keeps that
                // much blank at its own end, so the newest row can still scroll
                // clear of the plate.
                Positioned.fill(
                  child: ComposerInsetScope(height: _composer, child: body),
                ),
                // The composer's own plate: the page again, a little
                // see-through, feathered where the transcript meets it.
                // Full-page, exactly as the native chat draws it: the plate is
                // solid over the composer and feathers above it. A box the
                // height of the composer would clip the feather into a hard edge.
                Positioned.fill(
                  child: IgnorePointer(
                    // 整块托板一段渐变：顶边透明、底边实心，输入框和活动行
                    // 都在里面，不再在托板上方另起一段淡出。
                    child: BackdropVeil.inside(solidHeight: _composer, opacity: 0.86),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _Measured(
                    onHeight: (height) => _composer.value = math.max(0, height - _overlap),
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: AppSpace.floatingWidth),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: bottom,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(left: 0, right: 0, top: 0, child: header),
              ],
            ),
          ),
        ),
    );
    return frame;
  }
}

/// An error over the composer, or nothing.
class BotErrorSlot extends StatelessWidget {
  const BotErrorSlot({super.key, required this.error, required this.onDismiss});

  final String? error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => SmoothSize(
    duration: AppMotion.of(context, AppMotion.standard),
    curve: AppMotion.std,
    alignment: Alignment.bottomCenter,
    child: error == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ErrorBanner(message: error!, onDismiss: onDismiss),
          ),
  );
}

// ── Transcript ───────────────────────────────────────────────────────────────

/// One row of a transcript, newest last.
sealed class BotRow {
  const BotRow();
}

/// One turn's memory change, drawn under that turn's last line.
///
/// It takes the place the 「完成了工作」 line used to hold at the end of a turn:
/// the line that says what the turn did, instead of that it ended. Tapping it
/// opens the memory it changed.
final class BotMemoryNoticeRow extends BotRow {
  const BotMemoryNoticeRow(this.notice, {this.botId});

  final MemoryNotice notice;

  /// The Bot whose memory changed; null opens the group's.
  final String? botId;
}

/// Inserts each turn's [MemoryNotice] under the last row that turn stamped.
///
/// Turn numbers restart with every part, so a page read from history only gets
/// a line when some row on it still carries that turn: the notice is placed the
/// way a deliverable card is, and a page that cannot place it draws nothing.
List<BotRow> attachMemoryNotices(
  List<BotRow> rows,
  Map<int, MemoryNotice> notices, {
  String? botId,
}) {
  if (notices.isEmpty || rows.isEmpty) return rows;
  int? turnOf(BotRow row) => switch (row) {
    BotItemRow(:final item) => item.turn,
    BotToolGroupRow(:final items) => items.isEmpty ? null : items.last.turn,
    _ => null,
  };
  final lastAt = <int, int>{};
  for (var i = 0; i < rows.length; i++) {
    final turn = turnOf(rows[i]);
    if (turn != null && notices.containsKey(turn)) lastAt[turn] = i;
  }
  if (lastAt.isEmpty) return rows;
  final out = <BotRow>[];
  for (var i = 0; i < rows.length; i++) {
    out.add(rows[i]);
    for (final entry in lastAt.entries) {
      if (entry.value != i) continue;
      // A deliverable card of the same turn stays above the quiet line: the
      // block is what the turn made, the line is what it noted.
      var at = out.length;
      while (at > 0 && out[at - 1] is BotArtifactsRow) {
        at--;
      }
      out.insert(at, BotMemoryNoticeRow(notices[entry.key]!, botId: botId));
    }
  }
  return out;
}

/// 这一轮的这一段（首行加它的续行）的数字:耗时、步数、tokens。
typedef BotRunFigures = ({Duration duration, int steps, int tokens});

final class BotItemRow extends BotRow {
  const BotItemRow(this.item, {this.continued = false, this.figures});
  final DsBotItem item;

  /// Same speaker as the row above: no face, no name.
  final bool continued;

  /// 这一段这一轮的统计,摆在首行的成员行上;续行自己不再重复一遍。
  final BotRunFigures? figures;
}

final class BotTimeRow extends BotRow {
  const BotTimeRow(this.time);
  final DateTime time;
}

final class BotPendingRow extends BotRow {
  const BotPendingRow(this.pending);
  final DsBotPending pending;
}

final class BotStreamingRow extends BotRow {
  const BotStreamingRow(this.text);
  final String text;
}

final class BotTypingRow extends BotRow {
  const BotTypingRow(this.bot, this.label);
  final DsBot bot;
  final String label;
}

/// What a turn delivered, drawn under the last row of that turn.
final class BotArtifactsRow extends BotRow {
  const BotArtifactsRow(this.group, {this.sessionId});
  final TurnArtifacts group;

  /// The Session the artifacts came from when it is not the page's own — a
  /// member's Session in a group.
  final String? sessionId;
}

/// Rows for [items]: a time line before a message more than 15 minutes after
/// the one before it, and [continued] runs of one speaker.
List<BotRow> transcriptRows(
  List<DsBotItem> items, {
  List<DsBotPending> pending = const [],
  String? streaming,
  BotTypingRow? typing,
}) {
  final rows = <BotRow>[];
  DateTime? last;
  String? speaker;
  for (final item in items) {
    final time = item.time;
    if (time != null && (last == null || time.difference(last) > const Duration(minutes: 15))) {
      rows.add(BotTimeRow(time));
      speaker = null;
    }
    if (time != null) last = time;
    final who = item.kind == DsBotItemKind.bot ? 'bot:${item.botId ?? item.name}' : item.kind.name;
    final continued = item.kind == DsBotItemKind.bot && who == speaker;
    rows.add(BotItemRow(item, continued: continued));
    speaker = item.kind == DsBotItemKind.event || item.kind == DsBotItemKind.divider ? null : who;
  }
  for (final entry in pending) {
    rows.add(BotPendingRow(entry));
  }
  if (streaming != null) rows.add(BotStreamingRow(streaming));
  if (typing != null) rows.add(typing);
  return _withRunFigures(rows);
}

/// 一段话只说一次账:续行不再各带一份耗时,把这一段最后一行的数字合到首行的
/// 成员行上。没有数字的段原样返回。
List<BotRow> _withRunFigures(List<BotRow> rows) {
  final out = [...rows];
  for (var i = 0; i < out.length; i++) {
    final row = out[i];
    if (row is! BotItemRow) continue;
    var last = i;
    while (last + 1 < out.length && out[last + 1] is BotItemRow && (out[last + 1] as BotItemRow).continued) {
      last++;
    }
    BotRunFigures? figures;
    for (var k = last; k >= i; k--) {
      final item = (out[k] as BotItemRow).item;
      final took = item.duration;
      if (took != null && took >= const Duration(seconds: 1)) {
        figures = (duration: took, steps: item.steps ?? 0, tokens: item.tokens ?? 0);
        break;
      }
    }
    if (figures != null) {
      final first = out[i] as BotItemRow;
      out[i] = BotItemRow(first.item, figures: figures);
    }
    i = last;
  }
  return out;
}

/// The entries a Bot's chat draws: a turn's thinking is **one** line, and only
/// while it is the newest thing.
///
/// A step that reasons stamps its own `thinking` before its reply or tools, so
/// one turn can add several with messages in between. Only the last one can
/// still be "what the Bot is doing": as soon as a reply or a tool row follows
/// it, that step is over, and [running] false (a finished turn, or a part read
/// from history) drops it too.
List<DsBotItem> botTranscriptItems(List<DsBotItem> items, {required bool running, bool fold = true}) {
  // 思考行（网页版的 reasoning 行）：跑到哪跟到哪，正文和工具行来了它也不走。
  // 一条就是一行、收起状态由它自己管，所以不再按 running 丢它 ——「完成后收起
  // 过程」管的是工具与步骤的明细，不是这行本身。
  return items;
}

/// Puts [group]'s deliverables under the turn they belong to.
///
/// Turn numbers restart with every part, so this only attaches when the newest
/// row that carries a turn is that same turn: a page read from history never
/// picks up the current part's card.
/// Cards for several members at once, each under that member's last line.
///
/// A group's lines carry no DSH turn numbers, so a card cannot be placed by turn
/// (that is what [attachArtifacts] does for one conversation). It goes under the
/// last line the member spoke instead — where a reader looks for "what did they
/// deliver". One card per member; a member with nothing delivered is skipped.
List<BotRow> attachMemberArtifacts(
  List<BotRow> rows,
  Map<String, ({String sessionId, TurnArtifacts group})> byBot, {
  int roundStart = -1,
}) {
  // No user line on this page (or only a history page): no card at all — the
  // round that delivered cannot be told apart from the past.
  if (byBot.isEmpty || roundStart < 0) return rows;
  final lastAt = <String, int>{};
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (row is! BotItemRow) continue;
    final item = row.item;
    if (item.kind != DsBotItemKind.bot) continue;
    final botId = item.botId;
    if (botId == null || !byBot.containsKey(botId) || i <= roundStart) continue;
    lastAt[botId] = i;
  }
  if (lastAt.isEmpty) return rows;
  final out = <BotRow>[];
  for (var i = 0; i < rows.length; i++) {
    out.add(rows[i]);
    for (final entry in lastAt.entries) {
      if (entry.value != i) continue;
      final delivery = byBot[entry.key]!;
      out.add(BotArtifactsRow(delivery.group, sessionId: delivery.sessionId));
    }
  }
  return out;
}

/// [group] without the files a member card already drew: in a group the relay
/// Session repeats what members delivered (their presented files are relayed
/// into it), and one file must draw one card. Null when nothing would be left.
TurnArtifacts? unclaimedArtifacts(TurnArtifacts? group, Set<String> claimed) {
  if (group == null || group.files.isEmpty) return null;
  final fresh = [
    for (final file in group.files)
      if (!claimed.contains(file.path)) file,
  ];
  return fresh.isEmpty ? null : TurnArtifacts(turn: group.turn, endSeq: group.endSeq, files: fresh);
}

List<BotRow> attachArtifacts(List<BotRow> rows, TurnArtifacts? group, {bool atOldestEnd = true}) {
  if (group == null || group.files.isEmpty) return rows;
  int? turnOf(BotRow row) => switch (row) {
    BotItemRow(:final item) => item.turn,
    BotToolGroupRow(:final items) => items.isEmpty ? null : items.last.turn,
    _ => null,
  };
  // Where the card goes, without letting an old part's card land in a new one:
  //
  // 1. under the last row stamped with exactly this turn;
  // 2. otherwise only when no row belongs to a *later* turn (a new turn already
  //    started, so the card must not drift down), falling back to the last Bot
  //    message;
  // 3. a page with no turn stamps at all (an older host) may only use that
  //    fallback when it is not a history page — otherwise it would hang an old
  //    part's card under the newest row of a page read backwards.
  var at = -1;
  var anyTurn = false;
  var anyLater = false;
  for (var i = 0; i < rows.length; i++) {
    final turn = turnOf(rows[i]);
    if (turn == null) continue;
    anyTurn = true;
    if (turn == group.turn) at = i;
    if (turn > group.turn) anyLater = true;
  }
  if (at < 0) {
    // A page that stamps turns but never this one (the turn was paged out) must
    // not fall back either: the card would hang off another turn's last row.
    if (anyLater || anyTurn) return rows;
    if (!atOldestEnd) return rows;
    for (var i = rows.length - 1; i >= 0; i--) {
      final row = rows[i];
      if (row is BotItemRow && row.item.kind == DsBotItemKind.bot) {
        at = i;
        break;
      }
    }
  }
  if (at < 0) return rows;
  return [...rows]..insert(at + 1, BotArtifactsRow(group));
}

// ── Tool wording ─────────────────────────────────────────────────────────────

/// What a tool call is doing, said as an action rather than by the tool's own
/// name: 「正在查看文件」 instead of `read_file`. The chat page classifies its
/// own calls in `ui/chat/turn_summary.dart`; a Bot's entries carry only a name
/// and no arguments, so the name map lives here.
enum BotToolKind { run, read, edit, search, browse, message, group, memory, recall, team, ask, work }

BotToolKind botToolKind(String name) {
  final n = name.toLowerCase();
  bool any(List<String> keys) => keys.any(n.contains);
  if (any(['bash', 'shell', 'pwsh', 'exec', 'run', 'terminal', 'command'])) return BotToolKind.run;
  // Before the file verbs: `todo_write` writes no file.
  if (any(['todo', 'plan'])) return BotToolKind.work;
  if (any(['memory'])) return BotToolKind.memory;
  if (any(['recall', 'history', 'transcript'])) return BotToolKind.recall;
  if (any(['team', 'bot_', 'delegate', 'assign'])) return BotToolKind.team;
  if (any(['ask', 'question'])) return BotToolKind.ask;
  if (any(['room', 'group'])) return BotToolKind.group;
  if (any(['message', 'reply', 'send'])) return BotToolKind.message;
  if (any(['write', 'edit', 'patch', 'mkdir', 'delete', 'remove', 'move', 'copy'])) return BotToolKind.edit;
  if (any(['read', 'cat', 'list', 'view', 'glob'])) return BotToolKind.read;
  if (any(['search', 'grep', 'find'])) return BotToolKind.search;
  if (any(['fetch', 'browse', 'browser', 'web_view', 'http', 'url'])) return BotToolKind.browse;
  return BotToolKind.work;
}

/// What one call did, for a finished row: 「查看文件」.
String botToolLabel(L10n l10n, BotToolKind kind) => switch (kind) {
  BotToolKind.run => l10n.botsToolRun,
  BotToolKind.read => l10n.botsToolRead,
  BotToolKind.edit => l10n.botsToolEdit,
  BotToolKind.search => l10n.botsToolSearch,
  BotToolKind.browse => l10n.botsToolBrowse,
  BotToolKind.message => l10n.botsToolMessage,
  BotToolKind.group => l10n.botsToolGroup,
  BotToolKind.memory => l10n.botsToolMemory,
  BotToolKind.recall => l10n.botsToolRecall,
  BotToolKind.team => l10n.botsToolTeam,
  BotToolKind.ask => l10n.botsToolAsk,
  BotToolKind.work => l10n.botsToolWork,
};

/// What one call is doing, while it runs: 「正在查看文件」.
String botToolWorkingLabel(L10n l10n, BotToolKind kind) => switch (kind) {
  BotToolKind.run => l10n.botsToolWorkingRun,
  BotToolKind.read => l10n.botsToolWorkingRead,
  BotToolKind.edit => l10n.botsToolWorkingEdit,
  BotToolKind.search => l10n.botsToolWorkingSearch,
  BotToolKind.browse => l10n.botsToolWorkingBrowse,
  BotToolKind.message => l10n.botsToolWorkingMessage,
  BotToolKind.group => l10n.botsToolWorkingGroup,
  BotToolKind.memory => l10n.botsToolWorkingMemory,
  BotToolKind.recall => l10n.botsToolWorkingRecall,
  BotToolKind.team => l10n.botsToolWorkingTeam,
  BotToolKind.ask => l10n.botsToolWorkingAsk,
  BotToolKind.work => l10n.botsToolWorkingWork,
};

/// A run of calls said as what the Bot did: 「执行 3 条命令 · 改了 2 个文件」.
/// Same segments and order as the chat page's `ToolSummary`.
String botToolSummary(L10n l10n, List<DsBotItem> items) {
  var commands = 0, edited = 0, read = 0, searched = 0, web = 0, other = 0;
  for (final item in items) {
    switch (botToolKind(item.toolName ?? '')) {
      case BotToolKind.run:
        commands++;
      case BotToolKind.edit:
        edited++;
      case BotToolKind.read:
        read++;
      case BotToolKind.search:
        searched++;
      case BotToolKind.browse:
        web++;
      case BotToolKind.message ||
          BotToolKind.group ||
          BotToolKind.memory ||
          BotToolKind.recall ||
          BotToolKind.team ||
          BotToolKind.ask ||
          BotToolKind.work:
        other++;
    }
  }
  final parts = [
    if (commands > 0) l10n.activitySummaryCommands(commands),
    if (edited > 0) l10n.activitySummaryEditedFiles(edited),
    if (read > 0) l10n.activitySummaryReadFiles(read),
    if (searched > 0) l10n.activitySummarySearches(searched),
    if (web > 0) l10n.activitySummaryWeb(web),
    if (other > 0) l10n.activitySummaryOther(other),
  ];
  return parts.isEmpty ? l10n.activitySummaryTotal(items.length) : parts.join(' · ');
}

/// How long a run of calls took, as 「8 秒」; null when the host sent nothing
/// and the entries carry no times either.
String? botToolSpan(L10n l10n, List<DsBotItem> items) {
  var total = Duration.zero;
  for (final item in items) {
    if (item.duration case final duration?) total += duration;
  }
  if (total == Duration.zero && items.length >= 2) {
    final times = [for (final item in items) ?item.time];
    if (times.length >= 2) total = times.last.difference(times.first);
  }
  if (total < const Duration(seconds: 1)) return null;
  return l10n.activitySpanSecondsText('${(total.inMilliseconds / 1000).round()}');
}

/// Consecutive tool calls from this many on fold into one group, as the chat
/// page groups them.
const toolGroupThreshold = 3;

/// A run of consecutive tool calls, folded so they do not push the reply down.
final class BotToolGroupRow extends BotRow {
  const BotToolGroupRow(this.items);

  final List<DsBotItem> items;
}

/// [rows] with runs of [toolGroupThreshold] or more tool calls folded into one
/// [BotToolGroupRow]; a shorter run stays as the lines it was.
List<BotRow> groupToolRows(List<BotRow> rows, {bool fold = true}) {
  final out = <BotRow>[];
  var run = <BotItemRow>[];
  final threshold = fold ? toolGroupThreshold : 1 << 30;
  void flush() {
    if (run.length >= threshold) {
      out.add(BotToolGroupRow([for (final row in run) row.item]));
    } else {
      out.addAll(run);
    }
    run = <BotItemRow>[];
  }

  for (final row in rows) {
    if (row is BotItemRow && row.item.kind == DsBotItemKind.tool) {
      run.add(row);
      continue;
    }
    if (run.isNotEmpty) flush();
    out.add(row);
  }
  if (run.isNotEmpty) flush();
  return out;
}

/// A folded run of tool calls: one line with how many ran, open while they are
/// still running and folded again once they are done.
class BotToolGroup extends StatefulWidget {
  const BotToolGroup({super.key, required this.items});

  final List<DsBotItem> items;

  @override
  State<BotToolGroup> createState() => _BotToolGroupState();
}

class _BotToolGroupState extends State<BotToolGroup> {
  late bool _open = widget.items.any(_running);

  static bool _running(DsBotItem item) => item.toolStatus == 'running';

  @override
  void didUpdateWidget(covariant BotToolGroup old) {
    super.didUpdateWidget(old);
    final was = old.items.any(_running);
    final now = widget.items.any(_running);
    // Still running: open. Just finished: fold back, as the chat page does.
    if (now && !was) _open = true;
    if (!now && was) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final failed = widget.items.any((item) => item.toolStatus == 'failed');
    final tone = failed ? colors.warning : colors.textTertiary;
    final running = widget.items.where(_running).toList();
    // Running: what the last call under way is doing. Finished: what the run
    // did, then how long it took.
    final label = running.isEmpty
        ? botToolSummary(l10n, widget.items)
        : botToolWorkingLabel(l10n, botToolKind(running.last.toolName ?? ''));
    final span = running.isEmpty ? botToolSpan(l10n, widget.items) : null;
    final shown = span == null ? label : '$label · $span';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: shown,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: AppShape.radiusSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(failed ? AppIcons.warning : AppIcons.terminal, size: 16, color: tone),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      shown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(_open ? AppIcons.collapse : AppIcons.expand, size: 16, color: tone),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in widget.items)
                  BotToolRow(name: item.toolName ?? '', status: item.toolStatus),
              ],
            ),
          ),
      ],
    );
  }
}

/// The composer's measured height, for the transcript below it.
class ComposerInsetScope extends InheritedWidget {
  const ComposerInsetScope({super.key, required this.height, required super.child});

  final ValueListenable<double> height;

  static ValueListenable<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ComposerInsetScope>()?.height;

  @override
  bool updateShouldNotify(ComposerInsetScope oldWidget) => oldWidget.height != height;
}

/// The transcript, newest at the bottom; scrolling up to the oldest row asks
/// for the page before.
class BotTranscript extends StatefulWidget {
  const BotTranscript({
    super.key,
    required this.rows,
    required this.rowBuilder,
    required this.topInset,
    this.bottomInset = 0,
    this.hasEarlier = false,
    this.loadingEarlier = false,
    this.onEarlier,
    this.scrolledUnder,
    this.empty,
    this.notice,
  });

  final List<BotRow> rows;
  final Widget Function(BuildContext context, BotRow row) rowBuilder;
  final double topInset;

  /// How much of the transcript the composer covers: the last row keeps this
  /// much clear at the bottom, measured from the composer's real height.
  final double bottomInset;

  final bool hasEarlier;
  final bool loadingEarlier;
  final VoidCallback? onEarlier;
  final ValueNotifier<double>? scrolledUnder;

  /// Shown when there are no rows.
  final Widget? empty;

  /// One line the list carries under the newest row, while it still holds
  /// rows: 「这一段里没有他的发言」 over the user's own lines. Not [empty],
  /// which replaces the whole list.
  final Widget? notice;

  @override
  State<BotTranscript> createState() => _BotTranscriptState();
}

class _BotTranscriptState extends State<BotTranscript> {
  final _controller = ScrollController();
  bool _away = false;

  /// The rows held while the person reads: frozen at the frame they scrolled
  /// away, so nothing under the finger moves — not even a growing reply —
  /// however much arrives. Cleared when the newest row is on screen again.
  List<BotRow>? _frozen;

  /// Rows that arrived while the list was scrolled away: the badge on the way
  /// back. Reset as soon as the newest row is on screen again.
  int _new = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_check);
    // The list has a position only after its first layout; a page that opens
    // already scrolled away must still offer the way back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  @override
  void didUpdateWidget(BotTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    final added = widget.rows.length - oldWidget.rows.length;
    // Sent from here: the newest line is the person's own, so it always lands
    // in view, reading or not.
    int pendingRows(List<BotRow> rows) => rows.whereType<BotPendingRow>().length;
    final ownSend = pendingRows(widget.rows) > pendingRows(oldWidget.rows);
    if (_away && ownSend) {
      _toBottom();
      return;
    }
    if (added > 0 && _away && mounted) {
      // Freeze on the frame the person was reading: the count says what came.
      _frozen ??= oldWidget.rows;
      setState(() => _new += added);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_check);
    _controller.dispose();
    super.dispose();
  }

  /// This list's own position only. A `ScrollNotification` also carries the
  /// scrolls of what the rows hold (a code block, a long table), and their
  /// extents read as "far from the bottom" even when this list is at its end.
  void _check() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    // Reversed: content above the top edge is what lies past the scroll end.
    final above = position.maxScrollExtent - position.pixels;
    widget.scrolledUnder?.value = (above / 24).clamp(0.0, 1.0);
    if (above < 400 && widget.hasEarlier && !widget.loadingEarlier) widget.onEarlier?.call();
    // Reversed, pixels counts from the newest row: 0 is the bottom. `above`
    // is the distance to the oldest end, which is a different question.
    final away = position.pixels > 240;
    if (away != _away && mounted) {
      setState(() {
        _away = away;
        if (!away) {
          _frozen = null;
          _new = 0;
        }
      });
    }
    if (!away && _new != 0 && mounted) setState(() => _new = 0);
  }

  void _toBottom() {
    setState(() {
      _new = 0;
      _frozen = null;
      _away = false;
    });
    _controller.animateTo(0, duration: AppMotion.of(context, AppMotion.standard), curve: AppMotion.std);
  }

  @override
  Widget build(BuildContext context) {
    final composer = ComposerInsetScope.maybeOf(context);
    if (composer != null) {
      return ValueListenableBuilder<double>(
        valueListenable: composer,
        builder: (context, height, _) => _body(context, widget.bottomInset + height),
      );
    }
    return _body(context, widget.bottomInset);
  }

  Widget _body(BuildContext context, double bottomInset) {
    final rows = _away ? (_frozen ?? widget.rows) : widget.rows;
    if (rows.isEmpty && widget.empty != null) {
      return Padding(
        padding: EdgeInsets.only(top: widget.topInset, bottom: bottomInset),
        child: Center(child: widget.empty),
      );
    }
    final extra = widget.hasEarlier ? 1 : 0;
    final notice = widget.notice;
    final noticeCount = notice == null ? 0 : 1;
    return Stack(
      children: [
        ListView.builder(
            controller: _controller,
            reverse: true,
        // 末尾留出托板的高度：最后一条仍能滚到托板上方,同时往下滚时正文
        // 会从托板下面穿过去。
        padding: EdgeInsets.fromLTRB(0, widget.topInset, 0, 8 + bottomInset),
        itemCount: rows.length + extra + noticeCount,
        itemBuilder: (context, index) {
          if (notice != null && index == 0) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppSpace.readingWidth),
                child: notice,
              ),
            );
          }
          if (index == rows.length + noticeCount) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          final row = rows[rows.length - 1 - (index - noticeCount)];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSpace.readingWidth),
              child: widget.rowBuilder(context, row),
            ),
          );
        },
        ),
        // Scrolled away from the newest row: one tap brings it back.
        Positioned(
          right: 16,
          bottom: 16,
          // Hidden is hidden to the finger and to a screen reader too: a
          // scaled-to-zero button would still take both.
          child: IgnorePointer(
            ignoring: !_away,
            child: ExcludeSemantics(
              excluding: !_away,
              child: AnimatedScale(
                scale: _away ? 1 : 0,
            duration: AppMotion.of(context, AppMotion.quick),
            curve: AppMotion.std,
            child: Semantics(
              button: true,
              label: context.l10n.chatBackToBottom,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _away ? _toBottom : null,
                  child: SizedBox.square(
                    dimension: 40,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Center(child: Icon(AppIcons.scrollToBottom, size: 22)),
                        // What arrived while away: the button alone says "back to
                        // the newest line", the count says why it is worth it.
                        if (_new > 0)
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Semantics(
                              label: context.l10n.chatNewContentCount(_new),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  _new > 99 ? '99+' : '$_new',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onError,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ),
        ),
        ),
      ],
    );
  }
}

/// Space above a row: tight inside one speaker's run, wider between turns.
/// Rows start where the composer starts (12), so a member's face sits on the
/// same left edge as the field below it; the right keeps the old air.
EdgeInsets rowPadding(BotRow row) => switch (row) {
  BotItemRow(continued: true) => const EdgeInsets.fromLTRB(12, 4, 16, 0),
  BotTimeRow() => const EdgeInsets.fromLTRB(12, 20, 16, 4),
  BotArtifactsRow() => const EdgeInsets.fromLTRB(12, 12, 16, 0),
  BotMemoryNoticeRow() => const EdgeInsets.fromLTRB(12, 2, 16, 0),
  _ => const EdgeInsets.fromLTRB(12, 16, 16, 0),
};

/// 「14:05」 between messages far apart, with a hairline on each side so the
/// break in the conversation reads as one.
class BotTimeLine extends StatelessWidget {
  const BotTimeLine(this.time, {super.key});

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.colorScheme.outlineVariant.withValues(alpha: 0.7);
    return Row(
      children: [
        Expanded(child: Container(key: const ValueKey('time-line-left'), height: 1, color: line)),
        const SizedBox(width: 10),
        Text(
          shortTime(time),
          style: AppType.tabular(theme.textTheme.labelSmall!.copyWith(color: DshColors.of(context).textTertiary)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(key: const ValueKey('time-line-right'), height: 1, color: line)),
      ],
    );
  }
}

/// A quiet centred line: something that happened, not something said.
class BotEventLine extends StatelessWidget {
  const BotEventLine({super.key, required this.text, this.icon, this.danger = false});

  final String text;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final color = danger ? dsh.danger : dsh.textTertiary;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color, height: 1.45);
    return Center(
      child: Text.rich(
        TextSpan(
          children: [
            if (icon != null) ...[
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(icon, size: 14, color: color),
              ),
              const TextSpan(text: ' '),
            ],
            TextSpan(text: text),
          ],
        ),
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}

/// A Bot's words in its own chat: bare full-width Markdown, like the chat's
/// replies; long-press copies or selects.
class BotReplyText extends StatelessWidget {
  const BotReplyText({
    super.key,
    required this.text,
    this.streaming = false,
    this.actions = const [MessageAction.copy, MessageAction.selectText, MessageAction.share],
    this.onQuote,
    this.onLinkTap,
    this.mentions = const [],
  });

  final String text;
  final bool streaming;

  /// What its long-press menu offers; 引用 is added in [_menu] where it applies.
  /// A group member's line offers the same set as the Bot's own.
  final List<MessageAction> actions;

  /// 引用: puts this line above the composer. Null where引用 does not apply.
  final ValueChanged<String>? onQuote;

  /// A link in the reply that the page can open itself (a file in the workspace);
  /// null keeps every link on its default path.
  final bool Function(String href)? onLinkTap;

  /// The group's members, so an `@名字` in the line wears that member's ink, as
  /// the web draws it. Empty in a Bot's own chat, where nobody can be called.
  final List<InlineMention> mentions;

  Future<void> _menu(BuildContext context) async {
    if (actions.isEmpty) return;
    // A Bot's reply carries ```dsh-ui JSON for the phone to draw: the preview,
    // 复制 and 引用 show the words instead, as the chat's own menu does.
    final plain = dshUiPlainText(text);
    final action = await showMessageMenu(
      context,
      text: plain,
      actions: [...actions, if (onQuote != null) MessageAction.quote],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case MessageAction.copy:
        await copyMessage(context, plain);
      case MessageAction.selectText:
        // The sheet renders it: the Markdown, as the reply reads.
        await showSelectTextSheet(context, text, markdown: true);
      case MessageAction.share:
        // As 复制: a view's JSON is not what the reply says.
        await shareText(context, plain);
      case MessageAction.quote:
        onQuote?.call(plain);
      case MessageAction.edit || MessageAction.regenerate || MessageAction.branch:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: streaming || actions.isEmpty ? null : () => _menu(context),
    child: MarkdownBody(
      text: text,
      streaming: streaming,
      selectable: false,
      repairBareViews: true,
      mentions: mentions,
      onLinkTap: onLinkTap,
    ),
  );
}

/// One message in a group: the speaker's face and name on the first of a
/// run, then the text beside the face's column.
///
/// ```
/// ◉  Chief  管理员  14:05
///    @Writer 写个初稿
///    第二句接着同一个人
/// ```
/// 消息布局: a Bot's line as the web draws it — a bubble tinted with the
/// speaker's ink — or, in 平铺, plain text at the column's width.
class BotTextBubble extends StatelessWidget {
  const BotTextBubble({
    super.key,
    required this.child,
    required this.ink,
    required this.flat,
    this.leftInset = 14,
    this.offset,
  });

  final Widget child;
  final Color ink;
  final bool flat;

  /// 文字离气泡左沿多远。群里把它缩成头像和正文之间的那段距离，气泡再整体
  /// 往左让出同样的 10dp，正文的左边就和名字的左边落在一条线上。
  final double leftInset;

  /// 整个气泡的平移（群里往左让出 [leftInset]）。
  final Offset? offset;

  @override
  Widget build(BuildContext context) {
    if (flat) return child;
    final base = Theme.of(context).colorScheme.surface;
    final bubble = DecoratedBox(
      decoration: ShapeDecoration(
        // 3% of the member's ink, over the surface: the web's own tint.
        color: Color.alphaBlend(ink.withValues(alpha: 0.06), base),
        shape: AppShape.bubble,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(leftInset, 9, 14, 9),
        child: child,
      ),
    );
    final shift = offset;
    return shift == null ? bubble : Transform.translate(offset: shift, child: bubble);
  }
}

/// A group line's footnote: `39 秒 · 7 步 · 109K tokens ›`, the same sentence a
/// Bot's own reply ends with. Tapping it opens the member Session's 用量 panel.
class BotGroupFootnote extends StatelessWidget {
  const BotGroupFootnote({
    super.key,
    required this.duration,
    this.steps = 0,
    this.tokens = 0,
    this.onTap,
  });

  final Duration duration;
  final int steps;
  final int tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final label = [
      formatSpan(duration),
      if (steps > 0) l10n.chatTurnSteps(steps),
      if (tokens > 0) '${formatTokens(tokens)} tokens',
    ].join(' · ');
    final style = AppType.tabular(
      theme.textTheme.labelSmall!.copyWith(fontSize: 12, color: dsh.textTertiary, height: 1.3),
    );
    return Semantics(
      button: onTap != null,
      label: label,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        customBorder: Squircle.border(AppShape.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: style),
              ),
              Icon(AppIcons.disclosure, size: 14, color: dsh.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class GroupMessage extends ConsumerWidget {
  const GroupMessage({
    super.key,
    required this.item,
    required this.bot,
    required this.continued,
    this.admin = false,
    this.onOpenBot,
    this.onShowAll,
    this.onQuote,
    this.onLinkTap,
    this.mentions = const [],
    this.onStats,
    this.figures,
  });

  final DsBotItem item;

  /// Null when the speaker is no longer on the team.
  final DsBot? bot;
  final bool continued;
  final bool admin;
  final VoidCallback? onOpenBot;

  /// A long post sent as a file: reads it whole.
  final VoidCallback? onShowAll;

  /// 引用 on a group line (not offered on a line with no text).
  final ValueChanged<String>? onQuote;

  /// A link in the line that the page opens itself (the speaker's Session resolves
  /// the path); null keeps the default link behaviour.
  final bool Function(String href)? onLinkTap;

  /// The group's members: `@名字` in the line wears that member's ink.
  final List<InlineMention> mentions;

  /// The 统计面板 behind the line's footnote (用量 of the member's Session in this
  /// group). Null on a line without one, which draws no footnote.
  final VoidCallback? onStats;

  /// 这一段这一轮的统计（首行才有）：摆在这一行的成员行上。
  final BotRunFigures? figures;

  static const face = 28.0;
  static const gap = 10.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final flat = ref.watch(settingsProvider.select((s) => s.flatBubbles));
    final text = botLineText(item);
    final name = bot?.name ?? item.name ?? 'Bot';
    final color = bot?.ink ?? item.color ?? dsBotDefaultColor(item.botId ?? name);
    final avatar = bot == null ? BotMonogram(name: name, color: color, size: face) : BotAvatar(bot: bot!, size: face);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!continued)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: botNameInk(context, color),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (admin) ...[const SizedBox(width: 6), BotTag(l10n.botsAdmin)],
                // 时间与统计靠行尾：宽屏下气泡变宽，它们不能留在名字后面。
                // 挤的时候先缩名字和统计，时间固定在最右。
                const Spacer(),
                // 这一轮的统计摆在成员行上：耗时 · 步数 · tokens，点开是统计面板。
                // 数字来自这一段的最后一行（见 _withRunFigures），续行不再各带一份。
                if (figures case final run?) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: BotGroupFootnote(
                      duration: run.duration,
                      steps: run.steps,
                      tokens: run.tokens,
                      onTap: onStats,
                    ),
                  ),
                ],
                if (item.time != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    shortTime(item.time),
                    style: AppType.tabular(theme.textTheme.labelSmall!.copyWith(color: dsh.textTertiary)),
                  ),
                ],
              ],
            ),
          ),
        BotTextBubble(
          ink: botInk(context, color),
          flat: flat,
          // 正文左边与名字左边对齐：气泡自己往左让出头像和正文之间的 10dp，
          // 左边距也用这 10dp，于是没有气泡时文字落在哪儿，有气泡时也落在哪儿。
          leftInset: gap,
          // 气泡整体往左让出这一段（不缩内容宽度），正文左边就落在名字左边；
          // 头像那一列刚好到这儿，气泡的圆角贴着头像的右沿。
          offset: flat ? null : Offset(-gap, 0),
          child: BotReplyText(
          text: text,
          mentions: mentions,
          // One menu, not two: the inner one wins the gesture arena anyway.
          // A file-only line has no text worth copying, selecting or sharing.
          actions: text.isEmpty
              ? const []
              : const [MessageAction.copy, MessageAction.selectText, MessageAction.share],
          onQuote: onQuote,
          onLinkTap: onLinkTap,
          ),
        ),
        if (onShowAll != null)
          TextButton(
            onPressed: onShowAll,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            child: Text(l10n.botsShowAll),
          ),
      ],
    );
    return Semantics(
      label: name,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: face,
            child: continued ? null : GestureDetector(onTap: onOpenBot, child: avatar),
          ),
          const SizedBox(width: gap),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// A step's thinking, drawn the way a conversation draws it: the same
/// collapsible [ThinkingPill] the native chat uses, in the Bot's own line.
class BotThinkingLine extends StatelessWidget {
  const BotThinkingLine({
    super.key,
    required this.text,
    this.bot,
    this.active = false,
    this.streaming = false,
    this.growIn = false,
  });

  /// The reasoning as the Host wrote it.
  final String text;

  /// Whose line it is; null where the page already shows the speaker (a Bot's
  /// own chat draws no faces beside its rows).
  final DsBot? bot;

  final bool active;
  final bool streaming;
  final bool growIn;

  @override
  Widget build(BuildContext context) {
    final pill = ThinkingPill(reasoning: text, active: active, streaming: streaming, growIn: growIn);
    final bot = this.bot;
    if (bot == null) return pill;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BotAvatar(bot: bot, size: GroupMessage.face, working: active),
        const SizedBox(width: GroupMessage.gap),
        Expanded(child: pill),
      ],
    );
  }
}

/// 「Writer 正在输入…」 under the last message while a member speaks.
class BotTypingLine extends StatelessWidget {
  const BotTypingLine({super.key, required this.bot, required this.label});

  final DsBot bot;
  final String label;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    return Row(
      children: [
        BotAvatar(bot: bot, size: GroupMessage.face, working: true),
        const SizedBox(width: GroupMessage.gap),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(height: 14, child: TypingIndicator(color: dsh.textTertiary)),
      ],
    );
  }
}

/// 复制 / 选择文字 / 引用 for a person's line outside a conversation (a Bot's or
/// a group's): what makes sense without the chat's own semantics. 分享 is not
/// one of them — a person's bubbles have none — and the preview is masked so a
/// pasted key never shows in the sheet, while 复制 takes the text as typed.
Future<void> botLineMenu(BuildContext context, String text, {ValueChanged<String>? onQuote}) async {
  final action = await showMessageMenu(
    context,
    text: maskSecrets(text, mark: '•'),
    actions: [MessageAction.copy, MessageAction.selectText, if (onQuote != null) MessageAction.quote],
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case MessageAction.copy:
      await copyMessage(context, text);
    case MessageAction.selectText:
      // Plain text: a person's message is not rendered as Markdown.
      await showSelectTextSheet(context, text, markdown: false);
    case MessageAction.quote:
      onQuote?.call(text);
    default:
      break;
  }
}

/// A line's text as it should read on the phone.
///
/// A line that carries files arrives with one `[File "name" (N bytes) attached]`
/// line beside them: that is the host writing the files into the text for a
/// reader that cannot see the row of cards. The phone draws the cards, so those
/// lines are dropped here instead of showing as noise under the bubble (a line
/// that was only files then reads as nothing at all).
String botLineText(DsBotItem item) {
  if (item.files.isEmpty) return item.text;
  return item.text
      .split('\n')
      .where((line) => !_fileMarker.hasMatch(line.trim()))
      .join('\n')
      .trim();
}

final _fileMarker = RegExp(r'^\[File ".*" \(\d+ bytes?\) attached\]$');

/// The person's message: its pictures and files above, its text in the bubble.
/// A line that carries only attachments has no bubble at all.
class BotUserMessage extends StatelessWidget {
  const BotUserMessage({
    super.key,
    required this.text,
    this.pending = false,
    this.pendingSince,
    this.pendingStatus = DsBotPendingStatus.sending,
    this.images = 0,
    this.attachments,
    this.onQuote,
    this.onRetry,
    this.onWithdraw,
    this.queueLabel,
    this.queueIcon,
    this.queueActions = const [],
  });

  /// Set when the Host's inbox holds this message: its slot's words, icon and
  /// actions, which replace the sending/failed note.
  final String? queueLabel;
  final IconData? queueIcon;
  final List<(String, VoidCallback)> queueActions;

  /// Failed only: 重试 reuses the same request id, 撤回 puts the text back.
  final VoidCallback? onRetry;
  final VoidCallback? onWithdraw;

  final String text;
  final bool pending;

  /// 发送中 / 没能发送: the bubble says which, without adding a second line.
  final DsBotPendingStatus pendingStatus;

  /// When a queued line was made. The label says how long it has waited — an
  /// approximation (a retry or a page rebuild restarts the clock), enough to show
  /// it has not been picked up yet, not a record.
  final DateTime? pendingSince;

  /// How many images the line carries when the host only counted them; that is
  /// all an older host says, so the line says so instead of drawing nothing.
  final int images;

  /// [SentAttachments] for the line's pictures and files, or null.
  final Widget? attachments;

  /// 引用: this line goes above the composer.
  final ValueChanged<String>? onQuote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shown = text.isEmpty && attachments == null && images > 0 ? l10n.botsImagePlaceholder : text;
    if (shown.isEmpty && attachments == null) return const SizedBox.shrink();
    final failed = pending && pendingStatus == DsBotPendingStatus.failed;
    // 0.72 while it is not landed; fully opaque once it is, or once it failed
    // (a half-transparent failure reads as "still sending").
    final alpha = pending && !failed ? 0.72 : 1.0;
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onLongPress: pending || text.trim().isEmpty ? null : () => botLineMenu(context, text, onQuote: onQuote),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedOpacity(
              opacity: alpha,
              duration: AppMotion.of(context, const Duration(milliseconds: 150)),
              child: UserBubble(text: shown, attachments: attachments),
            ),
            if (pending) ...[
              const SizedBox(height: 6),
              _PendingNote(
                failed: failed,
                since: pendingSince,
                onRetry: onRetry,
                onWithdraw: onWithdraw,
                label: queueLabel,
                icon: queueIcon,
                actions: queueActions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 发送中 (with a small clock), 还在等服务器确认 after 8 s, or 没能发送.
class _PendingNote extends StatelessWidget {
  const _PendingNote({
    required this.failed,
    this.since,
    this.onRetry,
    this.onWithdraw,
    this.label,
    this.icon,
    this.actions = const [],
  });

  final bool failed;
  final DateTime? since;
  final VoidCallback? onRetry;
  final VoidCallback? onWithdraw;

  /// From the Host's inbox when it holds this message (排队 / 插话).
  final String? label;
  final IconData? icon;
  final List<(String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final waited = since == null ? Duration.zero : DateTime.now().difference(since!);
    final label = this.label ?? (failed
        ? l10n.botsSendFailed
        : waited > const Duration(seconds: 8)
        ? l10n.botsSendStillWaiting
        : l10n.botsSending);
    final tone = failed ? colors.danger : colors.textTertiary;
    Widget action(String text, Color color, VoidCallback? onTap) => Padding(
      padding: const EdgeInsets.only(left: 4),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: color,
          textStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        child: Text(text),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(failed ? AppIcons.error : (icon ?? AppIcons.time), size: 13, color: tone),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: tone)),
        if (actions.isNotEmpty)
          for (final (text, onTap) in actions)
            action(text, Theme.of(context).colorScheme.primary, onTap)
        else ...[
          if (failed && onRetry != null) action(l10n.commonRetry, Theme.of(context).colorScheme.primary, onRetry),
          if (failed && onWithdraw != null) action(l10n.chatWithdraw, colors.textTertiary, onWithdraw),
        ],
      ],
    );
  }
}

/// A tool call in a Bot's chat: what it is doing, and whether it is still
/// running. Said as an action (「正在查看文件」), not by the tool's own name;
/// the host sends no arguments or output, so there is nothing to expand.
class BotToolRow extends StatelessWidget {
  const BotToolRow({super.key, required this.name, this.status});

  final String name;

  /// `running` / `done` / `failed`.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final failed = status == 'failed';
    final running = status == 'running';
    final kind = botToolKind(name);
    final shown = running ? botToolWorkingLabel(l10n, kind) : botToolLabel(l10n, kind);
    final label = failed ? l10n.commonFailed : null;
    final tone = failed ? colors.warning : colors.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(failed ? AppIcons.warning : running ? AppIcons.running : AppIcons.done, size: 16, color: tone),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              shown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: tone)),
          ],
        ],
      ),
    );
  }
}

/// 「记忆已更新」 under the turn that did it: one quiet line, tappable, and the
/// only place a Bot's chat says a memory write happened (the web client says it
/// the same way, in the same place).
class BotMemoryLine extends StatelessWidget {
  const BotMemoryLine({super.key, required this.notice, this.onTap});

  final MemoryNotice notice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final failed = notice.change == MemoryChange.failed;
    final text = switch (notice.change) {
      MemoryChange.updated => l10n.botsMemoryUpdated,
      MemoryChange.already => l10n.botsMemoryAlready,
      MemoryChange.unchanged => l10n.botsMemoryUnchanged,
      MemoryChange.failed => l10n.botsMemoryFailed,
    };
    final why = failed ? memoryReasonText(l10n, notice.reason) : null;
    final tone = failed ? colors.warning : colors.textTertiary;
    final line = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(failed ? AppIcons.warning : AppIcons.bookmark, size: 14, color: tone),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            [
              text,
              if (notice.count > 1) '×${notice.count}',
              if (why != null) '· $why',
            ].join(' '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: tone),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: onTap == null
          ? line
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: line),
            ),
    );
  }
}

/// Why a memory write changed nothing, in the interface language
/// (`remember` / `forget` answer with a code; the host's words stay in the log).
String memoryReasonText(L10n l10n, String? code) => switch (code) {
  'memory/empty' => l10n.botsMemoryReasonEmpty,
  'memory/no-match' => l10n.botsMemoryReasonNoMatch,
  'memory/refused' || 'memory/denied' => l10n.botsMemoryReasonRefused,
  _ => l10n.botsMemoryReasonOther,
};

// ── Cards ────────────────────────────────────────────────────────────────────

/// A question card from `ask_user`: the options as capsules (one or several),
/// an own answer when the Bot allows it, 「发送」.
class BotQuestionCard extends StatefulWidget {
  const BotQuestionCard({super.key, required this.question, required this.onAnswer, required this.onDismiss});

  final DsBotQuestion question;
  final Future<bool> Function(List<String> selected, String? custom) onAnswer;
  final VoidCallback onDismiss;

  @override
  State<BotQuestionCard> createState() => _BotQuestionCardState();
}

class _BotQuestionCardState extends State<BotQuestionCard> {
  final Set<String> _picked = {};
  final _custom = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final custom = _custom.text.trim();
    setState(() => _sending = true);
    final ok = await widget.onAnswer(_picked.toList(), custom.isEmpty ? null : custom);
    if (mounted && !ok) setState(() => _sending = false);
  }

  void _tap(String label) {
    HapticFeedback.selectionClick();
    setState(() {
      if (widget.question.multiSelect) {
        _picked.contains(label) ? _picked.remove(label) : _picked.add(label);
      } else {
        _picked
          ..clear()
          ..add(label);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final q = widget.question;
    final ready = _picked.isNotEmpty || _custom.text.trim().isNotEmpty;
    return ChatCard(
      icon: AppIcons.question,
      title: q.question,
      titleMaxLines: 3,
      tone: ChatCardTone.ask,
      trailing: CardCloseKey(onTap: widget.onDismiss),
      children: [
        if (q.detail case final detail?)
          Padding(
            padding: const EdgeInsets.fromLTRB(ChatCard.inset, 0, ChatCard.inset, 8),
            child: Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(ChatCard.inset, 0, ChatCard.inset, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in q.options)
                Tooltip(
                  message: option.description ?? '',
                  child: CapsuleChoiceChip(
                    label: option.label,
                    selected: _picked.contains(option.label),
                    onSelected: () {
                      if (!_sending) _tap(option.label);
                    },
                  ),
                ),
            ],
          ),
        ),
        if (q.allowCustom)
          Padding(
            padding: const EdgeInsets.fromLTRB(ChatCard.inset, 8, ChatCard.inset, 0),
            child: TextField(
              controller: _custom,
              enabled: !_sending,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: l10n.botsWriteOwn, isDense: true),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(ChatCard.inset, 12, ChatCard.inset, ChatCard.inset),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: cardButton,
              onPressed: ready && !_sending ? _send : null,
              child: Text(l10n.commonSend),
            ),
          ),
        ),
      ],
    );
  }
}

/// A view card from `show_view` that waits: its text, then the first thing to
/// answer (options, a confirmation or a short form).
class BotViewCard extends StatefulWidget {
  const BotViewCard({super.key, required this.view, required this.onAnswer, required this.onDismiss, this.onOpenInWeb});

  final DsBotViewCard view;
  final VoidCallback? onOpenInWeb;
  final Future<bool> Function(String action, Map<String, Object?> values) onAnswer;
  final VoidCallback onDismiss;

  @override
  State<BotViewCard> createState() => _BotViewCardState();
}

// Unseen inputs must never turn into silently submitted server defaults.
bool canRenderBotView(Map<String, Object?> view) => !_viewFormula(view) && _nativeViewNode(view);

bool _viewFormula(Object? value) {
  if (value is Map) {
    if (value.containsKey('=') ||
        (value['let'] != null && (value['let'] is! Map || (value['let'] as Map).isNotEmpty))) {
      return true;
    }
    return value.values.any(_viewFormula);
  }
  return value is List && value.any(_viewFormula);
}

bool _viewScalar(Object? value) => value is String || value is bool || (value is num && value.isFinite);
bool _optionalViewText(Object? value) => value == null || value is String;

bool _nativeViewNode(Object? node, [int depth = 0]) {
  if (node is! Map || depth > 6) return false;
  final id = node['id'];
  final actionId = id is String && id.isNotEmpty;
  return switch (node['type']) {
    'text' => node['text'] is String,
    'metric' => node['label'] is String && _viewScalar(node['value']) && node['caption'] == null,
    'progress' =>
      node['percent'] is num &&
          (node['percent'] as num).isFinite &&
          _optionalViewText(node['label']) &&
          node['value'] == null &&
          node['max'] == null &&
          node['valueLabel'] == null,
    'submit' => actionId && _optionalViewText(node['label']),
    'confirm' => actionId && _optionalViewText(node['confirmLabel']) && _optionalViewText(node['cancelLabel']),
    'options' =>
      actionId &&
          node['options'] is List &&
          (node['options'] as List).isNotEmpty &&
          (node['options'] as List).every(
            (option) => option is Map && option['label'] is String && _optionalViewText(option['description']),
          ),
    'form' =>
      actionId &&
          _optionalViewText(node['submitLabel']) &&
          node['fields'] is List &&
          (node['fields'] as List).every(
            (field) =>
                field is Map &&
                field['id'] is String &&
                field['label'] is String &&
                _optionalViewText(field['placeholder']),
          ),
    'choice' => _validViewChoice(node),
    'stack' ||
    'row' => node['children'] is List && (node['children'] as List).every((child) => _nativeViewNode(child, depth + 1)),
    _ => false,
  };
}

Object? _viewChoiceValue(Map option) => option['value'] ?? option['label'];

bool _validViewChoice(Map node) {
  if (node['id'] is! String || (node['id'] as String).isEmpty || node['label'] is! String) return false;
  final options = node['options'];
  if (options is! List || options.isEmpty) return false;
  final values = <Object?>{};
  final labels = <String>{};
  for (final option in options) {
    if (option is! Map || option['label'] is! String || (option['label'] as String).trim().isEmpty) return false;
    final value = _viewChoiceValue(option);
    if (value is! String && value is! bool && !(value is num && value.isFinite)) return false;
    if (!values.add(value) || !labels.add(option['label'] as String)) return false;
  }
  return values.contains(node['value'] ?? _viewChoiceValue(options.first as Map));
}

List<Map<String, Object?>> _viewChoices(Map<String, Object?> view) {
  if (!canRenderBotView(view)) return const [];
  final choices = <Map<String, Object?>>[];
  void walk(Map node) {
    if (node['type'] == 'choice') choices.add(node.cast<String, Object?>());
    if (node['type'] == 'stack' || node['type'] == 'row') {
      for (final child in node['children'] as List) {
        walk(child as Map);
      }
    }
  }

  walk(view);
  return choices;
}

/// What a view card shows: its lines and the component to answer.
({List<String> lines, Map<String, Object?>? control}) readView(Map<String, Object?> view) {
  final lines = <String>[];
  if (!canRenderBotView(view)) return (lines: lines, control: null);
  Map<String, Object?>? control;
  void walk(Object? node, int depth) {
    if (node is! Map || depth > 6) return;
    final type = node['type'];
    switch (type) {
      case 'text':
        if (node['text'] case final String text when text.trim().isNotEmpty) lines.add(text.trim());
      case 'metric':
        lines.add(appL10n.botsViewMetric(node['label'] ?? '', node['value'] ?? ''));
      case 'progress':
        final label = node['label'];
        lines.add('${label is String && label.isNotEmpty ? '$label ' : ''}${node['percent'] ?? 0}%');
      case 'options' || 'confirm' || 'form' || 'submit':
        control ??= node.cast<String, Object?>();
      default:
        break;
    }
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        walk(child, depth + 1);
      }
    }
  }

  walk(view, 0);
  return (lines: lines, control: control);
}

class _BotViewCardState extends State<BotViewCard> {
  final Set<String> _picked = {};
  final Map<String, Object?> _choiceValues = {};
  final Map<String, TextEditingController> _fields = {};
  bool _sending = false;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _answer(String action, Map<String, Object?> values) async {
    if (_sending || !canRenderBotView(widget.view.view)) return;
    final choices = _viewChoices(widget.view.view);
    final answer = {
      ...values,
      if (choices.isNotEmpty)
        'inputs': {for (final choice in choices) choice['id'] as String: _choiceValues[choice['id']]},
    };
    setState(() => _sending = true);
    final ok = await widget.onAnswer(action, answer);
    if (mounted && !ok) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (!canRenderBotView(widget.view.view)) {
      return ChatCard(
        icon: AppIcons.panel,
        title: widget.view.title,
        titleMaxLines: 2,
        tone: ChatCardTone.ask,
        trailing: CardCloseKey(onTap: widget.onDismiss),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(ChatCard.inset, 4, ChatCard.inset, ChatCard.inset),
            child: FilledButton(
              key: const ValueKey('bot-view-open-web'),
              onPressed: widget.onOpenInWeb,
              child: Text(l10n.commonOpenInWeb, textAlign: TextAlign.center),
            ),
          ),
        ],
      );
    }
    final (:lines, :control) = readView(widget.view.view);
    final id = control?['id'] as String? ?? '';
    final choices = _viewChoices(widget.view.view);
    final children = <Widget>[
      for (final line in lines)
        Padding(
          padding: const EdgeInsets.fromLTRB(ChatCard.inset, 0, ChatCard.inset, 6),
          child: Text(line, style: theme.textTheme.bodyMedium),
        ),
    ];
    for (final choice in choices) {
      final choiceId = choice['id'] as String;
      final options = (choice['options'] as List).cast<Map>();
      _choiceValues.putIfAbsent(choiceId, () => choice['value'] ?? _viewChoiceValue(options.first));
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(ChatCard.inset, 4, ChatCard.inset, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(choice['label'] as String, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in options)
                    CapsuleChoiceChip(
                      label: option['label'] as String,
                      selected: _choiceValues[choiceId] == _viewChoiceValue(option),
                      onSelected: () {
                        if (_sending) return;
                        setState(() => _choiceValues[choiceId] = _viewChoiceValue(option));
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    switch (control?['type']) {
      case 'submit':
        children.add(
          _CardActions(
            children: [
              Flexible(
                child: FilledButton(
                  style: cardButton,
                  onPressed: _sending ? null : () => _answer(id, const {}),
                  child: Text(control!['label'] as String? ?? l10n.commonSend, textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        );
      case 'options':
        final multi = control!['multi'] == true;
        final options = [
          for (final o in (control['options'] as List?) ?? const [])
            if (o is Map && o['label'] is String) o['label'] as String,
        ];
        children
          ..add(
            Padding(
              padding: const EdgeInsets.fromLTRB(ChatCard.inset, 4, ChatCard.inset, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in options)
                    CapsuleChoiceChip(
                      label: label,
                      selected: _picked.contains(label),
                      onSelected: () {
                        if (_sending) return;
                        setState(() {
                          if (multi) {
                            _picked.contains(label) ? _picked.remove(label) : _picked.add(label);
                          } else {
                            _picked
                              ..clear()
                              ..add(label);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          )
          ..add(
            _CardActions(
              children: [
                FilledButton(
                  style: cardButton,
                  onPressed: _picked.isEmpty || _sending ? null : () => _answer(id, {'selected': _picked.toList()}),
                  child: Text(l10n.commonSend),
                ),
              ],
            ),
          );
      case 'confirm':
        children.add(
          _CardActions(
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _sending ? null : () => _answer(id, {'confirmed': false}),
                child: Text(control!['cancelLabel'] as String? ?? l10n.commonCancel),
              ),
              FilledButton(
                style: cardButton,
                onPressed: _sending ? null : () => _answer(id, {'confirmed': true}),
                child: Text(control['confirmLabel'] as String? ?? l10n.commonConfirm),
              ),
            ],
          ),
        );
      case 'form':
        final fields = [
          for (final f in (control!['fields'] as List?) ?? const [])
            if (f is Map && f['id'] is String) f.cast<String, Object?>(),
        ];
        for (final field in fields) {
          final controller = _fields.putIfAbsent(field['id']! as String, TextEditingController.new);
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(ChatCard.inset, 4, ChatCard.inset, 4),
              child: TextField(
                controller: controller,
                enabled: !_sending,
                decoration: InputDecoration(
                  labelText: field['label'] as String? ?? '',
                  hintText: field['placeholder'] as String?,
                  isDense: true,
                ),
              ),
            ),
          );
        }
        children.add(
          _CardActions(
            children: [
              FilledButton(
                style: cardButton,
                onPressed: _sending
                    ? null
                    : () => _answer(id, {
                        'fields': {for (final e in _fields.entries) e.key: e.value.text},
                      }),
                child: Text(control['submitLabel'] as String? ?? l10n.botsSubmit),
              ),
            ],
          ),
        );
      default:
        children.add(const SizedBox(height: ChatCard.inset - 6));
    }
    return ChatCard(
      icon: AppIcons.panel,
      title: widget.view.title,
      titleMaxLines: 2,
      tone: ChatCardTone.ask,
      trailing: CardCloseKey(onTap: widget.onDismiss),
      children: children,
    );
  }
}

class _CardActions extends StatelessWidget {
  const _CardActions({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(ChatCard.inset, 12, ChatCard.inset, ChatCard.inset),
    child: Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: children),
  );
}

/// A Bot that waits for its model before it greets.
class BotModelCard extends StatelessWidget {
  const BotModelCard({super.key, required this.name, required this.onPick});

  final String name;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => ChatCard(
    icon: AppIcons.model,
    title: context.l10n.botsChooseModelFor(name),
    tone: ChatCardTone.ask,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(ChatCard.inset, 0, ChatCard.inset, ChatCard.inset),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.botsModelGreeting,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
              ),
            ),
            FilledButton(onPressed: onPick, child: Text(context.l10n.botsChooseModel)),
          ],
        ),
      ),
    ],
  );
}

/// The ✕ at the end of a card's title row, the size of the title's icon so the
/// two line up.
class CardCloseKey extends StatelessWidget {
  const CardCloseKey({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.l10n.botsSkipAnswer,
    child: InkResponse(
      onTap: onTap,
      radius: 18,
      child: SizedBox.square(
        dimension: 20,
        child: Icon(AppIcons.close, size: 18, color: DshColors.of(context).textTertiary),
      ),
    ),
  );
}

/// The compact buttons at the foot of a card.
final cardButton = FilledButton.styleFrom(
  minimumSize: const Size(0, 36),
  padding: const EdgeInsets.symmetric(horizontal: 20),
  visualDensity: VisualDensity.compact,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// Reports its child's laid-out height, so the frame can leave exactly that
/// much room without asking for a frame's worth of delay: the value is written
/// after layout, and the next frame already uses it.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasured(onHeight);
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onHeight);

  final ValueChanged<double> onHeight;
  double _last = -1;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _last) return;
    _last = height;
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
