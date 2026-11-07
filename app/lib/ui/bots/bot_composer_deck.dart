// The composer's surroundings in a Bot's chat and in a group chat. The chat
// page owns all of these; here they are keyed by the Session behind the Bot
// (`bot.sessionId`) or by the group's own Session (`room.id`), which is what
// each slot reads.

import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show ModelSelection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/bots_state.dart';
import '../../state/chat_state.dart';
import '../../state/cloud_speech.dart';
import '../../state/connection_state.dart';
import '../../state/room_activity_state.dart' show roomMembersActivityProvider, roomUsageTotal;
import '../../state/session_modes.dart';
import '../../state/usage_state.dart';
import '../../state/voice_model_state.dart';
import '../../state/voice_state.dart';
import '../../state/voice_settings.dart';
import '../../usage/usage_stats.dart';
import '../../l10n/l10n.dart';
import '../common/app_sheet.dart' show SheetGroup, showAppSheet;
import '../common/sheet_title_bar.dart' show SheetTitleBar;
import '../chat/dock/chat_dock.dart';
import '../chat/dock/dock_pill.dart' show DockSlot;
import '../chat/dock/dock_stack.dart';
import '../chat/balance_widgets.dart' show LowBalanceBanner;
import '../chat/usage_sheet.dart' show ContextRing, showUsageSheet;
import '../session/session_tab.dart';
import '../chat/voice/voice_controller.dart';
import '../chat/widgets/activity_strip.dart';
import '../chat/widgets/permission_pill.dart';
import '../chat/widgets/plus_panel.dart' show showPermissionSheet;
import '../plugins/native/composer_strip.dart';
import '../plugins/native/native_composer_bar.dart';
import '../safe_mode/safe_mode_banner.dart';
import '../settings/settings_widgets.dart' show SettingsTile;
import '../theme/app_icons.dart';
import '../theme/theme.dart' show DshColors;
import 'room_activity_strip.dart' show RoomStatus;
import 'room_aggregate_details_page.dart';

/// Everything the native composer carries above itself: the safe-mode banner,
/// the permission pill, the status deck (todo, goal, activity, a plugin's status
/// line) and the plugin / ui.json capsule row. Each is zero high when empty.
class BotComposerDeck extends ConsumerWidget {
  const BotComposerDeck({
    super.key,
    required this.sessionId,
    required this.running,
    this.showSessionBars = true,
    this.roomActivity,
    this.activitySessionId,
    this.showActivity = true,
    this.onRoomActivityTap,
  });

  final String sessionId;
  final bool running;

  /// The todo, goal and permission parts speak of one conversation. A group has
  /// no single one of those, so its deck keeps the activity and plugin strips.
  /// (The activity strip used to be gated by this too, which contradicted it.)
  final bool showSessionBars;

  /// A tap on the group's status line: the group's own activity figures. Null
  /// leaves the line without one.
  final VoidCallback? onRoomActivityTap;

  /// A group's own status line. Null in a Bot's chat, where the activity strip
  /// reads a single turn; a group has no single turn to read.
  final RoomStatus? roomActivity;

  /// The Session the activity strip reads when there is no [roomActivity]:
  /// a Bot's own Session, or the member whose conversation the group shows.
  /// Null falls back to [sessionId].
  final String? activitySessionId;

  /// False when the page knows there is no strip to show (a member target with
  /// no Session in this group yet): the deck stays quiet instead of reading a
  /// Session that is not the one on screen.
  final bool showActivity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 「自动允许中 ×」 while everything runs unlocked, else 「⚠ 完全权限」 when the
    // conversation is looser than 工作区内修改. As in the chat page: in the
    // capsule row while idle, beside the activity strip while a turn runs.
    final autoApprove =
        showSessionBars && ref.watch(chatProvider(sessionId).select((s) => s.autoApprove));
    final preset = showSessionBars
        ? ref.watch(sessionModesProvider(sessionId).select((m) => m.risky ? m.preset : null))
        : null;
    void disableAutoApprove() => ref.read(chatProvider(sessionId).notifier).setAutoApprove(false);
    void openPermissions() => unawaited(showPermissionSheet(context, sessionId));

    Widget? capsule() {
      if (autoApprove) return AutoApprovePill(onDisable: disableAutoApprove);
      if (preset == null) return null;
      return PermissionPill(preset: preset, onTap: openPermissions);
    }

    Widget? stripRisk() {
      if (autoApprove) return StripRiskChip.autoApprove(context, onDisable: disableAutoApprove);
      if (preset == null) return null;
      return StripRiskChip.permission(context, preset: preset, onTap: openPermissions);
    }

    // The capsule row gives way to the deck while anything is happening: a
    // member running, or a member waiting for an answer. Idle, it leads.
    final busy = running || roomActivity?.waiting == true || roomActivity?.activity != null;
    final pillsInCapsules = !busy;
    final shownCapsule = pillsInCapsules ? capsule() : null;
    // The chat page draws the low-balance reminder above everything else, and
    // only while connected: a message fails on a spent balance in a Bot's chat
    // and in a group of one too, so both get the same line.
    final connected = ref.watch(activeConnectionProvider).value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (connected)
          const Padding(padding: EdgeInsets.only(bottom: 8), child: LowBalanceBanner())
        else
          const SizedBox(width: double.infinity),
        // Safe mode / trial banner; draws nothing otherwise.
        const SafeModeBanner(padding: EdgeInsets.only(bottom: 8)),
        BackdropGroup(
          child: DockStack(
            cards: [
              if (showSessionBars) ...[
                TodoDockSlot(sessionId: sessionId),
                GoalDockSlot(sessionId: sessionId),
              ],
              // A group speaks through the upstream strip alone: it shows the
              // member who is running, read from that member's Session in this
              // group, and how many are running is in the group's own header.
              if (!showActivity) ...[] else if (roomActivity case final status?) ...[
                // One strip, and the upstream one: 「另外还有 N 位在跑」 as its
                // own card floated above the composer on a second layer, and the
                // group's own header already says how many are running.
                ActivityStripSlot(
                  sessionId: status.sessionId ?? activitySessionId ?? sessionId,
                  onTap: onRoomActivityTap,
                  todoProgress: !showSessionBars,
                ),
              ] else
                ActivityStripSlot(sessionId: activitySessionId ?? sessionId),
              ComposerStripSlot(sessionId: sessionId, visible: !running),
            ],
            // Running: the permission chip rides beside the activity strip,
            // which is the second row only while a turn runs.
            accessory: running ? stripRisk() : null,
          ),
        ),
        // The capsules (ui.json's and plugins') and, while idle, the permission
        // chip as their leading: one row, as the chat page has it.
        // The status line already rides in the deck as a card; not twice.
        NativeComposerBar(sessionId: sessionId, visible: !busy, strip: false, leading: shownCapsule),
      ],
    );
  }
}

/// The context ring beside a group's send key: the share of the group's *total*
/// window, the same figures the 上下文 tab shows. Nothing until those figures
/// arrive — a ring must not flicker — and nothing when no window is known.
class RoomContextRing extends ConsumerWidget {
  const RoomContextRing({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(dsBotProvider.select((s) => s.team));
    final room = team?.room(roomId);
    if (room == null) return const SizedBox.shrink();
    final sessionId = room.sessionId;
    final usage = sessionId == null ? SessionUsage.empty : ref.watch(sessionUsageProvider(sessionId));
    final members = ref.watch(roomMembersActivityProvider(roomId)).value;
    if (members == null) return const SizedBox.shrink();
    final fraction = roomUsageTotal(usage, members).contextFraction;
    if (fraction == null) return const SizedBox.shrink();
    return ContextRing(
      fraction: fraction,
      onTap: () => Navigator.of(context).push(
        RoomAggregateDetailsPage.route(roomId, initialTab: SessionTab.context),
      ),
    );
  }
}

/// The context ring beside the send key, for a conversation that has a model
/// and a context window of its own.
class BotContextRing extends ConsumerWidget {
  const BotContextRing({super.key, required this.sessionId, required this.model});

  final String sessionId;
  final ModelSelection? model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fraction = ref.watch(sessionUsageProvider(sessionId).select((s) => s.contextFraction));
    if (fraction == null) return const SizedBox.shrink();
    return ContextRing(
      fraction: fraction,
      onTap: () => showUsageSheet(context, sessionId: sessionId, model: model),
    );
  }
}

/// The composer's microphone, built the way the chat page builds it. [alive]
/// keeps a probe that finishes after the page is gone from touching anything.
VoiceInputController createBotVoice(
  WidgetRef ref,
  TextEditingController input, {
  required bool Function() alive,
}) => VoiceInputController(
  input: input,
  bridge: ref.read(voiceBridgeProvider),
  mode: () => ref.read(voiceSettingsProvider.notifier).ready(),
  // 云端 is the app's own call, on the providers the app already reads.
  cloud: () => alive() ? resolveCloudSpeechModelFrom(ref) : Future<CloudSpeechModel?>.value(),
  // The voice model lives in the on-device engine: it counts for that host only.
  modelReady: () =>
      alive() &&
      (ref.read(activeConnectionProvider).value?.isLocal ?? false) &&
      ref.read(voiceModelProvider).status == VoiceModelStatus.ready,
  hostIsLocal: () => alive() && (ref.read(activeConnectionProvider).value?.isLocal ?? false),
  client: () => alive() ? ref.read(activeConnectionProvider).value?.client : null,
  onRecognized: () {
    if (alive()) ref.read(usageStatsProvider.notifier).count(UsageCount.voice);
  },
);

/// 长按发送键 while a turn runs: how the message reaches it.
///
/// 插话 is off everywhere for now: DS Bot's `send` ignores the mode it is given
/// (`queue` is hard-coded there), so offering it would name a behaviour the
/// host does not have. Turn it on when the host reads `mode`.
Future<SendMode?> showBotSendOptions(BuildContext context, {bool steer = false}) => showAppSheet<SendMode>(
  context,
  builder: (sheet) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitleBar(appL10n.chatSendMode),
        SheetGroup(
          margin: const EdgeInsets.symmetric(horizontal: SheetTitleBar.inset),
          children: [
            for (final (mode, icon, title, subtitle) in [
              if (steer) (SendMode.steer, AppIcons.steer, appL10n.chatSteer, appL10n.chatSteerHint),
              (SendMode.interrupt, AppIcons.interrupt, appL10n.chatInterruptAndSend, appL10n.chatInterruptHint),
              (SendMode.queue, AppIcons.queued, appL10n.chatQueue, appL10n.chatQueueHint),
            ])
              SettingsTile(
                tinted: false,
                chevron: false,
                icon: icon,
                title: title,
                subtitle: subtitle,
                onTap: () => Navigator.pop(sheet, mode),
              ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    ),
  ),
);

/// The wire value of a send mode. `interrupt` is a stop plus a queued send:
/// DSH keeps the inbox across a stop, so a prompt queued before it would wait
/// for whatever is sent next.
String botSendMode(SendMode mode) => mode == SendMode.steer ? 'steer' : 'queue';

/// 打断并发送 stops the turn first and then sends; the other modes only send.
/// One never happens without the other.
Future<void> runBotSend(
  SendMode mode, {
  required Future<void> Function() stop,
  required Future<void> Function(SendMode mode) send,
}) async {
  if (mode == SendMode.interrupt) await stop();
  await send(mode);
}

