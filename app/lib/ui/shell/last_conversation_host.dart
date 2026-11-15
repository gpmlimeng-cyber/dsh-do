// Opens the conversation this phone was showing when it was last closed.
//
// One shot per launch: it waits for the sessions list and the DS Bot team (up
// to [waitFor] seconds), then either lands on that conversation or leaves the
// app on a new chat. It never picks a "closest" conversation when the one it
// remembers is gone: a wrong conversation that looks like a restore is worse
// than an empty one.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../../state/last_conversation.dart';
import '../../state/room_chat_target.dart';
import '../../state/sessions_state.dart';
import '../bots/bot_chat_page.dart';
import '../bots/room_chat_page.dart';
import '../common/brief_notice.dart';

class LastConversationHost extends ConsumerStatefulWidget {
  const LastConversationHost({super.key, required this.child});

  final Widget child;

  /// How long the first screen may wait for the sessions and the team before
  /// the launch gives up and shows a new chat.
  @visibleForTesting
  static const waitFor = Duration(seconds: 5);

  @override
  ConsumerState<LastConversationHost> createState() => _LastConversationHostState();
}

class _LastConversationHostState extends ConsumerState<LastConversationHost> {
  /// A choice was already made for this launch (a share, a shortcut, the
  /// person tapping something): nothing is restored over it.
  bool _spent = false;
  bool _loaded = false;
  LastConversation? _memory;
  Timer? _deadline;
  ProviderSubscription<Object?>? _sessionsWatch;
  ProviderSubscription<Object?>? _teamWatch;

  @override
  void initState() {
    super.initState();
    _sessionsWatch = ref.listenManual(sessionsProvider, (_, _) => _attempt());
    _teamWatch = ref.listenManual<DsBotStatus>(dsBotProvider, (previous, next) {
      if (previous?.team == null && next.team != null) _attempt();
    });
    _deadline = Timer(LastConversationHost.waitFor, () {
      if (!_spent) _spend();
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _sessionsWatch?.close();
    _teamWatch?.close();
    super.dispose();
  }

  Future<void> _load() async {
    final memory = await ref.read(lastConversationStoreProvider).read();
    if (!mounted) return;
    _loaded = true;
    _memory = memory;
    if (memory == null) {
      _spend();
      return;
    }
    _attempt();
  }

  /// Ends this launch's restore: whatever was remembered is not applied.
  void _spend() {
    if (_spent) return;
    _spent = true;
    _deadline?.cancel();
    _deadline = null;
  }

  void _attempt() {
    if (_spent || !_loaded) return;
    final memory = _memory;
    if (memory == null) {
      _spend();
      return;
    }
    // The person already chose a conversation: their choice stands.
    if (ref.read(currentSessionProvider.notifier).selectionRevision > 0) {
      _spend();
      return;
    }
    final sessions = ref.read(sessionsProvider).value;
    final team = ref.read(dsBotProvider).team;
    final action = lastConversationAction(
      memory: memory,
      sessions: sessions == null ? null : [for (final session in sessions) session.sessionId],
      team: team,
    );
    switch (action) {
      case LastConversationAction.wait:
        return; // Still within the deadline: keep waiting.
      case LastConversationAction.newChat:
        // What it named is gone; do not retry it next launch either, and say
        // so rather than opening the app on an unexplained empty chat.
        unawaited(ref.read(lastConversationStoreProvider).forget());
        _gone(
          memory.kind == LastConversationKind.session
              ? context.l10n.lastConversationMissingSession
              : context.l10n.lastConversationMissingObject,
        );
        _spend();
        return;
      case LastConversationAction.openSession:
        _spend();
        if (ref.read(currentSessionProvider) == null) {
          ref.read(currentSessionProvider.notifier).select(memory.id);
        }
        return;
      case LastConversationAction.openBot:
        _spend();
        _push(BotChatPage(botId: memory.id));
        return;
      case LastConversationAction.openRoom:
        _spend();
        _push(RoomChatPage(roomId: memory.id, initialTarget: RoomChatTarget.member(memory.memberId!)));
        return;
      case LastConversationAction.openRoomChat:
        _spend();
        _push(RoomChatPage(roomId: memory.id));
        return;
    }
  }

  /// Says, once the shell is up, why the app is on an empty chat.
  void _gone(String text) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showBriefNotice(context, text);
    });
  }

  /// Opens a page without the push transition: a cold start should not show a
  /// page sliding in over another one.
  void _push(Widget page) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.maybeOf(context);
      if (navigator == null) return;
      navigator.push(
        PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) => page,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
