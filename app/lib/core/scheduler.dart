/// The app's entry point to scheduling, ported from
/// `src/core/scheduler/scheduler.ts`. The clock is passed in.
library;

import '../schema/cards.dart';
import 'day.dart';
import 'fsrs.dart';
import 'models.dart';
import 'queue.dart';
import 'repository.dart';

class GradeResult {
  const GradeResult(this.state, this.entry, this.becameLeech);
  final CardState state;

  /// Carries its stored ID.
  final ReviewLogEntry entry;

  /// True when this grade made the card a leech, which also suspended it.
  final bool becameLeech;
}

/// A card's state before a suspend or bury, so it can be put back.
class PreviousState {
  const PreviousState(this.cardId, this.state);
  final String cardId;
  final CardState? state;
}

enum SetAside { suspend, bury }

class Scheduler {
  Scheduler(this.repository);

  final Repository repository;

  Future<Card> _findCard(String cardId) async {
    for (final stored in await repository.listDecks()) {
      // Every card type, so a card can be graded whatever the settings.
      for (final card in deriveCards(stored.deck, flagPairs: true)) {
        if (card.id == cardId) return card;
      }
    }
    throw StateError('No installed deck has card "$cardId"');
  }

  /// What to study at [now], across every installed deck.
  Future<Queue> queue(int now) async {
    final settings = await repository.settings();
    final decks = await repository.listDecks();
    final day = studyDay(now, settings.dayRolloverHour);
    final states = await repository.allCardStates();
    final todaysLog = await repository.reviewsBetween(day.start, day.end);
    return buildQueue(
      decks: decks,
      states: states,
      todaysLog: todaysLog,
      settings: settings,
      now: now,
    );
  }

  /// When the next card studied before comes due after [now], or null.
  Future<int?> nextDue(int now) async {
    final settings = await repository.settings();
    final decks = (await repository.listDecks()).where((d) => !d.paused);
    final states = await repository.allCardStates();
    final live = {
      for (final d in decks)
        for (final c in deriveCards(d.deck, flagPairs: settings.flagPairs))
          c.id,
    };
    int? next;
    for (final state in states) {
      if (!live.contains(state.cardId) ||
          state.suspended ||
          state.fsrs.phase == CardPhase.newCard) {
        continue;
      }
      final buried = state.buriedUntil ?? 0;
      final due = state.fsrs.due > buried ? state.fsrs.due : buried;
      if (due > now && (next == null || due < next)) next = due;
    }
    return next;
  }

  /// Grades a card: stores its next FSRS state and a review log entry.
  Future<GradeResult> grade(
    String cardId,
    Rating rating,
    int now, {
    int durationMs = 0,
  }) async {
    final settings = await repository.settings();
    final previous = await repository.getCardState(cardId);
    final (deckId, optionId) = previous != null
        ? (previous.deckId, previous.optionId)
        : await _findCard(cardId).then((c) => (c.deckId, c.optionId));
    final before = previous != null && previous.fsrs.phase != CardPhase.newCard
        ? previous.fsrs
        : null;
    final after = nextState(before, rating, now, settings.desiredRetention);
    final lapsed = after.lapses > (before?.lapses ?? 0);
    final becameLeech =
        lapsed &&
        after.lapses >= settings.leechThreshold &&
        !(previous?.leech ?? false);
    final state = CardState(
      cardId: cardId,
      deckId: deckId,
      optionId: optionId,
      fsrs: after,
      suspended: becameLeech || (previous?.suspended ?? false),
      buriedUntil: previous?.buriedUntil,
      leech: becameLeech || (previous?.leech ?? false),
    );
    final entry = ReviewLogEntry(
      cardId: cardId,
      deckId: deckId,
      reviewedAt: now,
      rating: rating,
      durationMs: durationMs,
      before: before,
      after: after,
    );
    final id = await repository.recordReview(state, entry);
    return GradeResult(state, entry.withId(id), becameLeech);
  }

  /// Sets cards aside without grading: suspend until unsuspended, bury until
  /// the next study day. Returns their earlier states for [restore].
  Future<List<PreviousState>> setAside(
    List<String> cardIds,
    SetAside how,
    int now,
  ) async {
    final settings = await repository.settings();
    final current = await repository.getCardStates(cardIds);
    final updated = <CardState>[];
    for (final (i, cardId) in cardIds.indexed) {
      var base = current[i];
      if (base == null) {
        final card = await _findCard(cardId);
        base = CardState(
          cardId: cardId,
          deckId: card.deckId,
          optionId: card.optionId,
          fsrs: newFsrsState(now),
        );
      }
      updated.add(
        how == SetAside.suspend
            ? base.copyWith(suspended: true)
            : base.copyWith(
                buriedUntil: () =>
                    nextStudyDayStart(now, settings.dayRolloverHour),
              ),
      );
    }
    await repository.putCardStates(updated);
    return [
      for (final (i, id) in cardIds.indexed) PreviousState(id, current[i]),
    ];
  }

  /// Puts back states returned by [setAside].
  Future<void> restore(List<PreviousState> previous) async {
    await repository.atomically((repo) async {
      await repo.putCardStates([
        for (final p in previous)
          if (p.state != null) p.state!,
      ]);
      await repo.deleteCardStates([
        for (final p in previous)
          if (p.state == null) p.cardId,
      ]);
    });
  }

  Future<void> unsuspend(List<String> cardIds) async {
    final states = await repository.getCardStates(cardIds);
    await repository.putCardStates([
      for (final s in states)
        if (s != null && s.suspended) s.copyWith(suspended: false),
    ]);
  }
}
