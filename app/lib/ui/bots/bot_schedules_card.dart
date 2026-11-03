// A Bot's automation tasks on its details page: the next few, by when they
// actually run next, and the way to the full list.

import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/header_schedule_state.dart';
import '../../state/schedule_editor_state.dart';
import '../chat/header_schedule_format.dart';
import '../common/list_page_row.dart';
import '../features/feature_kit.dart';
import '../features/schedule_editor/schedule_editor_page.dart';
import '../features/schedules_page.dart';
import '../theme/app_icons.dart';

/// The rows the card lists before the full page takes over.
const botSchedulesShown = 3;

class BotSchedulesCard extends ConsumerWidget {
  const BotSchedulesCard({super.key, required this.sessionId, required this.botName});

  /// The conversation the Bot's tasks belong to.
  final String sessionId;

  /// What the editor's run-location row calls that conversation.
  final String botName;

  /// Opens the editor on [task], or on a new task bound to this conversation.
  void _edit(BuildContext context, DateTime now, ScheduleTask? task) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScheduleEditorPage(
            task: task,
            now: now,
            sessionId: task == null ? sessionId : null,
            sessionLabel: task == null ? botName : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tasks = ref.watch(sessionSchedulesProvider(sessionId));
    // The device zone decides a rule that stores none of its own; until it
    // loads, say what the rule is and leave the next run out.
    final zone = ref.watch(deviceTimeZoneProvider).value;
    final now = ref.watch(scheduleClockProvider)();
    final list = tasks.value;
    final rows = [
      for (final task in list ?? const <ScheduleTask>[])
        (task: task, next: zone == null ? null : _nextRun(task, zone)),
    ]..sort((a, b) {
        final an = a.next;
        final bn = b.next;
        if (an == null) return bn == null ? 0 : 1;
        if (bn == null) return -1;
        return an.compareTo(bn);
      });
    return ListPageCard(
      title: l10n.featuresSchedules,
      children: [
        if (list == null && tasks.isLoading)
          const QuietSpinner(padding: EdgeInsets.symmetric(vertical: 16))
        else if (list == null)
          ListPageRow(
            icon: AppIcons.error,
            title: l10n.featuresSchedulesReadFailed,
            onTap: () => ref.invalidate(sessionSchedulesProvider(sessionId)),
          )
        else if (list.isEmpty)
          // Nothing scheduled yet: the row itself starts the first task here.
          ListPageRow(
            icon: AppIcons.add,
            title: l10n.commonNotSet,
            onTap: () => _edit(context, now, null),
          )
        else
          for (final row in rows.take(botSchedulesShown))
            ListPageRow(
              icon: AppIcons.scheduled,
              title: scheduleRuleLine(row.task, deviceZone: zone, at: now),
              subtitle: row.next == null ? null : scheduleStamp(row.next!, now),
              onTap: () => _edit(context, now, row.task),
            ),
        if (list != null && list.isNotEmpty)
          ListPageRow(
            icon: AppIcons.scheduled,
            title: l10n.featuresSchedules,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => SchedulesPage(sessionId: sessionId)),
            ),
          ),
      ],
    );
  }
}

/// When [task] really runs next, or null when the host committed none yet.
DateTime? _nextRun(ScheduleTask task, String zone) {
  final runs = scheduleNextRuns(task, deviceZone: zone, count: 1);
  return runs.isEmpty ? null : runs.first;
}
