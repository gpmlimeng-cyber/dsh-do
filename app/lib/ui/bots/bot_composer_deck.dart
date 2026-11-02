// The composer's surroundings in a Bot's chat and in a group chat. The chat
// page owns all of these; here they are keyed by the Session behind the Bot
// (`bot.sessionId`) or by the group's own Session (`room.id`), which is what
// each slot reads.

import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show ModelSelection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/chat_state.dart';
import '../../state/connection_state.dart';
import '../../state/session_modes.dart';
import '../../state/usage_state.dart';
import '../../state/voice_model_state.dart';
import '../../state/voice_state.dart';
import '../../state/voice_settings.dart';
import '../../usage/usage_stats.dart';
import '../chat/dock/chat_dock.dart';
import '../chat/dock/dock_stack.dart';
import '../chat/usage_sheet.dart' show ContextRing, showUsageSheet;
import '../chat/voice/voice_controller.dart';
import '../chat/widgets/activity_strip.dart';
import '../chat/widgets/auto_approve_pill.dart';
import '../chat/widgets/permission_pill.dart';
import '../chat/widgets/plus_panel.dart' show showPermissionSheet;
import '../plugins/native/composer_strip.dart';
import '../plugins/native/native_composer_bar.dart';
import '../safe_mode/safe_mode_banner.dart';

/// Everything the native composer carries above itself: the safe-mode banner,
/// the permission pill, the status deck (todo, goal, activity, a plugin's status
/// line) and the plugin / ui.json capsule row. Each is zero high when empty.
class BotComposerDeck extends ConsumerWidget {
  const BotComposerDeck({
    super.key,
    required this.sessionId,
    required this.running,
    this.showSessionBars = true,
  });

  final String sessionId;
  final bool running;

  /// The todo, goal and permission parts speak of one conversation. A group has
  /// no single one of those, so its deck keeps the activity and plugin strips.
  final bool showSessionBars;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 「自动允许中 ×」 while everything runs unlocked, else 「⚠ 完全权限」 when the
    // conversation is looser than 工作区内修改.
    Widget? pill() {
      if (!showSessionBars) return null;
      if (ref.watch(chatProvider(sessionId).select((s) => s.autoApprove))) {
        return AutoApprovePill(
          onDisable: () => ref.read(chatProvider(sessionId).notifier).setAutoApprove(false),
        );
      }
      final preset = ref.watch(sessionModesProvider(sessionId).select((m) => m.risky ? m.preset : null));
      if (preset == null) return null;
      return PermissionPill(preset: preset, onTap: () => unawaited(showPermissionSheet(context, sessionId)));
    }

    final shownPill = pill();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Safe mode / trial banner; draws nothing otherwise.
        const SafeModeBanner(padding: EdgeInsets.only(bottom: 8)),
        if (shownPill case final shown?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(alignment: Alignment.centerLeft, child: shown),
          ),
        BackdropGroup(
          child: DockStack(
            cards: [
              if (showSessionBars) ...[
                TodoDockSlot(sessionId: sessionId),
                GoalDockSlot(sessionId: sessionId),
                ActivityStripSlot(sessionId: sessionId),
              ],
              ComposerStripSlot(sessionId: sessionId, visible: !running),
            ],
          ),
        ),
        // The capsules (ui.json's and plugins'); nothing at all without any.
        NativeComposerBar(sessionId: sessionId, visible: !running),
      ],
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
  // The voice model lives in the on-device engine: it counts for that host only.
  modelReady: () =>
      alive() &&
      (ref.read(activeConnectionProvider).value?.isLocal ?? false) &&
      ref.read(voiceModelProvider).status == VoiceModelStatus.ready,
  client: () => alive() ? ref.read(activeConnectionProvider).value?.client : null,
  onRecognized: () {
    if (alive()) ref.read(usageStatsProvider.notifier).count(UsageCount.voice);
  },
);
