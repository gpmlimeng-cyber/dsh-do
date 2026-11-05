// Who a group line came from.
//
// The Host writes a member's line with `botId = senderSessionId` (see the
// plugin's `mobile.js`: `source.senderSessionId`), and older lines with the
// Bot's own id. An event line carries the Bot id. Every reader that asks "which
// member said this" must resolve both against the room's member Sessions —
// never against a private Session, so a group line can only belong to a member
// of the group.

import 'package:dsh_client/dsh_client.dart';

/// The Bot id behind a sender id, or null when it names no member of [room].
String? roomSpeakerId(DsBotRoom room, DsBotTeam team, String? senderId) {
  if (senderId == null || senderId.isEmpty) return null;
  // Older lines, and every event line: the id is the Bot's.
  if (team.bot(senderId) != null) return senderId;
  // A member's line: the sender is that member's Session in this group.
  for (final id in room.members) {
    if (room.sessions[id] == senderId) return id;
  }
  return null;
}

/// [item]'s sender, when it is one of [room]'s members.
String? roomSpeakerOf(DsBotRoom room, DsBotTeam team, DsBotItem item) => roomSpeakerId(room, team, item.botId);

/// The newest line each member wrote in [items], by Bot id.
Map<String, DateTime> roomSpeakerTimes(DsBotRoom room, DsBotTeam team, List<DsBotItem> items) {
  final out = <String, DateTime>{};
  for (final item in items) {
    final id = roomSpeakerOf(room, team, item);
    final time = item.time;
    if (id == null || time == null) continue;
    final seen = out[id];
    if (seen == null || time.isAfter(seen)) out[id] = time;
  }
  return out;
}
