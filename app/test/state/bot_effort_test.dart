// 「想多久再回」的映射：四档 → 宿主 effort，以及从 modelCatalog 里查某只 Bot
// 模型的档位列表。全是纯函数，没有 I/O。

import 'package:dsh_app/state/bot_effort.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

List<ReasoningEffort> _efforts(List<String> ids) =>
    [for (final id in ids) ReasoningEffort(id, id.toUpperCase(), null)];

ModelCatalog _catalog() => ModelCatalog(
      defaultSelection: null,
      routableProviders: const ['deepseek'],
      groups: [
        ProviderGroup('deepseek', 'DeepSeek', [
          ModelInfo(provider: 'deepseek', id: 'v4-pro', name: 'Pro', efforts: _efforts(['off', 'low', 'high', 'max'])),
          ModelInfo(provider: 'deepseek', id: 'flash', name: 'Flash', efforts: _efforts(['off', 'low'])),
          ModelInfo(provider: 'deepseek', id: 'plain', name: 'Plain'),
        ]),
      ],
      failures: const [],
    );

void main() {
  final full = _efforts(['off', 'low', 'high', 'max']);

  group('四档写回宿主的值', () {
    test('秒回 takes off, and falls back to the lowest level', () {
      expect(wireEffortFor(ReplyPace.instant, full), 'off');
      expect(wireEffortFor(ReplyPace.instant, _efforts(['minimal', 'low'])), 'minimal');
      expect(wireEffortFor(ReplyPace.instant, _efforts(['low', 'high'])), 'low');
      expect(wireEffortFor(ReplyPace.instant, _efforts(['xhigh'])), 'xhigh');
    });

    test('看情况 clears the field with an empty string, never null', () {
      expect(wireEffortFor(ReplyPace.adaptive, full), '');
      expect(wireEffortFor(ReplyPace.adaptive, const []), '');
    });

    test('多想想 prefers high and degrades both ways', () {
      expect(wireEffortFor(ReplyPace.thoughtful, full), 'high');
      expect(wireEffortFor(ReplyPace.thoughtful, _efforts(['low', 'medium'])), 'medium');
      expect(wireEffortFor(ReplyPace.thoughtful, _efforts(['xhigh'])), 'xhigh');
      expect(wireEffortFor(ReplyPace.thoughtful, _efforts(['low'])), 'low');
    });

    test('深思熟虑 prefers max and degrades both ways', () {
      expect(wireEffortFor(ReplyPace.deep, full), 'max');
      expect(wireEffortFor(ReplyPace.deep, _efforts(['low', 'high'])), 'high');
      expect(wireEffortFor(ReplyPace.deep, _efforts(['xhigh'])), 'xhigh');
      expect(wireEffortFor(ReplyPace.deep, _efforts(['low'])), 'low');
    });

    test('a model without levels writes nothing but does not crash', () {
      for (final pace in ReplyPace.values) {
        expect(wireEffortFor(pace, const []), '');
      }
    });
  });

  group('从已存的 effort 反查档位', () {
    test('no effort or an empty string is 看情况', () {
      expect(paceOf(null, full), ReplyPace.adaptive);
      expect(paceOf('', full), ReplyPace.adaptive);
    });

    test('each supported id maps back to its tier', () {
      expect(paceOf('off', full), ReplyPace.instant);
      expect(paceOf('minimal', full), ReplyPace.instant);
      expect(paceOf('low', full), ReplyPace.instant);
      expect(paceOf('high', full), ReplyPace.thoughtful);
      expect(paceOf('max', full), ReplyPace.deep);
      expect(paceOf('xhigh', full), ReplyPace.deep);
      expect(paceOf('medium', full), ReplyPace.adaptive);
    });

    test('a value the model no longer supports reads as 看情况, not a stale tier', () {
      expect(paceOf('max', _efforts(['off', 'low'])), ReplyPace.adaptive);
      expect(paceOf('high', _efforts(['low', 'medium'])), ReplyPace.adaptive);
    });
  });

  group('从 modelCatalog 查模型的档位', () {
    test('no catalog or no model means no levels', () {
      expect(effortsOf(null, 'deepseek/v4-pro'), isEmpty);
      expect(effortsOf(_catalog(), null), isEmpty);
      expect(effortsOf(_catalog(), ''), isEmpty);
    });

    test('an exact provider/model ref finds its levels', () {
      expect(effortsOf(_catalog(), 'deepseek/v4-pro').map((e) => e.id), ['off', 'low', 'high', 'max']);
    });

    test('a model id without the provider still finds them', () {
      expect(effortsOf(_catalog(), 'v4-pro').map((e) => e.id), ['off', 'low', 'high', 'max']);
      // 宿主给的 provider 和 catalog 里的分组名不一致时，按 model id 兜一层。
      expect(effortsOf(_catalog(), 'other/v4-pro').map((e) => e.id), ['off', 'low', 'high', 'max']);
    });

    test('a model without thinking levels returns an empty list (row hidden)', () {
      expect(effortsOf(_catalog(), 'deepseek/plain'), isEmpty);
      expect(effortsOf(_catalog(), 'deepseek/nope'), isEmpty);
    });
  });
}
