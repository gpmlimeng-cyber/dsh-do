// The light-mode fixtures, each shape checked without a UI so a broken fixture
// fails here before the IM tests read it. The two widget tests run the divider
// and the long name through the pages that already exist: that is also the pro
// mode's baseline, which the `BotChatLook` change must keep unchanged.

import 'package:dsh_app/ui/bots/bot_chat_page.dart';
import 'package:dsh_app/ui/bots/bots_page.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bots/support.dart' show dsBotOverrides;
import '../../chat/support/harness.dart' show loadTestFonts, usePhoneView;
import '../../shell/golden_harness.dart' show goldenApp;
import 'support/im_fixtures.dart';

Future<void> frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('fixtures', () {
    test('three parts page back through the cursor and its divider', () async {
      final api = DsBotApi(threePartTransport());
      final current = await api.chat('m1');
      expect(current.items.map((item) => item.text).toList(), ['当前段的问题', '当前段的回答']);
      expect(current.cursor, isNotNull);

      final older = await api.chat('m1', cursor: current.cursor);
      expect(older.items.map((item) => item.text).toList(), ['第二段的问题', '第二段的回答', '']);
      expect(older.items.last.kind, DsBotItemKind.divider);
      expect(older.cursor, isNotNull);

      final oldest = await api.chat('m1', cursor: older.cursor);
      expect(oldest.items.map((item) => item.text).toList(), ['第一段的问题', '第一段的回答']);
      expect(oldest.cursor, isNull);
    });

    test('one Bot can be both awaiting an answer and working', () {
      final state = approvalAndWorkTransport().handlers['state']!(<String, Object?>{}) as Map<String, Object?>;
      final team = DsBotTeam.fromJson(state);
      final live = DsBotLive.fromJson(state);
      expect(team.questionOf(team.bot('b2')!), isNotNull);
      expect(live.bots['b2'], isNotNull);
      expect(live.activity['b2'], 'tool');
      expect(live.approvals.any((approval) => approval.botId == 'b2' && approval.answerable), isTrue);
    });

    test('the long-name fixture keeps the whole name in the data', () {
      final state = longNameTransport().handlers['state']!(<String, Object?>{}) as Map<String, Object?>;
      final team = DsBotTeam.fromJson(state);
      final bot = team.bots.firstWhere((bot) => bot.id == 'b2');
      final room = team.rooms.firstWhere((room) => room.id == 'r1');
      expect(bot.name, longBotName);
      expect(bot.name.length, greaterThan(40));
      expect(room.name, longRoomName);
    });

    test('the empty fixture is a team with no Bots or groups', () {
      final state = emptyTeamTransport().handlers['state']!(<String, Object?>{}) as Map<String, Object?>;
      final team = DsBotTeam.fromJson(state);
      expect(team.bots, isEmpty);
      expect(team.rooms, isEmpty);
      expect(team.mainBotIds, isEmpty);
    });

    test('one send fails offline and the next one goes through', () async {
      final api = DsBotApi(offlineSendTransport());
      await expectLater(api.send('m1', '你好'), throwsA(isA<DshRemoteException>()));
      await api.send('m1', '你好');
    });

    test('the divider fixture parses as a divider item', () async {
      final page = await DsBotApi(dividerTransport()).chat('m1');
      expect(page.items.first.kind, DsBotItemKind.divider);
      expect(page.cursor, isNull);
    });
  });

  testWidgets('a part divider renders as the earlier-part row', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(goldenApp(
      home: const BotChatPage(botId: 'm1'),
      brightness: Brightness.light,
      overrides: dsBotOverrides(dividerTransport()),
    ));
    await frames(tester);
    expect(find.text('更早的部分'), findsOneWidget);
  });

  testWidgets('a very long name stays one row and raises no layout error', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(goldenApp(
      home: const BotsPage(),
      brightness: Brightness.light,
      overrides: dsBotOverrides(longNameTransport()),
    ));
    await frames(tester);
    expect(find.text(longBotName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
