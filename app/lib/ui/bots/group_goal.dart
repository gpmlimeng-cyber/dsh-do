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
import '../chat/dock/dock_pill.dart';
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

/// 顶栏上的探针：有目标画环；没目标画一颗灰点（点一下说明它问了什么、
/// 得到什么），方便一眼分清「后端没有目标」还是「画不出来」。
class GoalBarProbe extends ConsumerWidget {
  const GoalBarProbe({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 连接一就绪就回头取一次：api 只存在于控制器上，不改变 status，所以
    // 光靠 watch 依赖等不到它。
    ref.listen(dsBotProvider.select((s) => s.team != null), (previous, next) {
      if (next && previous != true) ref.invalidate(groupGoalProvider(roomId));
    });
    final style = ref.watch(settingsProvider.select((s) => s.goalBarStyle));
    final async = ref.watch(groupGoalProvider(roomId));
    final api = ref.read(dsBotProvider.notifier).api;
    return switch (async) {
      AsyncData(value: final goal?) when goal.title.isNotEmpty => GroupGoalPill(
        goal: goal,
        style: style,
        onTap: () => showGoalExpand(context, roomId),
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

/// 收起态那颗：简单模式只有一颗环，完整模式是「图标 + 标题 + 环」。
///
/// 与顶栏其他键同一套：44 高的玻璃底（[BotChatHeader.key44]、chrome、grouped），
/// 按下态由 GlassSurface 给，圆的给环、长的给胶囊。读屏只念一遍标题：外层把
/// 标题作标签，里面的文字与环都不再单独念。
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
    final ring = GoalRing(goal: goal, size: expandArrow ? 36 : 30, announce: false);
    if (style == GoalBarStyle.simple && !expandArrow) {
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
            child: Center(child: ring),
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
          borderRadius: DockMetrics.shape,
          grouped: true,
          onTap: onTap,
          child: Tooltip(
            message: goal.title,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
        if (goal.status == 'drafting')
          Text(
            // The title is already in the bar above: an echo here reads as two
            // different things saying the same words.
            goal.brief.isEmpty || goal.brief.trim() == goal.title.trim()
                ? l10n.chatGoalHint
                : goal.brief,
            style: theme.textTheme.bodyMedium,
          )
        else if (stage == null) ...[
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
        if (_checks && hasChecks) ...[
          const SizedBox(height: 6),
          if (goal.objective.isNotEmpty) _Block(label: l10n.chatGoal, value: goal.objective),
          if (goal.acceptance.isNotEmpty) _Block(label: l10n.chatGoalAcceptanceDone, value: goal.acceptance),
          for (final rule in goal.constraints) _Block(label: l10n.chatGoalRule, value: rule),
        ],
        const SizedBox(height: 6),
        // The web's foot: 「目标与验收」 on the left, the actions as one cluster
        // on the right, in the same order it uses.
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
            if (goal.status == 'paused' && working)
              TextButton(
                onPressed: _busy ? null : _stopWorkOnly,
                style: controlStyle,
                child: Text(l10n.chatStopWorkToo),
              ),
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
                child: Text(_armed ? '${l10n.commonStop}?' : l10n.commonStop),
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
  // The panel was looked at, not typed in: closing it must not hand the focus
  // (and the keyboard) back to the composer.
  FocusManager.instance.primaryFocus?.unfocus();
}

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
