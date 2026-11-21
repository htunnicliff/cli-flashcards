import 'package:cliflashcards/core/library.dart';
import 'package:cliflashcards/core/models.dart';
import 'package:cliflashcards/core/review_format.dart';
import 'package:cliflashcards/core/setting_limits.dart';
import 'package:cliflashcards/core/stats.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('formatInterval', () {
    expect(formatInterval(30000), '<1m');
    expect(formatInterval(10 * minute), '10m');
    expect(formatInterval(3 * 3600000), '3h');
    expect(formatInterval(4 * day), '4d');
    expect(formatInterval(75 * day), '2.5mo');
    expect(formatInterval(438 * day), '1.2y');
  });

  test('formatNextDue', () {
    expect(formatNextDue(noon + 12 * minute, noon), 'in 12 minutes');
    expect(formatNextDue(noon + 3 * 3600000, noon), 'today at 3:00 PM');
    expect(
      formatNextDue(noon + day - 3 * 3600000, noon),
      'tomorrow at 9:00 AM',
    );
  });

  test('commandParts', () {
    final parts = commandParts('rg ____ <pattern> src');
    expect(parts.map((p) => p.kind), [
      PartKind.tool,
      PartKind.blank,
      PartKind.arg,
      PartKind.tool,
    ]);
  });

  test('flavor and variants', () {
    expect(variantForFlavor(['bsd', 'gnu'], DeckFlavor.bsd), 'bsd');
    expect(variantForFlavor(['default'], DeckFlavor.gnu), 'default');
    expect(
      resolveFlavor(null, ['gnu', 'gnu', 'bsd'], DeckFlavor.bsd),
      DeckFlavor.gnu,
    );
    expect(resolveFlavor(null, [], DeckFlavor.bsd), DeckFlavor.bsd);
  });

  test('searchOptions puts flag prefix matches first', () {
    final options = [
      option('count', ['-c', '--count']),
      option('ignore-case', ['-i', '--ignore-case']),
    ];
    expect(searchOptions(options, '--ign').map((o) => o.id), ['ignore-case']);
    expect(searchOptions(options, 'summary').length, 2);
  });

  test('describeChanges', () {
    final a = deck([
      option('a', ['-a']),
    ]);
    final b = deck([
      option('b', ['-b']),
      option('c', ['-c']),
    ]);
    expect(describeChanges(diffDecks(a, b)), '2 options added, 1 removed');
  });

  test('setting limits clamp and step', () {
    expect(desiredRetentionLimits.normalize(0.5), 0.7);
    expect(desiredRetentionLimits.normalize(0.904), 0.9);
    expect(newCardsPerDayLimits.normalize(12.6), 13);
  });

  test('streak counts through yesterday before today’s first review', () {
    final byDay = reviewsByDay([
      for (final offset in [1, 2, 4])
        ReviewLogEntry(
          cardId: 'x',
          deckId: 'd',
          reviewedAt: noon - offset * day,
          rating: Rating.good,
          durationMs: 0,
          before: null,
          after: FsrsStateTest.any,
        ),
    ], 4);
    expect(currentStreak(byDay, noon, 4), 2);
    expect(heatLevel(3, 12), 1);
    expect(heatLevel(12, 12), 4);
  });
}

extension FsrsStateTest on FsrsState {
  static const any = FsrsState(
    phase: CardPhase.review,
    due: 0,
    stability: 1,
    difficulty: 5,
    elapsedDays: 0,
    scheduledDays: 1,
    learningSteps: 0,
    reps: 1,
    lapses: 0,
  );
}
