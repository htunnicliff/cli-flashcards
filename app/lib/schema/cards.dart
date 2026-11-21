/// Cards derived from deck options at runtime, ported from `src/schema/cards.ts`.
/// Card IDs must match the web app's exactly, so progress carries over.
library;

import 'deck.dart';
import 'flags.dart';

enum CardType {
  flagToMeaning('flag-to-meaning'),
  meaningToFlag('meaning-to-flag'),
  cloze('cloze'),
  shortToLong('short-to-long'),
  longToShort('long-to-short');

  const CardType(this.id);

  /// The spelling used in card IDs.
  final String id;

  bool get isFlagPair => this == shortToLong || this == longToShort;
}

/// Shown in place of the flag on cloze cards.
const clozeBlank = '____';

class Card {
  const Card({
    required this.id,
    required this.type,
    required this.deckId,
    required this.optionId,
    required this.flag,
    required this.answers,
    required this.summary,
    required this.detail,
    this.cloze,
    this.command,
    this.blanked,
    this.exampleDescription,
    this.shown,
    this.targets,
  });

  /// `{tool}:{variant}:{optionId}:{cardType}`.
  final String id;
  final CardType type;
  final String deckId;
  final String optionId;

  /// The option's primary flag.
  final String flag;

  /// Every accepted spelling, primary first.
  final List<String> answers;
  final String summary;
  final String detail;

  // Cloze cards.
  final String? cloze;
  final String? command;
  final String? blanked;
  final String? exampleDescription;

  // Flag pair cards.
  /// The one spelling the front shows.
  final String? shown;

  /// The spellings of the other form that count, the expected one first.
  final List<String>? targets;

  bool get isFlagPair => type.isFlagPair;
}

String cardId(Deck deck, String optionId, CardType type) =>
    '${deck.tool}:${deck.variant}:$optionId:${type.id}';

/// `primary` when set, otherwise the first flag.
String primaryFlag(Option option) => option.primary ?? option.flags.first;

/// All spellings with the primary flag first.
List<String> answerFlags(Option option) {
  final primary = primaryFlag(option);
  return [primary, ...option.flags.where((f) => f != primary)];
}

class ClozeMatch {
  const ClozeMatch(this.command, this.cloze, this.blanked, this.description);
  final String command;
  final String cloze;
  final String blanked;
  final String? description;
}

final _whitespaceSplit = RegExp(r'(\s+)');

/// Splits like JS `str.split(/(\s+)/)`: words and the whitespace between them.
List<String> _splitKeepingSpace(String s) {
  final parts = <String>[];
  var last = 0;
  for (final m in _whitespaceSplit.allMatches(s)) {
    parts.add(s.substring(last, m.start));
    parts.add(m.group(0)!);
    last = m.end;
  }
  parts.add(s.substring(last));
  return parts;
}

/// The first example that spells one of the option's flags as its own token,
/// preferring the primary flag.
ClozeMatch? findCloze(Option option) {
  for (final flag in answerFlags(option)) {
    for (final example in option.examples) {
      final tokens = _splitKeepingSpace(example.command);
      final index = tokens.indexWhere(
        (t) => t == flag || t.startsWith('$flag='),
      );
      if (index == -1) continue;
      tokens[index] = clozeBlank + tokens[index].substring(flag.length);
      return ClozeMatch(
        example.command,
        tokens.join(),
        flag,
        example.description,
      );
    }
  }
  return null;
}

/// The option's short and long spellings, or null when it lacks one form.
({List<String> short, List<String> long})? flagPair(Option option) {
  final flags = answerFlags(option);
  final short = flags.where(isShortFlag).toList();
  final long = flags.where(isLongFlag).toList();
  return short.isNotEmpty && long.isNotEmpty
      ? (short: short, long: long)
      : null;
}

List<Card> _optionCards(Deck deck, Option option, bool flagPairs) {
  Card make(
    CardType type, {
    String? cloze,
    String? command,
    String? blanked,
    String? exampleDescription,
    String? shown,
    List<String>? targets,
  }) => Card(
    id: cardId(deck, option.id, type),
    type: type,
    deckId: deck.id,
    optionId: option.id,
    flag: primaryFlag(option),
    answers: answerFlags(option),
    summary: option.summary,
    detail: option.description,
    cloze: cloze,
    command: command,
    blanked: blanked,
    exampleDescription: exampleDescription,
    shown: shown,
    targets: targets,
  );

  final cards = [make(CardType.flagToMeaning), make(CardType.meaningToFlag)];
  final cloze = findCloze(option);
  if (cloze != null) {
    cards.add(
      make(
        CardType.cloze,
        cloze: cloze.cloze,
        command: cloze.command,
        blanked: cloze.blanked,
        exampleDescription: cloze.description,
      ),
    );
  }
  final pair = flagPairs ? flagPair(option) : null;
  if (pair != null) {
    cards
      ..add(
        make(CardType.shortToLong, shown: pair.short.first, targets: pair.long),
      )
      ..add(
        make(CardType.longToShort, shown: pair.long.first, targets: pair.short),
      );
  }
  return cards;
}

final _cache = Expando<Map<bool, List<Card>>>();

/// Every card for a deck: each visible option × each card type that applies.
/// Results are cached per deck instance, since decks are immutable.
List<Card> deriveCards(Deck deck, {bool flagPairs = false}) {
  final perDeck = _cache[deck] ??= {};
  return perDeck[flagPairs] ??= List.unmodifiable([
    for (final option in deck.options)
      if (!option.hidden) ..._optionCards(deck, option, flagPairs),
  ]);
}
