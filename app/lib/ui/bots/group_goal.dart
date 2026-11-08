// 群目标：输入区上方一条，点开在原地展开成一张「目标与验收」清单。
//
// 壳照输入区上方的 todo 条（ui/chat/dock/todo_bar.dart）：一条折叠，点一下
// 原地长出来，再点收起，最多占屏幕四成，多了在壳里滚。里面的信息照网页版
// ds-bot 的 goal.js：一排阶段点、这一段的验收、成员任务、三个键。
//
// 同一份内容也单独弹成抽屉（对话详情的进度页点一下就打开它）。

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../chat/dock/dock_pill.dart';
import '../common/app_sheet.dart';
import '../common/expand_reveal.dart';
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
  return switch (goal.status) {
    'active' => dsh.success,
    'paused' => dsh.warning,
    _ => dsh.textTertiary,
  };
}

/// 输入区上方那条：没有目标时 0 高。
class GroupGoalBar extends ConsumerWidget {
  const GroupGoalBar({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(groupGoalProvider(roomId)).value;
    return DockSlot(
      key: const ValueKey('group-goal'),
      child: goal == null || goal.title.isEmpty ? null : _GoalCard(goal: goal, roomId: roomId),
    );
  }
}

/// 同一份内容单独弹成抽屉：对话详情的进度页点目标或某一步时打开。
Future<void> showGroupGoalSheet(BuildContext context, String roomId) => showAppSheet<void>(
  context,
  isScrollControlled: true,
  builder: (sheetContext) => Consumer(
    builder: (context, ref, _) {
      final l10n = context.l10n;
      final goal = ref.watch(groupGoalProvider(roomId)).value;
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: goal == null || goal.title.isEmpty
              ? Text(l10n.chatGoalNone, style: Theme.of(context).textTheme.bodyMedium)
              : GroupGoalPanel(goal: goal, roomId: roomId),
        ),
      );
    },
  ),
);

class _GoalCard extends ConsumerStatefulWidget {
  const _GoalCard({required this.goal, required this.roomId});

  final DsBotGroupGoal goal;
  final String roomId;

  @override
  ConsumerState<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends ConsumerState<_GoalCard> {
  bool _open = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dsh = DshColors.of(context);
    final goal = widget.goal;
    final stage = goal.stage;
    final word = goalStateWord(l10n, goal);
    final done = goal.status == 'complete';
    final header = Semantics(
      button: true,
      expanded: _open,
      label: l10n.botsGlyphViewGoal,
      excludeSemantics: true,
      child: InkWell(
        onTap: _toggle,
        customBorder: const RoundedSuperellipseBorder(borderRadius: DockMetrics.shape),
        child: DockRow(
          leading: DockGlyph.icon(
            done ? AppIcons.success : AppIcons.goal,
            color: done ? dsh.success : dsh.textTertiary,
          ),
          content: Text.rich(
            TextSpan(
              children: [
                if (goal.position.isNotEmpty) ...[
                  TextSpan(text: goal.position, style: AppType.tabular(DockText.title(context))),
                  TextSpan(text: ' · ', style: DockText.detail(context)),
                ],
                TextSpan(
                  text: stage != null && stage.title.isNotEmpty ? stage.title : goal.title,
                  style: DockText.detail(context),
                ),
                if (word != null) TextSpan(text: ' · $word', style: DockText.detail(context, color: goalStateColor(context, goal))),
              ],
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          accessory: goal.stages.length > 1 ? _Segments(goal: goal, at: goal.current) : null,
          trailing: DockGlyph(
            child: AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: AppMotion.of(context, AppMotion.standard),
              curve: AppMotion.std,
              child: Icon(AppIcons.collapse, size: DockGlyph.iconSize, color: dsh.textTertiary),
            ),
          ),
        ),
      ),
    );
    final maxBody = (MediaQuery.sizeOf(context).height * 0.4).clamp(180.0, 360.0);
    return GlassSurface(
      tier: GlassTier.chrome,
      borderRadius: DockMetrics.shape,
      grouped: true,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            ExpandReveal(
              open: _open,
              duration: AppMotion.standard,
              curve: AppMotion.std,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxBody),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(DockMetrics.edge, 0, DockMetrics.edge, DockMetrics.edge),
                  child: GroupGoalPanel(goal: goal, roomId: widget.roomId),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 目标的内容：阶段条、这一段、目标与验收、三个键。条里和抽屉里同一份。
class GroupGoalPanel extends ConsumerStatefulWidget {
  const GroupGoalPanel({super.key, required this.goal, required this.roomId});

  final DsBotGroupGoal goal;
  final String roomId;

  @override
  ConsumerState<GroupGoalPanel> createState() => _GroupGoalPanelState();
}

class _GroupGoalPanelState extends ConsumerState<GroupGoalPanel> {
  bool _busy = false;

  /// 正在看的是哪一段；空 = 当前段。
  int? _selected;

  DsBotGroupGoal get _goal => widget.goal;

  int get _at => _selected ?? _goal.current;

  DsBotGoalStage? get _stage {
    final at = _at;
    if (at < 0 || at >= _goal.stages.length) return null;
    return _goal.stages[at];
  }

  Future<void> _control(String action) async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await ref.read(dsBotProvider.notifier).api?.goalControl(widget.roomId, _goal.id, action);
      ref.invalidate(groupGoalProvider(widget.roomId));
    } catch (error) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final goal = _goal;
    final stage = _stage;
    final small = theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary);
    final controlStyle = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: theme.textTheme.labelMedium,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (goal.stages.length > 1)
          _StageBar(
            goal: goal,
            at: _at,
            onSelect: (index) => setState(() => _selected = index),
          ),
        if (stage != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(stage.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (stage.passed)
                Text(l10n.commonCompleted, style: theme.textTheme.labelSmall?.copyWith(color: dsh.success))
              else if (_at == goal.current)
                Text(l10n.chatGoalStageCurrent, style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary)),
            ],
          ),
          if (stage.acceptance.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(l10n.chatGoalStageDone, style: small),
            const SizedBox(height: 1),
            Text(stage.acceptance, style: theme.textTheme.bodyMedium),
          ],
          if (stage.tasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(l10n.chatGoalTasks, style: small),
            const SizedBox(height: 2),
            for (final task in stage.tasks) _TaskRow(task: task),
          ],
        ] else if (goal.status == 'drafting')
          Text(l10n.chatGoalHint, style: theme.textTheme.bodyMedium?.copyWith(color: dsh.textTertiary)),
        if (goal.objective.isNotEmpty || goal.acceptance.isNotEmpty || goal.constraints.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(l10n.chatGoalAcceptance, style: small),
          const SizedBox(height: 2),
          if (goal.objective.isNotEmpty) _Labeled(value: goal.objective),
          if (goal.acceptance.isNotEmpty) _Labeled(value: goal.acceptance),
          for (final rule in goal.constraints) _Labeled(value: rule),
        ],
        if (goal.status == 'active' || goal.status == 'paused') ...[
          const SizedBox(height: 8),
          Row(
            children: [
              if (goal.status == 'active')
                TextButton(onPressed: _busy ? null : () => _control('pause'), style: controlStyle, child: Text(l10n.chatPauseGoal))
              else
                TextButton(onPressed: _busy ? null : () => _control('resume'), style: controlStyle, child: Text(l10n.chatResumeGoal)),
              const SizedBox(width: 4),
              TextButton(
                onPressed: _busy ? null : () => _control('stop'),
                style: controlStyle.copyWith(foregroundColor: WidgetStatePropertyAll(theme.colorScheme.error)),
                child: Text(l10n.chatClearGoal),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 折叠条右端的一排阶段点：过的是勾，当前那颗亮着。
class _Segments extends StatelessWidget {
  const _Segments({required this.goal, required this.at});

  final DsBotGroupGoal goal;
  final int at;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, stage) in goal.stages.indexed)
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stage.passed
                  ? dsh.success
                  : index == at
                  ? primary
                  : dsh.textTertiary.withValues(alpha: 0.28),
            ),
          ),
      ],
    );
  }
}

/// 展开后的阶段条：一颗一段，点哪段看哪段。
class _StageBar extends StatelessWidget {
  const _StageBar({required this.goal, required this.at, required this.onSelect});

  final DsBotGroupGoal goal;
  final int at;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final primary = theme.colorScheme.primary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        children: [
          for (final (index, stage) in goal.stages.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: InkWell(
                onTap: () => onSelect(index),
                customBorder: const StadiumBorder(),
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stage.passed
                        ? dsh.success.withValues(alpha: 0.16)
                        : index == at
                        ? primary.withValues(alpha: 0.16)
                        : dsh.textTertiary.withValues(alpha: 0.08),
                    border: index == at ? Border.all(color: primary, width: 1.2) : null,
                  ),
                  child: stage.passed
                      ? Icon(AppIcons.success, size: 13, color: dsh.success)
                      : Text(
                          '${index + 1}',
                          style: AppType.tabular(
                            theme.textTheme.labelSmall!.copyWith(
                              color: index == at ? primary : dsh.textTertiary,
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

/// 一个成员这一步：状态图标 + 名字 + 状态词（+ 被打回几次），下一行是活。
class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final DsBotGoalTask task;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final (word, tone, icon) = switch (task.status) {
      'working' => (l10n.chatGoalTaskWorking, dsh.warning, AppIcons.inProgress),
      'reported' => (l10n.chatGoalTaskReported, theme.colorScheme.primary, AppIcons.inProgress),
      'done' => (l10n.chatGoalTaskDone, dsh.success, AppIcons.success),
      _ => (l10n.chatGoalTaskPending, dsh.textTertiary, AppIcons.pending),
    };
    final style = theme.textTheme.bodySmall!.copyWith(
      color: task.status == 'done' ? dsh.textTertiary : theme.colorScheme.onSurfaceVariant,
    );
    final line = MediaQuery.textScalerOf(context).scale(style.fontSize ?? 12) * (style.height ?? 1.4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: DockMetrics.glyph,
            height: line,
            child: Center(child: Icon(icon, size: 15, color: tone)),
          ),
          const SizedBox(width: DockMetrics.glyphGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        task.bot,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(word, style: theme.textTheme.labelSmall?.copyWith(color: tone)),
                    if (task.rework > 0) ...[
                      const SizedBox(width: 6),
                      Text(l10n.chatGoalRework(task.rework), style: theme.textTheme.labelSmall?.copyWith(color: dsh.warning)),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(task.task, style: style, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 2),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
