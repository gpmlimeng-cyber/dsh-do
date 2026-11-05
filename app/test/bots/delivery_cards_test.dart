// One file, one card: a group's relay Session repeats what members delivered,
// and members can repeat each other. The card must stay under the member who
// produced it, and the relay keeps only what no member claimed.

import 'package:dsh_app/state/artifacts.dart';
import 'package:dsh_app/ui/bots/bot_chat_kit.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

Artifact _file(String path, int turn) => Artifact(path: path, origin: ArtifactOrigin.written, turn: turn);

TurnArtifacts _turn(int turn, List<String> paths) =>
    TurnArtifacts(turn: turn, endSeq: 1000 + turn, files: [for (final path in paths) _file(path, turn)]);

BotItemRow _botLine(String botId, int turn) =>
    BotItemRow(DsBotItem(kind: DsBotItemKind.bot, botId: botId, turn: turn, text: 'done'));

BotItemRow _userLine() => const BotItemRow(DsBotItem(kind: DsBotItemKind.user, text: 'go'));

/// The page's own collection: members in the group's order, each keeping only
/// the files no earlier member claimed.
Map<String, ({String sessionId, TurnArtifacts group})> _collect(Map<String, TurnArtifacts> byMember) {
  final seen = <String>{};
  final byBot = <String, ({String sessionId, TurnArtifacts group})>{};
  for (final entry in byMember.entries) {
    final group = entry.value;
    final fresh = [
      for (final file in group.files)
        if (seen.add(file.path)) file,
    ];
    if (fresh.isEmpty) continue;
    byBot[entry.key] = (
      sessionId: '${entry.key}-session',
      group: TurnArtifacts(turn: group.turn, endSeq: group.endSeq, files: fresh),
    );
  }
  return byBot;
}

void main() {
  group('unclaimedArtifacts', () {
    test('drops what a member card already drew', () {
      final relay = _turn(3, ['/w/a.md', '/w/b.md']);
      final left = unclaimedArtifacts(relay, {'/w/a.md'});
      expect(left, isNotNull);
      expect([for (final file in left!.files) file.path], ['/w/b.md']);
    });

    test('nothing left: no card at all', () {
      final relay = _turn(3, ['/w/a.md', '/w/b.md']);
      expect(unclaimedArtifacts(relay, {'/w/a.md', '/w/b.md'}), isNull);
      expect(unclaimedArtifacts(null, {'/w/a.md'}), isNull);
    });
  });

  group('cards in a group chat', () {
    test('two members delivering the same file draw one card', () {
      final byBot = _collect({
        'm1': _turn(1, ['/w/a.md', '/w/b.md']),
        'm2': _turn(1, ['/w/a.md']),
      });
      final rows = attachMemberArtifacts([_userLine(), _botLine('m1', 1), _botLine('m2', 1)], byBot, roundStart: 0);
      final cards = rows.whereType<BotArtifactsRow>().toList();
      expect(cards.length, 1);
      expect(cards.single.sessionId, 'm1-session');
      expect([for (final file in cards.single.group.files) file.path], ['/w/a.md', '/w/b.md']);
    });

    test('the relay keeps only what no member claimed', () {
      final byBot = _collect({'m1': _turn(1, ['/w/a.md'])});
      // The relay's turn is the row's turn, so its card is placed by turn.
      final relay = unclaimedArtifacts(_turn(1, ['/w/a.md', '/w/c.md']), {'/w/a.md'});
      final rows = attachMemberArtifacts(
        attachArtifacts([_userLine(), _botLine('m1', 1)], relay, atOldestEnd: true),
        byBot,
        roundStart: 0,
      );
      final cards = rows.whereType<BotArtifactsRow>().toList();
      expect(cards.length, 2);
      final paths = [
        for (final card in cards)
          for (final file in card.group.files) file.path,
      ];
      expect(paths, containsAll(['/w/a.md', '/w/c.md']));
      // The member's card is the only one that names that file.
      expect(cards.where((card) => card.group.files.any((file) => file.path == '/w/a.md')).length, 1);
    });
  });
}
