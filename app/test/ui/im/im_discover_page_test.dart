// 轻松模式的「发现」页：原生 2 列 `FeatureCard` 卡片，不是旧的 4 列小格。
//
// 断言七件事：分组顺序与 15 格、每行两张、每张卡都有一句说明、
// 分享卡打开底部弹层而不是整页、需要会话的格子禁用但点一下有提示、
// 有会话时可用、旧 4 列网格不再存在。

import 'dart:io';

import 'package:dsh_app/state/sessions_state.dart';
import 'package:dsh_app/ui/common/tile_grid.dart';
import 'package:dsh_app/ui/im/im_discover_page.dart';
import 'package:dsh_app/ui/im/im_strings.dart';
import 'package:dsh_app/ui/share_code/profile_share_sheet.dart';
import 'package:dsh_app/ui/share_hosted/hosted_links_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../chat/support/harness.dart' show FixedSession, loadTestFonts;
import '../../shell/golden_harness.dart' show goldenApp;

/// 一屏放得下全部分组：默认手机高度只有两屏，靠后的分组还没被 build。
void useTallView(WidgetTester tester, {double logicalHeight = 2400}) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(780, logicalHeight * 2);
  tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
  tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 32);
  addTearDown(tester.view.reset);
}

final _groups = [
  ImStrings.groupChats,
  ImStrings.groupContents,
  ImStrings.groupTools,
  ImStrings.groupExtensions,
  ImStrings.groupHost,
  ImStrings.groupSettings,
];

void main() {
  setUpAll(loadTestFonts);

  Future<void> open(WidgetTester tester, {String? session}) async {
    useTallView(tester);
    await tester.pumpWidget(goldenApp(
      home: const ImDiscoverPage(),
      brightness: Brightness.light,
      overrides: [
        if (session != null) currentSessionProvider.overrideWith(() => FixedSession(session)),
      ],
    ));
    await tester.pump();
  }

  testWidgets('the groups keep their order and the page has the 15 approved cards', (tester) async {
    await open(tester);
    final tops = [for (final group in _groups) tester.getTopLeft(find.text(group)).dy];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]), reason: '「${_groups[i]}」要在「${_groups[i - 1]}」下面');
    }
    // 《轻松模式-需求》5.3 的名单是 6 组 15 格；名单外入口走「全部设置」。
    expect(find.byType(FeatureCard), findsNWidgets(15));
    expect(find.text('自动化任务'), findsNothing, reason: '定时任务在名单外（需求 D8），不该出现在发现页');
  });

  testWidgets('cards sit two per row', (tester) async {
    await open(tester);
    final cards = tester.widgetList<FeatureCard>(find.byType(FeatureCard)).toList();
    final rects = [for (final card in cards) tester.getRect(find.byWidget(card))];
    expect(rects[0].top, moreOrLessEquals(rects[1].top), reason: '同一行的两张卡顶部对齐');
    expect(rects[1].left, greaterThan(rects[0].left));
    expect(rects[2].top, greaterThan(rects[0].top), reason: '第三张换到下一行');
    expect(rects[2].left, moreOrLessEquals(rects[0].left), reason: '下一行重新从左边开始');
  });

  testWidgets('every card carries a one-line subtitle', (tester) async {
    await open(tester);
    final cards = tester.widgetList<FeatureCard>(find.byType(FeatureCard)).toList();
    final missing = [
      for (final card in cards)
        if ((card.subtitle ?? '').trim().isEmpty) card.title,
    ];
    expect(missing, isEmpty, reason: '每张卡都要有一句说明，缺的：$missing');
    // 产品报的贴错格：分享卡不该用分享配置的摘要。
    final share = tester.widget<FeatureCard>(find.widgetWithText(FeatureCard, '分享配置'));
    expect(share.subtitle, '分享给同事');
  });

  testWidgets('the share card opens the sheet, not a full page', (tester) async {
    await open(tester);
    await tester.tap(find.widgetWithText(FeatureCard, '分享配置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfileShareSheet), findsOneWidget, reason: '和 设置 → 隐私 同一个底部弹层');
    expect(find.byType(HostedLinksPage), findsNothing, reason: '不要 push 整页');
  });

  testWidgets('a card that needs a conversation is disabled but still answers a tap', (tester) async {
    await open(tester);
    final jobs = tester.widget<FeatureCard>(find.widgetWithText(FeatureCard, '后台任务'));
    expect(jobs.enabled, isFalse);

    await tester.tap(find.widgetWithText(FeatureCard, '后台任务'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(ImStrings.needsConversation), findsOneWidget, reason: '禁用不等于没反应，要给提示');
  });

  testWidgets('a session turns the same card on', (tester) async {
    await open(tester, session: 's1');
    final jobs = tester.widget<FeatureCard>(find.widgetWithText(FeatureCard, '后台任务'));
    expect(jobs.enabled, isTrue);
  });

  test('the old four-column grid is gone, not parked next to the cards', () {
    expect(File('lib/ui/im/im_feature_grid.dart').existsSync(), isFalse, reason: 'D11：旧网格要连文件一起删');
    final refs = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!entity.path.endsWith('.dart')) continue;
      if (RegExp(r'ImFeatureGrid|ImFeatureCell').hasMatch(entity.readAsStringSync())) refs.add(entity.path);
    }
    expect(refs, isEmpty, reason: 'D11：发现页只能有一套卡片形态，不引旧网格');
  });
}
