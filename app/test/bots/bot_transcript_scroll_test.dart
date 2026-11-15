// 反向列表里 pixels = 0 就是最新消息处：停在底部时不该出现「回到底部」。
import 'package:dsh_app/ui/bots/bot_chat_kit.dart';
import 'package:dsh_app/ui/theme/app_icons.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart' show pumpFrames, testApp;

void main() {
  List<BotRow> longList() => [
    for (var i = 0; i < 40; i++)
      BotItemRow(DsBotItem(kind: DsBotItemKind.bot, text: '第 $i 条消息，用来把列表撑长一点。')),
  ];

  bool hidden(WidgetTester tester) => tester
      .widget<IgnorePointer>(
        find.ancestor(of: find.byIcon(AppIcons.scrollToBottom), matching: find.byType(IgnorePointer)).first,
      )
      .ignoring;

  testWidgets('the way back down stays hidden while the newest row is in view', (tester) async {
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: BotTranscript(
            rows: longList(),
            topInset: 0,
            // Tall rows on purpose: the list has to really scroll past 600,
            // otherwise jumpTo(600) is clamped and the assertion below proves
            // nothing.
            rowBuilder: (context, row) => switch (row) {
              BotItemRow(:final item) => SizedBox(height: 40, child: Text(item.text)),
              _ => const SizedBox.shrink(),
            },
          ),
        ),
      ),
    );
    await pumpFrames(tester, 3);
    // Opened at the newest row.
    expect(hidden(tester), isTrue);

    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    // The premise of the third check, pinned so a smaller canvas cannot quietly
    // turn it into a no-op.
    expect(position.maxScrollExtent, greaterThan(600));
    position.jumpTo(0);
    await pumpFrames(tester, 2);
    expect(hidden(tester), isTrue);

    position.jumpTo(600);
    await pumpFrames(tester, 2);
    expect(hidden(tester), isFalse);
  });
}
