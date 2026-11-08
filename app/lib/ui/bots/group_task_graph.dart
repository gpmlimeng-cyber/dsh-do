// 群任务的图：节点按依赖分层从左到右排，曲线连前置，打开时缩到能看全。
// 双指缩放、手指拖动平移；点节点亮它的上下游，再点一下打开任务面板。
// 布局永远由依赖算，不做拖拽改位置（手机上拖就是平移画布）。

import 'dart:math' as math;

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'group_tasks.dart';

/// 一张任务的图，单独一页。
class GroupTaskGraphPage extends ConsumerWidget {
  const GroupTaskGraphPage({super.key, required this.roomId});

  final String roomId;

  static Route<void> route(String roomId) =>
      MaterialPageRoute<void>(builder: (_) => GroupTaskGraphPage(roomId: roomId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final all = ref.watch(groupTasksProvider(roomId)).value;
    final view = all?.manual;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.botsTasks)),
      body: view == null
          ? Center(child: Text(l10n.botsTaskLoading))
          : view.tasks.length < 2
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.botsTaskNoneOpen,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          : GroupTaskGraph(view: view, roomId: roomId),
    );
  }
}

/// 画布本体：算布局、画曲线、放节点。
class GroupTaskGraph extends StatefulWidget {
  const GroupTaskGraph({super.key, required this.view, required this.roomId});

  final DsBotTasksView view;
  final String roomId;

  @override
  State<GroupTaskGraph> createState() => _GroupTaskGraphState();
}

class _GroupTaskGraphState extends State<GroupTaskGraph> {
  static const _nodeW = 108.0;
  static const _nodeH = 48.0;
  static const _gapX = 56.0;
  static const _gapY = 14.0;
  static const _inset = 24.0;

  final _controller = TransformationController();
  String? _focus;
  bool _fitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GroupTaskGraph old) {
    super.didUpdateWidget(old);
    if (old.view.version != widget.view.version) _fitted = false;
  }

  /// 拓扑分层：没有前置的在第 0 层，其余取前置里最深的 +1。有环就当第 0 层。
  Map<String, int> _levels(List<DsBotTask> tasks) {
    final byId = {for (final task in tasks) task.id: task};
    final levels = <String, int>{};
    int level(String id, Set<String> path) {
      final cached = levels[id];
      if (cached != null) return cached;
      final task = byId[id];
      if (task == null || task.deps.isEmpty || !path.add(id)) return levels[id] = 0;
      var deepest = 0;
      for (final dep in task.deps) {
        deepest = math.max(deepest, level(dep, path));
      }
      path.remove(id);
      return levels[id] = deepest + 1;
    }

    for (final task in tasks) {
      level(task.id, <String>{});
    }
    return levels;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = widget.view.tasks;
    final byId = {for (final task in tasks) task.id: task};
    final levels = _levels(tasks);
    final rows = <int, int>{};
    final placed = <String, Rect>{};
    for (final task in tasks) {
      final column = levels[task.id] ?? 0;
      final row = rows[column] ?? 0;
      rows[column] = row + 1;
      placed[task.id] = Rect.fromLTWH(
        _inset + column * (_nodeW + _gapX),
        _inset + row * (_nodeH + _gapY),
        _nodeW,
        _nodeH,
      );
    }
    final columns = levels.values.fold<int>(0, (a, b) => math.max(a, b)) + 1;
    final deepestRow = rows.values.isEmpty ? 0 : rows.values.reduce((a, b) => math.max(a, b));
    final width = _inset * 2 + columns * _nodeW + (columns - 1) * _gapX;
    final height = _inset * 2 + deepestRow * _nodeH + (deepestRow) * _gapY + _nodeH;
    final related = <String>{};
    if (_focus != null) {
      related.add(_focus!);
      for (final dep in byId[_focus!]?.deps ?? const <String>[]) {
        related.add(dep);
      }
      for (final task in tasks) {
        if (task.deps.contains(_focus)) related.add(task.id);
      }
    }
    return LayoutBuilder(
      builder: (context, box) {
        if (!_fitted) {
          _fitted = true;
          final scale = math.min(1.0, math.min(box.maxWidth / width, box.maxHeight / height));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _controller.value = Matrix4.identity()..scale(scale);
          });
        }
        return InteractiveViewer(
          transformationController: _controller,
          constrained: false,
          minScale: 0.35,
          maxScale: 2.2,
          boundaryMargin: const EdgeInsets.all(120),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EdgePainter(
                      placed: placed,
                      tasks: tasks,
                      focus: _focus,
                      line: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
                      hot: theme.colorScheme.primary,
                    ),
                  ),
                ),
                for (final task in tasks)
                  Positioned.fromRect(
                    rect: placed[task.id]!,
                    child: _Node(
                      task: task,
                      dimmed: _focus != null && !related.contains(task.id),
                      focused: _focus == task.id,
                      onTap: () {
                        if (_focus == task.id) {
                          openGroupTaskPanel(context, roomId: widget.roomId, id: task.id);
                        } else {
                          setState(() => _focus = task.id);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 一个节点：编号、标题、底边一条状态色。
class _Node extends StatelessWidget {
  const _Node({required this.task, required this.dimmed, required this.focused, required this.onTap});

  final DsBotTask task;
  final bool dimmed;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final colors = theme.colorScheme;
    final tone = taskTone(context, task);
    final closed = task.closed;
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused ? colors.primary : dsh.textTertiary.withValues(alpha: 0.22),
                width: focused ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${task.shortId}',
                          style: AppType.tabular(
                            theme.textTheme.labelSmall!.copyWith(color: tone, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: closed ? dsh.textTertiary : colors.onSurface,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  height: 4,
                  color: tone.withValues(alpha: closed ? 0.35 : 0.9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 依赖曲线：从来源右中到目标左中。
class _EdgePainter extends CustomPainter {
  const _EdgePainter({
    required this.placed,
    required this.tasks,
    required this.focus,
    required this.line,
    required this.hot,
  });

  final Map<String, Rect> placed;
  final List<DsBotTask> tasks;
  final String? focus;
  final Color line;
  final Color hot;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final task in tasks) {
      final to = placed[task.id];
      if (to == null) continue;
      for (final dep in task.deps) {
        final from = placed[dep];
        if (from == null) continue;
        final lit = focus == null || focus == task.id || focus == dep;
        paint.color = lit && focus != null ? hot : line;
        paint.strokeWidth = lit && focus != null ? 2 : 1.4;
        final start = Offset(from.right, from.center.dy);
        final end = Offset(to.left, to.center.dy);
        final dx = math.max(28.0, (end.dx - start.dx) * 0.45);
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(start.dx + dx, start.dy, end.dx - dx, end.dy, end.dx, end.dy);
        canvas.drawPath(path, paint);
        // 箭头
        final arrow = Path()
          ..moveTo(end.dx - 5, end.dy - 3.5)
          ..lineTo(end.dx, end.dy)
          ..lineTo(end.dx - 5, end.dy + 3.5);
        canvas.drawPath(arrow, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) =>
      old.focus != focus || old.placed != placed || old.tasks != tasks || old.line != line;
}

/// 任务的状态色，图和清单共用一个口径。
Color taskTone(BuildContext context, DsBotTask task) {
  final dsh = DshColors.of(context);
  final colors = Theme.of(context).colorScheme;
  return switch (task.status) {
    'done' => dsh.success,
    'doing' => colors.primary,
    'claimed' => colors.primary.withValues(alpha: 0.7),
    'failed' => dsh.warning,
    _ => dsh.textTertiary,
  };
}
