import 'package:cliflashcards/core/day.dart';
import 'package:cliflashcards/core/models.dart';
import 'package:cliflashcards/core/queue.dart';
import 'package:cliflashcards/core/scheduler.dart';
import 'package:cliflashcards/schema/deck.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late Scheduler scheduler;

  final testDeck = deck([
    option('ignore-case', ['-i', '--ignore-case']),
    option('word-regexp', ['-w', '--word-regexp']),
    option('count', ['-c', '--count'], tier: Tier.common),
    option('pre', ['--pre'], tier: Tier.obscure),
  ]);

  setUp(() async {
    final repo = await memoryRepository();
    await repo.installDeck(testDeck, now: noon);
    await repo.updateSettings((s) => s.copyWith(flagPairs: false));
    scheduler = Scheduler(repo);
  });

  test(
    'new cards come one per option, core tier first, obscure left out',
    () async {
      final queue = await scheduler.queue(noon);
      expect(queue.items.map((i) => i.card.id), [
        'rg:default:ignore-case:flag-to-meaning',
        'rg:default:word-regexp:flag-to-meaning',
        'rg:default:count:flag-to-meaning',
      ]);
      expect(queue.items.every((i) => i.kind == QueueKind.newCard), isTrue);
      expect(queue.today.newLeft, 20);
    },
  );

  test(
    'grading a new card starts its learning steps and buries siblings',
    () async {
      const id = 'rg:default:ignore-case:flag-to-meaning';
      final result = await scheduler.grade(id, Rating.good, noon);
      expect(result.state.fsrs.phase, CardPhase.learning);
      expect(result.entry.id, isNotNull);

      final later = await scheduler.queue(noon + 11 * minute);
      expect(later.items.first.card.id, id);
      expect(later.items.first.kind, QueueKind.learning);
      expect(
        later.items
            .map((i) => i.card.optionId)
            .where((o) => o == 'ignore-case'),
        hasLength(1),
      );
      expect(later.today.newDone, 1);
    },
  );

  test('daily new card limit counts grades from today', () async {
    await scheduler.repository.updateSettings(
      (s) => s.copyWith(newCardsPerDay: 1),
    );
    expect((await scheduler.queue(noon)).items, hasLength(1));
    await scheduler.grade(
      'rg:default:ignore-case:flag-to-meaning',
      Rating.easy,
      noon,
    );
    final queue = await scheduler.queue(noon + minute);
    expect(queue.items.where((i) => i.kind == QueueKind.newCard), isEmpty);
    expect(queue.today.newLeft, 0);
  });

  test('a card that lapses enough times becomes a suspended leech', () async {
    await scheduler.repository.updateSettings(
      (s) => s.copyWith(leechThreshold: 2),
    );
    const id = 'rg:default:count:meaning-to-flag';
    var t = noon;
    await scheduler.grade(id, Rating.easy, t);
    GradeResult? last;
    for (var i = 0; i < 2; i++) {
      final state = await scheduler.repository.getCardState(id);
      t = state!.fsrs.due + minute;
      await scheduler.grade(id, Rating.again, t); // lapse
      t += 11 * minute;
      last = await scheduler.grade(id, Rating.easy, t);
    }
    final state = await scheduler.repository.getCardState(id);
    expect(state!.leech, isTrue);
    expect(state.suspended, isTrue);
    expect(last!.becameLeech, isFalse);
  });

  test(
    'bury hides a card until the next study day; restore puts it back',
    () async {
      const id = 'rg:default:ignore-case:flag-to-meaning';
      final previous = await scheduler.setAside([id], SetAside.bury, noon);
      final buried = await scheduler.repository.getCardState(id);
      expect(buried!.buriedUntil, nextStudyDayStart(noon, 4));
      expect(
        (await scheduler.queue(noon)).items.map((i) => i.card.id),
        isNot(contains(id)),
      );
      await scheduler.restore(previous);
      expect(await scheduler.repository.getCardState(id), isNull);
    },
  );

  test('suspend and unsuspend', () async {
    const id = 'rg:default:word-regexp:flag-to-meaning';
    await scheduler.setAside([id], SetAside.suspend, noon);
    expect((await scheduler.repository.getCardState(id))!.suspended, isTrue);
    await scheduler.unsuspend([id]);
    expect((await scheduler.repository.getCardState(id))!.suspended, isFalse);
  });

  test('nextDue reports the earliest studied card', () async {
    await scheduler.grade(
      'rg:default:ignore-case:flag-to-meaning',
      Rating.again,
      noon,
    );
    expect(await scheduler.nextDue(noon), noon + minute);
  });

  test('undo removes the grade and restores the state', () async {
    const id = 'rg:default:ignore-case:flag-to-meaning';
    final result = await scheduler.grade(id, Rating.good, noon);
    await scheduler.repository.undoReview(result.entry.id!, id, null);
    expect(await scheduler.repository.getCardState(id), isNull);
    expect(await scheduler.repository.reviewCount(), 0);
  });

  test('study days roll over at the configured hour', () {
    final twoAm = DateTime(2026, 3, 10, 2).millisecondsSinceEpoch;
    expect(
      studyDayStart(twoAm, 4),
      DateTime(2026, 3, 9, 4).millisecondsSinceEpoch,
    );
    expect(
      nextStudyDayStart(twoAm, 4),
      DateTime(2026, 3, 10, 4).millisecondsSinceEpoch,
    );
  });
}
