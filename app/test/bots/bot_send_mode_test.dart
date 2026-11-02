// 发送方式：长按发送键的三个选择怎么落到 `send` 的 mode 上，以及
// 「打断并发送」必须先停再发。
import 'package:dsh_app/state/chat_state.dart' show SendMode;
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
