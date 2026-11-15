import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/ui/bots/bot_chat_kit.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart';
import '../shell/golden_harness.dart' show goldenApp;

/// Bot 视图卡的逐节点渲染：认不出的节点不再连累整张卡，输入控件的值随提交走。
void main() {
  setUpAll(loadTestFonts);

  Future<({List<(String, Map<String, Object?>)> answers})> pumpCard(
    WidgetTester t,
    Map<String, Object?> view,
  ) async {
    final answers = <(String, Map<String, Object?>)>[];
    await t.pumpWidget(
      goldenApp(
        brightness: Brightness.light,
        home: Scaffold(
          body: BotViewCard(
            view: DsBotViewCard(id: 'native', title: '填报', view: view),
            onAnswer: (action, values) async {
              answers.add((action, values));
              return true;
            },
            onDismiss: () {},
          ),
        ),
      ),
    );
    return (answers: answers);
  }

  testWidgets('callout + form 能填能提交', (t) async {
    final card = await pumpCard(t, {
      'type': 'stack',
      'children': [
        {'type': 'callout', 'text': '请核对实际结果', 'tone': 'info'},
        {
          'type': 'form',
          'id': 'submit-form',
          'submitLabel': '提交',
          'fields': [
            {'id': 'name', 'label': '名字'},
          ],
        },
      ],
    });
    expect(find.text('请核对实际结果'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Ada');
    await t.tap(find.widgetWithText(FilledButton, '提交'));
    await t.pump();
    expect(card.answers, hasLength(1));
    expect(card.answers.single.$1, 'submit-form');
    expect((card.answers.single.$2['fields'] as Map)['name'], 'Ada');
  });

  testWidgets('chart 不影响别的内容，confirm 照样能点', (t) async {
    final card = await pumpCard(t, {
      'type': 'stack',
      'children': [
        {
          'type': 'chart',
          'categories': ['A', 'B'],
          'series': [
            {
              'values': [2, 5],
            },
          ],
        },
        {'type': 'text', 'text': '图表的说明'},
        {'type': 'confirm', 'id': 'ok', 'confirmLabel': '确认', 'cancelLabel': '取消'},
      ],
    });
    expect(find.text('图表的说明'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, '确认'));
    await t.pump();
    expect(card.answers.single.$1, 'ok');
    expect(card.answers.single.$2['confirmed'], true);
  });

  testWidgets('slider / number / toggle 的值跟着 submit 一起提交', (t) async {
    final card = await pumpCard(t, {
      'type': 'stack',
      'children': [
        {'type': 'slider', 'id': 'level', 'label': '等级', 'value': 2, 'min': 0, 'max': 4, 'step': 1},
        {'type': 'number', 'id': 'count', 'label': '数量', 'value': 3},
        {'type': 'toggle', 'id': 'allow', 'label': '允许', 'value': true},
        {'type': 'submit', 'id': 'go'},
      ],
    });
    await t.tap(find.widgetWithText(FilledButton, appL10n.commonSend));
    await t.pump();
    final inputs = card.answers.single.$2['inputs'] as Map;
    expect(inputs['level'], 2);
    expect(inputs['count'], 3);
    expect(inputs['allow'], true);
  });

  testWidgets('metric 的 caption 不再让整张卡退回网页', (t) async {
    final card = await pumpCard(t, {
      'type': 'stack',
      'children': [
        {'type': 'metric', 'label': '月均', 'value': '¥4,180', 'caption': '示例数据'},
        {'type': 'submit', 'id': 'done', 'label': '知道了'},
      ],
    });
    expect(find.text('示例数据'), findsOneWidget);
    expect(find.byKey(const ValueKey('bot-view-open-web')), findsNothing);
    await t.tap(find.widgetWithText(FilledButton, '知道了'));
    await t.pump();
    expect(card.answers, hasLength(1));
  });
}
