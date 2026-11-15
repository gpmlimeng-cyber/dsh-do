// The drawer's highlight follows the page on top: a Bot or a group chat lights
// its own row and leaves no Session row current; backing out lights the
// Session being looked at again.

import 'package:dsh_app/state/bots_state.dart';
import 'package:dsh_app/state/drawer_view_state.dart';
import 'package:dsh_app/state/session_attention_state.dart';
import 'package:dsh_app/state/sessions_state.dart';
import 'package:dsh_app/state/workspaces_state.dart';
import 'package:dsh_app/ui/shell/drawer/drawer_list.dart';
import 'package:dsh_app/ui/shell/drawer/session_tile.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bots/support.dart' show FakeDsBotTransport, dsBotOverrides;
import '../shell/golden_harness.dart' show FakeCurrentSession, goldenApp, sampleNow;
import 'support.dart';

class _Workspaces extends WorkspacesController {
  @override
  WorkspacesState build() => const WorkspacesState(status: WorkspacesStatus.ready);
}

SessionSummary _session(String id, String title) => SessionSummary(
  sessionId: id,
  updatedAt: sampleNow,
  running: false,
  blank: false,
  agentAvailable: false,
  projections: SessionProjections(1, {'title': title}),
);

Future<ProviderContainer> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(storedView(const DrawerView(loaded: true)));
  await tester.pumpWidget(
    goldenApp(
      brightness: Brightness.light,
      overrides: [
        ...dsBotOverrides(FakeDsBotTransport()),
        drawerScopeProvider.overrideWithValue(
          DrawerScope(sessions: [_session('s1', '一'), _session('s2', '二')], bots: const [], scoped: false),
        ),
        workspacesProvider.overrideWith(_Workspaces.new),
        currentSessionProvider.overrideWith(() => FakeCurrentSession('s1')),
        pendingInteractionsProvider.overrideWith(() => FixedPending(const {})),
        unreadSessionIdsProvider.overrideWithValue(const {}),
      ],
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 600,
          child: DrawerConversationList(
            now: sampleNow,
            onClose: () {},
            onOpen: (_) {},
            onLongPress: (_) {},
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return ProviderScope.containerOf(tester.element(find.byType(DrawerConversationList)));
}

SessionTile _tile(WidgetTester tester, String key) => tester.widget<SessionTile>(find.byKey(ValueKey(key)));

void main() {
  testWidgets('a Bot or group chat lights its row and clears the Session row', (tester) async {
    final container = await _pump(tester);

    // The Session on screen is the current one.
    expect(_tile(tester, 'session-s1').current, isTrue);
    expect(_tile(tester, 'bot-m1').current, isFalse);

    // A Bot's chat covers the list: its own row lights, no Session row does.
    container.read(dsBotViewingProvider.notifier).set('m1');
    await tester.pump();
    expect(_tile(tester, 'bot-m1').current, isTrue);
    expect(_tile(tester, 'session-s1').current, isFalse);
    expect(_tile(tester, 'session-s2').current, isFalse);

    // A group's chat behaves the same.
    container.read(dsBotViewingProvider.notifier).set('r1');
    await tester.pump();
    expect(_tile(tester, 'bot-r1').current, isTrue);
    expect(_tile(tester, 'bot-m1').current, isFalse);
    expect(_tile(tester, 'session-s1').current, isFalse);

    // Back to the Session: the old row lights again, the chat row goes out.
    container.read(dsBotViewingProvider.notifier).leave('r1');
    await tester.pump();
    expect(_tile(tester, 'session-s1').current, isTrue);
    expect(_tile(tester, 'bot-r1').current, isFalse);
  });
}
