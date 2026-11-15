// The light messages list: one flat list with no group headings, and pinned
// chats lifted into the tile area at the top instead of staying in the rows.
// Pinned state lives in `im.pinned` (`im_pinned.dart`).

import 'package:dsh_app/ui/im/im_chat_row.dart';
import 'package:dsh_app/ui/im/im_messages_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bots/support.dart' show FakeDsBotTransport, dsBotOverrides;
import '../../chat/support/harness.dart' show loadTestFonts, usePhoneView;
import '../../shell/golden_harness.dart' show goldenApp;

Future<void> frames(WidgetTester tester, [int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);

  Widget page() => ImMessagesPage(
    onOpenBot: (_) {},
    onOpenRoom: (_) {},
    onGoDiscover: () {},
  );

  Future<void> open(WidgetTester tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(goldenApp(
      brightness: Brightness.light,
      home: page(),
      overrides: dsBotOverrides(FakeDsBotTransport()),
    ));
    await frames(tester);
  }

  testWidgets('the list is flat and has no group headings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await open(tester);
    // Both languages, so the assertion does not depend on the suite's locale.
    for (final title in ['置顶', 'Pinned', '对话', 'Chats', '群聊', 'Groups']) {
      expect(find.text(title), findsNothing, reason: 'group heading "$title" must be gone');
    }
    // Chief, Writer and Coder stay in one flat list; the group is one more row.
    expect(find.byType(ImChatRow), findsNWidgets(3));
  });

  testWidgets('a pinned chat moves to the tiles and leaves the flat rows', (tester) async {
    SharedPreferences.setMockInitialValues({'im.pinned': ['bot:b2']});
    await open(tester);
    // Writer (b2) is pinned: its face is in the tile area, its row is gone.
    expect(find.text('Writer'), findsOneWidget);
    expect(find.descendant(of: find.byType(ImChatRow), matching: find.text('Writer')), findsNothing);
    // The other two Bots stay as flat rows.
    expect(find.byType(ImChatRow), findsNWidgets(2));
  });
}
