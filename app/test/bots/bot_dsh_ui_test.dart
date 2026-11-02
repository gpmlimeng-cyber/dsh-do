// 可视化回复：Bot 自己的会话和群里，```dsh-ui 围栏要画成原生卡片，
// 而不是落成一段代码 / 原始 JSON。
import 'package:dsh_app/ui/bots/bot_chat_page.dart';
import 'package:dsh_app/ui/bots/room_chat_page.dart';
import 'package:dsh_app/ui/chat/dsh_ui/dsh_ui_block.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart' show loadTestFonts, usePhoneView;
import '../shell/golden_harness.dart' show goldenApp;
import 'support.dart';

const _reply = '前一句\n\n```dsh-ui\n{"type":"metric","label":"月均","value":"¥4,180"}\n```';

Future<void> _frames(WidgetTester tester, [int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a Bot reply draws its dsh-ui view', (tester) async {
    final fake = FakeDsBotTransport()
      ..chatItems = [
        {'kind': 'bot', 'text': _reply, 'time': DateTime.now().millisecondsSinceEpoch},
      ];
    usePhoneView(tester);
    await tester.pumpWidget(
      goldenApp(
        home: const BotChatPage(botId: 'm1'),
        brightness: Brightness.light,
        overrides: dsBotOverrides(fake),
      ),
    );
    await _frames(tester);
    expect(find.byType(DshUiBlock), findsOneWidget);
    expect(find.textContaining('{"type":"metric"'), findsNothing);
  });

  testWidgets('a group Bot reply draws its dsh-ui view', (tester) async {
    final fake = FakeDsBotTransport()
      ..roomItems = [
        {'kind': 'user', 'text': '画个图', 'time': DateTime.now().millisecondsSinceEpoch - 60000},
        {
          'id': 'c1:0',
          'kind': 'bot',
          'botId': 'm1',
          'name': 'Chief',
          'text': _reply,
          'time': DateTime.now().millisecondsSinceEpoch,
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
    expect(find.byType(DshUiBlock), findsOneWidget);
  });
}
