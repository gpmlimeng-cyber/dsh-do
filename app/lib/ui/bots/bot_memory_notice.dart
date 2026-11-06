// What a Bot's `remember` / `forget` call did to its memory.
//
// The web client draws one quiet line per change in the conversation, and the
// wording is decided by the tool result, not by the call: 「记忆已更新」,
// 「已经保存过了」, 「没能保存到记忆 · 原因」. The same words are worked out here
// from the Bot's own session log, so the phone says exactly what the web says
// instead of turning every finished call into a success.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/chat_state.dart';

/// The memory tools whose results the conversation reports.
const memoryTools = {'remember', 'forget'};

/// A write that changed the memory (`Saved to …` / `Updated in …` /
/// `Removed from …`).
final _saved = RegExp(r'^(Saved to|Updated in|Removed from) ');

/// An entry that was there already (`Already in …`).
final _already = RegExp(r'^Already in ');

enum MemoryChange {
  /// The memory changed.
  updated,

  /// Nothing to do: the entry was already there.
  already,

  /// The host refused or the write failed.
  failed,

  /// It answered with something this client does not read as a change.
  unchanged,
}

/// One turn's memory change, as one line.
class MemoryNotice {
  const MemoryNotice({required this.turn, required this.change, this.count = 1, this.reason});

  final int turn;
  final MemoryChange change;

  /// How many writes this line stands for.
  final int count;

  /// The host's reason, when it gave a code (`memory/empty`, …).
  final String? reason;

  MemoryNotice merged(MemoryChange next, String? why) {
    // One line per turn: a failure is the thing worth saying, otherwise the
    // strongest state wins so 「已更新」 is never hidden by 「已存在」.
    final strongest = switch ((change, next)) {
      _ when change == MemoryChange.failed || next == MemoryChange.failed => MemoryChange.failed,
      _ when change == MemoryChange.updated || next == MemoryChange.updated => MemoryChange.updated,
      _ when change == MemoryChange.already || next == MemoryChange.already => MemoryChange.already,
      _ => MemoryChange.unchanged,
    };
    return MemoryNotice(turn: turn, change: strongest, count: count + 1, reason: reason ?? why);
  }
}

/// Every finished turn's memory change, keyed by turn ([memoryTools] only).
Map<int, MemoryNotice> memoryNoticesByTurn(Iterable<SessionLogEvent> events) {
  final calls = <String, SessionLogEvent>{};
  final out = <int, MemoryNotice>{};
  for (final event in events) {
    switch (event) {
      case ToolCallEvent(:final callId, :final name):
        if (memoryTools.contains(name)) calls[callId] = event;
      case ToolResultEvent(:final turn, :final isError, :final message, :final failure):
        if (!calls.containsKey(event.callId)) break;
        final text = message.text.trim();
        final MemoryChange change;
        if (isError) {
          change = MemoryChange.failed;
        } else if (_saved.hasMatch(text)) {
          change = MemoryChange.updated;
        } else if (_already.hasMatch(text)) {
          change = MemoryChange.already;
        } else {
          change = MemoryChange.unchanged;
        }
        final why = failure?.code;
        out[turn] = out.containsKey(turn)
            ? out[turn]!.merged(change, why)
            : MemoryNotice(turn: turn, change: change, reason: why);
      default:
        break;
    }
  }
  return out;
}

/// The notices of one session's finished turns.
///
/// Derived from the turn list, like the deliverable cards: a notice is complete
/// once its turn ended, and rebuilding on every streaming chunk would cost more
/// than the line is worth.
final sessionMemoryNoticesProvider = Provider.autoDispose.family<Map<int, MemoryNotice>, String>((ref, sessionId) {
  final turns = ref.watch(chatProvider(sessionId).select((s) => s.turns));
  final finished = {
    for (final trace in turns)
      if (!trace.running && trace.endSeq != null) trace.turn,
  };
  final chat = ref.read(chatProvider(sessionId));
  final all = memoryNoticesByTurn(chat.events);
  return {
    for (final entry in all.entries)
      if (finished.contains(entry.key)) entry.key: entry.value,
  };
});
