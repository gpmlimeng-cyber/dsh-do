// Portions derived from DS Bot (https://github.com/Fei2411/DeepSeek-Bot), Apache-2.0,
// Copyright 2026 Fei2411 and the DS Bot contributors. See THIRD_PARTY_NOTICES.md.
// Modified: the mention rules of `ds-bot/src/shared/mentions.js` and the drawing side
// of `ds-bot/src/client/text.js` (`linkMentions`), for a Flutter message body: the web
// turns each `@Name` into a link and paints it in that member's ink; here the same
// spans are marked in the source and an `InlinePattern` paints them the same way.
//
// One rule everywhere: `@Name` is a mention only when it names a member of this group,
// the longest name wins (`@新 Bot 2` never reads as `@新 Bot`), and code, inline code,
// Markdown links and addresses (`a@b`, `medium.com/@Writer`) stay literal text.

import 'dart:ui' show Color;

/// A member a group line may call: the name after `@` and the ink it wears.
class InlineMention {
  const InlineMention({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is InlineMention && other.name == name && other.color == color;

  @override
  int get hashCode => Object.hash(name, color);
}

/// 正文里圈出一个提及用的私用区字符(见 [markMentions]),由
/// `MarkdownBody` 的 `InlinePattern` 换成上色的文字 —— 和流式光标同一套做法。
const mentionMarkOpen = '\uE002';
const mentionMarkClose = '\uE003';

/// A letter, digit, `_`, `-`, `/` or `\` right after a name means a longer word
/// (`@Mi` in `@MiniMax`); `.x` means a path (`@docs/guide.md`).
final _nameGoesOn = RegExp(r'^(?:[a-z0-9_\-/\\]|\.[a-z0-9_-])', caseSensitive: false);

/// A letter, digit, `_`, `.` or `/` before the `@` means an address.
final _addressBefore = RegExp(r'[a-z0-9_./]', caseSensitive: false);

/// Code — fenced (closed or still streaming) or inline — and Markdown links, with
/// or without a title, are literal text.
final _literal = RegExp(
  r"""```[\s\S]*?(?:```|$)|`[^`\n]*`|\[[^\]\n]*\]\([^)\s]*(?:\s+(?:"[^"\n]*"|'[^'\n]*'))?\)""",
);

/// Every `@Name` of a member in [text], in order, longest name first.
List<({int start, int end, String name})> mentionSpans(String text, Iterable<String> names) {
  if (!text.contains('@')) return const [];
  final sorted = [for (final name in names) if (name.trim().isNotEmpty) name]
    ..sort((a, b) => b.length.compareTo(a.length));
  if (sorted.isEmpty) return const [];
  final skip = [for (final match in _literal.allMatches(text)) match];
  bool literal(int at) => skip.any((match) => at >= match.start && at < match.end);
  final spans = <({int start, int end, String name})>[];
  for (var at = text.indexOf('@'); at >= 0; at = text.indexOf('@', at + 1)) {
    if (at > 0 && _addressBefore.hasMatch(text[at - 1])) continue;
    if (literal(at)) continue;
    String? found;
    for (final name in sorted) {
      if (!_fitsAt(text, at + 1, name)) continue;
      found = name;
      break;
    }
    if (found == null) continue;
    final end = at + 1 + found.length;
    spans.add((start: at, end: end, name: found));
    at = end - 1;
  }
  return spans;
}

bool _fitsAt(String text, int at, String word) {
  if (at + word.length > text.length) return false;
  if (text.substring(at, at + word.length).toLowerCase() != word.toLowerCase()) return false;
  return !_nameGoesOn.hasMatch(text.substring(at + word.length));
}

/// [text] with every member mention wrapped in [mentionMarkOpen] / [mentionMarkClose];
/// the body left as written otherwise, so the Markdown still parses.
String markMentions(String text, Iterable<InlineMention> mentions) {
  final spans = mentionSpans(text, [for (final mention in mentions) mention.name]);
  if (spans.isEmpty) return text;
  final out = StringBuffer();
  var cursor = 0;
  for (final span in spans) {
    out
      ..write(text.substring(cursor, span.start))
      ..write(mentionMarkOpen)
      ..write(text.substring(span.start, span.end))
      ..write(mentionMarkClose);
    cursor = span.end;
  }
  out.write(text.substring(cursor));
  return out.toString();
}

/// [text] with the marks taken back out: for a body that draws one line as it is
/// (a code block, a formula's source) and must not show them.
String unmarkMentions(String text) =>
    text.contains(mentionMarkOpen) || text.contains(mentionMarkClose)
    ? text.replaceAll(mentionMarkOpen, '').replaceAll(mentionMarkClose, '')
    : text;
