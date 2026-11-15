// 眨眼的纯公式：同一份实现 painter 也在用，所以这里断的就是画面上的节奏。
//
// 口径：周期 2.2–4.8 秒（按 seed 错开），闭眼 110ms；`seed % 100 < 18` 的
// 在 160ms 后补一次 90ms 的连眨。

import 'package:dsh_app/state/mascot_clock.dart';
import 'package:flutter_test/flutter_test.dart';

const _window = 10000;

/// 时间轴上连续的闭眼段：起点与长度（毫秒）。
List<({int start, int length})> _runs(int seed) {
  final out = <({int start, int length})>[];
  int? start;
  for (var t = 0; t <= _window; t++) {
    final blink = mascotBlinkAt(Duration(milliseconds: t), seed);
    if (blink && start == null) start = t;
    if (!blink && start != null) {
      out.add((start: start, length: t - start));
      start = null;
    }
  }
  if (start != null) out.add((start: start, length: _window + 1 - start));
  return out;
}

void main() {
  test('every seed blinks at least three times in ten seconds', () {
    for (final seed in [0, 7, 42, 99, 12345, 2351703228]) {
      final runs = _runs(seed);
      expect(runs.length, greaterThanOrEqualTo(3), reason: 'seed $seed: $runs');
    }
  });

  test('a blink never stays shut longer than 110ms', () {
    for (final seed in [0, 3, 7, 42, 99, 12345, 2351703228]) {
      for (final run in _runs(seed)) {
        expect(run.length, lessThanOrEqualTo(110), reason: 'seed $seed at ${run.start}ms');
      }
    }
  });

  test('a double blink comes 50ms after the first one and lasts 90ms', () {
    // seed % 100 < 18 的才连眨；seed 7 就是其中一只。
    final runs = _runs(7);
    final index = runs.indexWhere((run) => run.length == 90);
    expect(index, greaterThan(0), reason: 'seed 7 应该有 90ms 的第二段');
    // 两段之间留 50ms：110 → 160 的相位窗口（第一段可能被测试窗口切短）。
    for (var i = 1; i < runs.length; i++) {
      if (runs[i].length != 90) continue;
      expect(runs[i].start - (runs[i - 1].start + runs[i - 1].length), 50, reason: '第 $i 段');
    }
    expect(runs[index - 1].length, anyOf(103, 110));
  });

  test('two avatars do not blink in step', () {
    var differs = 0;
    for (var t = 0; t <= _window; t++) {
      final a = mascotBlinkAt(Duration(milliseconds: t), 3);
      final b = mascotBlinkAt(Duration(milliseconds: t), 4);
      if (a != b) differs++;
    }
    expect(differs, greaterThan(0), reason: 'seed 3 与 4 在同一时刻要错开');
  });

  test('the formula is pure: the same input always gives the same answer', () {
    for (final seed in [5, 314, 2351703228]) {
      for (final t in [0, 999, 4400]) {
        expect(
          mascotBlinkAt(Duration(milliseconds: t), seed),
          mascotBlinkAt(Duration(milliseconds: t), seed),
        );
      }
    }
  });
}
