// 群任务板：输入区上方一条，点开在原地展开成清单。
//
// 壳照 todo 条（ui/chat/dock/todo_bar.dart）和目标条（group_goal.dart）：一条
// 折叠，点一下原地长出来，再点收起，最多占屏幕四成，多了在壳里滚。里面的
// 信息照 ds-bot 的群任务：状态、负责人、前置依赖、时间线。
//
// 图（依赖画布）由外壳负责，这里只管清单。

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
import 'group_task_graph.dart';

/// 群的任务板，随群消息和回合变化重新取一次。
final groupTasksProvider = FutureProvider.autoDispose.family<DsBotTasksView?, String>((ref, roomId) async {
  final api = ref.watch(dsBotProvider.notifier).api;
  if (api == null) return null;
  ref.watch(roomChatProvider(roomId).select((s) => (s.items.length, s.running)));
  try {
    return await api.tasksView(roomId);
  } catch (_) {
    // An older Host without the task board: the bar stays away.
    return null;
  }
});

/// 一条任务的状态词。
String taskStateWord(L10n l10n, DsBotTask task) => switch (task.status) {
  'claimed' => l10n.botsTaskClaimed,
  'doing' => l10n.botsTaskDoing,
  'done' => l10n.commonCompleted,
  'failed' => l10n.botsTaskFailed,
  'cancelled' => l10n.botsTaskCancelled,
  _ => l10n.botsTaskPending,
};

Color taskStateColor(BuildContext context, DsBotTask task) {
  final dsh = DshColors.of(context);
  return switch (task.status) {
    'done' => dsh.success,
    'failed' => dsh.warning,
    'doing' || 'claimed' => Theme.of(context).colorScheme.primary,
    'cancelled' => dsh.textTertiary,
    _ => dsh.textTertiary,
  };
}

IconData taskStateIcon(DsBotTask task) => switch (task.status) {
  'done' => AppIcons.checkboxOn,
  'cancelled' => AppIcons.close,
  'failed' => AppIcons.warning,
  'doing' || 'claimed' => AppIcons.play,
  _ => AppIcons.checkboxOff,
};

/// 输入区上方那条：没有任务时 0 高。
class GroupTaskBar extends ConsumerStatefulWidget {
  const GroupTaskBar({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<GroupTaskBar> createState() => _GroupTaskBarState();
}

class _GroupTaskBarState extends ConsumerState<GroupTaskBar> {
  bool _open = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final all = ref.watch(groupTasksProvider(widget.roomId)).value;
    if (all == null) {
      return DockSlot(key: const ValueKey('group-tasks'), child: null);
    }
    // 目标推进时同步进来的阶段任务不算在这条条上：那条归目标条。
    final view = all.manual;
    final open = view.open;
    // 没有欠着的活了就整条收起：跟目标条一样，不一直贴着输入框。
    if (view.isEmpty || open.isEmpty) {
      return DockSlot(key: const ValueKey('group-tasks'), child: null);
    }
    final current = view.current;
    // 已取消的不进分母，也不进分子：它是一件不做的事，不是欠着的活。
    final counted = [for (final task in view.tasks) if (!task.cancelled) task];
    final total = counted.length;
    final done = counted.where((task) => task.done).length;
    // 和普通会话那条 todo 一个说法：在跑的写「正在」，没人跑就写「下一步」。
    final label = current != null
        ? l10n.botsTaskRunning(current.title)
        : view.open.isEmpty
        ? l10n.chatTodoAllDone
        : l10n.chatTodoNext(view.open.first.title);
    final header = Semantics(
      button: true,
      expanded: _open,
      label: l10n.botsTasks,
      excludeSemantics: true,
      child: InkWell(
        onTap: _toggle,
        customBorder: const RoundedSuperellipseBorder(borderRadius: DockMetrics.shape),
        child: DockRow(
          leading: DockGlyph.icon(
            done == total ? AppIcons.success : AppIcons.checkboxOff,
            color: done == total ? dsh.success : dsh.textTertiary,
          ),
          content: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$done/$total',
                  style: AppType.tabular(DockText.title(context)),
                ),
                TextSpan(text: ' · ', style: DockText.detail(context)),
                TextSpan(text: label, style: DockText.detail(context)),
              ],
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          accessory: total > 1 ? _TaskSegments(view: view) : null,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (open.isEmpty)
                        Text(
                          l10n.botsTaskNoneOpen,
                          style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
                        )
                      else
                        for (final task in open) GroupTaskRow(view: all, task: task, roomId: widget.roomId),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => showAddGroupTaskSheet(context, widget.roomId),
                            icon: const Icon(AppIcons.add, size: 16),
                            label: Text(l10n.botsTaskAdd),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              textStyle: theme.textTheme.labelMedium,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: l10n.botsTasks,
                            onPressed: () => Navigator.of(context).push(GroupTaskGraphPage.route(widget.roomId)),
                            icon: const Icon(AppIcons.diagram, size: 18),
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.all(6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 折叠条右端的一排小点：完成的是勾色，当前那颗亮着，其余暗着。
class _TaskSegments extends StatelessWidget {
  const _TaskSegments({required this.view});

  final DsBotTasksView view;

  @override
  Widget build(BuildContext context) {
    final dsh = DshColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final tasks = view.tasks.take(8).toList(growable: false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final task in tasks)
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: task.done
                  ? dsh.success
                  : task.status == 'doing' || task.status == 'claimed'
                  ? primary
                  : dsh.textTertiary.withValues(alpha: 0.28),
            ),
          ),
      ],
    );
  }
}

/// 清单里的一行：状态、标题、负责人、等待或可开工。
class GroupTaskRow extends ConsumerWidget {
  const GroupTaskRow({super.key, required this.view, required this.task, required this.roomId});

  final DsBotTasksView view;
  final DsBotTask task;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final team = ref.watch(dsBotProvider.select((s) => s.team));
    final waiting = view.waitingOn(task);
    final ready = view.ready.contains(task.id);
    final owner = task.assignee == null ? null : (team?.bot(task.assignee!)?.name ?? task.assignee!);
    final side = waiting.isNotEmpty
        ? l10n.botsTaskWaitingFor(waiting.map((t) => t.shortId).join('、'))
        : ready && !task.closed
        ? '${owner ?? l10n.botsUnassigned} · ${l10n.botsTaskReady}'
        : owner ?? l10n.botsUnassigned;
    return InkWell(
      onTap: () => openGroupTaskPanel(context, roomId: roomId, id: task.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(taskStateIcon(task), size: 15, color: taskStateColor(context, task)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: task.done || task.cancelled ? TextDecoration.lineThrough : null,
                  color: task.closed ? dsh.textTertiary : null,
                  fontWeight: task.doing ? FontWeight.w600 : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              side,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: waiting.isNotEmpty ? dsh.warning : dsh.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一张任务的面板：状态、负责人、前置、说明、时间线，和「开始 / 完成 / 取消」。
Future<void> openGroupTaskPanel(BuildContext context, {required String roomId, required String id}) =>
    showAppSheet<void>(
      context,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final view = ref.watch(groupTasksProvider(roomId)).value;
          final task = view?.task(id);
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: task == null || view == null
                  ? Text(context.l10n.botsTaskGone, style: Theme.of(context).textTheme.bodyMedium)
                  : GroupTaskPanel(view: view, task: task, roomId: roomId),
            ),
          );
        },
      ),
    );

class GroupTaskPanel extends ConsumerStatefulWidget {
  const GroupTaskPanel({super.key, required this.view, required this.task, required this.roomId});

  final DsBotTasksView view;
  final DsBotTask task;
  final String roomId;

  @override
  ConsumerState<GroupTaskPanel> createState() => _GroupTaskPanelState();
}

class _GroupTaskPanelState extends ConsumerState<GroupTaskPanel> {
  bool _busy = false;

  /// The task as the board has it now, not the copy the sheet opened with:
  /// a write bumps its revision and the sheet has to show the new one.
  DsBotTask get _task {
    final view = ref.read(groupTasksProvider(widget.roomId)).value;
    for (final task in view?.tasks ?? const <DsBotTask>[]) {
      if (task.id == widget.task.id) return task;
    }
    return widget.task;
  }

  Future<void> _update({String? status, String? assignee, String? verdict, String? acceptance}) async {
    if (_busy) return;
    final api = ref.read(dsBotProvider.notifier).api;
    if (api == null) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await api.taskUpdate(
        widget.roomId,
        _task.id,
        attemptId: _task.attemptId,
        rev: _task.rev,
        status: status,
        assignee: assignee,
        verdict: verdict,
        acceptance: acceptance,
      );
      ref.invalidate(groupTasksProvider(widget.roomId));
      ref.invalidate(_taskEventsProvider((roomId: widget.roomId, id: _task.id)));
    } catch (error) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    final api = ref.read(dsBotProvider.notifier).api;
    if (api == null) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await api.taskRemove(widget.roomId, _task.id, attemptId: _task.attemptId);
      ref.invalidate(groupTasksProvider(widget.roomId));
      ref.invalidate(_taskEventsProvider((roomId: widget.roomId, id: _task.id)));
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickOwner() async {
    final team = ref.read(dsBotProvider).team;
    final room = team?.room(widget.roomId);
    if (team == null || room == null) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final memberId in room.members)
              if (team.bot(memberId) case final member?)
                ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(member.name.isEmpty ? '?' : member.name.substring(0, 1)),
                  ),
                  title: Text(member.name),
                  selected: memberId == _task.assignee,
                  onTap: () => Navigator.of(context).pop(memberId),
                ),
          ],
        ),
      ),
    );
    if (picked != null && picked != _task.assignee) await _update(assignee: picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final small = theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary);
    final team = ref.watch(dsBotProvider.select((s) => s.team));
    ref.watch(groupTasksProvider(widget.roomId));
    final task = _task;
    final waiting = widget.view.waitingOn(task);
    final owner = task.assignee == null ? l10n.botsUnassigned : (team?.bot(task.assignee!)?.name ?? task.assignee!);
    final controlStyle = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: theme.textTheme.labelMedium,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(taskStateIcon(task), size: 16, color: taskStateColor(context, task)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task.title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(taskStateWord(l10n, task), style: theme.textTheme.labelSmall?.copyWith(color: taskStateColor(context, task))),
          ],
        ),
        const SizedBox(height: 10),
        Text(l10n.botsOwner, style: small),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(child: Text(owner, style: theme.textTheme.bodyMedium)),
            if (!task.fromGoal && !task.terminal)
              TextButton(onPressed: _busy ? null : _pickOwner, style: controlStyle, child: Text(l10n.botsTaskReassign)),
          ],
        ),
        if (task.deps.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l10n.botsDependencies, style: small),
          const SizedBox(height: 2),
          Text(
            waiting.isEmpty
                ? l10n.botsTaskReady
                : l10n.botsTaskBlocked(waiting.map((t) => t.shortId).join('、')),
            style: theme.textTheme.bodyMedium?.copyWith(color: waiting.isEmpty ? dsh.success : dsh.warning),
          ),
        ],
        if (task.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l10n.botsTaskNote, style: small),
          const SizedBox(height: 2),
          Text(task.note, style: theme.textTheme.bodyMedium),
        ],
        if (task.fromGoal) ...[
          const SizedBox(height: 8),
          Text(l10n.botsTaskFromGoal, style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary)),
        ],
        const SizedBox(height: 8),
        if (!task.fromGoal && !task.terminal)
          Row(
            children: [
              if (task.pending)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          if (waiting.isNotEmpty) {
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              SnackBar(content: Text(l10n.botsTaskBlocked(waiting.map((t) => t.shortId).join('、')))),
                            );
                            return;
                          }
                          _update(status: 'doing');
                        },
                  style: controlStyle,
                  child: Text(l10n.botsTaskStart),
                ),
              if (task.claimed || task.doing)
                TextButton(onPressed: _busy ? null : () => _update(status: 'done'), style: controlStyle, child: Text(l10n.commonDone)),
              const SizedBox(width: 4),
              TextButton(
                onPressed: _busy ? null : () => _update(status: 'cancelled'),
                style: controlStyle.copyWith(foregroundColor: WidgetStatePropertyAll(theme.colorScheme.error)),
                child: Text(l10n.botsTaskCancel),
              ),
              if (task.pending || task.terminal)
                TextButton(
                  onPressed: _busy ? null : _remove,
                  style: controlStyle,
                  child: Text(l10n.commonDelete),
                ),
            ],
          ),
        if (task.failed && !task.fromGoal)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : () => _update(status: 'pending'),
              style: controlStyle,
              child: Text(l10n.botsTaskReopen),
            ),
          ),
        const SizedBox(height: 12),
        Text(l10n.botsTaskTimeline, style: small),
        const SizedBox(height: 2),
        _TaskTimeline(roomId: widget.roomId, id: task.id),
      ],
    );
  }
}

/// 一条任务的时间线：最近的几条，翻不到底也够了。
class _TaskTimeline extends ConsumerWidget {
  const _TaskTimeline({required this.roomId, required this.id});

  final String roomId;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final events = ref.watch(_taskEventsProvider((roomId: roomId, id: id)));
    return switch (events) {
      AsyncData(:final value) when value.isEmpty => Text(
        l10n.botsTaskNoEvents,
        style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
      ),
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final event in value.skip(value.length > 20 ? value.length - 20 : 0))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                _eventLine(context, l10n, event),
                style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
              ),
            ),
        ],
      ),
      AsyncError() => Text(
        l10n.botsTaskNoEvents,
        style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
      ),
      _ => Text(
        l10n.botsTaskLoading,
        style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
      ),
    };
  }

  String _eventLine(BuildContext context, L10n l10n, DsBotTaskEvent event) {
    final time = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(event.at));
    final at = time.format(context);
    final who = event.by.isEmpty ? '' : '${event.by} ';
    final from = event.from ?? '';
    final to = event.to ?? '';
    final state = from.isEmpty || to.isEmpty ? '' : '$from → $to';
    return [at, who, event.kind, if (state.isNotEmpty) state, if (event.text.isNotEmpty) event.text].where((part) => part.isNotEmpty).join(' · ');
  }
}

final _taskEventsProvider = FutureProvider.autoDispose.family<List<DsBotTaskEvent>, ({String roomId, String id})>((ref, key) async {
  final api = ref.watch(dsBotProvider.notifier).api;
  if (api == null) return const [];
  try {
    return await api.taskEvents(key.roomId, key.id);
  } catch (_) {
    return const [];
  }
});

/// 「加一条」：标题、负责人（可空）、前置（可选）。
Future<void> showAddGroupTaskSheet(BuildContext context, String roomId) => showAppSheet<void>(
  context,
  isScrollControlled: true,
  builder: (sheetContext) => _AddTaskSheet(roomId: roomId),
);

class _AddTaskSheet extends ConsumerStatefulWidget {
  const _AddTaskSheet({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<_AddTaskSheet> {
  final _title = TextEditingController();
  final _selectedDeps = <String>{};
  String? _owner;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _title.text.trim();
    if (title.isEmpty || _busy) return;
    final api = ref.read(dsBotProvider.notifier).api;
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.taskAdd(
        widget.roomId,
        title: title,
        assignee: _owner,
        deps: _selectedDeps.toList(growable: false),
      );
      ref.invalidate(groupTasksProvider(widget.roomId));
      if (mounted) Navigator.of(context).maybePop();
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
    final team = ref.watch(dsBotProvider.select((s) => s.team));
    final room = team?.room(widget.roomId);
    final view = ref.watch(groupTasksProvider(widget.roomId)).value;
    final members = [for (final id in room?.members ?? const <String>[]) ?team?.bot(id)];
    final openTasks = [for (final task in view?.tasks ?? const <DsBotTask>[]) if (!task.closed) task];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.botsTaskAdd, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            autofocus: true,
            maxLength: 200,
            decoration: InputDecoration(hintText: l10n.botsTaskTitleHint, counterText: ''),
            onSubmitted: (_) => _add(),
          ),
          if (members.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l10n.botsOwner, style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text(l10n.botsUnassigned),
                  selected: _owner == null,
                  onSelected: (_) => setState(() => _owner = null),
                ),
                for (final member in members)
                  ChoiceChip(
                    label: Text(member.name),
                    selected: _owner == member.id,
                    onSelected: (_) => setState(() => _owner = member.id),
                  ),
              ],
            ),
          ],
          if (openTasks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l10n.botsDependencies, style: theme.textTheme.labelSmall?.copyWith(color: dsh.textTertiary)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final task in openTasks)
                  FilterChip(
                    label: Text(task.shortId),
                    selected: _selectedDeps.contains(task.id),
                    onSelected: (on) => setState(() => on ? _selectedDeps.add(task.id) : _selectedDeps.remove(task.id)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _add,
              child: Text(l10n.botsTaskSave),
            ),
          ),
        ],
      ),
    );
  }
}
