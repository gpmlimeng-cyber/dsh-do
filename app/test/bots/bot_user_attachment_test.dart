// 用户自己发的附件：Bot 私聊和群聊都要画成文件卡片，不是一段文字。
import 'package:dsh_app/ui/bots/bot_chat_page.dart';
import 'package:dsh_app/ui/bots/room_chat_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart' show loadTestFonts, usePhoneView;
import '../shell/golden_harness.dart' show goldenApp;
import 'support.dart';

Map<String, Object?> _userWithFile(String name) => {
  'kind': 'user',
  'text': '',
  'files': [
    {'id': 'sha256:${'a'.padRight(64, 'a')}', 'name': name, 'mediaType': 'text/plain'},
  ],
  'time': DateTime(2026, 1, 1, 10).millisecondsSinceEpoch,
};

Future<void> _frames(WidgetTester tester, [int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a user message with a file draws a card in the Bot chat', (tester) async {
    final fake = FakeDsBotTransport()..chatItems = [_userWithFile('report.txt')];
    usePhoneView(tester);
    await tester.pumpWidget(
      goldenApp(
        home: const BotChatPage(botId: 'm1'),
        brightness: Brightness.light,
        overrides: dsBotOverrides(fake),
      ),
    );
    await _frames(tester);
    expect(find.text('report.txt'), findsOneWidget);
  });

  testWidgets('a user message with a file draws a card in the group chat', (tester) async {
    final fake = FakeDsBotTransport()
      ..roomItems = [
        {
          'id': '1',
          'kind': 'user',
          'text': '',
          'files': [
            {'id': 'sha256:${'b'.padRight(64, 'b')}', 'name': 'notes.md', 'mediaType': 'text/markdown'},
          ],
          'time': DateTime(2026, 1, 1, 10).millisecondsSinceEpoch,
        },
      ];
    usePhoneView(tester);
    await tester.pumpWidget(
      goldenApp(
        home: const RoomChatPage(roomId: 'r1'),
        brightness: Brightness.light,
        overrides: dsBotOverrides(fake),
      ),
    );
    await _frames(tester);
    expect(find.text('notes.md'), findsOneWidget);
  });
}
