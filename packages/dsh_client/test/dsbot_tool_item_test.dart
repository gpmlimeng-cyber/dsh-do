// A tool call is an entry of the conversation now: the host sends its call id,
// the tool's name and whether it is running, done or failed — and nothing else,
// so the phone has nothing to expand.
import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

void main() {
  test('a tool entry keeps its call, name and status', () {
    final item = DsBotItem.fromJson({
      'kind': 'tool',
      'callId': 'c1',
      'name': 'read_file',
      'status': 'running',
      'time': 5,
    });
    expect(item.kind, DsBotItemKind.tool);
    expect(item.callId, 'c1');
    expect(item.toolName, 'read_file');
    expect(item.toolStatus, 'running');
  });

  test('an entry without a kind is still unknown, not a tool', () {
    expect(DsBotItem.fromJson({'text': 'hi'}).kind, DsBotItemKind.unknown);
  });
}
