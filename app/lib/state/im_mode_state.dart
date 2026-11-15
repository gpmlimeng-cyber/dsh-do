// 聊天界面: the professional home, or the light IM one (消息 / 伙伴 / 发现 / 我).
//
// A third axis next to 界面 (ui_mode_state.dart: native or web inside the
// professional home) and 模式 (AppMode on the 1.0.16 line): this one only picks
// which home lib/ui/web/mode_home.dart builds, and the light home never draws
// the web one.
//
// Kept in one place so the light shell can switch it, and so the settings page
// and the 我 tab read the same stored value. The default is 专业: an upgrade
// opens where it always did.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 专业 (the existing home) or 轻松 (the IM shell).
enum InterfaceMode { pro, light }

/// The stored choice; [loaded] once read back at launch.
class InterfaceModeState {
  const InterfaceModeState({this.mode = InterfaceMode.pro, this.loaded = false});

  final InterfaceMode mode;
  final bool loaded;

  bool get light => mode == InterfaceMode.light;
}

class InterfaceModeController extends Notifier<InterfaceModeState> {
  static const key = 'interface.mode';

  /// Written once, when the light home first opens: the intro card is shown
  /// only on that first time.
  static const introKey = 'interface.mode.lightIntroSeen';

  /// In-process fallback when there is no preferences backend (tests): the
  /// card still appears once per run, not on every rebuild.
  bool _introClaimed = false;

  @override
  InterfaceModeState build() {
    unawaited(_load());
    return const InterfaceModeState();
  }

  Future<void> _load() async {
    var mode = InterfaceMode.pro;
    try {
      final prefs = await SharedPreferences.getInstance();
      mode = InterfaceMode.values.asNameMap()[prefs.getString(key)] ?? InterfaceMode.pro;
    } catch (_) {
      // No preferences backend (tests) or an unreadable store: 专业.
    }
    // A switch made while reading back wins over the stored value.
    if (!state.loaded) state = InterfaceModeState(mode: mode, loaded: true);
  }

  /// Switches and remembers it for the next launch.
  Future<void> set(InterfaceMode mode) async {
    state = InterfaceModeState(mode: mode, loaded: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, mode.name);
    } catch (_) {}
  }

  /// Whether the one-time intro card was already shown on this install.
  Future<bool> introSeen() async {
    if (_introClaimed) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(introKey) ?? false;
    } catch (_) {
      // No preferences backend (tests): the caller shows it once per run.
      return false;
    }
  }

  /// Marks the intro card as shown. A dismissed card counts as shown too.
  Future<void> markIntroSeen() async {
    _introClaimed = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(introKey, true);
    } catch (_) {}
  }
}

final interfaceModeProvider = NotifierProvider<InterfaceModeController, InterfaceModeState>(
  InterfaceModeController.new,
);
