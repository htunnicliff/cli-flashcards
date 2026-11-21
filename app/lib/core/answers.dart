/// Checks a typed flag against the option a card asks for, accepting every
/// way the tool itself would read it. Ported from `src/core/answers/index.ts`.
library;

import '../schema/cards.dart';
import '../schema/deck.dart';
import '../schema/flags.dart';

class AnswerResult {
  const AnswerResult({
    required this.correct,
    required this.expected,
    this.matched,
    this.preferred,
  });
  final bool correct;

  /// The flag the card expects.
  final String expected;

  /// The full spelling the answer was read as.
  final String? matched;

  /// Set when the answer was right but not spelled as the primary flag.
  final String? preferred;
}

typedef Named = ({Option option, String flag});

/// The options a single command-line word names, in the order the tool reads them.
List<Named> optionsNamedBy(
  String word,
  List<Option> options, [
  ParsingStyle style = ParsingStyle.gnu,
]) {
  if (!word.startsWith('-') || word == '-' || word == '--') return [];
  final name = word.split('=').first;
  for (final option in options) {
    if (option.flags.contains(name)) return [(option: option, flag: name)];
  }

  if (word.startsWith('--')) {
    if (style != ParsingStyle.gnu || name.length < 3) return [];
    final matches = <Named>[];
    for (final option in options) {
      for (final f in option.flags) {
        if (f.startsWith('--') && f.startsWith(name)) {
          matches.add((option: option, flag: f));
          break;
        }
      }
    }
    return matches.length == 1 ? matches : [];
  }

  if (style == ParsingStyle.strict) return [];
  final named = <Named>[];
  for (final char in word.substring(1).runes) {
    final flag = '-${String.fromCharCode(char)}';
    Option? found;
    for (final o in options) {
      if (o.flags.contains(flag)) {
        found = o;
        break;
      }
    }
    if (found == null) return [];
    named.add((option: found, flag: flag));
    if (found.argument != null) break;
  }
  return named;
}

final _spaces = RegExp(r'\s+');

/// Whether [input] names [option]. The answer must hold exactly one flag word.
/// [only] accepts just these exact spellings (flag pair cards).
AnswerResult checkAnswer(
  String input, {
  required Option option,
  required List<Option> options,
  ParsingStyle? style,
  List<String>? only,
}) {
  final expected = only?.first ?? primaryFlag(option);
  final scope = [
    for (final o in options)
      if (o.subcommand == option.subcommand) o,
  ];
  final flagWords = input
      .trim()
      .split(_spaces)
      .where((w) => w.startsWith('-'))
      .toList();
  if (flagWords.length != 1) {
    return AnswerResult(correct: false, expected: expected);
  }
  final word = flagWords.single;
  final name = word.split('=').first;

  if (only != null) {
    if (!only.contains(name)) {
      return AnswerResult(correct: false, expected: expected);
    }
    return AnswerResult(correct: true, expected: expected, matched: name);
  }

  final named = optionsNamedBy(word, scope, style ?? ParsingStyle.gnu);
  final hit = named.where((n) => n.option.id == option.id).firstOrNull;
  if (hit == null) return AnswerResult(correct: false, expected: expected);
  final typedAsPrimary = named.length == 1 && name == expected;
  return AnswerResult(
    correct: true,
    expected: expected,
    matched: hit.flag,
    preferred: typedAsPrimary ? null : expected,
  );
}

/// Whether a short form exists, so the result can call the primary "short form".
bool hasShortForm(Option option) => option.flags.any(isShortFlag);

enum DiffKind { same, added, removed }

class DiffPart {
  DiffPart(this.kind, this.text);
  final DiffKind kind;
  String text;
}

/// A character diff from [from] to [to] (longest common subsequence).
List<DiffPart> diffChars(String from, String to) {
  final a = from.runes.map(String.fromCharCode).toList();
  final b = to.runes.map(String.fromCharCode).toList();
  final lengths = List.generate(
    a.length + 1,
    (_) => List<int>.filled(b.length + 1, 0),
  );
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lengths[i][j] = a[i] == b[j]
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] > lengths[i][j + 1]
                ? lengths[i + 1][j]
                : lengths[i][j + 1]);
    }
  }
  final parts = <DiffPart>[];
  void push(DiffKind kind, String text) {
    if (parts.isNotEmpty && parts.last.kind == kind) {
      parts.last.text += text;
    } else {
      parts.add(DiffPart(kind, text));
    }
  }

  var i = 0, j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      push(DiffKind.same, a[i]);
      i++;
      j++;
    } else if (j < b.length &&
        (i == a.length || lengths[i][j + 1] >= lengths[i + 1][j])) {
      push(DiffKind.added, b[j]);
      j++;
    } else {
      push(DiffKind.removed, a[i]);
      i++;
    }
  }
  return parts;
}
