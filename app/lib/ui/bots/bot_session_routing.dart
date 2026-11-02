// Where a searched conversation opens. A Bot's chat and a group chat are DSH
// Sessions like any other, so the Host's title/content search returns them;
// opening one of those ids in the plain chat shows a Session the person cannot
// drive (a message sent there never reaches the Bot). Route the hit to the Bot
// or group page instead.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/bots_state.dart';
import 'bot_chat_page.dart';
import 'room_chat_page.dart';

/// Opens the Bot or group page when [sessionId] is one of its chat Sessions,
/// and returns true so the caller keeps its own conversation route out of it.
///
/// Every part counts, past ones included: `BotChatPage` reads `chat(botId)`,
/// which walks all of a Bot's parts, and `RoomChatPage` reads the group's own
/// records — neither is tied to one Session id. A hit in a past part therefore
/// lands on the same page, where it can still be read and answered.
///
/// False — the caller's plain conversation route stays — only when DS Bot has
/// no team or the id belongs to neither a Bot nor a group.
///
/// [beforeOpen] runs after the match and before the navigation — the sessions
/// drawer closes itself there.
bool openTeamChatIfOwned(
  BuildContext context,
  WidgetRef ref,
  String sessionId, {
  VoidCallback? beforeOpen,
}) {
  final team = ref.read(dsBotProvider).team;
  if (team == null) return false;
  if (team.botOfSession(sessionId) case final bot?) {
    beforeOpen?.call();
    _open(context, BotChatPage.route(bot.id));
    return true;
  }
  if (team.roomOfSession(sessionId) case final room?) {
    beforeOpen?.call();
    _open(context, RoomChatPage.route(room.id));
    return true;
  }
  return false;
}

void _open(BuildContext context, Route<void> route) {
  final navigator = Navigator.of(context);
  // The search page can be opened from a feature page: land on the shell first,
  // the same way a plain conversation pick does.
  navigator.popUntil((r) => r.isFirst);
  unawaited(navigator.push(route));
}
