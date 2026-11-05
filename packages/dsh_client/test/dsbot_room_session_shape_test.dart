import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

/// `room-chat` answers two shapes at once (plugin 0.2.8+): the old `items`
/// built from a capped `room.log`, and `sessionItems` with the group Session's
/// whole history. A phone reads the new one where it needs more than the last
/// lines — a member's conversation.
void main() {
  Map<String, Object?> page({Object? sessionItems, Object? sessionCursor}) => {
    'roomId': 'r1',
    'items': [
      {'id': '1', 'kind': 'user', 'text': 'hi', 'time': null},
    ],
    'cursor': {'beforeSeq': 1},
    if (sessionItems != null) 'sessionItems': sessionItems,
    if (sessionCursor != null) 'sessionCursor': sessionCursor,
    'running': false,
  };

  test('a host that sends the Session shape is read as such', () {
    final parsed = DsBotRoomPage.fromJson(
      page(
        sessionItems: [
          {'id': '9', 'kind': 'bot', 'botId': 'session-bot', 'name': 'Writer', 'text': 'words', 'time': 1000},
        ],
        sessionCursor: {'beforeSeq': 9},
      ),
    );
    expect(parsed.items, hasLength(1));
    expect(parsed.sessionItems, isNotNull);
    expect(parsed.sessionItems, hasLength(1));
    expect(parsed.sessionItems!.single.botId, 'session-bot');
    expect(parsed.sessionItems!.single.time, isNotNull);
    expect(parsed.sessionCursor, {'beforeSeq': 9});
  });

  test('an older host leaves the Session shape absent, not empty', () {
    final parsed = DsBotRoomPage.fromJson(page());
    expect(parsed.items, hasLength(1));
    expect(parsed.sessionItems, isNull);
    expect(parsed.sessionCursor, isNull);
  });
}
