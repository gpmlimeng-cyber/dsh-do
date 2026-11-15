// 长步骤的「还要多久」:同一种步骤最近几次花了多久,取中位数当预估。
//
// 这不是真进度 —— 工具不告诉我们进行到哪一步。它只是「上一次这类命令跑了 2 分,
// 这次已经 1 分 10 秒」这种老实估算,所以界面上的措辞是「约」。样本少于两次不
// 给预估,免得第一次就胡说。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

class StepEta {
  StepEta._();

  static const _key = 'step_eta_v1';
  static const _keep = 5;
  static final Map<String, List<Duration>> _seen = {};
  static Future<void>? _loading;

  /// 读一次磁盘上的历史(进程内只做一次)。
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      for (final entry in map.entries) {
        final name = entry.key;
        final list = entry.value;
        if (name is! String || list is! List) continue;
        final durations = [for (final ms in list) if (ms is int) Duration(milliseconds: ms)];
        if (durations.isNotEmpty) _seen[name] = durations;
      }
    } catch (_) {
      // 读不出来就当没有历史:预估只是锦上添花,不能挡住界面。
    }
  }

  /// 这一类步骤通常要多久;样本不够就 null。
  static Duration? estimate(String key) {
    final list = _seen[key];
    if (list == null || list.length < 2) return null;
    final sorted = [...list]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// 记下这一次跑了多久。太短的不记(点开就结束的命令没有参考价值)。
  static void record(String key, Duration took) {
    if (key.isEmpty || took < const Duration(seconds: 3)) return;
    final list = _seen.putIfAbsent(key, () => []);
    list.add(took);
    if (list.length > _keep) list.removeRange(0, list.length - _keep);
    unawaited(_save());
  }

  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({for (final entry in _seen.entries) entry.key: [for (final d in entry.value) d.inMilliseconds]}),
      );
    } catch (_) {
      // 存不下来只影响下一次的预估。
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _seen.clear();
    _loading = null;
  }

  @visibleForTesting
  static List<Duration>? samplesForTest(String key) => _seen[key];

  @visibleForTesting
  static bool get isEmptyForTest => _seen.isEmpty;

  static bool sameSamples(String key, List<Duration> other) {
    final list = _seen[key];
    return list != null && listEquals(list, other);
  }
}
