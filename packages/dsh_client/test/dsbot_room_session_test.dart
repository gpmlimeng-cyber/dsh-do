// A group's Session can move on: `id` only names its first part, and staging a
// file under the old one leaves the receipt where the prompt never looks.
import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

void main() {
  test('a group carries the Session it runs in now', () {
    final moved = DsBotRoom.fromJson({'id': 'r1', 'name': 'Ops', 'sessionId': 'r1-part2'});
    expect(moved.id, 'r1');
    expect(moved.sessionId, 'r1-part2');
  });

  test('an older host sends no Session, and the id stands in for it', () {
    final plain = DsBotRoom.fromJson({'id': 'r1', 'name': 'Ops'});
    expect(plain.sessionId, isNull);
  });
}
