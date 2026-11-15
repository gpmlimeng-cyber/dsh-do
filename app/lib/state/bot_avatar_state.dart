// 头像外观: 文字 (the Bot's initial), the Host's photo, a mascot, or an emoji.
//
// The Host only knows a photo (`bot.imageRef`) and a color; everything here is
// a local override, kept per Bot on this phone (决定: 头像配置先只存本地).
// A Bot without an entry renders exactly as before — photo if the Host has
// one, else the initial — so old Bots and a cleared store change nothing.
//
// The mascot model is [MascotSpec] (ui/mascots/mascot_avatar.dart): 前端's
// renderer enums plus the serialisation, one definition only. This file owns
// where it is stored and how it degrades, not how it is drawn.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/mascots/mascot_avatar.dart' show MascotCharacter, MascotColor, MascotMotion, MascotSpec;
import 'hosts_state.dart';

/// How a Bot's avatar is drawn.
enum BotAvatarKind { text, photo, mascot, emoji }

/// A Bot's local avatar choice. `null` for a Bot means 「as it always was」:
/// the Host photo when there is one, else the initial.
class BotAvatarConfig {
  /// 字团: the letter sits where the mascot's face would be, on the mascot's
  /// body. [mascot] is the body kept when the person switches 字团 ↔ 吉祥物;
  /// null means 「derive one from the Bot id」 (see [letterMascotOf]).
  const BotAvatarConfig.text([this.mascot])
    : kind = BotAvatarKind.text,
      emoji = '';

  const BotAvatarConfig.photo()
    : kind = BotAvatarKind.photo,
      mascot = null,
      emoji = '';

  const BotAvatarConfig.mascot(MascotSpec this.mascot)
    : kind = BotAvatarKind.mascot,
      emoji = '';

  const BotAvatarConfig.emoji(this.emoji)
    : kind = BotAvatarKind.emoji,
      mascot = null;

  final BotAvatarKind kind;
  final MascotSpec? mascot;
  final String emoji;

  bool get isMascot => kind == BotAvatarKind.mascot && mascot != null;

  /// A random mascot. With [avoid] it follows the product rule (角色和颜色必换、
  /// 动作随机、五官保持) by delegating to [MascotSpec.randomDifferent], so the
  /// rule lives in one place; without it, just a fresh look.
  ///
  /// [seed] seeds the generator, so a re-roll made with the same seed and the
  /// same [avoid] is reproducible. The returned spec carries its own seed; the
  /// look itself is reproduced by keeping the spec, not by re-seeding.
  factory BotAvatarConfig.randomMascot({Random? random, MascotSpec? avoid, int? seed}) {
    final rng = seed != null ? Random(seed) : random ?? Random();
    final spec = avoid == null ? MascotSpec.random(rng, seed: seed) : MascotSpec.randomDifferent(avoid, rng);
    return BotAvatarConfig.mascot(spec);
  }

  factory BotAvatarConfig.fromJson(Object? json) => switch (json) {
    {'kind': 'text', 'mascot': final Object? look} => BotAvatarConfig.text(MascotSpec.fromJson(look)),
    {'kind': 'text'} => const BotAvatarConfig.text(),
    {'kind': 'mascot', 'mascot': final Object? look} => BotAvatarConfig.mascot(MascotSpec.fromJson(look)),
    {'kind': 'emoji', 'emoji': final Object? glyph} => BotAvatarConfig.emoji('${glyph ?? ''}'),
    {'kind': 'photo'} => const BotAvatarConfig.photo(),
    _ => const BotAvatarConfig.text(),
  };

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (mascot case final look?) 'mascot': look.toJson(),
    if (kind == BotAvatarKind.emoji) 'emoji': emoji,
  };

  @override
  bool operator ==(Object other) =>
      other is BotAvatarConfig && other.kind == kind && other.mascot == mascot && other.emoji == emoji;

  @override
  int get hashCode => Object.hash(kind, mascot, emoji);
}

/// Per-Bot overrides for the active Host, keyed by Bot id. Stored as one JSON
/// map per Host (`bot_avatar_v1` → `{v:1, hosts: {host: {botId: config}}}`):
/// small, easy to migrate, and Bot ids from two Hosts never collide.
class BotAvatarStore extends Notifier<Map<String, BotAvatarConfig>> {
  static const preferenceKey = 'bot_avatar_v1';
  static const maxPerHost = 200;

  /// host.encode() → {botId → config}, every Host seen on this phone.
  Map<String, Map<String, BotAvatarConfig>> _all = {};
  late String _hostKey;
  bool _restored = false;

  /// True once the stored entries are in (the UI can tell 「no mascot」 from
  /// 「not read yet」).
  bool get restored => _restored;

  @override
  Map<String, BotAvatarConfig> build() {
    _hostKey = ref.watch(activeHostProvider).encode();
    // Read the stored map once; a Host switch only changes which slice is shown.
    if (!_restored) unawaited(_restore());
    return _all[_hostKey] ?? const {};
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(preferenceKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        final hosts = decoded is Map ? decoded['hosts'] : null;
        if (hosts is Map) {
          for (final MapEntry(key: host, value: bots) in hosts.entries) {
            if (host is! String || bots is! Map) continue;
            _all[host] = {
              for (final MapEntry(key: botId, value: config) in bots.entries)
                if (botId is String) botId: BotAvatarConfig.fromJson(config),
            };
          }
        }
      }
    } catch (_) {
      // Unreadable or older shape: every Bot falls back to its old avatar.
    }
    _restored = true;
    if (ref.mounted) state = _all[_hostKey] ?? const {};
  }

  BotAvatarConfig? of(String botId) => state[botId];

  /// Sets [botId]'s look and remembers it for the next launch.
  Future<void> set(String botId, BotAvatarConfig config) async {
    final forHost = Map<String, BotAvatarConfig>.from(_all[_hostKey] ?? const {});
    forHost[botId] = config;
    // Bounded: a phone that has met many Bots keeps the newest choices.
    while (forHost.length > maxPerHost) {
      forHost.remove(forHost.keys.first);
    }
    _all[_hostKey] = forHost;
    state = forHost;
    await _save();
  }

  /// Back to the Bot's old avatar (the Host photo or its initial).
  Future<void> clear(String botId) async {
    final forHost = Map<String, BotAvatarConfig>.from(_all[_hostKey] ?? const {})..remove(botId);
    _all[_hostKey] = forHost;
    state = forHost;
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        preferenceKey,
        jsonEncode({
          'v': 1,
          'hosts': {
            for (final MapEntry(key: host, value: bots) in _all.entries)
              host: {for (final MapEntry(key: botId, value: config) in bots.entries) botId: config.toJson()},
          },
        }),
      );
    } catch (_) {
      // No preferences backend (tests): the look still holds for this run.
    }
  }
}

/// 字团用哪套「身体 / 颜色 / 动作」：有配置过的 mascot 就用它（在字团和吉祥物
/// 之间切换时保留同一副身体），没配过就按 botId 稳定派生——同一个 Bot 每次冷启动
/// 都长一样，不同 Bot 大概率不同。不新增存档字段。
MascotSpec letterMascotOf(BotAvatarConfig? config, String botId) {
  final configured = config?.mascot;
  if (configured != null) return configured;
  final seed = stableSeedOf(botId);
  // 派生不用 model：那是「跟随角色默认」，两个同角色 Bot 会撞脸。
  final colors = [for (final color in MascotColor.values) if (color != MascotColor.model) color];
  return MascotSpec(
    character: MascotCharacter.values[seed % MascotCharacter.values.length],
    color: colors[(seed ~/ 7) % colors.length],
    motion: MascotMotion.values[(seed ~/ 13) % MascotMotion.values.length],
  );
}

/// FNV-1a over UTF-8: 稳定、跨进程一致（`String.hashCode` 不保证这一点）。
int stableSeedOf(String value) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(value)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

final botAvatarProvider = NotifierProvider<BotAvatarStore, Map<String, BotAvatarConfig>>(BotAvatarStore.new);
