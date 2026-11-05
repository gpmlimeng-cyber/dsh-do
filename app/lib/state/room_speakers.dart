import 'package:dsh_client/dsh_client.dart';

/// The Bot id behind a group line, or null when it names no member of [room].
///
/// `botId` is the Bot id on this Host (it looks like `session-<uuid>` because a
/// Bot's id is also its private Session's id), so there is no session→Bot
/// reverse mapping. A line whose id is missing (an older Host, or a relay path
/// that drops the source) still names its sender: the line carries `name`, and
/// a unique member name settles it.
String? roomSpeakerId(DsBotRoom room, DsBotTeam team, String? senderId, {String? name}) {
  if (senderId != null && senderId.isNotEmpty) {
    final bot = team.bot(senderId);
    if (bot != null) return bot.id;
  }
  final named = name?.trim();
  if (named == null || named.isEmpty) return null;
  String? found;
  for (final id in room.members) {
    final bot = team.bot(id);
    if (bot == null || bot.name != named) continue;
    if (found != null) return null; // two members share the name: not decided
    found = bot.id;
  }
  return found;
}

/// [item]'s sender among [room]'s members.
String? roomSpeakerOf(DsBotRoom room, DsBotTeam team, DsBotItem item) =>
    roomSpeakerId(room, team, item.botId, name: item.name);

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
