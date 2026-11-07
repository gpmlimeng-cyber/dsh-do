// 群目标：输入区上方一条胶囊，点开是「目标与验收」面板。
//
// 数据来自 ds-bot 的 goal-view（阶段、完成标准、成员任务都在它的 room.goal 里）,
// 样式沿用 App 自己的 DockRow / SheetGroup：网页版的信息层级，原生的样子。

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../chat/dock/dock_pill.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
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
      child: goal == null || goal.title.isEmpty ? null : _Bar(goal: goal, roomId: roomId),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.goal, required this.roomId});

  final DsBotGroupGoal goal;
  final String roomId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dsh = DshColors.of(context);
    final stage = goal.stage;
    return Semantics(
      button: true,
      label: l10n.botsGlyphViewGoal,
      child: GlassSurface(
        tier: GlassTier.chrome,
        borderRadius: DockMetrics.shape,
        grouped: true,
        onTap: () => showGroupGoalSheet(context, roomId),
        child: DockRow(
          leading: DockGlyph.icon(AppIcons.goal, color: dsh.textTertiary),
          content: Row(
            children: [
              Text(l10n.chatGoal, style: DockText.title(context)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  goal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DockText.detail(context),
                ),
              ),
              if (goal.position.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(goal.position, style: DockText.detail(context, color: dsh.textTertiary)),
              ],
              if (stage != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    stage.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DockText.detail(context, color: dsh.textTertiary),
                  ),
                ),
              ],
            ],
          ),
          accessory: goalStateWord(l10n, goal) == null
              ? null
              : Text(goalStateWord(l10n, goal)!, style: DockText.title(context, color: goalStateColor(context, goal))),
          trailing: DockGlyph(
            child: Icon(AppIcons.more, size: DockGlyph.iconSize, color: dsh.textTertiary),
          ),
        ),
      ),
    );
  }
}

/// 「目标与验收」面板。
Future<void> showGroupGoalSheet(BuildContext context, String roomId) =>
    showAppSheet<void>(context, isScrollControlled: true, builder: (_) => GroupGoalSheet(roomId: roomId));

class GroupGoalSheet extends ConsumerStatefulWidget {
  const GroupGoalSheet({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<GroupGoalSheet> createState() => _GroupGoalSheetState();
}

class _GroupGoalSheetState extends ConsumerState<GroupGoalSheet> {
  bool _busy = false;

  Future<void> _control(DsBotGroupGoal goal, String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(dsBotProvider.notifier).api?.goalControl(widget.roomId, goal.id, action);
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
    final goal = ref.watch(groupGoalProvider(widget.roomId)).value;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitleBar(l10n.chatGoalPanel),
            if (goal == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(l10n.chatGoalNone, style: theme.textTheme.bodyMedium?.copyWith(color: dsh.textTertiary)),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(goal.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (goal.position.isNotEmpty)
                      Text(goal.position, style: AppType.tabular(theme.textTheme.labelMedium!.copyWith(color: dsh.textTertiary))),
                    if (goalStateWord(l10n, goal) case final word?) ...[
                      const SizedBox(width: 8),
                      Text(word, style: theme.textTheme.labelMedium?.copyWith(color: goalStateColor(context, goal))),
                    ],
                  ],
                ),
              ),
              if (goal.stages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: _StageDots(goal: goal),
                ),
              if (goal.stage case final stage?) ...[
                SheetGroup(title: l10n.chatGoalStageCurrent, children: [
                  _Labeled(label: l10n.chatGoalStageDone, value: stage.acceptance),
                ]),
                if (stage.tasks.isNotEmpty)
                  SheetGroup(title: l10n.chatGoalTasks, children: [
                    for (final task in stage.tasks) _TaskRow(task: task),
                  ]),
              ],
              if (goal.objective.isNotEmpty || goal.acceptance.isNotEmpty || goal.constraints.isNotEmpty)
                SheetGroup(title: l10n.chatGoalAcceptance, children: [
                  if (goal.objective.isNotEmpty) _Labeled(label: l10n.chatGoal, value: goal.objective),
                  if (goal.acceptance.isNotEmpty) _Labeled(label: l10n.chatGoalAcceptanceDone, value: goal.acceptance),
                  for (final rule in goal.constraints) _Labeled(label: l10n.chatGoalRule, value: rule),
                ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Row(
                  children: [
                    if (goal.status == 'active')
                      Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _control(goal, 'pause'), child: Text(l10n.chatPauseGoal))),
                    if (goal.status == 'paused')
                      Expanded(child: FilledButton(onPressed: _busy ? null : () => _control(goal, 'resume'), child: Text(l10n.chatResumeGoal))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _control(goal, 'stop'),
                        style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                        child: Text(l10n.chatClearGoal),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StageDots extends StatelessWidget {
  const _StageDots({required this.goal});

  final DsBotGroupGoal goal;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        for (final (index, stage) in goal.stages.indexed) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: stage.passed ? dsh.success : dsh.textTertiary.withValues(alpha: 0.3),
              ),
            ),
          Container(
            width: index == goal.current ? 12 : 9,
            height: index == goal.current ? 12 : 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stage.passed ? dsh.success : index == goal.current ? primary : dsh.textTertiary.withValues(alpha: 0.35),
            ),
          ),
        ],
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final DsBotGoalTask task;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final word = switch (task.status) {
      'working' => l10n.chatGoalTaskWorking,
      'reported' => l10n.chatGoalTaskReported,
      'done' => l10n.chatGoalTaskDone,
      _ => l10n.chatGoalTaskPending,
    };
    final tone = switch (task.status) {
      'working' => dsh.warning,
      'reported' => theme.colorScheme.primary,
      'done' => dsh.success,
      _ => dsh.textTertiary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(task.bot, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge)),
              if (task.rework > 0) ...[
                Text(l10n.chatGoalRework(task.rework), style: theme.textTheme.labelSmall?.copyWith(color: dsh.warning)),
                const SizedBox(width: 6),
              ],
              Text(word, style: theme.textTheme.labelSmall?.copyWith(color: tone)),
            ],
          ),
          const SizedBox(height: 2),
          Text(task.task, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary)),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
