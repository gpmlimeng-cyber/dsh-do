// A rendered Stop action belongs to the connection and target it displayed.
// Changes retire it immediately, including transitions before the next frame.
import 'package:dsh_client/dsh_client.dart' show DsBotTeam;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/bots_state.dart';
import '../../state/connection_state.dart';

class BotStopGuard {
  BotStopGuard(this._ref) {
    _status = _ref.listenManual(dsBotProvider, (_, _) => _check());
    _connection = _ref.listenManual(activeConnectionProvider, (_, _) => _check());
  }

  final WidgetRef _ref;
  late final ProviderSubscription<DsBotStatus> _status;
  late final ProviderSubscription<AsyncValue<HostConnection?>> _connection;
  String? _botId;
  String? _roomId;
  Object? _identity;
  int _epoch = 0;
  bool _disposed = false;

  void _check() {
    if (_disposed) return;
    final status = _ref.read(dsBotProvider);
    final bot = _botId == null ? null : status.team?.bot(_botId!);
    final next = (
      status.host,
      status.hello?.boot,
      _ref.read(dsBotProvider.notifier).api,
      _ref.read(activeConnectionProvider).value?.client,
      _botId,
      bot?.sessionId,
      _roomId,
      status.team?.room(_roomId)?.sessionId,
      _roomId == null || status.team?.room(_roomId!) != null,
      status.readOnly,
    );
    if (_identity != next) {
      _identity = next;
      _epoch++;
    }
  }

  Future<void> Function() action({String? botId, String? roomId}) {
    _botId = botId;
    _roomId = roomId;
    _check();
    final epoch = _epoch;
    final status = _ref.read(dsBotProvider);
    final client = _ref.read(activeConnectionProvider).value?.client;
    final sessionId = stopTarget(team: status.team, botId: botId, roomId: roomId);
    final available =
        _ref.read(dsBotProvider.notifier).api != null &&
        status.readOnly == null &&
        (roomId == null || status.team?.room(roomId) != null);
    return () async {
      _check();
      if (_disposed || epoch != _epoch || !available || client == null || sessionId == null) return;
      try {
        await client.cancel(sessionId);
      } catch (_) {
        // The turn may already have ended; keep the existing quiet Stop behavior.
      }
    };
  }

  void dispose() {
    _disposed = true;
    _status.close();
    _connection.close();
  }
}

/// The Session a Stop cancels: a Bot's current part, or the Session a group's
/// round runs in now. The group's `id` only names its first part, so cancelling
/// that one after a part change would stop nothing.
String? stopTarget({required DsBotTeam? team, String? botId, String? roomId}) {
  if (botId != null) return team?.bot(botId)?.sessionId;
  if (roomId == null) return null;
  return team?.room(roomId)?.sessionId ?? roomId;
}
