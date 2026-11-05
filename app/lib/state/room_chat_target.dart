// Which conversation a group's chat page shows: the group itself, or one
// member's own conversation in it. Switching is page state — no route, no
// second data channel — so the group details page stays under the chat page and
// one back returns to it.

import 'package:flutter/foundation.dart';

@immutable
class RoomChatTarget {
  const RoomChatTarget._(this.memberId);

  /// The group chat: every line the mode lets through.
  static const all = RoomChatTarget._(null);

  /// One member's conversation in this group.
  const RoomChatTarget.member(String id) : this._(id);

  /// The member whose conversation is shown; null for the group chat.
  final String? memberId;

  bool get isAll => memberId == null;

  @override
  bool operator ==(Object other) => other is RoomChatTarget && other.memberId == memberId;

  @override
  int get hashCode => memberId.hashCode;

  @override
  String toString() => isAll ? 'RoomChatTarget.all' : 'RoomChatTarget.member($memberId)';
}
