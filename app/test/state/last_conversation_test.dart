// 上次的会话: what a cold start reopens. The record is this phone's view state;
// a missing object never falls back to a "closest" one.

import 'dart:convert';

import 'package:dsh_app/state/bots_state.dart';
import 'package:dsh_app/state/last_conversation.dart';
import 'package:dsh_app/state/sessions_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DsBotTeam team({List<Map<String, Object?>> bots = const [], List<Map<String, Object?>> rooms = const []}) =>
    DsBotTeam.fromJson({'revision': 1, 'bots': bots, 'rooms': rooms});

Map<String, Object?> bot(String id) => {'id': id, 'name': id};

Map<String, Object?> room({required String id, List<String> members = const [], Map<String, String> sessions = const {}}) => {
  'id': id,
  'name': id,
  'members': members,
  'sessions': sessions,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the record', () {
    test('a session, a Bot and a member conversation survive a round trip', () {
      for (final memory in const [
        LastConversation(kind: LastConversationKind.session, id: 's1'),
        LastConversation(kind: LastConversationKind.bot, id: 'b1'),
        LastConversation(kind: LastConversationKind.room, id: 'r1', memberId: 'b2'),
      ]) {
        expect(LastConversation.fromJson(jsonDecode(jsonEncode(memory.toJson()))), memory);
      }
    });

    test('nonsense reads as nothing remembered', () {
      expect(LastConversation.fromJson(null), isNull);
      expect(LastConversation.fromJson({'kind': 'elsewhere', 'id': 'x'}), isNull);
      expect(LastConversation.fromJson({'kind': 'session', 'id': ''}), isNull);
      expect(LastConversation.fromJson({'kind': 'session', 'id': 7}), isNull);
    });
  });

  group('the store', () {
    test('remembers the last conversation and drops the old key', () async {
      SharedPreferences.setMockInitialValues({LastConversationStore.legacyKey: 'old-session'});
      final store = LastConversationStore();
      expect(await store.read(), const LastConversation(kind: LastConversationKind.session, id: 'old-session'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LastConversationStore.legacyKey), isNull);
      expect(prefs.getString(LastConversationStore.key), isNotNull);
      // Read once, then the new record answers; the migration cannot run twice.
      await store.rememberRoom('r1', memberId: 'b1');
      expect(await store.read(), const LastConversation(kind: LastConversationKind.room, id: 'r1', memberId: 'b1'));
    });

    test('forget leaves nothing to restore', () async {
      final store = LastConversationStore();
      await store.rememberBot('b1');
      await store.forget();
      expect(await store.read(), isNull);
    });
  });

  group('the decision', () {
    const session = LastConversation(kind: LastConversationKind.session, id: 's1');
    const botChat = LastConversation(kind: LastConversationKind.bot, id: 'b1');
    const roomChat = LastConversation(kind: LastConversationKind.room, id: 'r1');
    const memberChat = LastConversation(kind: LastConversationKind.room, id: 'r1', memberId: 'b1');

    test('waits while the answer is not in', () {
      expect(lastConversationAction(memory: session, sessions: null, team: null), LastConversationAction.wait);
      expect(lastConversationAction(memory: botChat, sessions: null, team: null), LastConversationAction.wait);
    });

    test('a native session that is gone lands on a new chat', () {
      expect(lastConversationAction(memory: session, sessions: const ['s2'], team: null), LastConversationAction.newChat);
      expect(lastConversationAction(memory: session, sessions: const ['s1'], team: null), LastConversationAction.openSession);
    });

    test('a removed Bot lands on a new chat, a present one opens its chat', () {
      final present = team(bots: [bot('b1')]);
      expect(lastConversationAction(memory: botChat, sessions: const [], team: present), LastConversationAction.openBot);
      expect(lastConversationAction(memory: botChat, sessions: const [], team: team()), LastConversationAction.newChat);
    });

    test('a group that is gone lands on a new chat', () {
      expect(lastConversationAction(memory: roomChat, sessions: const [], team: team()), LastConversationAction.newChat);
      final present = team(bots: [bot('b1')], rooms: [room(id: 'r1', members: ['b1'])]);
      expect(lastConversationAction(memory: roomChat, sessions: const [], team: present), LastConversationAction.openRoomChat);
    });

    test('a member target lands on the group when the member left or never spoke', () {
      final noSession = team(bots: [bot('b1')], rooms: [room(id: 'r1', members: ['b1'])]);
      expect(lastConversationAction(memory: memberChat, sessions: const [], team: noSession), LastConversationAction.openRoomChat);
      final gone = team(bots: [bot('b1')], rooms: [room(id: 'r1', members: const [])]);
      expect(lastConversationAction(memory: memberChat, sessions: const [], team: gone), LastConversationAction.openRoomChat);
      final spoke = team(
        bots: [bot('b1')],
        rooms: [
          room(id: 'r1', members: const ['b1'], sessions: const {'b1': 'g1'}),
        ],
      );
      expect(lastConversationAction(memory: memberChat, sessions: const [], team: spoke), LastConversationAction.openRoom);
    });
  });

  group('the controller', () {
    test('selecting a session remembers it, 新对话 forgets it', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(lastConversationStoreProvider);
      container.read(currentSessionProvider.notifier).select('s1');
      expect(await store.read(), const LastConversation(kind: LastConversationKind.session, id: 's1'));
      container.read(currentSessionProvider.notifier).select(null);
      expect(await store.read(), isNull);
      expect(container.read(currentSessionProvider.notifier).selectionRevision, 2);
    });
  });
}
