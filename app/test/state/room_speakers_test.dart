// A group line's `botId` is the Bot id. It looks like a Session id (a Bot's id
// is also its private Session's id), but it is not the member's Session in the
// group: that one lives in `room.sessions[botId]` and is only used for details
// and files. No reverse mapping exists — the host audit found 7/7 sender values
// in the Bot table and 0/7 in `room.sessions`.

import 'package:dsh_app/state/room_message_mode.dart';
import 'package:dsh_app/state/room_speakers.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bots/support.dart' show sampleTeam;

/// The sample team's group, with each member's Session in it named.
(DsBotTeam, DsBotRoom) _team() {
  final base = sampleTeam();
  final room = (base['rooms']! as List).first as Map<String, Object?>;
  final sessions = {
    for (final id in (room['members']! as List).cast<String>()) id: 'session-$id',
  };
  final data = <String, Object?>{...base, 'rooms': [{...room, 'sessions': sessions}]};
  final team = DsBotTeam.fromJson(data);
  return (team, team.room('r1')!);
}

DsBotItem _line(DsBotItemKind kind, String? botId, {String text = 'hi', int time = 1000}) =>
    DsBotItem(kind: kind, botId: botId, text: text, time: DateTime.fromMillisecondsSinceEpoch(time));

void main() {
  group('roomSpeakerId', () {
    test('a line names a Bot of the team', () {
      final (team, room) = _team();
      expect(roomSpeakerId(room, team, 'b2'), 'b2');
    });

    test('a group Session id is not a speaker: no reverse mapping', () {
      final (team, room) = _team();
      expect(roomSpeakerId(room, team, 'session-b2'), isNull);
      expect(roomSpeakerId(room, team, 'someone-else'), isNull);
      expect(roomSpeakerId(room, team, null), isNull);
      expect(roomSpeakerId(room, team, ''), isNull);
    });

    test('a line that lost its id still names a unique member', () {
      final (team, room) = _team();
      expect(roomSpeakerId(room, team, null, name: 'Writer'), 'b2');
      expect(roomSpeakerId(room, team, null, name: 'Nobody'), isNull);
    });

    test('two members with the same name decide nothing', () {
      final base = sampleTeam();
      final room = (base['rooms']! as List).first as Map<String, Object?>;
      final bots = [
        for (final bot in base['bots']! as List) {...(bot as Map<String, Object?>), 'name': 'Same'},
      ];
      final team = DsBotTeam.fromJson(<String, Object?>{...base, 'bots': bots, 'rooms': [room]});
      expect(roomSpeakerId(team.room('r1')!, team, null, name: 'Same'), isNull);
    });
  });

  group('roomSpeakerTimes', () {
    test('keeps the newest line per member, keyed by Bot id', () {
      final (team, room) = _team();
      final times = roomSpeakerTimes(room, team, [
        _line(DsBotItemKind.bot, 'b2', time: 1000),
        _line(DsBotItemKind.bot, 'b2', time: 3000),
        _line(DsBotItemKind.user, null, time: 5000),
        _line(DsBotItemKind.bot, 'unknown', time: 9000),
      ]);
      expect(times.keys, ['b2']);
      expect(times['b2']!.millisecondsSinceEpoch, 3000);
    });
  });

  group('memberTargetItems', () {
    test('keeps the member and the person, nothing else', () {
      final items = [
        _line(DsBotItemKind.user, null),
        _line(DsBotItemKind.bot, 'b2'),
        _line(DsBotItemKind.bot, 'b3'),
        _line(DsBotItemKind.event, 'b3'),
      ];
      final shown = memberTargetItems(items, 'b2');
      expect(shown.length, 2);
      expect(shown.first.kind, DsBotItemKind.user);
      expect(shown.last.botId, 'b2');
    });
  });

  group('visibleRoomItems member mode', () {
    test('matches on botId', () {
      final items = [
        _line(DsBotItemKind.user, null),
        _line(DsBotItemKind.bot, 'b2'),
        _line(DsBotItemKind.bot, 'b3'),
      ];
      final shown = visibleRoomItems(items, RoomMessageMode.member('b3'), memberNames: const []);
      expect(shown.length, 1);
      expect(shown.single.botId, 'b3');
    });
  });
}
