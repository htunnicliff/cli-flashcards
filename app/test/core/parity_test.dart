import 'dart:convert';
import 'dart:io';

import 'package:cliflashcards/core/answers.dart';
import 'package:cliflashcards/schema/cards.dart';
import 'package:cliflashcards/schema/deck.dart';
import 'package:cliflashcards/schema/manifest.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final manifest = DeckManifest.fromJson(_json('assets/decks/index.json'));
  final decks = {
    for (final e in manifest.decks)
      e.id: Deck.fromJson(_json('assets/decks/${e.file}')),
  };

  test('parses every built deck listed in the manifest', () {
    expect(decks, isNotEmpty);
    for (final e in manifest.decks) {
      final deck = decks[e.id]!;
      expect(deck.deckVersion, e.deckVersion);
      expect(deck.options.where((o) => !o.hidden).length, e.optionCount);
    }
  });

  test('derives the same cards as the web app', () {
    final golden =
        _json('test/fixtures/cards_golden.json')['cards']
            as Map<String, dynamic>;
    expect(golden.keys.toSet(), decks.keys.toSet());
    for (final MapEntry(key: id, value: expected) in golden.entries) {
      final cards = deriveCards(decks[id]!, flagPairs: true);
      final actual = [
        for (final c in cards)
          {
            'id': c.id,
            'flag': c.flag,
            'answers': c.answers,
            if (c.cloze != null) 'cloze': c.cloze,
            if (c.cloze != null) 'blanked': c.blanked,
            if (c.shown != null) 'shown': c.shown,
            if (c.shown != null) 'targets': c.targets,
          },
      ];
      expect(actual, expected, reason: id);
    }
  });

  test('flag pair cards only appear when asked for', () {
    final deck = decks.values.first;
    expect(deriveCards(deck).any((c) => c.isFlagPair), isFalse);
    expect(deriveCards(deck, flagPairs: true).any((c) => c.isFlagPair), isTrue);
  });

  test('checks typed answers the same way as the web app', () {
    final golden =
        (_json('test/fixtures/answers_golden.json')['answers'] as List)
            .cast<Map<String, dynamic>>();
    for (final g in golden) {
      final deck = decks[g['deck']]!;
      final option = deck.options.firstWhere((o) => o.id == g['option']);
      final result = checkAnswer(
        g['input'] as String,
        option: option,
        options: deck.options,
        style: deck.parsingStyle,
      );
      final reason = '${g['deck']} ${g['option']} "${g['input']}"';
      expect(result.correct, g['correct'], reason: reason);
      expect(result.expected, g['expected'], reason: reason);
      expect(result.matched, g['matched'], reason: reason);
      expect(result.preferred, g['preferred'], reason: reason);
    }
  });

  test('flag pair answers accept only the listed spellings', () {
    final deck = decks.values.first;
    final card = deriveCards(
      deck,
      flagPairs: true,
    ).firstWhere((c) => c.type == CardType.shortToLong);
    final option = deck.options.firstWhere((o) => o.id == card.optionId);
    final right = checkAnswer(
      card.targets!.first,
      option: option,
      options: deck.options,
      only: card.targets,
    );
    expect(right.correct, isTrue);
    final shown = checkAnswer(
      card.shown!,
      option: option,
      options: deck.options,
      only: card.targets,
    );
    expect(shown.correct, isFalse);
  });

  test('diffChars marks what was typed against what was expected', () {
    final parts = diffChars('--ignor-case', '--ignore-case');
    expect(parts.map((p) => '${p.kind.name}:${p.text}').toList(), [
      'same:--ignor',
      'added:e',
      'same:-case',
    ]);
  });
}
