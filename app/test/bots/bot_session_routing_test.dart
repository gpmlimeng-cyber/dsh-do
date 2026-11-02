// 搜索结果的落点: a hit on any part of a Bot's or group's Session opens that
// page, while an ordinary conversation keeps the plain chat route.

import 'package:dsh_app/ui/bots/bot_chat_page.dart';
import 'package:dsh_app/ui/bots/bot_session_routing.dart';
import 'package:dsh_app/ui/bots/room_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart' show loadTestFonts, usePhoneView;
import '../shell/golden_harness.dart' show goldenApp;
import 'support.dart';

Future<void> frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Stands in for the search page: one key that routes [id] like a picked hit.
class _Picked extends ConsumerWidget {
  const _Picked({required this.id, required this.result});

  final String id;
  final ValueSetter<bool> result;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => result(openTeamChatIfOwned(context, ref, id)),
        child: const Text('打开'),
      ),
    ),
  );
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<bool?> pick(WidgetTester tester, String id) async {
    bool? handled;
    usePhoneView(tester);
    await tester.pumpWidget(
      goldenApp(
        home: _Picked(id: id, result: (value) => handled = value),
        brightness: Brightness.light,
        overrides: dsBotOverrides(FakeDsBotTransport()),
      ),
    );
    await frames(tester);
    await tester.tap(find.text('打开'));
    await tester.pump();
    await frames(tester);
    return handled;
  }

  testWidgets('a Bot current Session opens its Bot page', (tester) async {
    expect(await pick(tester, 'm1c'), isTrue);
    expect(find.byType(BotChatPage), findsOneWidget);
    expect(tester.widget<BotChatPage>(find.byType(BotChatPage)).botId, 'm1');
  });

  testWidgets('a group current Session opens its group page', (tester) async {
    // This team's group has no separate `sessionId`: its id names the current part.
    expect(await pick(tester, 'r1'), isTrue);
    expect(find.byType(RoomChatPage), findsOneWidget);
    expect(tester.widget<RoomChatPage>(find.byType(RoomChatPage)).roomId, 'r1');
  });

  testWidgets('a past part still opens the Bot page', (tester) async {
    // 'm1' is Chief's earlier part (its `parts`), not the chat it reads now:
    // BotChatPage walks every part, so the hit belongs there all the same.
    expect(await pick(tester, 'm1'), isTrue);
    expect(find.byType(BotChatPage), findsOneWidget);
    expect(tester.widget<BotChatPage>(find.byType(BotChatPage)).botId, 'm1');
  });

  testWidgets('a past group part still opens the group page', (tester) async {
    // 'g2' is one of the group's earlier parts; its page reads the group's own
    // records, not one Session.
    expect(await pick(tester, 'g2'), isTrue);
    expect(find.byType(RoomChatPage), findsOneWidget);
    expect(tester.widget<RoomChatPage>(find.byType(RoomChatPage)).roomId, 'r1');
  });

  testWidgets('an ordinary conversation keeps the plain conversation route', (tester) async {
    expect(await pick(tester, 'plain-session'), isFalse);
    expect(find.byType(BotChatPage), findsNothing);
    expect(find.text('打开'), findsOneWidget);
  });

  testWidgets('without DS Bot every hit keeps the plain conversation route', (tester) async {
    bool? handled;
    usePhoneView(tester);
    // A transport whose team read fails: DS Bot is missing, so no team is known.
    final fake = FakeDsBotTransport()
      ..handlers['state'] = (_) => throw Exception('no ds-bot');
    await tester.pumpWidget(
      goldenApp(
        home: _Picked(id: 'm1c', result: (value) => handled = value),
        brightness: Brightness.light,
        overrides: dsBotOverrides(fake),
      ),
    );
    await frames(tester);
    await tester.tap(find.text('打开'));
    await tester.pump();
    await frames(tester);
    expect(handled, isFalse);
    expect(find.byType(BotChatPage), findsNothing);
  });
}
