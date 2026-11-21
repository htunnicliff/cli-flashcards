import 'dart:convert';
import 'dart:io';

import 'package:cliflashcards/core/fsrs.dart';
import 'package:cliflashcards/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final golden = jsonDecode(
    File('test/fixtures/fsrs_golden.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final sequences = (golden['sequences'] as List).cast<Map<String, dynamic>>();

  test('matches ts-fsrs on every golden sequence', () {
    var checked = 0;
    for (final (i, sequence) in sequences.indexed) {
      final retention = (sequence['desiredRetention'] as num).toDouble();
      FsrsState? state;
      for (final (j, step) in (sequence['steps'] as List).indexed) {
        final s = step as Map<String, dynamic>;
        state = nextState(
          state,
          Rating.of(s['rating'] as int),
          s['now'] as int,
          retention,
        );
        final expected = FsrsState.fromJson(s['after'] as Map<String, dynamic>);
        expect(state, expected, reason: 'sequence $i step $j');
        expect(
          retrievability(state, s['retrievabilityAt'] as int),
          closeTo((s['retrievability'] as num).toDouble(), 1e-12),
          reason: 'retrievability, sequence $i step $j',
        );
        checked++;
      }
    }
    expect(checked, greaterThan(1000));
  });

  test('a new card is due now and reports zero retrievability', () {
    final state = newFsrsState(1000);
    expect(state.phase, CardPhase.newCard);
    expect(state.due, 1000);
    expect(retrievability(state, 5000), 0);
  });

  test('replay rebuilds the state from grades', () {
    const t = 1767225600000;
    final reviews = [
      (reviewedAt: t, rating: Rating.good),
      (reviewedAt: t + 600000, rating: Rating.good),
      (reviewedAt: t + 3 * 86400000, rating: Rating.again),
    ];
    var state = nextState(null, Rating.good, t, 0.9);
    state = nextState(state, Rating.good, t + 600000, 0.9);
    state = nextState(state, Rating.again, t + 3 * 86400000, 0.9);
    expect(replay(reviews, 0.9), state);
    expect(state.phase, CardPhase.relearning);
    expect(state.lapses, 1);
  });
}
