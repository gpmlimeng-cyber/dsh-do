// 群目标：群聊页顶栏那颗胶囊，点开在它下面展开整份计划。
//
// 这是 ds-bot 网页端那颗「目标胶囊」（src/client/goal.js）的移植：收起态是
// 群名胶囊尾端那颗同心圆球（环内写「3/4」，颜色随状态），完整模式与群名合成
// 一颗胶囊的两段；展开态胶囊铺满顶栏、其余按钮隐藏，下面长出面板。
//
// 数据来自 ds-bot 的 goal-view；面板里的行用 App 现成的列表行与按钮。

import 'dart:math' as math;

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import '../chat/chat_header.dart' show ChatHeader;
import '../chat/header_schedule.dart' show HeaderScheduleCap;
import '../chat/dock/dock_pill.dart';
import 'bot_avatar.dart';
import 'bot_chat_kit.dart';

/// 群的目标，随群消息和回合变化重新取一次。
final groupGoalProvider = FutureProvider.autoDispose.family<DsBotGroupGoal?, String>((ref, roomId) async {
  // 顶栏比连接先建好是常态，那一刻控制器还没有 api。这里等它，但用
  // onDispose 记住自己是否已被销毁：销毁后立刻收手，不再拿着空值静默结束。
  var disposed = false;
  ref.onDispose(() => disposed = true);
  ref.watch(dsBotProvider.select((s) => s.availability));
  for (var i = 0; i < 40; i++) {
    if (disposed) return null;
    final api = ref.read(dsBotProvider.notifier).api;
    if (api != null) {
      return (await api.goalView(roomId)).goal;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return null;
});

String? goalStateWord(L10n l10n, DsBotGroupGoal goal) => switch (goal.status) {
  'active' => l10n.chatGoalRunning,
  'paused' => l10n.chatGoalPaused,
  'drafting' => l10n.chatGoalHint,
  'complete' => l10n.commonCompleted,
  'stopped' => l10n.chatGoalStopped,
  _ => null,
};

Color goalStateColor(BuildContext context, DsBotGroupGoal goal) {
  final dsh = DshColors.of(context);
  final primary = Theme.of(context).colorScheme.primary;
  return switch (goal.status) {
    'complete' => dsh.success,
    'paused' || 'drafting' => dsh.warning,
    'stopped' => dsh.textTertiary,
    _ => goal.idle ? dsh.warning : primary,
  };
}

/// 当前段的任务都交了、等管理员判：环色更亮一档。
bool goalChecking(DsBotGroupGoal goal) {
  final stage = goal.stage;
  if (stage == null || stage.tasks.isEmpty) return false;
  return stage.tasks.every((task) => task.status == 'reported' || task.status == 'done');
}

/// 圆形进度环：已过的段数 / 总段数，环内写「3/4」。
class GoalRing extends StatelessWidget {
  const GoalRing({super.key, required this.goal, this.size = 30, this.onTap, this.announce = true});

  final DsBotGroupGoal goal;
  final double size;
  final VoidCallback? onTap;

  /// False where a visible title sits beside the ring: the screen reader reads
  /// the title once, from that text, not twice.
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = goalStateColor(context, goal);
    final total = goal.stages.isEmpty ? goal.stageCount : goal.stages.length;
    final passed = goal.stages.where((stage) => stage.passed).length;
    final fraction = total == 0 ? 0.0 : passed / total;
    final label = goal.status == 'drafting' ? '·' : '$passed/$total';
    final ring = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          fraction: fraction,
          tone: tone,
          track: tone.withValues(alpha: 0.18),
          stroke: size >= 36 ? 2.5 : 2,
        ),
        child: Center(
          child: Text(
            label,
            style: AppType.tabular(
              theme.textTheme.labelSmall!.copyWith(
                // 字号跟着环走（直径 ×0.3 取整）：24 → 8.5、30 与 32 → 10.5、
                // 36 → 11、40 → 12。
                fontSize: size >= 40
                    ? 12
                    : size >= 36
                    ? 11
                    : size >= 32
                    ? 10.5
                    : size <= 24
                    ? 8.5
                    : 9.5,
                height: 1,
                fontWeight: FontWeight.w700,
                color: tone,
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      label: announce ? goal.title : null,
      child: onTap == null ? ring : InkResponse(onTap: onTap, radius: size, child: ring),
    );
  }
}

/// 顶栏那颗「圆」本身：一颗环 + 暂停角标，没有第二层底。收起态的小球和展开
/// 态右段共用这一颗，所以收起 / 展开时是同一个圆，尺寸、内缩、描边都一样
/// （直径见 [GroupGoalPill._ballSize]，照标题胶囊尾端的时钟键）。
///
/// 目标达成后这颗换外观：36 圆盘 + 垃圾桶，写明「清除目标」。桶不染红——清除是
/// 正常收尾，不是危险操作；点它仍只开面板，真正清除在面板里。
Widget goalRingBall(BuildContext context, {required DsBotGroupGoal goal, required double size}) {
  final theme = Theme.of(context);
  final dsh = DshColors.of(context);
  if (goal.status == 'complete') {
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: const CircleBorder(),
      ),
      child: Icon(AppIcons.delete, size: 18, color: theme.colorScheme.onSurfaceVariant),
    );
  }
  return SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        GoalRing(goal: goal, size: size, announce: false),
        // 暂停角标 10，贴环左上外缘、不进环内：36 里 11 号的「2/4」已经占到
        // 环宽的三分之二。
        if (goal.status == 'paused')
          Positioned(left: -2, top: -2, child: Icon(AppIcons.paused, size: 10, color: dsh.warning)),
      ],
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.tone,
    required this.track,
    required this.stroke,
  });

  final double fraction;
  final Color tone;
  final Color track;

  /// 环宽：36 起 2.5（36 下 2 太细），面板里 24 / 30 / 32 那几颗仍是 2。
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 2.5) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    paint.color = track;
    canvas.drawCircle(center, radius, paint);
    if (fraction <= 0) return;
    paint.color = tone;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction || old.tone != tone || old.track != track;
}

/// 顶栏上的目标：两态由一次点击决定，不由设置决定。
///
/// - 小球（默认）：群名完整，右端一颗圆形按钮（环）。点它展开成胶囊。
/// - 完整胶囊：点开面板；窄屏时撑满一行（群名缩成圆头像由页面决定）。
///
/// 没有目标（后端没给、被清除、或回落成空标题）时什么都不画。
class GoalBarProbe extends ConsumerWidget {
  const GoalBarProbe({
    super.key,
    required this.roomId,
    this.expanded = false,
    this.onExpand,
    this.onCollapse,
    this.bare = false,
  });

  final String roomId;

  /// 并进群名那颗胶囊里：只画内容，不带玻璃底（外壳由顶栏给）。
  final bool bare;

  /// False: the ball. True: the full pill (the person tapped the ball).
  final bool expanded;

  /// 点小球。
  final VoidCallback? onExpand;

  /// 面板的「收起成小球」：面板自己关，页面把小球收回来。
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 连接一就绪就回头取一次：api 只存在于控制器上，不改变 status，所以
    // 光靠 watch 依赖等不到它。
    ref.listen(dsBotProvider.select((s) => s.team != null), (previous, next) {
      if (next && previous != true) ref.invalidate(groupGoalProvider(roomId));
    });
    final async = ref.watch(groupGoalProvider(roomId));
    // 重新拉取时（回合结束、新消息都会失效它）手里那份不算丢：先照上一份画，
    // 拉回来再换成新的。否则每来一条消息胶囊就缩成一个小转圈，再弹回去。
    final goal = async.value;
    if (goal != null && goal.title.isNotEmpty) {
      // 合体态：右段（旗帜 + 两行文字 + 环）并进那颗大胶囊。
      return bare && expanded
          ? GoalInlineSegment(
              goal: goal,
              onTap: () => showGoalExpand(context, roomId),
              onLongPress: onCollapse,
            )
          : GroupGoalPill(
              goal: goal,
              expanded: expanded,
              // 收成小球且并进群名胶囊时，只画那颗同心球（外壳由顶栏给）。
              bare: bare && !expanded,
              // 点它只开面板——展开态与收起态点下去是同一件事：清除也只发生
              // 在面板里（这颗球刚才还是「开面板」，换个不可逆动作最危险）。
              onTap: () => showGoalExpand(context, roomId),
              // 长按：展开态收成小球、收起态展回胶囊；手动改过的以手动为准。
              onLongPress: expanded ? onCollapse : onExpand,
            );
    }
    // 一次都还没读到：占位照那颗球的大小，目标读到后不跳。
    // 没有目标：不占位（原来那颗灰点与它的调试 SnackBar 已删掉）。
    if (!async.isLoading) return const SizedBox.shrink();
    return SizedBox.square(
      dimension: bare ? GroupGoalPill._ballSize : 30,
      child: const Center(
        child: SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 1.6)),
      ),
    );
  }
}

/// 胶囊第二行：网页 `goalView` 的 `barLabel`，逐条照抄
/// （`ds-bot/src/client/goal.js:42`）。只拆成两段是为了整段省略，拼起来就是
/// 网页那一行。
///
/// 网页的 `current` 只在进行中 / 暂停时有：其余状态就算 `current` 还指在
/// 某一段上，也不再说是「当前阶段」。
({String head, String tail}) goalDynamicLine(L10n l10n, DsBotGroupGoal goal) {
  final current = goal.status == 'active' || goal.status == 'paused' ? goal.stage : null;
  final title = current?.title ?? '';
  if (goal.status == 'drafting') return (head: l10n.chatGoalAligning, tail: '');
  if (goal.status == 'stopped') return (head: l10n.chatGoalStopped, tail: '');
  if (goal.status == 'complete') return (head: l10n.chatGoalReached, tail: '');
  if (goal.status == 'paused') return (head: l10n.chatGoalPaused, tail: title);
  if (goal.idle) return (head: l10n.chatGoalIdleWord, tail: title);
  if (current == null) return (head: l10n.chatGoalFinalCheck, tail: '');
  // 这一段的任务都交了，就是在验收；空任务列表在网页里也算「都交了」。
  final checking = current.tasks.every((task) => task.status == 'reported' || task.status == 'done');
  // 网页这条带阶段名：「验收中 · {title}」，这里整句放进 head、tail 留空。
  if (checking) return (head: l10n.chatGoalChecking(title), tail: '');
  return (head: title, tail: '');
}

/// 下行按「·」分段省略：前缀整段保留，后缀放不下就整段换成「…」；后缀为空时
/// 连「 · 」一起去掉。返回的是拼好的成品，调用处不再自己拼，也不再用字符级
/// `TextOverflow.ellipsis`。
String splitForPill({
  required String head,
  required String tail,
  required double maxWidth,
  required TextStyle style,
  required TextScaler scaler,
}) {
  final cleanTail = tail.trim();
  if (cleanTail.isEmpty) return head;
  final full = '$head · $cleanTail';
  bool fits(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return painter.width <= maxWidth;
  }

  if (fits(full)) return full;
  return '$head · …';
}

/// 目标胶囊的高度：严格等于群名那颗标题胶囊——直接用同一份公式
///（[ChatHeader.pillHeightOf]），不再自己算一套。两行文字、32 的环都放得下，
/// 不许为了塞文字把它撑回去；字放大时也跟着同一个公式长。
double pillHeightOf(BuildContext context) => ChatHeader.pillHeightOf(context);

/// 合体胶囊的右段：第一行旗帜 + 目标标题，第二行动态，右端进度环；自己带
/// 右圆角的水波，点它开面板、长按收成小球。外壳由顶栏那颗胶囊给。
///
/// 任何宽度都保留两行（两行在高度上一直装得下，隐掉动态行不腾宽只丢信息），
/// 两段之间也不画分隔线：左段头像、右段目标紧贴，靠各自的点击区与水波分开。
class GoalInlineSegment extends StatelessWidget {
  const GoalInlineSegment({
    super.key,
    required this.goal,
    required this.onTap,
    this.onLongPress,
  });

  final DsBotGroupGoal goal;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final height = pillHeightOf(context);
    final radius = BorderRadius.horizontal(right: Radius.circular(height / 2));
    // 环 = 收起态那颗球（36，与胶囊右端半圆同心同径）；内缩 4 见下面的
    // 右内边，和球在胶囊里的位置一致。
    final ringSize = GroupGoalPill._ballSize;
    final paused = goal.status == 'paused';
    // 没有分隔线：这一段自己就是一个点击区（右圆角裁水波），左段头像那颗
    // 仍是另一个点击区，两段各管各的。
    Widget segment({required Widget child}) => Semantics(
      // 独立节点：读屏能单独点到「目标」这一段，与左段那颗群详情分开。
      container: true,
      button: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        customBorder: RoundedRectangleBorder(borderRadius: radius),
        child: child,
      ),
    );

    final l10n = context.l10n;
    // 竖排两行、左对齐：行 1 = 旗帜 + 标题，行 2 = 圆点 + 动态。行 2 的起点
    // 对齐标题的左边缘（不是对齐旗帜，也不居中）。
    const flagSize = 14.0;
    const flagGap = 4.0;
    const dotSize = 6.0;
    const dotGap = 5.0;
    const lineGap = 2.0;
    // 行 2 的缩进：旗帜 + 间距，圆点正好在标题左边缘下面。
    const secondIndent = flagSize + flagGap;
    final passed = goal.stages.where((stage) => stage.passed).length;
    final total = goal.stages.isEmpty ? goal.stageCount : goal.stages.length;
    final flag = Icon(
      paused
          ? AppIcons.paused
          : goal.status == 'complete'
          ? AppIcons.success
          : AppIcons.goal,
      size: flagSize,
      color: paused
          ? dsh.warning
          : goal.status == 'complete'
          ? dsh.success
          : dsh.textTertiary,
    );
    final line = goalDynamicLine(l10n, goal);
    // 达成后进度不丢：环换成了清除按钮，所以把「4/4」挪到第二行来写。
    final secondLine = goal.status == 'complete' && total > 0
        ? '${l10n.chatGoalReached} · $passed/$total'
        : null;
    return segment(
      child: Padding(
        // 右内边 = 环的内缩（(胶囊高 − 环直径) / 2 = 4），环才和胶囊右端那颗
        // 半圆同心，读作一个圆。
        padding: EdgeInsets.only(right: HeaderScheduleCap.insetFor(height)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final second = theme.textTheme.labelSmall!.copyWith(
              fontSize: 10.5,
              height: 1.3,
              color: dsh.textTertiary,
            );
            // 文字块：左 6 / 右 12（UI 的内边），右边再留 6 给环。
            final textWidth =
                constraints.maxWidth - 6 - 12 - 6 - ringSize;
            final text = secondLine ?? splitForPill(
              head: line.head,
              tail: line.tail,
              maxWidth: math.max(0.0, textWidth - secondIndent - dotSize - dotGap),
              style: second,
              scaler: MediaQuery.textScalerOf(context),
            );
            return Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6, right: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            flag,
                            const SizedBox(width: flagGap),
                            Expanded(
                              child: Text(
                                goal.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontSize: 12.5,
                                  height: 1.2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (text.isNotEmpty && text != goal.title) ...[
                          const SizedBox(height: lineGap),
                          Padding(
                            padding: const EdgeInsets.only(left: secondIndent),
                            child: Row(
                              children: [
                                // 圆点不进读屏：第二行文字本身已经说清状态。
                                ExcludeSemantics(
                                  child: _GoalPulseDot(
                                    color: goalStateColor(context, goal),
                                    alive: goal.status == 'active',
                                    size: dotSize,
                                  ),
                                ),
                                const SizedBox(width: dotGap),
                                Expanded(
                                  child: Text(
                                    text,
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: second,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                goalRingBall(context, goal: goal, size: ringSize),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 第二行最左那颗圆点：进行中呼吸（透明度 0.3→1、缩放 0.85→1.05，1.6 秒
/// 来回、ease-in-out），其余状态静止。系统要求减少动画、或「灵动动效」关着时
/// 一律静止在 1.0——这时候还在呼吸，等于骗用户说它还在跑。
class _GoalPulseDot extends StatefulWidget {
  const _GoalPulseDot({required this.color, required this.alive, required this.size});

  final Color color;
  final bool alive;
  final double size;

  @override
  State<_GoalPulseDot> createState() => _GoalPulseDotState();
}

class _GoalPulseDotState extends State<_GoalPulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  // 不在 initState 里碰 context 的继承依赖，交给 didChangeDependencies。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_GoalPulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// 呼吸只在「进行中 + 允许动效」时跑。
  void _sync() {
    final run = widget.alive && AppMotion.fluid(context);
    if (run && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!run && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = DecoratedBox(
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      child: SizedBox.square(dimension: widget.size),
    );
    if (!widget.alive || !AppMotion.fluid(context)) return dot;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: 0.3 + 0.7 * _t.value,
        child: Transform.scale(scale: 0.85 + 0.2 * _t.value, child: child),
      ),
      child: dot,
    );
  }
}

/// 胶囊第二行前面那颗：网页 `.bt-goal-dot` 的 8px 圆点，完成后换成
/// `.bt-goal-check` 的 14px 勾。颜色照 CSS：进行中绿、起草强调色、暂停与等你
/// 是星色、已停止 ink-3。
class _GoalBarMark extends StatelessWidget {
  const _GoalBarMark({required this.goal});

  final DsBotGroupGoal goal;

  static const double _dot = 8;
  static const double _check = 14;

  /// 这一格占多宽，调用处按它扣掉文字可用宽度。
  double get width => goal.status == 'complete' ? _check : _dot;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    if (goal.status == 'complete') {
      return Icon(AppIcons.done, size: _check, color: dsh.success);
    }
    final color = switch (goal.status) {
      'drafting' => Theme.of(context).colorScheme.primary,
      'stopped' => dsh.textTertiary,
      'paused' => dsh.warning,
      _ when goal.idle => dsh.warning,
      _ => dsh.success,
    };
    return Container(
      width: _dot,
      height: _dot,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// 胶囊那第二行：状态点 + 「状态 · 阶段/进度」。胶囊与面板顶部共用这一份数据
/// 与同一套整段省略规则，不再各写一套。
class _GoalBarLine extends StatelessWidget {
  const _GoalBarLine({required this.goal, required this.style, required this.maxWidth, this.topGap = 0});

  final DsBotGroupGoal goal;
  final TextStyle style;
  final double maxWidth;

  /// 上面留几像素：胶囊里第二行跟标题之间要 2，面板里单独一行不要。
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final mark = _GoalBarMark(goal: goal);
    final line = goalDynamicLine(context.l10n, goal);
    final text = splitForPill(
      head: line.head,
      tail: line.tail,
      maxWidth: math.max(0, maxWidth - mark.width - 6),
      style: style,
      scaler: MediaQuery.textScalerOf(context),
    );
    // 两行同字就不写第二遍。
    if (text == goal.title) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(width: 6),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.clip, style: style)),
        ],
      ),
    );
  }
}

/// 面板顶部那份第二行：浮卡把胶囊整颗盖住了，这一行就在面板里接着显示，
/// 内容与省略规则跟胶囊那行完全一样。
class _GoalPanelSecondLine extends StatelessWidget {
  const _GoalPanelSecondLine({required this.goal});

  final DsBotGroupGoal goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.centerLeft,
          child: _GoalBarLine(
            goal: goal,
            maxWidth: constraints.maxWidth,
            style: theme.textTheme.labelSmall!.copyWith(
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w400,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏那颗：小球（环）或完整胶囊（图标 + 标题 + 环）。
///
/// 高度严格等于群名那颗标题胶囊（同一个公式），玻璃底与按下态由 GlassSurface
/// 给。读屏只念一遍标题。
class GroupGoalPill extends StatelessWidget {
  const GroupGoalPill({
    super.key,
    required this.goal,
    required this.onTap,
    this.onLongPress,
    this.expanded = false,
    this.expandArrow = false,
    this.bare = false,
  });

  final DsBotGroupGoal goal;
  final VoidCallback onTap;

  /// 完整胶囊长按收成小球；小球长按无动作（点它就展开）。
  final VoidCallback? onLongPress;

  /// False: the ball. True: the full pill.
  final bool expanded;

  /// 展开面板的头部那颗多一个收起箭头。
  final bool expandArrow;

  /// 收成小球时并进群名那颗胶囊的尾端：只画球本身（同心圆井 + 环），
  /// 不带玻璃底，球自己吃点击。几何由顶栏给（36、间距 8、内缩）。
  final bool bare;

  /// 进度环的尺寸：单独站着的那颗小球与完整胶囊共用这一个值。
  static const double _ringSize = 32;

  /// 那颗球的直径 = 环的直径：收起态和展开态右段是同一颗 36 的环，收 / 展时
  /// 大小不变、不跳。尺寸照标题胶囊尾端的时钟键（[HeaderScheduleCap.size]）。
  /// 两处都读这一个常量，别再各写一套。
  static const double _ballSize = HeaderScheduleCap.size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final paused = goal.status == 'paused';
    // 完整胶囊和小球用同一颗环：换形态时环不应该变小。并进胶囊的球更小一层，
    // 跟合体段那颗 24 走，收起 / 展开时环本身不变。
    final ring = GoalRing(goal: goal, size: _ringSize, announce: false);
    // 暂停了就写在前面：小球放不下文字，角标就是那颗暂停。
    Widget? pauseBadge(double size) => paused
        ? Positioned(
            left: 2,
            top: 2,
            child: Icon(AppIcons.paused, size: size, color: dsh.warning),
          )
        : null;
    if (bare) {
      // 挂在一颗胶囊的尾端：位置与几何照标题胶囊尾端的时钟键，里面的球是
      // 我们自己的——环 + 暂停角标，底子用目标自己的状态色淡淡一层，不是
      // 时钟那口中性灰井。
      return Semantics(
        // container + onTap：折在群名胶囊里的这颗球要自己成一个可点的节点，
        // 否则读屏里它会跟左段那颗「查看详情」并成同一个按钮（点不到）。
        container: true,
        button: true,
        // 达成后这颗是「清除目标」的入口，读屏也照这个念。
        label: goal.status == 'complete' ? context.l10n.chatClearGoal : goal.title,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: goalRingBall(context, goal: goal, size: _ballSize),
          ),
        ),
      );
    }
    if (!expanded) {
      return Semantics(
        button: true,
        label: goal.title,
        excludeSemantics: true,
        child: SizedBox.square(
          // 小球也照群名那颗的高度，换形态时不吃掉一行的高度。
          dimension: pillHeightOf(context),
          child: GlassSurface(
            tier: GlassTier.chrome,
            circle: true,
            grouped: true,
            onTap: onTap,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [ring, ?pauseBadge(13)],
            ),
          ),
        ),
      );
    }
    // 文字列：上行目标，下行当前动态。宽度由外层给——撑满时吃满余量，定宽时
    // 只占内容宽。
    final text = LayoutBuilder(
      builder: (context, constraints) {
        // 网页 `.bt-goal-bar`：12 / 行高 16、ink-2，前面一颗 8px 状态点；
        // 完成后那颗点换成 14 的勾。
        final small = theme.textTheme.labelSmall!.copyWith(
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w400,
          color: theme.colorScheme.onSurfaceVariant,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              goal.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
            _GoalBarLine(goal: goal, style: small, maxWidth: constraints.maxWidth, topGap: 2),
          ],
        );
      },
    );
    return Semantics(
      button: true,
      label: goal.title,
      excludeSemantics: true,
      child: SizedBox(
        height: pillHeightOf(context),
        // Tooltip 在 GlassSurface 外面：它在触屏上默认用长按出现，套在里面会
        // 抢走长按（更靠近手指），胶囊就永远收不成小球。放外面后 InkWell 更
        // 深，长按归它，桌面悬停提示照旧。
        child: Tooltip(
          message: goal.title,
          child: GlassSurface(
            tier: GlassTier.chrome,
            stadium: true,
            grouped: true,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 撑满一行时（窄屏）文字列吃满余量，环因此贴住右内边；定宽
                  // 时（宽屏）不参与弹性分配，胶囊就按内容宽站住。
                  final fill = constraints.hasBoundedWidth;
                  return Row(
                    mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
                    children: [
                      // 暂停时前面那颗换成暂停，和目标状态的读法一致。
                      if (paused)
                        Icon(AppIcons.paused, size: 18, color: dsh.warning)
                      else
                        Icon(
                          goal.status == 'complete' ? AppIcons.success : AppIcons.goal,
                          size: 18,
                          color: goal.status == 'complete' ? dsh.success : dsh.textTertiary,
                        ),
                      const SizedBox(width: 6),
                      if (fill) Expanded(child: text) else Flexible(child: text),
                      const SizedBox(width: 8),
                      ring,
                      if (expandArrow) ...[
                        const SizedBox(width: 2),
                        Icon(AppIcons.collapse, size: 16, color: dsh.textTertiary),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 展开后的面板：阶段圆点、选中这一段、目标与验收、底部按钮。顶栏下浮层用。
class GoalPanel extends ConsumerStatefulWidget {
  const GoalPanel({
    super.key,
    required this.goal,
    required this.roomId,
    required this.onClose,
  });

  final DsBotGroupGoal goal;
  final String roomId;
  final VoidCallback onClose;

  /// False when the actions live in the card's own header (the floating card)。

  @override
  ConsumerState<GoalPanel> createState() => _GoalPanelState();
}

class _GoalPanelState extends ConsumerState<GoalPanel> {
  int? _selected;

  DsBotGroupGoal get _goal => widget.goal;

  int get _at => _goal.status == 'active' || _goal.status == 'paused' ? _goal.current : -1;

  int get _viewing => _selected ?? _at;

  DsBotGoalStage? get _stage {
    final at = _viewing;
    if (at < 0 || at >= _goal.stages.length) return null;
    return _goal.stages[at];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final goal = _goal;
    final stage = _stage;
    final at = _at;
    final small = theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary);
    final controlStyle = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: theme.textTheme.labelMedium,
    );
    // 「连当前工作一起停」 only means something while the goal is paused and a
    // member is still running.
    final room = ref.watch(dsBotProvider.select((s) => s.team?.room(widget.roomId)));
    final admin = room == null ? l10n.botsABot : (ref.read(dsBotProvider).team?.bot(room.admin ?? '')?.name ?? l10n.botsABot);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 网页端只按状态判（`goal.js:183`）：起草态不画，其余哪怕只有一段也画。
        if (goal.status != 'drafting')
          _StageStrip(
            stages: goal.stages,
            at: at,
            viewing: _viewing,
            onSelect: (index) => setState(() => _selected = index),
          ),
        // 起草态：标题在头部，正文先放 brief（与标题同值时不重复），再补一句
        // 状态——整块空着会被当成没加载出来。
        if (goal.status == 'drafting') ...[
          if (goal.brief.trim().isNotEmpty && goal.brief.trim() != goal.title.trim()) ...[
            Text(goal.brief, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
          ],
          Text(l10n.chatGoalDrafting, style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary)),
        ] else if (stage == null) ...[
          if (goal.summary.isNotEmpty) Text(goal.summary, style: theme.textTheme.bodyMedium),
          if (goal.evidence.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(goal.evidence, style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary)),
          ],
          if (goal.status == 'stopped' && goal.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(goal.reason, style: theme.textTheme.bodySmall?.copyWith(color: dsh.warning)),
          ],
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Text(stage.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (stage.passed)
                Text(l10n.commonCompleted, style: theme.textTheme.labelSmall?.copyWith(color: dsh.success))
              else if (_viewing == at)
                Text(l10n.chatGoalStageCurrent, style: small),
              if (_viewing != at && at >= 0)
                TextButton(
                  onPressed: () => setState(() => _selected = at),
                  style: controlStyle,
                  child: Text(l10n.botsGoalBackToCurrent),
                ),
            ],
          ),
          if (stage.acceptance.isNotEmpty) ...[
            const SizedBox(height: 6),
            // 和「证据」「打回重做」同一档：次级字号与颜色（网页 `.bt-goal-line`）。
            Text(
              l10n.chatGoalDoneWhen(stage.acceptance),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (_viewing == at && stage.reworks > 0 && stage.feedback.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              stage.reworks > 1
                  ? l10n.chatGoalReworkByTimes(stage.reworks, admin, stage.feedback)
                  : l10n.chatGoalReworkBy(admin, stage.feedback),
              style: theme.textTheme.bodySmall?.copyWith(color: dsh.warning),
            ),
          ],
          if (stage.evidence.isNotEmpty && stage.passed) ...[
            const SizedBox(height: 6),
            Text(
              '${l10n.chatGoalEvidence}：${stage.evidence}',
              style: theme.textTheme.bodySmall?.copyWith(color: dsh.success),
            ),
          ],
          if (stage.tasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(l10n.chatGoalTasks, style: small),
            const SizedBox(height: 2),
            for (final task in stage.tasks) _GoalTaskRow(task: task, roomId: widget.roomId),
          ],
        ],
        // 「连当前工作一起停」与折叠栏一样在卡片的固定区，不随正文滚动。
      ],
    );
  }
}

/// 卡片底部的固定折叠栏：「目标与验收」（浅色，图标在小字前面，整行可点），
/// 右侧可挂一颗动作（「同时停止当前工作」）。它不在正文的滚动区里，滚正文时
/// 这一行不走；展开的三块在它上方、正文之后，自己一块滚动区。
class GoalChecksBar extends StatelessWidget {
  const GoalChecksBar({
    super.key,
    required this.goal,
    required this.open,
    required this.onToggle,
    this.trailing,
  });

  final DsBotGroupGoal goal;
  final bool open;
  final VoidCallback onToggle;

  /// 这一行最右那颗：「同时停止当前工作」（网页端在底栏的 facts 区）。
  final Widget? trailing;

  /// 有没有可展开的东西：目标 / 验收方法 / 规则，一样都没有就不出这一行，
  /// 也不出它下面的内容。
  static bool has(DsBotGroupGoal goal) =>
      goal.objective.isNotEmpty || goal.acceptance.isNotEmpty || goal.constraints.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    // 这一行左边是可折叠的「目标与验收」，右边是页面挂过来的那颗（同时停止
    // 当前工作）；两个都没有就不占位。
    final toggle = has(goal)
        ? Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onToggle,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                // 网页端这一行是浅色（`.bt-goal-checks` 用 ink-2），不是正文色。
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                textStyle: theme.textTheme.labelMedium?.copyWith(fontSize: 14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: AppMotion.of(context, AppMotion.standard),
                    child: Icon(AppIcons.collapse, size: 14, color: dsh.textTertiary),
                  ),
                  const SizedBox(width: 6),
                  Text(l10n.chatGoalPanel),
                ],
              ),
            ),
          )
        : null;
    if (toggle == null && trailing == null) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(child: toggle ?? const SizedBox.shrink()),
        if (trailing case final trailing?)
          Padding(padding: const EdgeInsets.only(right: 8), child: trailing),
      ],
    );
  }
}

/// 展开的三块：目标 / 验收方法 / 规则。在折叠行上方、正文之后（网页端
/// `bt-goal-ckbody` 在 `bt-goal-foot` 之前），自己一块滚动区。
class GoalChecksBody extends StatelessWidget {
  const GoalChecksBody({super.key, required this.goal});

  final DsBotGroupGoal goal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (goal.objective.isNotEmpty) _Block(label: l10n.chatGoal, value: goal.objective),
        if (goal.acceptance.isNotEmpty) _Block(label: l10n.chatGoalAcceptanceDone, value: goal.acceptance),
        for (final rule in goal.constraints) _Block(label: l10n.chatGoalRule, value: rule),
      ],
    );
  }
}

/// 一句话标签加一段值：验收展开里的三块都用它。
class _Block extends StatelessWidget {
  const _Block({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary)),
          const SizedBox(height: 1),
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 顶部一排阶段圆点：已过的显示勾，当前的高亮，点一颗切换看那段。
class _StageStrip extends StatelessWidget {
  const _StageStrip({required this.stages, required this.at, required this.viewing, required this.onSelect});

  final List<DsBotGoalStage> stages;
  final int at;
  final int viewing;
  final ValueChanged<int> onSelect;

  /// 两节点之间的空档（含连接线）：原来 5 太挤，线也画不下。
  static const _gap = 28.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final primary = theme.colorScheme.primary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          for (final (index, stage) in stages.indexed) ...[
            // 两端不留线：只连两个节点之间。
            if (index > 0)
              SizedBox(
                width: _gap,
                height: 26,
                child: Center(
                  child: SizedBox(
                    width: _gap,
                    height: 1.5,
                    child: ColoredBox(
                      color: stages[index - 1].passed ? dsh.success : dsh.textTertiary.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
            InkWell(
              onTap: () => onSelect(index),
              customBorder: const StadiumBorder(),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: stage.passed
                      ? dsh.success.withValues(alpha: 0.16)
                      : index == viewing
                      ? primary.withValues(alpha: 0.16)
                      : dsh.textTertiary.withValues(alpha: 0.08),
                  border: index == viewing ? Border.all(color: primary, width: 1.2) : null,
                ),
                child: stage.passed
                    ? Icon(AppIcons.success, size: 14, color: dsh.success)
                    : Text(
                        '${index + 1}',
                        style: AppType.tabular(
                          theme.textTheme.labelSmall!.copyWith(
                            fontSize: 12,
                            color: index == viewing ? primary : dsh.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 这一段里的一个成员任务：头像（状态长在头像上）、名字与这件事接在一段文字
/// 里，按行宽自然折行。网页的 `TaskRow` 就是这么画的（`goal.js:135`）。
class _GoalTaskRow extends ConsumerWidget {
  const _GoalTaskRow({required this.task, required this.roomId});

  final DsBotGoalTask task;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // 名字取团队里的当前名字：Host 给的 task.bot 是发任务时的快照，改名后
    // 那一份就旧了。
    final team = ref.watch(dsBotProvider.select((s) => s.team));
    final bot = team?.bot(task.botId);
    final name = bot?.name ?? (task.bot.isEmpty ? task.botId : task.bot);
    // 这个群里已经在跑也算「在做」：网页把 roomWork 和任务状态一起判。
    final live = ref.watch(
      dsBotProvider.select(
        (s) => (s.live.rooms[roomId] ?? const <DsBotWork>[]).any((work) => work.botId == task.botId),
      ),
    );
    final returned = task.status == 'reported' || task.status == 'done';
    return Opacity(
      // 待办整行压到 55%：还没轮到它，读得出但不抢眼。
      opacity: task.status == 'pending' ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.square(
              dimension: 20,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: bot == null
                        ? CircleAvatar(
                            radius: 10,
                            child: Text(
                              name.isEmpty ? '?' : name.substring(0, 1),
                              style: theme.textTheme.labelSmall,
                            ),
                          )
                        : BotAvatar(bot: bot, size: 20, working: live || task.status == 'working'),
                  ),
                  if (returned) const Positioned(right: -2, bottom: -2, child: _TaskDoneMark()),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: name,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        // 群聊消息、@提及用的是同一套名字颜色。
                        color: bot == null ? theme.colorScheme.onSurface : botNameInk(context, bot.ink),
                      ),
                    ),
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: task.task,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 已报 / 已完成那颗角标：12 的绿圆、9 的勾，外圈 1.5 的卡片底色（网页
/// `.bt-goal-tdone`）。
class _TaskDoneMark extends StatelessWidget {
  const _TaskDoneMark();

  @override
  Widget build(BuildContext context) {
    final ring = DshSurfaces.of(context).backdropTop;
    return Container(
      width: 12,
      height: 12,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DshColors.of(context).success,
        boxShadow: [BoxShadow(color: ring, spreadRadius: 1.5)],
      ),
      child: Icon(AppIcons.done, size: 9, color: ring),
    );
  }
}

/// 起草：写一句这个群要达成什么，交给管理员去对齐、再写成目标。
Future<void> showGoalCompose(BuildContext context, String roomId) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _GoalComposeSheet(roomId: roomId),
);

class _GoalComposeSheet extends ConsumerStatefulWidget {
  const _GoalComposeSheet({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_GoalComposeSheet> createState() => _GoalComposeSheetState();
}

class _GoalComposeSheetState extends ConsumerState<_GoalComposeSheet> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    final api = ref.read(dsBotProvider.notifier).api;
    if (api == null) return;
    setState(() => _sending = true);
    try {
      await api.goalDraft(widget.roomId, text);
      ref.invalidate(groupGoalProvider(widget.roomId));
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.chatGoal, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: l10n.chatGoalHint,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.chatGoalHint,
              style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(l10n.commonCancel)),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: Text(l10n.commonSend),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 从顶栏胶囊展开：顶栏铺满成目标本身，下面长出面板，其余内容被遮住。
/// 收起（箭头 / 点遮罩 / 返回键）就散了，原顶栏原样回来。
Future<void> showGoalExpand(BuildContext context, String roomId) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // 浮窗式卡片：靠边距和投影把内容让开，不铺遮罩。
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, _) => _GoalExpandLayer(roomId: roomId),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      ),
      child: FadeTransition(opacity: animation, child: child),
    ),
  );
  // The panel was looked at, not typed in: closing it must not hand the focus
  // (and the keyboard) back to the composer.
  FocusManager.instance.primaryFocus?.unfocus();
}

class _GoalExpandLayer extends ConsumerStatefulWidget {
  const _GoalExpandLayer({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_GoalExpandLayer> createState() => _GoalExpandLayerState();
}

class _GoalExpandLayerState extends ConsumerState<_GoalExpandLayer> {
  /// 停止的第一段：标题区让位给「确认终止？」，三个键不动、不推挤。
  final _confirming = ValueNotifier<bool>(false);

  bool _stopWorkBusy = false;

  /// 「目标与验收」展开着没有：内容在滚动区末尾，栏在固定区。
  bool _checks = false;

  @override
  void initState() {
    super.initState();
    // 打开面板先拉一次：后台或别处改过状态时，顶部那颗按钮不该拿旧值。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(groupGoalProvider(widget.roomId));
    });
  }

  /// 已暂停、但还有人在跑：只停工作，目标保持暂停（网页端这颗走
  /// stop-room-work，不是 goal-control）。
  Future<void> _stopWork() async {
    if (_stopWorkBusy) return;
    final api = ref.read(dsBotProvider.notifier).api;
    if (api == null) return;
    setState(() => _stopWorkBusy = true);
    try {
      await api.stopRoomWork(widget.roomId);
      ref.invalidate(groupGoalProvider(widget.roomId));
    } catch (error) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _stopWorkBusy = false);
    }
  }

  @override
  void dispose() {
    _confirming.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomId = widget.roomId;
    final goal = ref.watch(groupGoalProvider(roomId)).value;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final screenHeight = MediaQuery.sizeOf(context).height;
    // 展开「目标与验收」时卡片整体长高（内容在折叠行上方），平时维持 62%。
    final maxHeight = screenHeight * (_checks ? 0.86 : 0.62);
    // 胶囊顶边：顶栏在状态栏下起算、高 barHeightOf，胶囊在栏里垂直居中、高
    // pillHeightOf。卡片从这条线起，整颗胶囊才盖得住（原来固定 +6，胶囊比它
    // 高，顶上漏一截）。
    final pillTop = top + math.max(0.0, (BotChatHeader.barHeightOf(context) - pillHeightOf(context)) / 2);
    final working = ref.watch(
      dsBotProvider.select((s) => (s.live.rooms[widget.roomId] ?? const <DsBotWork>[]).isNotEmpty),
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 浮窗的规矩：卡片浮在内容上，不铺遮罩；点卡外收起。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              // 左右 12、圆角 24、头部 48 照手机控制的浮窗卡；顶边与胶囊顶边
              // 齐平，再往上 1 像素，两张圆角交界处也不漏。
              padding: EdgeInsets.fromLTRB(12, pillTop - 1, 12, 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: GlassSurface(
                  tier: GlassTier.chrome,
                  borderRadius: BorderRadius.circular(24),
                  child: goal == null
                      ? const SizedBox(height: 48)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 48,
                              child: Row(
                                children: [
                                  const SizedBox(width: 14),
                                  Icon(AppIcons.goal, size: 18, color: dsh.textTertiary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ValueListenableBuilder<bool>(
                                      valueListenable: _confirming,
                                      builder: (context, confirming, _) => Text(
                                        confirming ? l10n.chatGoalConfirmStop : goal.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: confirming ? theme.colorScheme.error : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 顶部是唯一动作区：暂停/停止（完成或停止后是
                                  // 清除）→ 收起圆盘，圆盘最右；三个 48 触控紧排，
                                  // 圆盘与动作之间不再加间距（靠 48 与 36 的差）。
                                  _GoalHeaderActions(roomId: roomId, goal: goal, confirming: _confirming),
                                  const SizedBox(width: 4),
                                  // 只关面板，不改胶囊形态：收起成小球是长按胶囊。
                                  _goalDisc(
                                    context,
                                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                                    icon: AppIcons.collapse,
                                    iconSize: 18,
                                    color: dsh.textTertiary,
                                    onTap: () => Navigator.of(context).maybePop(),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            // 浮卡把胶囊整颗盖住了，胶囊那第二行就在面板里接着
                            // 显示：同一份数据、同一套省略规则。
                            _GoalPanelSecondLine(goal: goal),
                            // 展开的三块跟正文同一条滚动：折叠行仍固定在底部。
                            Flexible(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GoalPanel(
                                      goal: goal,
                                      roomId: roomId,
                                      onClose: () => Navigator.of(context).maybePop(),
                                    ),
                                    if (_checks && GoalChecksBar.has(goal)) ...[
                                      const SizedBox(height: 10),
                                      GoalChecksBody(goal: goal),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            // 固定栏：滚正文时这一行不走。右侧那颗照网页端只放
                            // 「同时停止当前工作」：暂停且群里有人在跑才有。
                            const Divider(height: 1),
                            GoalChecksBar(
                              goal: goal,
                              open: _checks,
                              onToggle: () => setState(() => _checks = !_checks),
                              trailing: goal.status == 'paused' && working
                                  ? TextButton(
                                      onPressed: _stopWorkBusy ? null : _stopWork,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        visualDensity: VisualDensity.compact,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        textStyle: theme.textTheme.labelSmall?.copyWith(fontSize: 12),
                                      ),
                                      child: Text(l10n.chatStopWorkToo),
                                    )
                                  : null,
                            ),
                          ],
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

/// 浮窗那颗圆键：48 触控、36 圆盘、tonal 底。抽屉、⋯、收起成小球与卡片里的
/// 暂停/停止都是这一套。
Widget _goalDisc(
  BuildContext context, {
  required String tooltip,
  required IconData icon,
  required Color color,
  required VoidCallback? onTap,
  Color? background,
  double iconSize = 20,
}) {
  final theme = Theme.of(context);
  final tonal = background ?? theme.colorScheme.surfaceContainerHighest;
  return SizedBox.square(
    dimension: 48,
    child: Center(
      child: Material(
        color: tonal,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(
            message: tooltip,
            child: SizedBox.square(dimension: 36, child: Icon(icon, size: iconSize, color: color)),
          ),
        ),
      ),
    ),
  );
}

/// 卡片头部的两颗：暂停/恢复、停止。停止两段式，3 秒内再点才执行。
class _GoalHeaderActions extends ConsumerStatefulWidget {
  const _GoalHeaderActions({required this.roomId, required this.goal, this.confirming});

  final String roomId;
  final DsBotGroupGoal goal;

  /// 停止的第一段：让标题区显示「确认终止？」三秒。
  final ValueNotifier<bool>? confirming;

  @override
  ConsumerState<_GoalHeaderActions> createState() => _GoalHeaderActionsState();
}

class _GoalHeaderActionsState extends ConsumerState<_GoalHeaderActions> {
  bool _busy = false;
  bool _armed = false;

  /// 刚成功的那一步的本地状态：先让胶囊和这颗按钮立刻对上，随后拉回来的
  /// Host 那份再校正它（[didUpdateWidget] 里撤掉）。
  String? _showing;

  /// 这颗按钮读的状态：本地刚改的那一次优先，其余看 Host 的那份。胶囊读的
  /// 是同一个 provider（`groupGoalProvider`），所以两边永远说同一件事。
  String get _status => _showing ?? widget.goal.status;

  @override
  void didUpdateWidget(_GoalHeaderActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_showing != null && widget.goal.status == _showing) _showing = null;
  }

  /// 成功的是哪一步就显示成哪一步：不用等下一次拉取，也不用重开面板。
  void _optimistic(String action) {
    _showing = switch (action) {
      'pause' => 'paused',
      'resume' => 'active',
      'stop' => 'stopped',
      'clear' => null,
      _ => _showing,
    };
  }

  /// 拉一次 goal-view 并以它为准：只标脏不够，这里把读取等回来，成功与否
  /// 都能让界面在这一次操作里就对齐。
  Future<void> _reload() async {
    try {
      await ref.refresh(groupGoalProvider(widget.roomId).future);
    } catch (_) {
      // 拉失败就留着本地那次的状态；下一次失效还会再拉。
      return;
    }
    // Host 那份已经拉回来了，就以它为准：即使和刚才那一步对不上，也不能让
    // 本地那次的状态一直盖着真值。
    if (mounted && _showing != null) setState(() => _showing = null);
  }

  Future<void> _control(String action) async {
    if (_busy) return;
    final api = ref.read(dsBotProvider.notifier).api;
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.goalControl(widget.roomId, widget.goal.id, action);
      // 请求成功 = Host 已经改完：先把界面切成新状态，再把真值拉回来校正。
      if (mounted) setState(() => _optimistic(action));
      await _reload();
      if (action == 'clear' && mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setArmed(bool armed) {
    setState(() => _armed = armed);
    widget.confirming?.value = armed;
  }

  void _stop() {
    if (!_armed) {
      _setArmed(true);
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted && _armed) _setArmed(false);
      });
      return;
    }
    _setArmed(false);
    _control('stop');
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    if (status == 'complete' || status == 'stopped') {
      return _disc(
        tooltip: l10n.chatClearGoal,
        icon: AppIcons.close,
        color: dsh.textTertiary,
        onTap: _busy ? null : () => _control('clear'),
      );
    }
    if (status == 'drafting') {
      return _disc(
        tooltip: l10n.commonCancel,
        icon: AppIcons.close,
        color: dsh.textTertiary,
        onTap: _busy ? null : () => _control('clear'),
      );
    }
    if (status != 'active' && status != 'paused') return const SizedBox.shrink();
    final paused = status == 'paused';
    // 照手机控制的悬浮卡那两颗圆（OverlayCapsule.kt / CapsuleMetrics）：
    // 触控 48、可见 36、两键之间 4；暂停是 tonal 底 + ink 图标，暂停后换
    // accentSoft 底 + accent 的播放图标；停止是 danger 底 + 白方块。
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _disc(
          tooltip: paused ? l10n.chatResumeGoal : l10n.chatPauseGoal,
          icon: paused ? AppIcons.play : AppIcons.pause,
          iconSize: 18,
          color: paused ? theme.colorScheme.primary : theme.colorScheme.onSurface,
          background: paused ? theme.colorScheme.primary.withValues(alpha: 0.14) : null,
          onTap: _busy ? null : () => _control(paused ? 'resume' : 'pause'),
        ),
        const SizedBox(width: 4),
        // 二次确认走标题区那 3 秒，这颗键本身不变形。
        _disc(
          tooltip: _armed ? l10n.chatGoalConfirmStop : l10n.commonStop,
          icon: AppIcons.stop,
          iconSize: 16,
          color: dsh.onDangerContainer,
          background: dsh.dangerContainer,
          onTap: _busy ? null : _stop,
        ),
      ],
    );
  }

  Widget _disc({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    Color? background,
    double iconSize = 20,
  }) => _goalDisc(
    context,
    tooltip: tooltip,
    icon: icon,
    color: color,
    onTap: onTap,
    background: background,
    iconSize: iconSize,
  );
}

/// 兼容旧调用：群目标面板以前是底部抽屉，现在改为顶栏展开，这个函数只
/// 留给「从进度页点开面板」用——用一个薄抽屉装同一份内容。
Future<void> showGroupGoalSheet(BuildContext context, String roomId) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => Consumer(
    builder: (context, ref, _) {
      final goal = ref.watch(groupGoalProvider(roomId)).value;
      if (goal == null) return const SizedBox(height: 80);
      var checks = false;
      return SafeArea(
        top: false,
        child: StatefulBuilder(
          builder: (context, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GoalPanel(goal: goal, roomId: roomId, onClose: () => Navigator.of(context).maybePop()),
                      if (checks) ...[const SizedBox(height: 6), GoalChecksBody(goal: goal)],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              GoalChecksBar(
                goal: goal,
                open: checks,
                onToggle: () => setSheet(() => checks = !checks),
              ),
            ],
          ),
        ),
      );
    },
  ),
);
