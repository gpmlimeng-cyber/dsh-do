// The light list row's status priority (M3): 等你确认 > 正在输入 > 已完成. The row
// takes its Bot, team and live state as parameters, so these pump it on its own —
// no page, no drawer, no connection.

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/bots_state.dart' show DsBotInbox;
import 'package:dsh_app/ui/bots/bot_format.dart' show workPhrase;
import 'package:dsh_app/ui/im/im_chat_row.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/support/harness.dart' show loadTestFonts, testApp, usePhoneView;
import 'support/im_fixtures.dart';

void main() {
  setUpAll(loadTestFonts);

  /// The state map with the question removed, so only the live work is left.
  Map<String, Object?> stateWithoutQuestion() {
    final state = approvalAndWorkTransport().handlers['state']!(<String, Object?>{}) as Map<String, Object?>;
    state['questions'] = <String, Object?>{};
    return state;
  }

  testWidgets('等你确认 wins over 正在输入 when a Bot has both', (tester) async {
    usePhoneView(tester);
    final state = approvalAndWorkTransport().handlers['state']!(<String, Object?>{}) as Map<String, Object?>;
    final team = DsBotTeam.fromJson(state);
    final live = DsBotLive.fromJson(state);
    final bot = team.bot('b2')!;
    await tester.pumpWidget(testApp(ImChatRow(
      bot: bot,
      team: team,
      live: live,
      inbox: const DsBotInbox(),
      onTap: () {},
    )));
    final l10n = tester.element(find.byType(ImChatRow)).l10n;
    expect(find.text(l10n.commonWaitingAnswer), findsOneWidget);
    final doing = workPhrase(live.bots['b2'], activity: live.activity['b2'], team: team);
    expect(doing, isNotNull);
    expect(find.text(doing!), findsNothing);
  });

  testWidgets('a Bot only working still reads as working', (tester) async {
    usePhoneView(tester);
    final state = stateWithoutQuestion();
    final team = DsBotTeam.fromJson(state);
    final live = DsBotLive.fromJson(state);
    final bot = team.bot('b2')!;
    await tester.pumpWidget(testApp(ImChatRow(
      bot: bot,
      team: team,
      live: live,
      inbox: const DsBotInbox(),
      onTap: () {},
    )));
    final l10n = tester.element(find.byType(ImChatRow)).l10n;
    final doing = workPhrase(live.bots['b2'], activity: live.activity['b2'], team: team);
    expect(doing, isNotNull);
    expect(find.text(doing!), findsOneWidget);
    expect(find.text(l10n.commonWaitingAnswer), findsNothing);
  });

  testWidgets('a Bot doing nothing at all falls back to its role', (tester) async {
    usePhoneView(tester);
    final state = stateWithoutQuestion();
    final team = DsBotTeam.fromJson(state);
    final live = DsBotLive.fromJson({
      'activity': <String, Object?>{},
      'work': {'bots': <String, Object?>{}, 'rooms': <String, Object?>{}, 'approvals': <Object?>[]},
    });
    final bot = team.bot('b2')!;
    await tester.pumpWidget(testApp(ImChatRow(
      bot: bot,
      team: team,
      live: live,
      inbox: const DsBotInbox(),
      onTap: () {},
    )));
    expect(find.text(bot.role), findsOneWidget);
  });
}
