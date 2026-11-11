// 群会话的「信息」页签：只读摘要 + 一个入口。
//
// 能改的东西一律留在 ⋯「成员」那份群详情里——两处都能改必然漂移。这里不放任何
// 编辑动作、不列成员名单、不重复 hero 已有的群名与成员总数（那是群聚合页的事）。

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/adaptive_layout_state.dart';
import '../../state/bots_state.dart';
import '../common/list_page_row.dart';
import '../shell/adaptive/adaptive_scaffold.dart' show AdaptiveChrome;
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'room_details_page.dart';
import 'unavailable_message.dart';

class RoomInfoTab extends ConsumerWidget {
  const RoomInfoTab({super.key, required this.roomId});

  final String roomId;

  /// 打开群详情：宽屏落右栏（跟 ⋯「成员」同一处），窄屏 push 同一页。
  void _openDetails(BuildContext context, WidgetRef ref) {
    final layout = AdaptiveChrome.layoutOf(context);
    if (layout != null && layout.isExpanded && layout.panelAvailable) {
      ref.read(roomDetailsInPanelProvider.notifier).state = true;
      ref.read(layoutPrefsProvider.notifier).setPanelOpen(true);
      return;
    }
    Navigator.of(context).push(RoomDetailsPage.route(roomId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final status = ref.watch(dsBotProvider);
    final team = status.team;
    final room = team?.room(roomId);
    final unavailable =
        status.availability == DsBotAvailability.missing || status.availability == DsBotAvailability.outdated;
    if (team == null || room == null || unavailable) {
      return ListView(
        padding: const EdgeInsets.only(top: 16),
        children: [
          DsBotUnavailableMessage(status: status, goneIcon: AppIcons.groupChat, goneTitle: l10n.botsRoomGone),
        ],
      );
    }
    final memory = ref.watch(dsBotMemoryProvider((botId: null, roomId: room.id))).value;
    final approvals = status.live.approvals.where((a) => a.roomId == room.id && a.answerable).length;
    final admin = team.bot(room.admin);
    // 顶部一行：群主 · 记忆 · 待处理审批（0 就不说）。
    final summary = [
      admin?.name ?? l10n.botsAdmin,
      memory == null
          ? '—'
          : memory.entries.isEmpty
          ? l10n.botsNoMemory
          : '${memory.entries.length} ${l10n.botsMemoryUnit}',
      // 没有「待处理审批 N」这个文案键（本机改不了 l10n），先用现成那句话 + 数字。
      if (approvals > 0) '${l10n.botsMemberNeedsApproval} · $approvals',
    ].join(' · ');
    final notSet = l10n.commonNotSet;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(summary, style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary)),
        ),
        // 资料区：只读，点进来是群详情那座唯一编辑入口。
        ListPageCard(
          title: l10n.botsGroupChat,
          children: [
            ListPageRow(
              icon: AppIcons.folder,
              title: l10n.botsWorkingFolder,
              subtitle: room.workDir ?? notSet,
              subtitleMaxLines: 3,
              onTap: () => _openDetails(context, ref),
            ),
            ListPageRow(
              icon: AppIcons.announcement,
              title: l10n.botsGroupNotice,
              subtitle: room.notice.isEmpty ? notSet : room.notice,
              subtitleMaxLines: 3,
              onTap: () => _openDetails(context, ref),
            ),
            if (room.relayLimitDefault != null)
              ListPageRow(
                icon: AppIcons.pause,
                title: l10n.botsRelayLimit,
                subtitle: room.relayLimit?.toString() ?? l10n.botsRelayLimitDefault(room.relayLimitDefault!),
                onTap: () => _openDetails(context, ref),
              ),
            ListPageRow(
              icon: AppIcons.chart,
              title: l10n.botsMemory,
              subtitle: memory == null
                  ? '—'
                  : memory.entries.isEmpty
                  ? l10n.botsNoMemory
                  : '${memory.entries.length} ${l10n.botsMemoryUnit}',
              chevron: true,
              onTap: () => _openDetails(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // 唯一动作：跟 ⋯「成员」落到同一处。
        ListPageRow(
          key: const ValueKey('room-info-details'),
          icon: AppIcons.groupChat,
          title: '${l10n.botsMembers} · ${l10n.commonSettings}',
          chevron: true,
          onTap: () => _openDetails(context, ref),
        ),
      ],
    );
  }
}
