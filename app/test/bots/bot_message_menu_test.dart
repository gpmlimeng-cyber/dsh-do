// 长按一条 Bot 或群的消息：只有「复制 / 分享」，不带原生会话那套引用、重生成、编辑。
import 'package:dsh_app/ui/bots/bot_chat_kit.dart';
import 'package:dsh_app/ui/chat/render/markdown_body.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart' show pumpFrames, testApp;

void main() {
  testWidgets('a Bot reply offers copy and share on long press', (tester) async {
    await tester.pumpWidget(testApp(const Scaffold(body: BotReplyText(text: '写好了'))));
    await tester.longPress(find.byType(MarkdownBody));
    await pumpFrames(tester, 4);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
    // 引用 is offered now; 重生成 belongs to a conversation, not to this line.
    expect(find.text('引用'), findsOneWidget);
    expect(find.text('重新生成'), findsNothing);
  });

  testWidgets('a line the person wrote offers the same two', (tester) async {
    await tester.pumpWidget(testApp(const Scaffold(body: BotUserMessage(text: '你好'))));
    await tester.longPress(find.text('你好'));
    await pumpFrames(tester, 4);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
  });

  testWidgets('a group line offers the same two', (tester) async {
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: GroupMessage(
            item: DsBotItem(kind: DsBotItemKind.bot, text: '收到'),
            bot: const DsBot(id: 'b1', name: 'Writer', sessionId: 'b1c'),
            continued: false,
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(MarkdownBody));
    await pumpFrames(tester, 4);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
    // 群聊不是会话：选择文字不该出现；引用现在是有的。
    expect(find.text('选择文字'), findsNothing);
    expect(find.text('引用'), findsOneWidget);
  });

  testWidgets('a file-only group line has no menu at all', (tester) async {
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: GroupMessage(
            item: const DsBotItem(kind: DsBotItemKind.bot, text: ''),
            bot: const DsBot(id: 'b1', name: 'Writer', sessionId: 'b1c'),
            continued: false,
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(GroupMessage));
    await pumpFrames(tester, 4);
    expect(find.text('复制'), findsNothing);
    expect(find.text('分享'), findsNothing);
  });
}
