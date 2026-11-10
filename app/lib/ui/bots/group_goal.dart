// 群目标：群聊页顶栏那颗胶囊，点开在它下面展开整份计划。
//
// 这是 ds-bot 网页端那颗「目标胶囊」（src/client/goal.js）的移植：收起态是
// 一颗圆形进度环（环内写「3/4」，颜色随状态），完整模式则把群名收成圆形头像、
// 旁边排一颗带标题的胶囊；展开态胶囊铺满顶栏、其余按钮隐藏，下面长出面板。
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
        painter: _RingPainter(fraction: fraction, tone: tone, track: tone.withValues(alpha: 0.18)),
        child: Center(
          child: Text(
            label,
            style: AppType.tabular(
              theme.textTheme.labelSmall!.copyWith(
                // 字号跟着环走：24 小、30 中、32 与 36 大。
                fontSize: size >= 32 ? 10.5 : size <= 24 ? 8.5 : 9.5,
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

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.tone, required this.track});

  final double fraction;
  final Color tone;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 2.5) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
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
/// 没有目标时仍画那颗灰点（点一下说明它问了什么、得到什么），方便一眼
/// 分清「后端没有目标」还是「画不出来」。
class GoalBarProbe extends ConsumerWidget {
  const GoalBarProbe({super.key, required this.roomId, this.expanded = false, this.onExpand, this.onCollapse});

  final String roomId;

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
    final api = ref.read(dsBotProvider.notifier).api;
    return switch (async) {
      AsyncData(value: final goal?) when goal.title.isNotEmpty => GroupGoalPill(
        goal: goal,
        expanded: expanded,
        onTap: expanded ? () => showGoalExpand(context, roomId, onCollapse: onCollapse) : onExpand,
      ),
      AsyncLoading() => const SizedBox.square(
        dimension: 30,
        child: Center(child: SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 1.6))),
      ),
      _ => InkResponse(
        radius: 18,
        onTap: () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'api=${api == null ? 'null' : 'ok'}'
              ' · ${async.hasError ? 'err=${async.error}' : async.value == null ? 'goal=null' : 'title=${async.value!.title}'}'
              ' · room=$roomId',
            ),
            duration: const Duration(seconds: 8),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DshColors.of(context).textTertiary.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    };
  }
}

/// 顶栏那颗：小球（环）或完整胶囊（图标 + 标题 + 环）。
///
/// 与顶栏其他键同一套：44 高的玻璃底（[BotChatHeader.key44]、chrome、
/// grouped），按下态由 GlassSurface 给。读屏只念一遍标题。
class GroupGoalPill extends StatelessWidget {
  const GroupGoalPill({
    super.key,
    required this.goal,
    required this.onTap,
    this.expanded = false,
    this.expandArrow = false,
  });

  final DsBotGroupGoal goal;
  final VoidCallback onTap;

  /// False: the ball. True: the full pill.
  final bool expanded;

  /// 展开面板的头部那颗多一个收起箭头。
  final bool expandArrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final paused = goal.status == 'paused';
    final ring = GoalRing(goal: goal, size: expanded ? 24 : 32, announce: false);
    if (!expanded) {
      return Semantics(
        button: true,
        label: goal.title,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: BotChatHeader.key44,
          child: GlassSurface(
            tier: GlassTier.chrome,
            circle: true,
            grouped: true,
            onTap: onTap,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                ring,
                // 暂停了就写在前面：小球放不下文字，角标就是那颗暂停。
                if (paused)
                  Positioned(
                    left: 2,
                    top: 2,
                    child: Icon(AppIcons.paused, size: 13, color: dsh.warning),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: goal.title,
      excludeSemantics: true,
      child: SizedBox(
        height: BotChatHeader.key44,
        child: GlassSurface(
          tier: GlassTier.chrome,
          stadium: true,
          grouped: true,
          onTap: onTap,
          child: Tooltip(
            message: goal.title,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                  Flexible(
                    child: Text(
                      goal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(fontSize: 15, height: 1.3, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ring,
                  if (expandArrow) ...[
                    const SizedBox(width: 2),
                    Icon(AppIcons.collapse, size: 16, color: dsh.textTertiary),
                  ],
                ],
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
    this.showActions = true,
  });

  final DsBotGroupGoal goal;
  final String roomId;
  final VoidCallback onClose;

  /// False when the actions live in the card's own header (the floating card)。
  final bool showActions;

  @override
  ConsumerState<GoalPanel> createState() => _GoalPanelState();
}

class _GoalPanelState extends ConsumerState<GoalPanel> {
  bool _busy = false;
  bool _checks = false;
  bool _armed = false;
  int? _selected;

  DsBotGroupGoal get _goal => widget.goal;

  int get _at => _goal.status == 'active' || _goal.status == 'paused' ? _goal.current : -1;

  int get _viewing => _selected ?? _at;

  DsBotGoalStage? get _stage {
    final at = _viewing;
    if (at < 0 || at >= _goal.stages.length) return null;
    return _goal.stages[at];
  }

  Future<void> _control(String action, {bool stopWork = false}) async {
    if (_busy) return;
    final api = ref.read(dsBotProvider.notifier).api;
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.goalControl(widget.roomId, _goal.id, action, stopWork: stopWork);
      ref.invalidate(groupGoalProvider(widget.roomId));
      if (action == 'clear') widget.onClose();
    } catch (error) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 已暂停、但还有人在跑：只停工作，目标保持暂停。
  /// 网页端这颗「连当前工作一起停」走的也是 `stop-room-work`，不是 `goal-control`：
  /// 后者在 paused 下会把整个目标停掉。
  Future<void> _stopWorkOnly() async {
    if (_busy) return;
    final api = ref.read(dsBotProvider.notifier).api;
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.stopRoomWork(widget.roomId);
      ref.invalidate(groupGoalProvider(widget.roomId));
    } catch (error) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _stop() {
    if (!_armed) {
      // 网页端把确认写在按钮里（3 秒内再点），不弹提示条：弹条会盖住底部动作。
      setState(() => _armed = true);
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    setState(() => _armed = false);
    _control('stop');
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
    final hasChecks = goal.objective.isNotEmpty || goal.acceptance.isNotEmpty || goal.constraints.isNotEmpty;
    // 「连当前工作一起停」 only means something while the goal is paused and a
    // member is still running.
    final working = ref.watch(
      dsBotProvider.select((s) => (s.live.rooms[widget.roomId] ?? const <DsBotWork>[]).isNotEmpty),
    );
    final room = ref.watch(dsBotProvider.select((s) => s.team?.room(widget.roomId)));
    final admin = room == null ? l10n.botsABot : (ref.read(dsBotProvider).team?.bot(room.admin ?? '')?.name ?? l10n.botsABot);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (goal.status != 'drafting' && goal.stages.length > 1)
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
            Text(l10n.chatGoalStageDone, style: small),
            const SizedBox(height: 1),
            Text(stage.acceptance, style: theme.textTheme.bodyMedium),
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
            for (final task in stage.tasks) _GoalTaskRow(task: task),
          ],
        ],
        const SizedBox(height: 6),
        // 照网页端的 foot：左边「目标与验收」折叠钮，右边动作；动作沿用手机
        // 控制那套圆盘（暂停/恢复、停止红色两段式），清除/取消留成文字链。
        Row(
          children: [
            if (hasChecks)
              TextButton(
                onPressed: () => setState(() => _checks = !_checks),
                style: controlStyle,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.chatGoalAcceptance),
                    AnimatedRotation(
                      turns: _checks ? 0.5 : 0,
                      duration: AppMotion.of(context, AppMotion.standard),
                      child: Icon(AppIcons.collapse, size: 16, color: dsh.textTertiary),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            if (widget.showActions) _GoalHeaderActions(roomId: widget.roomId, goal: goal),
            if (widget.showActions && goal.status == 'paused' && working)
              TextButton(
                onPressed: _busy ? null : () => _stopWorkOnly,
                style: controlStyle,
                child: Text(l10n.chatStopWorkToo),
              ),
            if (widget.showActions && (goal.status == 'complete' || goal.status == 'stopped'))
              TextButton(onPressed: _busy ? null : () => _control('clear'), style: controlStyle, child: Text(l10n.chatClearGoal)),
            if (widget.showActions && goal.status == 'drafting')
              TextButton(onPressed: _busy ? null : () => _control('clear'), style: controlStyle, child: Text(l10n.commonCancel)),
          ],
        ),
        // 展开的验收内容在这一行下面，卡片往下长；折叠时不占高度。
        if (_checks && hasChecks) ...[
          if (goal.objective.isNotEmpty) _Block(label: l10n.chatGoal, value: goal.objective),
          if (goal.acceptance.isNotEmpty) _Block(label: l10n.chatGoalAcceptanceDone, value: goal.acceptance),
          for (final rule in goal.constraints) _Block(label: l10n.chatGoalRule, value: rule),
        ],
      ],
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

/// 这一段里的一个成员任务：头像、名字（成员自己的颜色）、这件事。
class _GoalTaskRow extends ConsumerWidget {
  const _GoalTaskRow({required this.task});

  final DsBotGoalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    // 名字取团队里的当前名字：Host 给的 task.bot 是发任务时的快照，改名后
    // 那一份就旧了。
    final team = ref.watch(dsBotProvider.select((s) => s.team));
    final bot = team?.bot(task.botId);
    final name = bot?.name ?? (task.bot.isEmpty ? task.botId : task.bot);
    final tone = switch (task.status) {
      'done' => dsh.success,
      'reported' => theme.colorScheme.primary,
      'working' => dsh.warning,
      _ => dsh.textTertiary,
    };
    final glyph = task.status == 'done' || task.status == 'reported'
        ? AppIcons.success
        : task.status == 'working'
        ? AppIcons.inProgress
        : AppIcons.pending;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 24,
            child: bot == null
                ? CircleAvatar(
                    radius: 12,
                    child: Text(name.isEmpty ? '?' : name.substring(0, 1), style: theme.textTheme.labelSmall),
                  )
                : BotAvatar(bot: bot, size: 24),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(glyph, size: 15, color: tone),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  task.task,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
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
Future<void> showGoalExpand(BuildContext context, String roomId, {VoidCallback? onCollapse}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // 浮窗式卡片：靠边距和投影把内容让开，不铺遮罩。
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, _) => _GoalExpandLayer(roomId: roomId, onCollapse: onCollapse),
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

class _GoalExpandLayer extends ConsumerWidget {
  const _GoalExpandLayer({required this.roomId, this.onCollapse});

  final String roomId;

  /// 面板里的「收起成小球」：关面板，并把顶栏收回小球。
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(groupGoalProvider(roomId)).value;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
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
              // 尺寸照手机控制的浮窗卡：左右 12、状态栏下 6、圆角 24、头部 48。
              padding: EdgeInsets.fromLTRB(12, top + 6, 12, 0),
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
                                    child: Text(
                                      goal.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  // 头部只留这一颗（和抽屉、⋯ 同一套圆键）：
                                  // 收回小球并关面板；进度页的薄抽屉没有小球
                                  // 可收，就只关面板。
                                  const SizedBox(width: 8),
                                  _goalDisc(
                                    context,
                                    tooltip: onCollapse == null
                                        ? MaterialLocalizations.of(context).closeButtonTooltip
                                        : l10n.chatGoalCollapseToBallHint,
                                    icon: AppIcons.collapse,
                                    iconSize: 18,
                                    color: dsh.textTertiary,
                                    onTap: () {
                                      onCollapse?.call();
                                      Navigator.of(context).maybePop();
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: GoalPanel(
                                  goal: goal,
                                  roomId: roomId,
                                  onClose: () => Navigator.of(context).maybePop(),
                                ),
                              ),
                            ),
                            _GoalClearLink(roomId: roomId, goal: goal),
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
  const _GoalHeaderActions({required this.roomId, required this.goal});

  final String roomId;
  final DsBotGroupGoal goal;

  @override
  ConsumerState<_GoalHeaderActions> createState() => _GoalHeaderActionsState();
}

class _GoalHeaderActionsState extends ConsumerState<_GoalHeaderActions> {
  bool _busy = false;
  bool _armed = false;

  Future<void> _control(String action) async {
    if (_busy) return;
    final api = ref.read(dsBotProvider.notifier).api;
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.goalControl(widget.roomId, widget.goal.id, action);
      ref.invalidate(groupGoalProvider(widget.roomId));
    } catch (error) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _stop() {
    if (!_armed) {
      setState(() => _armed = true);
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    setState(() => _armed = false);
    _control('stop');
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.goal.status;
    final l10n = context.l10n;
    final dsh = DshColors.of(context);
    if (status != 'active' && status != 'paused') return const SizedBox.shrink();
    final paused = status == 'paused';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _disc(
          tooltip: paused ? l10n.chatResumeGoal : l10n.chatPauseGoal,
          icon: paused ? AppIcons.play : AppIcons.pause,
          color: dsh.textTertiary,
          onTap: _busy ? null : () => _control(paused ? 'resume' : 'pause'),
        ),
        _disc(
          tooltip: _armed ? '${l10n.commonStop}?' : l10n.commonStop,
          icon: AppIcons.stop,
          color: _armed ? Theme.of(context).colorScheme.onError : Theme.of(context).colorScheme.error,
          background: _armed ? Theme.of(context).colorScheme.error : null,
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
  }) => _goalDisc(context, tooltip: tooltip, icon: icon, color: color, onTap: onTap, background: background);
}

/// 卡片底部：清除/取消留成文字链，不做大按钮（浮窗的「收成小球」就是这种位置）。
class _GoalClearLink extends ConsumerStatefulWidget {
  const _GoalClearLink({required this.roomId, required this.goal});

  final String roomId;
  final DsBotGroupGoal goal;

  @override
  ConsumerState<_GoalClearLink> createState() => _GoalClearLinkState();
}

class _GoalClearLinkState extends ConsumerState<_GoalClearLink> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final status = widget.goal.status;
    if (status != 'drafting' && status != 'complete' && status != 'stopped') {
      return const SizedBox(height: 8);
    }
    final l10n = context.l10n;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: TextButton(
          onPressed: _busy
              ? null
              : () async {
                  final api = ref.read(dsBotProvider.notifier).api;
                  if (api == null) return;
                  setState(() => _busy = true);
                  try {
                    await api.goalControl(widget.roomId, widget.goal.id, 'clear');
                    ref.invalidate(groupGoalProvider(widget.roomId));
                    if (mounted) Navigator.of(context).maybePop();
                  } catch (error) {
                    if (mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$error')));
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(status == 'drafting' ? l10n.commonCancel : l10n.chatClearGoal),
        ),
      ),
    );
  }
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
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: GoalPanel(goal: goal, roomId: roomId, onClose: () => Navigator.of(context).maybePop()),
        ),
      );
    },
  ),
);
