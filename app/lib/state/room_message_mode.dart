// What a group chat shows: every line, only what concerns the user, or one
// member's lines. Kept per group, stored beside the drawer's own preferences.

import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One group's mode: all lines, the lines that involve the user, or one
/// member's lines.
@immutable
class RoomMessageMode {
  const RoomMessageMode._(this.name, this.memberId);

  static const all = RoomMessageMode._('all', null);
  static const relevant = RoomMessageMode._('relevant', null);
  const RoomMessageMode.member(String id) : this._('member', id);

  /// `all`, `relevant`, or `member`.
  final String name;

  /// The member whose lines are shown; null for the other two modes.
  final String? memberId;

  bool get isAll => name == 'all';
  bool get isRelevant => name == 'relevant';

  /// What is stored: `all`, `relevant`, `member:<botId>`.
  String get key => memberId == null ? name : 'member:$memberId';

  static RoomMessageMode parse(String? key) {
    if (key == 'relevant') return relevant;
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

/// One group's mode, per group, remembered across launches. Local only: the
/// host has no setting for this and does not need one.
class RoomMessageModes extends Notifier<Map<String, RoomMessageMode>> {
  static const prefsKey = 'room_message_modes';

  /// Set once the stored modes are in; a pick made before that is kept in
  /// [_beforeLoad] and wins over the stored value.
  bool _loaded = false;
  final _beforeLoad = <String, RoomMessageMode>{};

  @override
  Map<String, RoomMessageMode> build() {
    unawaited(_load());
    return const {};
  }

  Future<void> _load() async {
    var stored = const <String, RoomMessageMode>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (!ref.mounted) return;
      if (raw != null) {
        final read = (jsonDecode(raw) as Map).cast<String, String>();
        stored = {for (final entry in read.entries) entry.key: RoomMessageMode.parse(entry.value)};
      }
    } catch (_) {
      // No preferences backend: every group stays on 「全部」.
    }
    _loaded = true;
    final picked = {..._beforeLoad};
    _beforeLoad.clear();
    state = {...stored, ...picked};
    if (picked.isNotEmpty) await _save();
  }

  Future<void> set(String roomId, RoomMessageMode mode) async {
    state = {...state, roomId: mode};
    if (!_loaded) {
      // The stored modes are still being read: keep this pick for [load].
      _beforeLoad[roomId] = mode;
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode({for (final entry in state.entries) entry.key: entry.value.key}));
    } catch (_) {
      // Remembered for this run only.
    }
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
///
/// 仅与我相关 is an approximation until the log carries `replyTo`/`round`: a
/// line counts while it sits in the stretch that starts with one of the user's
/// messages and holds no @mention of another member. The round's own event
/// lines stay, so the story does not fall apart.
List<DsBotItem> visibleRoomItems(
  List<DsBotItem> items,
  RoomMessageMode mode, {
  required List<String> memberNames,
}) {
  if (mode.isAll) return items;
  if (mode.memberId case final id?) {
    return [for (final item in items) if (item.botId == id) item];
  }
  final kept = <DsBotItem>[];
  var inMyStretch = false;
  for (final item in items) {
    switch (item.kind) {
      case DsBotItemKind.user:
        inMyStretch = true;
        kept.add(item);
      case DsBotItemKind.event || DsBotItemKind.divider:
        kept.add(item);
      case _:
        if (!inMyStretch) continue;
        if (_mentionsMember(item.text, memberNames)) {
          // The user's stretch ends where another member is addressed: what
          // follows is that member's conversation, not the user's.
          inMyStretch = false;
          continue;
        }
        kept.add(item);
    }
  }
  return kept;
}

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

bool _mentionsMember(String text, List<String> names) {
  for (final name in names) {
    if (name.isNotEmpty && text.contains('@$name')) return true;
  }
  return false;
}
