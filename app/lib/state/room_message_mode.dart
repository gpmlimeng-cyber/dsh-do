// What a group chat shows: every line, or one member's lines.
//
// Kept per group for this run only: the group's mode is not written to
// preferences, so a launch always starts on 「全部」. A filter that outlived a
// launch made a quiet group look dead — the person saw one member's silence
// and thought nobody had said anything.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One group's mode: all lines, or one member's lines.
@immutable
class RoomMessageMode {
  const RoomMessageMode._(this.name, this.memberId);

  static const all = RoomMessageMode._('all', null);
  const RoomMessageMode.member(String id) : this._('member', id);

  /// `all` or `member`.
  final String name;

  /// The member whose lines are shown; null for 「全部」.
  final String? memberId;

  bool get isAll => name == 'all';

  /// What is stored in the in-memory map: `all`, `member:<botId>`.
  String get key => memberId == null ? name : 'member:$memberId';

  /// Reads a saved or shared key. `relevant` (the old guessed third mode) is
  /// read as `all`, never as an empty screen.
  static RoomMessageMode parse(String? key) {
    if (key != null && key.startsWith('member:')) {
      final id = key.substring('member:'.length);
      if (id.isNotEmpty) return RoomMessageMode.member(id);
    }
    return all;
  }

  @override
  bool operator ==(Object other) => other is RoomMessageMode && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// One group's mode, per group, for this run only. Local state: the host has no
/// setting for this and does not need one.
class RoomMessageModes extends Notifier<Map<String, RoomMessageMode>> {
  @override
  Map<String, RoomMessageMode> build() => const {};

  void set(String roomId, RoomMessageMode mode) {
    state = {...state, roomId: mode};
  }
}

final roomMessageModesProvider = NotifierProvider<RoomMessageModes, Map<String, RoomMessageMode>>(
  RoomMessageModes.new,
);

final roomMessageModeProvider = Provider.family<RoomMessageMode, String>(
  (ref, roomId) => ref.watch(roomMessageModesProvider.select((modes) => modes[roomId] ?? RoomMessageMode.all)),
);

/// [items] as [mode] shows them. Rendering only: pending lines, unread counts,
/// 「已说 N」 and the round's progress read the full list.
List<DsBotItem> visibleRoomItems(
  List<DsBotItem> items,
  RoomMessageMode mode, {
  String? Function(DsBotItem item)? speakerOf,
}) {
  if (mode.isAll) return items;
  final id = mode.memberId;
  if (id == null) return items;
  // A member's line carries the sender's Session id on this Host, so the
  // caller resolves the speaker (state/room_speakers.dart) when it can.
  return [
    for (final item in items)
      if ((speakerOf?.call(item) ?? item.botId) == id) item,
  ];
}

/// The lines one member's conversation in this group shows: their own and the
/// user's own. A message sent there is a group message — it must not vanish the
/// instant it lands — so the person's lines stay, and other members' lines stay
/// in the group chat.
List<DsBotItem> memberTargetItems(
  List<DsBotItem> items,
  String memberId, {
  String? Function(DsBotItem item)? speakerOf,
}) => [
  for (final item in items)
    if (item.kind == DsBotItemKind.user || (speakerOf?.call(item) ?? item.botId) == memberId) item,
];

/// [items] without a `done` line whose previous line is the same member's own
/// words: the words already say it finished. A `done` line is kept when it is
/// the only trace — the member answered PASS or only ran tools — and the data
/// itself is never dropped, only not drawn.
List<DsBotItem> withoutDoneEchoes(List<DsBotItem> items) {
  final kept = <DsBotItem>[];
  for (final item in items) {
    if (item.kind == DsBotItemKind.event && item.event == 'done' && kept.isNotEmpty) {
      final previous = kept.last;
      final words = previous.kind == DsBotItemKind.bot || previous.kind == DsBotItemKind.answer;
      if (words && previous.botId == item.botId && previous.text.trim().isNotEmpty) continue;
    }
    kept.add(item);
  }
  return kept;
}
