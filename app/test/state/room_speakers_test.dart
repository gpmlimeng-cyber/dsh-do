// A group line's `botId` is the sender's Session id on this Host (the plugin
// writes `source.senderSessionId`); older lines carry the Bot id. Resolving both
// is what makes 「只看此成员」, the member conversation and the panel's "who has
// spoken" work at all.

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
    test('a member line names its sender Session', () {
      final (team, room) = _team();
      expect(roomSpeakerId(room, team, 'session-b2'), 'b2');
    });

    test('an older line names the Bot id itself', () {
      final (team, room) = _team();
      expect(roomSpeakerId(room, team, 'b2'), 'b2');
    });

    test('an id of nobody in this group is no member', () {
      final (team, room) = _team();
      expect(roomSpeakerId(room, team, 'session-someone-else'), isNull);
      expect(roomSpeakerId(room, team, null), isNull);
      expect(roomSpeakerId(room, team, ''), isNull);
    });
  });

  group('roomSpeakerTimes', () {
    test('keeps the newest line per member, keyed by Bot id', () {
      final (team, room) = _team();
      final times = roomSpeakerTimes(room, team, [
        _line(DsBotItemKind.bot, 'session-b2', time: 1000),
        _line(DsBotItemKind.bot, 'session-b2', time: 3000),
        _line(DsBotItemKind.user, null, time: 5000),
        _line(DsBotItemKind.bot, 'unknown-session', time: 9000),
      ]);
      expect(times.keys, ['b2']);
      expect(times['b2']!.millisecondsSinceEpoch, 3000);
    });
  });

  group('memberTargetItems', () {
    test('keeps the member and the person, nothing else', () {
      final (team, room) = _team();
      final items = [
        _line(DsBotItemKind.user, null),
        _line(DsBotItemKind.bot, 'session-b2'),
        _line(DsBotItemKind.bot, 'session-b3'),
        _line(DsBotItemKind.event, 'b3'),
      ];
      final shown = memberTargetItems(
        items,
        'b2',
        speakerOf: (item) => roomSpeakerOf(room, team, item),
      );
      expect(shown.length, 2);
      expect(shown.first.kind, DsBotItemKind.user);
      expect(shown.last.botId, 'session-b2');
    });
  });

  group('visibleRoomItems member mode', () {
    test('resolves the speaker instead of trusting the raw id', () {
      final (team, room) = _team();
      final items = [
        _line(DsBotItemKind.user, null),
        _line(DsBotItemKind.bot, 'session-b2'),
        _line(DsBotItemKind.bot, 'session-b3'),
      ];
      final shown = visibleRoomItems(
        items,
        RoomMessageMode.member('b3'),
        memberNames: const [],
        speakerOf: (item) => roomSpeakerOf(room, team, item),
      );
      expect(shown.length, 1);
      expect(shown.single.botId, 'session-b3');
    });
  });
}
