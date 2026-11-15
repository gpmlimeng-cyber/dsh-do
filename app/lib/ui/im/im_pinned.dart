// 轻松模式的置顶：Bot / 群 id 的集合，存本机（`im.pinned`）。
//
// 只影响轻松模式的消息列表，专业首页的「主 Bot 固定在上」不动。
// id 带前缀（`bot:` / `room:`），两类会话不会撞号。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ImPinnedController extends Notifier<Set<String>> {
  static const key = 'im.pinned';

  @override
  Set<String> build() {
    unawaited(_load());
    return const <String>{};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = {...?prefs.getStringList(key)};
    } catch (_) {
      // 没有 preferences 后端（测试）：本次运行不置顶，不炸。
    }
  }

  bool isPinned(String id) => state.contains(id);

  Future<void> toggle(String id) async {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, next.toList());
    } catch (_) {}
  }

  Future<void> unpin(String id) async {
    if (!state.contains(id)) return;
    final next = {...state}..remove(id);
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, next.toList());
    } catch (_) {}
  }
}

final imPinnedProvider = NotifierProvider<ImPinnedController, Set<String>>(ImPinnedController.new);
