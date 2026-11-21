/// Picks what to study now. Ported from `src/core/scheduler/queue.ts`.
library;

import '../schema/cards.dart';
import '../schema/deck.dart';
import 'day.dart';
import 'models.dart';

enum QueueKind { learning, review, newCard }

class QueueItem {
  const QueueItem(this.kind, this.card, [this.state]);
  final QueueKind kind;
  final Card card;

  /// Null for a new card that has never been graded.
  final CardState? state;
}

class QueueToday {
  const QueueToday({
    required this.reviewsDone,
    required this.reviewsLeft,
    required this.newDone,
    required this.newLeft,
  });
  final int reviewsDone;
  final int reviewsLeft;
  final int newDone;
  final int newLeft;
}

class Queue {
  const Queue(this.items, this.today, [this.nextLearningDue]);

  /// Learning steps, then due reviews, then new cards.
  final List<QueueItem> items;
  final QueueToday today;

  /// When the next learning-step card comes due later today, if one does.
  final int? nextLearningDue;
}

const _tierOrder = {Tier.core: 0, Tier.common: 1, Tier.obscure: 2};

String _optionKey(String deckId, String optionId) => '$deckId\u0000$optionId';

/// What a grade counts against, by what the card was before it.
QueueKind _countsAs(ReviewLogEntry entry) {
  final before = entry.before;
  if (before == null || before.phase == CardPhase.newCard) {
    return QueueKind.newCard;
  }
  return before.phase == CardPhase.review
      ? QueueKind.review
      : QueueKind.learning;
}

/// Pure: the caller loads the data and passes [now]. See the TypeScript
/// version for the full rules (sibling burying, tier order, daily limits).
Queue buildQueue({
  required List<StoredDeck> decks,
  required Iterable<CardState> states,
  required List<ReviewLogEntry> todaysLog,
  required Settings settings,
  required int now,
}) {
  final dayEnd = nextStudyDayStart(now, settings.dayRolloverHour);
  final stateById = {for (final s in states) s.cardId: s};

  final gradedToday = <String>{};
  final optionsGradedToday = <String>{};
  var reviewsDone = 0;
  var newDone = 0;
  for (final entry in todaysLog) {
    gradedToday.add(entry.cardId);
    final state = stateById[entry.cardId];
    final parts = entry.cardId.split(':');
    optionsGradedToday.add(
      state != null
          ? _optionKey(state.deckId, state.optionId)
          : _optionKey(entry.deckId, parts.length > 2 ? parts[2] : ''),
    );
    switch (_countsAs(entry)) {
      case QueueKind.review:
        reviewsDone++;
      case QueueKind.newCard:
        newDone++;
      case QueueKind.learning:
        break;
    }
  }

  final learning = <QueueItem>[];
  final reviews = <QueueItem>[];
  final fresh = <({QueueItem item, int tier, int deck, int order})>[];
  int? nextLearningDue;

  for (final (deckIndex, stored) in decks.indexed) {
    if (stored.paused) continue;
    final tierByOption = {for (final o in stored.deck.options) o.id: o.tier};
    final cards = deriveCards(stored.deck, flagPairs: settings.flagPairs);
    for (final (order, card) in cards.indexed) {
      final tier = tierByOption[card.optionId] ?? Tier.common;
      final state = stateById[card.id];
      if (state != null && state.suspended) continue;
      if (state?.buriedUntil != null && state!.buriedUntil! > now) continue;
      final siblingSeen =
          optionsGradedToday.contains(_optionKey(card.deckId, card.optionId)) &&
          !gradedToday.contains(card.id);
      if (siblingSeen) continue;

      final phase = state?.fsrs.phase ?? CardPhase.newCard;
      switch (phase) {
        case CardPhase.learning:
        case CardPhase.relearning:
          final due = state!.fsrs.due;
          if (due <= now) {
            learning.add(QueueItem(QueueKind.learning, card, state));
          } else if (due < dayEnd) {
            nextLearningDue = nextLearningDue == null || due < nextLearningDue
                ? due
                : nextLearningDue;
          }
        case CardPhase.review:
          if (state!.fsrs.due < dayEnd) {
            reviews.add(QueueItem(QueueKind.review, card, state));
          }
        case CardPhase.newCard:
          if (tier == Tier.obscure && !stored.includeObscure) continue;
          fresh.add((
            item: QueueItem(QueueKind.newCard, card, state),
            tier: _tierOrder[tier]!,
            deck: deckIndex,
            order: order,
          ));
      }
    }
  }

  int byDue(QueueItem a, QueueItem b) {
    final d = a.state!.fsrs.due - b.state!.fsrs.due;
    return d != 0 ? d.sign : a.card.id.compareTo(b.card.id);
  }

  learning.sort(byDue);
  reviews.sort(byDue);
  fresh.sort(
    (a, b) => a.tier != b.tier
        ? a.tier - b.tier
        : a.deck != b.deck
        ? a.deck - b.deck
        : a.order - b.order,
  );

  final reviewsLeft = (settings.maxReviewsPerDay - reviewsDone).clamp(
    0,
    1 << 31,
  );
  final newLeft = (settings.newCardsPerDay - newDone).clamp(0, 1 << 31);

  final queued = {
    for (final item in learning)
      _optionKey(item.card.deckId, item.card.optionId),
  };
  List<QueueItem> take(Iterable<QueueItem> candidates, int limit) {
    final taken = <QueueItem>[];
    for (final item in candidates) {
      if (taken.length >= limit) break;
      if (!queued.add(_optionKey(item.card.deckId, item.card.optionId))) {
        continue;
      }
      taken.add(item);
    }
    return taken;
  }

  final dueReviews = take(reviews, reviewsLeft);
  final newCards = take(fresh.map((f) => f.item), newLeft);

  return Queue(
    [...learning, ...dueReviews, ...newCards],
    QueueToday(
      reviewsDone: reviewsDone,
      reviewsLeft: reviewsLeft,
      newDone: newDone,
      newLeft: newLeft,
    ),
    nextLearningDue,
  );
}
