// 抽屉行右侧的那句话：Bot/群行才有，普通行不传；多选时让位给勾选。
import 'package:dsh_app/ui/shell/drawer/session_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart' show testApp;

Widget _tile({String? note, bool selecting = false}) => testApp(
  Scaffold(
    body: Center(
      child: SizedBox(
        width: 240,
        child: SessionTile(
          title: 'Chief',
          running: false,
          current: false,
          note: note,
          selecting: selecting,
          onTap: () {},
          onLongPress: null,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a row shows the note on its right', (tester) async {
    await tester.pumpWidget(_tile(note: '正在运行命令'));
    expect(find.text('正在运行命令'), findsOneWidget);
    expect(find.text('Chief'), findsOneWidget);
  });

  testWidgets('a row without a note stays as it was', (tester) async {
    await tester.pumpWidget(_tile());
    expect(find.byKey(const ValueKey('note')), findsNothing);
  });

  testWidgets('selecting hides the note', (tester) async {
    await tester.pumpWidget(_tile(note: '刚刚', selecting: true));
    expect(find.text('刚刚'), findsNothing);
  });

  testWidgets('a long note does not push the title out', (tester) async {
    await tester.pumpWidget(_tile(note: '正在运行命令正在运行命令正在运行命令'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Chief'), findsOneWidget);
    expect(tester.getSize(find.text('Chief')).width, greaterThan(0));
  });
}
