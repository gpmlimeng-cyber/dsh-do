import 'package:dsh_app/state/usage_state.dart' show SessionUsage, sessionUsageProvider;
import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/bots_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/features_state.dart' show permissionStateProvider;
import 'package:dsh_app/state/models_state.dart' show modelCatalogProvider;
import 'package:dsh_app/ui/bots/bot_details_page.dart';
import 'package:dsh_app/ui/bots/room_details_page.dart';
import 'package:dsh_app/ui/common/list_page_row.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart';
import '../shell/golden_harness.dart' as shell;
import '../shell/golden_harness.dart' show goldenApp;
import 'support.dart';
import 'package:dsh_app/state/chat_state.dart' show chatProvider, ChatState;
import 'package:dsh_app/state/sessions_state.dart' show sessionsProvider;
import 'package:dsh_app/state/workspaces_state.dart' show workspacesProvider;

class _Host extends ActiveHostController {
  @override
  HostRef build() => HostRef.local;
  @override
  void select(HostRef host) => state = host;
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final action in [
    'bot-delete',
    'room-delete',
    'bot-name',
    'room-name',
    'room-member',
    'memory-add',
    'memory-edit',
    'memory-delete',
  ]) {
    for (final switched in [false, true]) {
      testWidgets('$action target with switched=$switched', (tester) async {
        final old = FakeDsBotTransport(team: sampleTeam(working: false))..helloOnFeed = false;
        final next = FakeDsBotTransport(team: sampleTeam(working: false))..helloOnFeed = false;
        final endpoint = switch (action) {
          'bot-delete' => 'delete-bot',
          'room-delete' => 'delete-room',
          'bot-name' => 'update-bot',
          'room-name' || 'room-member' => 'update-room',
          'memory-edit' => 'memory-edit',
          'memory-delete' => 'memory-forget',
          _ => 'memory-add',
        };
        old.handlers[endpoint] = (_) => true;
        next.handlers[endpoint] = (_) => true;
        final isRoom = action.startsWith('room');
        usePhoneView(tester);
        await tester.pumpWidget(
          goldenApp(
            home: isRoom ? const RoomDetailsPage(roomId: 'r1') : const BotDetailsPage(botId: 'm1'),
            brightness: Brightness.light,
            overrides: [
              sessionsProvider.overrideWith(() => shell.FakeSessions(const [])),
              workspacesProvider.overrideWith(FakeWorkspaces.new),
              modelCatalogProvider.overrideWith((ref) async => testCatalog),
              permissionStateProvider.overrideWith((ref, sessionId) async => null),
              chatProvider.overrideWith2((id) => FakeChatController(id, const ChatState(loading: false))),
              activeHostProvider.overrideWith(_Host.new),
              sessionUsageProvider.overrideWith2((id) => FakeUsage(id, SessionUsage.empty)),
              activeConnectionProvider.overrideWith((ref) {
                final host = ref.watch(activeHostProvider);
                return AsyncData(
                  HostConnection(
                    client: fakeConnection.client,
                    label: host.id,
                    isLocal: host.isLocal,
                    kind: host.kind,
                    hostId: host.id,
                  ),
                );
              }),
              dsBotApiFactoryProvider.overrideWithValue((connection) => DsBotApi(connection.isLocal ? old : next)),
            ],
          ),
        );
        await frames(tester);
        // 详情页恢复后，「Bot 详情」是外层薄壳 + 页签里的 embedded 两份，
        // byType 会命中两处；容器是同一个，取第一个就够。
        final container = ProviderScope.containerOf(
          tester.element(isRoom ? find.byType(RoomDetailsPage) : find.byType(BotDetailsPage).first),
        );
        final label = switch (action) {
          'bot-delete' => appL10n.botsDeleteBot,
          'room-delete' => appL10n.botsDeleteGroup,
          'bot-name' => appL10n.botsBotName,
          'room-name' => appL10n.botsGroupName,
          'room-member' => 'Coder',
          'memory-edit' || 'memory-delete' => '回复尽量简短，先说结论',
          _ => appL10n.botsAddMemory,
        };
        // 详情的「信息」页签外层是水平页签，滚它到不了目标；只滚内容本身。
        // 文本也只在页签里那一份上点：`find.text` 全局找会连外层一起命中。
        final pane = isRoom ? find.byType(RoomDetailsPage) : find.byKey(const ValueKey('bot-info-m1'));
        final target = find.descendant(of: pane, matching: find.text(label));
        await tester.scrollUntilVisible(target, 250, scrollable: detailsScrollable(pane));
        // 详情页顶部有钉住的头部；`ensureVisible` 默认把目标对齐到视口顶，
        // 正好压在它下面（命中 `_RenderSliverPinnedPersistentHeader…`）。
        // 摆到中间，并且点整行（或按钮）而不是里面那段文字。
        final row = find.ancestor(of: target, matching: find.byType(ListPageRow));
        final tapTarget = row.evaluate().isEmpty ? target : row.last;
        await Scrollable.ensureVisible(tester.element(tapTarget), alignment: 0.45, duration: Duration.zero);
        await frames(tester);
        await tester.tap(tapTarget);
        await frames(tester);
        if (action == 'memory-edit') {
          await tester.tap(find.descendant(of: pane, matching: find.text(appL10n.commonEdit)));
          await frames(tester);
        }
        if (!action.endsWith('delete') && action != 'room-member') {
          await tester.enterText(find.byType(TextField), 'From the old host');
        }
        if (switched) container.read(activeHostProvider.notifier).select(const HostRef.ssh('next'));
        await frames(tester);
        expect(container.read(dsBotProvider).ready, isTrue);
        final confirm = action == 'room-member'
            ? appL10n.botsSetAdmin
            : action.endsWith('delete')
            ? appL10n.commonDelete
            : action == 'memory-add'
            ? appL10n.commonAdd
            : appL10n.commonSave;
        await tester.tap(
          action == 'memory-delete' || action == 'room-member'
              ? find.text(confirm)
              : find.widgetWithText(FilledButton, confirm),
        );
        await frames(tester);
        expect(next.endpoints, isNot(contains(endpoint)), reason: 'stale $action must not target new host');
        expect(
          old.endpoints,
          switched ? isNot(contains(endpoint)) : contains(endpoint),
          reason: 'only current $action may mutate original target',
        );
      });
    }
  }
}
