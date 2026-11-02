// 发送方式：长按发送键的三个选择怎么落到 `send` 的 mode 上，以及
// 「打断并发送」必须先停再发。
import 'package:dsh_app/state/chat_state.dart' show SendMode;
import 'package:dsh_app/ui/bots/bot_stop_guard.dart' show stopTarget;
import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_app/ui/bots/bot_composer_deck.dart' show botSendMode, runBotSend;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('steer joins the turn, everything else queues', () {
    expect(botSendMode(SendMode.steer), 'steer');
    expect(botSendMode(SendMode.queue), 'queue');
    expect(botSendMode(SendMode.interrupt), 'queue');
    // 空闲时没有可插话的回合，落到队列等同于直接开始。
    expect(botSendMode(SendMode.now), 'queue');
  });

  test('interrupt stops the turn before it sends', () async {
    final order = <String>[];
    await runBotSend(
      SendMode.interrupt,
      stop: () async => order.add('stop'),
      send: (mode) async => order.add('send:${botSendMode(mode)}'),
    );
    expect(order, ['stop', 'send:queue']);
  });

  test('steer never stops the turn', () async {
    final order = <String>[];
    await runBotSend(
      SendMode.steer,
      stop: () async => order.add('stop'),
      send: (mode) async => order.add('send:${botSendMode(mode)}'),
    );
    expect(order, ['send:steer']);
  });

  test('a group stop cancels the Session its round runs in now', () {
    const team = DsBotTeam(
      revision: 1,
      bots: [DsBot(id: 'b1', name: 'Chief', sessionId: 'b1-part2')],
      rooms: [DsBotRoom(id: 'r1', name: 'Ops', sessionId: 'r1-part2')],
    );
    // The group moved on to a new part: the id alone would cancel the old one.
    expect(stopTarget(team: team, roomId: 'r1'), 'r1-part2');
    // A host that names no Session keeps the old behaviour.
    expect(stopTarget(team: const DsBotTeam(revision: 1, rooms: [DsBotRoom(id: 'r1', name: 'Ops')]), roomId: 'r1'), 'r1');
    // A Bot's stop follows its current part.
    expect(stopTarget(team: team, botId: 'b1'), 'b1-part2');
    expect(stopTarget(team: team), isNull);
  });

  test('a stop that throws still leaves the send undone', () async {
    final order = <String>[];
    await expectLater(
      runBotSend(
        SendMode.interrupt,
        stop: () async => throw StateError('gone'),
        send: (mode) async => order.add('send:${botSendMode(mode)}'),
      ),
      throwsStateError,
    );
    expect(order, isEmpty);
  });
}
