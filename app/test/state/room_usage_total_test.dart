// The group's context ring and its totals: an unknown figure must read as
// unknown, never as an empty context. Covers the "0 % while idle" bug.

import 'package:dsh_app/state/room_activity_state.dart';
import 'package:dsh_app/state/usage_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

RoomMemberActivity _member({
  int? used,
  int? projected,
  int? window,
  bool inGroup = true,
}) =>
    RoomMemberActivity(
      bot: const DsBot(id: 'bot', name: 'Bot'),
      pressureTokens: used,
      projectedTokens: projected,
      window: window,
      inGroup: inGroup,
    );

void main() {
  group('roomUsageTotal', () {
    test('a group with a window but no prompt size hides the ring', () {
      final totals = roomUsageTotal(
        const SessionUsage(contextWindow: 1048576),
        const RoomMembersActivity(members: []),
      );
      expect(totals.contextWindow, isNull);
      expect(totals.contextFraction, isNull);
    });

    test('a member reporting 0 tokens adds no empty window', () {
      final totals = roomUsageTotal(
        const SessionUsage(pressureTokens: 0, contextWindow: 1048576),
        RoomMembersActivity(members: [_member(used: 0, window: 1048576)]),
      );
      expect(totals.contextWindow, isNull);
      expect(totals.pressureTokens, isNull);
      expect(totals.contextFraction, isNull);
    });

    test('one measured member sets the share; idle and out-of-room rows do not', () {
      final totals = roomUsageTotal(
        const SessionUsage(contextWindow: 1048576), // idle group Session
        RoomMembersActivity(members: [
          _member(used: 60000, window: 1048576),
          _member(used: null, window: 1048576), // idle member: no measurement
          _member(used: 200000, window: 1048576, inGroup: false), // private, not the room's
        ]),
      );
      expect(totals.pressureTokens, 60000);
      expect(totals.contextWindow, 1048576);
      expect(totals.contextFraction, closeTo(0.0572, 0.0001));
    });

    test('the measured value beats a projection, as the group Session does', () {
      final totals = roomUsageTotal(
        SessionUsage.empty,
        RoomMembersActivity(members: [_member(used: 1000, projected: 4000, window: 10000)]),
      );
      expect(totals.pressureTokens, 1000);
    });
  });

  group('RoomMemberActivity.contextShare', () {
    test('hides an unmeasured row instead of drawing 0 %', () {
      expect(_member(used: 0, window: 1000).contextShare, isNull);
      expect(_member(window: 1000).contextShare, isNull);
      expect(_member(used: 1000).contextShare, isNull);
      expect(_member(used: 500, window: 1000).contextShare, 0.5);
    });
  });
}
