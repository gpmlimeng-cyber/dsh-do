import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../update/update_http.dart';
import '../update/version.dart';

/// The newest DS Bot plugin the fork publishes.
///
/// The Bot pages need this fork's plugin (it carries the mobile API), and the
/// plugin market only knows the official one, so the phone asks the fork itself:
/// the `version` in `ds-bot/package.json` on the default branch is what the next
/// install would put there.
final dsBotPluginVersionUrl = Uri.parse(
  'https://api.github.com/repos/gpmlimeng-cyber/dsh-bot/contents/ds-bot/package.json?ref=main',
);

final dsBotPluginHttpProvider = Provider<UpdateHttp>((ref) => IoUpdateHttp());

/// What the last check learned, and when it ran.
class DsBotPluginUpdate {
  const DsBotPluginUpdate({this.latest, this.checkedAt, this.failed = false});

  /// The fork's newest version, when a check answered.
  final String? latest;

  /// When that answer arrived; null before the first check.
  final DateTime? checkedAt;

  /// The last check could not ask (offline, rate limit, a bad answer).
  final bool failed;

  /// Checks run at most once a day on their own; the row also checks on demand.
  static const period = Duration(hours: 24);

  bool get due {
    final at = checkedAt;
    return at == null || DateTime.now().difference(at) >= period;
  }

  /// True when [installed] (a version string) is older than [latest].
  bool isNewerThan(String? installed) {
    final mine = AppVersion.tryParse(installed);
    final theirs = AppVersion.tryParse(latest);
    if (theirs == null) return false;
    if (mine == null) return true;
    return theirs.isNewerThan(mine);
  }
}

final dsBotPluginUpdateProvider =
    AsyncNotifierProvider<DsBotPluginUpdateController, DsBotPluginUpdate>(DsBotPluginUpdateController.new);

class DsBotPluginUpdateController extends AsyncNotifier<DsBotPluginUpdate> {
  static const _latestKey = 'dsbot.plugin.latest';
  static const _checkedKey = 'dsbot.plugin.checkedAt';
  static const _failedKey = 'dsbot.plugin.failed';

  @override
  Future<DsBotPluginUpdate> build() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_checkedKey);
    final stored = DsBotPluginUpdate(
      latest: prefs.getString(_latestKey),
      checkedAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      failed: prefs.getBool(_failedKey) ?? false,
    );
    // The day's own check: the row shows what is known meanwhile.
    if (stored.due) unawaited(check());
    return stored;
  }

  /// Asks the fork when the last answer is older than [olderThan] — the app
  /// was brought back to the front, not the day's check — and does nothing
  /// otherwise. GitHub answers 60 requests an hour per address, so a resume
  /// must not ask every time.
  Future<void> checkIfStale({Duration olderThan = const Duration(minutes: 30)}) async {
    final known = state.value;
    final at = known?.checkedAt;
    if (at != null && DateTime.now().difference(at) < olderThan) return;
    if (state.isLoading) return;
    await check();
  }

  /// Asks the fork, then keeps the answer (and the day it arrived).
  Future<void> check() async {
    final before = state.value;
    state = const AsyncLoading<DsBotPluginUpdate>();
    DsBotPluginUpdate next;
    try {
      final http = ref.read(dsBotPluginHttpProvider);
      final response = await http.get(
        dsBotPluginVersionUrl,
        headers: const {'Accept': 'application/vnd.github.raw'},
        timeout: const Duration(seconds: 12),
      );
      if (response.status != 200) {
        await response.discard();
        throw StateError('HTTP ${response.status}');
      }
      final body = await response.text(maxBytes: 64 * 1024);
      final version = (jsonDecode(body) as Map<String, Object?>)['version'];
      if (version is! String || version.isEmpty) throw const FormatException('no version');
      next = DsBotPluginUpdate(latest: version, checkedAt: DateTime.now());
    } catch (_) {
      // A failed check keeps the last answer; the row says it could not ask.
      next = DsBotPluginUpdate(latest: before?.latest, checkedAt: before?.checkedAt, failed: true);
    }
    final prefs = await SharedPreferences.getInstance();
    final latest = next.latest;
    final at = next.checkedAt;
    if (latest == null) {
      await prefs.remove(_latestKey);
    } else {
      await prefs.setString(_latestKey, latest);
    }
    if (at == null) {
      await prefs.remove(_checkedKey);
    } else {
      await prefs.setInt(_checkedKey, at.millisecondsSinceEpoch);
    }
    await prefs.setBool(_failedKey, next.failed);
    state = AsyncData(next);
  }
}
