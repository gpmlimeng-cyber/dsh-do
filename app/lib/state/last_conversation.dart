// The conversation the app was showing when it was last closed.
//
// It is the whole of what the app remembers about where a person was: a native
// session, a Bot's chat, a group's chat, or one member's conversation in that
// group. Nothing of the page stack above it (a details page, a file list): a
// cold start lands on the conversation itself.
//
// It is this phone's view state, not the Host's: another device, or another
// Host, would land nowhere useful, and a missing id already degrades to a new
// chat (see [lastConversationAction]).

import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LastConversationKind { session, bot, room }

@immutable
class LastConversation {
  const LastConversation({required this.kind, required this.id, this.memberId, this.at});

  final LastConversationKind kind;

  /// The native session id, the Bot id, or the group id.
  final String id;

  /// For [LastConversationKind.room]: the member whose conversation was open,
  /// null for the group chat itself.
  final String? memberId;
  final DateTime? at;

  bool get isMember => kind == LastConversationKind.room && memberId != null;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'id': id,
    if (memberId case final member?) 'memberId': member,
    if (at case final at?) 'at': at.toUtc().toIso8601String(),
  };

  static LastConversation? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = switch (json['kind']) {
      'session' => LastConversationKind.session,
      'bot' => LastConversationKind.bot,
      'room' => LastConversationKind.room,
      _ => null,
    };
    final id = json['id'];
    if (kind == null || id is! String || id.isEmpty) return null;
    final memberId = json['memberId'];
    return LastConversation(
      kind: kind,
      id: id,
      memberId: memberId is String && memberId.isNotEmpty ? memberId : null,
      at: DateTime.tryParse(json['at'] is String ? json['at'] as String : ''),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LastConversation && other.kind == kind && other.id == id && other.memberId == memberId;

  @override
  int get hashCode => Object.hash(kind, id, memberId);

  @override
  String toString() => 'LastConversation(${kind.name}:$id${memberId == null ? '' : ':$memberId'})';
}

/// What a cold start should do with the remembered conversation.
enum LastConversationAction {
  /// Nothing to go on yet (the sessions or the team have not arrived): wait.
  wait,

  /// There is nothing remembered, or what it names is gone: a new chat.
  newChat,

  openSession,
  openBot,
  openRoom,

  /// The group is here but not that member's conversation: the group chat.
  openRoomChat,
}

/// The decision, on its own: no widget, no store, no route.
///
/// A remembered object that is gone never falls back to "the first" or "the
/// most recent" one — a person who is shown the wrong conversation believes the
/// restore worked. `sessions` null means the list has not been read yet; a
/// non-null `team` is the Host's answer for Bots and groups.
LastConversationAction lastConversationAction({
  required LastConversation memory,
  required List<String>? sessions,
  required DsBotTeam? team,
}) {
  switch (memory.kind) {
    case LastConversationKind.session:
      if (sessions == null) return LastConversationAction.wait;
      return sessions.contains(memory.id) ? LastConversationAction.openSession : LastConversationAction.newChat;
    case LastConversationKind.bot:
      if (team == null) return LastConversationAction.wait;
      return team.bot(memory.id) != null ? LastConversationAction.openBot : LastConversationAction.newChat;
    case LastConversationKind.room:
      if (team == null) return LastConversationAction.wait;
      final room = team.room(memory.id);
      if (room == null) return LastConversationAction.newChat;
      final member = memory.memberId;
      // A member who left the group, or whose conversation in it was never
      // opened, stands for nothing: the group chat is the honest landing.
      if (member != null && room.members.contains(member) && room.sessions.containsKey(member)) {
        return LastConversationAction.openRoom;
      }
      return LastConversationAction.openRoomChat;
  }
}

/// 上次的会话 in this phone's preferences.
///
/// One key, `last_conversation`, holding `{kind, id, memberId?, at}`. The old
/// `last_session_id` is read once, becomes a session record, and is removed.
class LastConversationStore {
  LastConversationStore();

  static const key = 'last_conversation';
  static const legacyKey = 'last_session_id';

  Future<LastConversation?> read() async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        final parsed = LastConversation.fromJson(jsonDecode(raw));
        if (parsed != null) return parsed;
      } catch (_) {
        // A record written by something else: read as nothing remembered.
      }
    }
    return _migrate(prefs);
  }

  Future<LastConversation?> _migrate(SharedPreferences prefs) async {
    final legacy = prefs.getString(legacyKey);
    if (legacy == null || legacy.isEmpty) return null;
    final migrated = LastConversation(kind: LastConversationKind.session, id: legacy, at: DateTime.now());
    try {
      await prefs.remove(legacyKey);
      await prefs.setString(key, jsonEncode(migrated.toJson()));
    } catch (_) {
      // Readable but not writable: this launch still opens it.
    }
    return migrated;
  }

  Future<void> remember(LastConversation memory) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(memory.toJson()));
    } catch (_) {
      // Preferences unavailable (tests) or unwritable: nothing is lost but the
      // memory of this conversation.
    }
  }

  Future<void> rememberSession(String sessionId) =>
      remember(LastConversation(kind: LastConversationKind.session, id: sessionId, at: DateTime.now()));

  Future<void> rememberBot(String botId) =>
      remember(LastConversation(kind: LastConversationKind.bot, id: botId, at: DateTime.now()));

  Future<void> rememberRoom(String roomId, {String? memberId}) =>
      remember(LastConversation(kind: LastConversationKind.room, id: roomId, memberId: memberId, at: DateTime.now()));

  Future<void> forget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove(legacyKey);
    } catch (_) {}
  }
}

final lastConversationStoreProvider = Provider<LastConversationStore>((ref) => LastConversationStore());
