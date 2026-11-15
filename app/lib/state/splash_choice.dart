// Which launch animation the splash screen plays, beside the person's own
// imported one: the built-in animations the UI made, or the still mark.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SplashChoice {
  mark('标志', null),
  animated('动图', 'assets/brand/splash/coka_splash.gif');

  const SplashChoice(this.label, this.asset);

  final String label;

  /// Null: the still mark instead of an animation.
  final String? asset;
}

class SplashChoiceController extends Notifier<SplashChoice> {
  static const preferenceKey = 'splash_choice';
  late Future<void> _loaded;

  @override
  SplashChoice build() {
    _loaded = _load();
    return SplashChoice.animated;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      final stored = prefs.getString(preferenceKey);
      state = SplashChoice.values.firstWhere((choice) => choice.name == stored, orElse: () => SplashChoice.animated);
    } catch (_) {
      // Unreadable preferences: keep the default for this run.
    }
  }

  Future<void> set(SplashChoice choice) async {
    await _loaded;
    if (!ref.mounted) return;
    state = choice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, choice.name);
  }
}

final splashChoiceProvider = NotifierProvider<SplashChoiceController, SplashChoice>(SplashChoiceController.new);
