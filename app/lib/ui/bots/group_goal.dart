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
import '../../state/settings_state.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';

/// 群的目标，随群消息和回合变化重新取一次。
final groupGoalProvider = FutureProvider.autoDispose.family<DsBotGroupGoal?, String>((ref, roomId) async {
  final api = ref.watch(dsBotProvider.notifier).api;
  if (api == null) return null;
  ref.watch(roomChatProvider(roomId).select((s) => (s.items.length, s.running)));
  try {
    return (await api.goalView(roomId)).goal;
  } catch (_) {
    return null;
  }
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
  const GoalRing({super.key, required this.goal, this.size = 30, this.onTap});

  final DsBotGroupGoal goal;
  final double size;
  final VoidCallback? onTap;

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
                fontSize: size <= 24 ? 8.5 : 9.5,
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
      label: goal.title,
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

/// 收起态那颗：简单模式只有一颗环，完整模式是「图标 + 标题 + 环」。
class GroupGoalPill extends StatelessWidget {
  const GroupGoalPill({
    super.key,
    required this.goal,
    required this.style,
    required this.onTap,
    this.expandArrow = false,
  });

  final DsBotGroupGoal goal;
  final GoalBarStyle style;
  final VoidCallback onTap;

  /// 展开态铺满整条顶栏时，右端多一个收起箭头。
  final bool expandArrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final tone = goalStateColor(context, goal);
    final ring = GoalRing(goal: goal, size: expandArrow ? 36 : 30);
    if (style == GoalBarStyle.simple && !expandArrow) {
      return Semantics(
        button: true,
        label: goal.title,
        child: InkResponse(onTap: onTap, radius: 24, child: Padding(padding: const EdgeInsets.all(6), child: ring)),
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                goal.status == 'complete' ? AppIcons.success : AppIcons.goal,
                size: 16,
                color: goal.status == 'complete' ? dsh.success : dsh.textTertiary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  goal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              ring,
              if (expandArrow) ...[
                const SizedBox(width: 2),
                Icon(AppIcons.collapse, size: 16, color: dsh.textTertiary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 展开后的面板：阶段圆点、选中这一段、目标与验收、底部按钮。顶栏下浮层用。
class GoalPanel extends ConsumerStatefulWidget {
  const GoalPanel({super.key, required this.goal, required this.roomId, required this.onClose});

  final DsBotGroupGoal goal;
  final String roomId;
  final VoidCallback onClose;

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

  Future<void> _control(String action) async {
    if (_busy) return;
    final api = ref.read(dsBotProvider.notifier).api;
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.goalControl(widget.roomId, _goal.id, action);
      ref.invalidate(groupGoalProvider(widget.roomId));
      if (action == 'clear') widget.onClose();
    } catch (error) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _stop() {
    if (!_armed) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${context.l10n.commonStop}?'), duration: const Duration(seconds: 2)),
      );
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
        if (goal.status == 'drafting')
          Text(goal.brief.isEmpty ? l10n.chatGoalHint : goal.brief, style: theme.textTheme.bodyMedium)
        else if (stage == null) ...[
          if (goal.summary.isNotEmpty) Text(goal.summary, style: theme.textTheme.bodyMedium),
          if (goal.evidence.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(goal.evidence, style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary)),
          ],
          if (goal.reason.isNotEmpty) ...[
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
              '${l10n.chatGoalRework(stage.reworks)} · ${stage.feedback}',
              style: theme.textTheme.bodySmall?.copyWith(color: dsh.warning),
            ),
          ],
          if (stage.evidence.isNotEmpty && stage.passed) ...[
            const SizedBox(height: 6),
            Text(l10n.chatGoalStageDone, style: small),
            Text(stage.evidence, style: theme.textTheme.bodySmall?.copyWith(color: dsh.success)),
          ],
          if (stage.tasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(l10n.chatGoalTasks, style: small),
            const SizedBox(height: 2),
            for (final task in stage.tasks) _GoalTaskRow(task: task),
          ],
        ],
        if (hasChecks) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() => _checks = !_checks),
            style: controlStyle,
            child: Text(l10n.chatGoalAcceptance),
          ),
          if (_checks) ...[
            if (goal.objective.isNotEmpty) _Block(label: l10n.chatGoal, value: goal.objective),
            if (goal.acceptance.isNotEmpty) _Block(label: l10n.chatGoalAcceptanceDone, value: goal.acceptance),
            for (final rule in goal.constraints) _Block(label: l10n.chatGoalRule, value: rule),
          ],
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            if (goal.status == 'active')
              TextButton(onPressed: _busy ? null : () => _control('pause'), style: controlStyle, child: Text(l10n.chatPauseGoal)),
            if (goal.status == 'paused')
              TextButton(onPressed: _busy ? null : () => _control('resume'), style: controlStyle, child: Text(l10n.chatResumeGoal)),
            if (goal.status == 'active' || goal.status == 'paused')
              TextButton(
                onPressed: _busy ? null : _stop,
                style: _armed
                    ? controlStyle.copyWith(foregroundColor: WidgetStatePropertyAll(theme.colorScheme.error))
                    : controlStyle,
                child: Text(l10n.commonStop),
              ),
            if (goal.status == 'complete' || goal.status == 'stopped')
              TextButton(onPressed: _busy ? null : () => _control('clear'), style: controlStyle, child: Text(l10n.chatClearGoal)),
            if (goal.status == 'drafting')
              TextButton(onPressed: _busy ? null : () => _control('clear'), style: controlStyle, child: Text(l10n.commonCancel)),
          ],
        ),
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
          for (final (index, stage) in stages.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: InkWell(
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
                              color: index == viewing ? primary : dsh.textTertiary,
                              fontWeight: FontWeight.w600,
                            ),
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

/// 这一段里的一个成员任务：头像、名字（成员自己的颜色）、这件事。
class _GoalTaskRow extends StatelessWidget {
  const _GoalTaskRow({required this.task});

  final DsBotGoalTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final reported = task.status == 'reported' || task.status == 'done';
    final live = task.status == 'working';
    final tone = switch (task.status) {
      'done' => dsh.success,
      'reported' => theme.colorScheme.primary,
      'working' => dsh.warning,
      _ => dsh.textTertiary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Icon(
                    reported ? AppIcons.success : live ? AppIcons.inProgress : AppIcons.pending,
                    size: 15,
                    color: tone,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${task.bot} ',
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: task.task, style: theme.textTheme.bodySmall),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary)),
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 从顶栏胶囊展开：顶栏铺满成目标本身，下面长出面板，其余内容被遮住。
/// 收起（箭头 / 点遮罩 / 返回键）就散了，原顶栏原样回来。
Future<void> showGoalExpand(BuildContext context, String roomId) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black.withValues(alpha: 0.24),
  transitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (dialogContext, _, _) => _GoalExpandLayer(roomId: roomId),
  transitionBuilder: (context, animation, _, child) => SlideTransition(
    position: Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    ),
    child: FadeTransition(opacity: animation, child: child),
  ),
);

class _GoalExpandLayer extends ConsumerWidget {
  const _GoalExpandLayer({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(groupGoalProvider(roomId)).value;
    final style = ref.watch(settingsProvider.select((s) => s.goalBarStyle));
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: EdgeInsets.only(top: top),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24)],
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: goal == null
                ? const SizedBox(height: 60)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 56,
                        child: Row(
                          children: [
                            Expanded(
                              child: GroupGoalPill(
                                goal: goal,
                                style: GoalBarStyle.full,
                                expandArrow: true,
                                onTap: () => Navigator.of(context).maybePop(),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: IconButton(
                                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                                onPressed: () => Navigator.of(context).maybePop(),
                                icon: Icon(AppIcons.close, size: 18, color: dsh.textTertiary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxHeight - 56),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: GoalPanel(
                            goal: goal,
                            roomId: roomId,
                            onClose: () => Navigator.of(context).maybePop(),
                          ),
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
