// `@成员` 的识别与着色标记:规则抄网页版 `ds-bot/src/shared/mentions.js`
// (`mentionSpans`)与 `ds-bot/src/client/text.js`(`linkMentions`)。
import 'dart:ui' show Color;

import 'package:dsh_app/ui/chat/render/message_mentions.dart';
import 'package:flutter_test/flutter_test.dart';

const _chief = InlineMention(name: 'Chief', color: Color(0xFF123456));
const _pm = InlineMention(name: '产品经理', color: Color(0xFF654321));

List<String> _names(String text, List<String> names) =>
    [for (final span in mentionSpans(text, names)) span.name];

void main() {
  test('a member name is a mention, anything else is not', () {
    expect(_names('请 @Chief 看一下', ['Chief', '产品经理']), ['Chief']);
    expect(_names('请 @某人 看一下', ['Chief', '产品经理']), isEmpty);
    expect(_names('没有圈人', ['Chief']), isEmpty);
  });

  test('the match does not care about case', () {
    expect(_names('@chief 上', ['Chief']), ['Chief']);
  });

  test('the longest name wins', () {
    expect(_names('@新 Bot 2 你好', ['新 Bot', '新 Bot 2']), ['新 Bot 2']);
  });

  test('a longer word after the name is not a call', () {
    expect(_names('@MiniMax 的接口', ['Mini']), isEmpty);
    expect(_names('@docs/guide.md', ['docs']), isEmpty);
    expect(_names('@产品经理看这个', ['产品经理']), ['产品经理']);
  });

  test('an address is not a call', () {
    expect(_names('a@Chief', ['Chief']), isEmpty);
    expect(_names('medium.com/@Chief', ['Chief']), isEmpty);
    expect(_names('联系 @Chief。', ['Chief']), ['Chief']);
  });

  test('code and links stay literal', () {
    expect(_names('```\n@Chief\n```', ['Chief']), isEmpty);
    expect(_names('`@Chief`', ['Chief']), isEmpty);
    expect(_names('[@Chief](https://x.test)', ['Chief']), isEmpty);
  });

  test('marking keeps the words and pairs up', () {
    const text = '请 @Chief 和 @产品经理 看一下 `@Chief`';
    final marked = markMentions(text, [_chief, _pm]);
    expect(unmarkMentions(marked), text);
    expect(marked.contains('$mentionMarkOpen@Chief$mentionMarkClose'), isTrue);
    expect(marked.contains('$mentionMarkOpen@产品经理$mentionMarkClose'), isTrue);
    // 行内代码里的那个不算,原样留着。
    expect(marked.contains('`@Chief`'), isTrue);
  });

  test('nothing to mark leaves the text alone', () {
    expect(markMentions('没有圈人', [_chief]), '没有圈人');
    expect(markMentions('请 @某人 看一下', [_chief]), '请 @某人 看一下');
  });

  test('members are equal by name and ink', () {
    expect(const InlineMention(name: 'Chief', color: Color(0xFF123456)), _chief);
    expect(const InlineMention(name: 'Chief', color: Color(0xFF000000)) == _chief, isFalse);
  });
}
