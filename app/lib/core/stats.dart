/// Stats page numbers, ported from `src/core/stats/stats.ts`.
library;

import 'dart:math' as math;

import '../schema/cards.dart';
import 'day.dart';
import 'models.dart';

/// A card is mature once its interval reaches three weeks.
const matureIntervalDays = 21;

/// Review counts keyed by study-day start.
Map<int, int> reviewsByDay(Iterable<ReviewLogEntry> log, int rolloverHour) {
  final counts = <int, int>{};
  for (final e in log) {
    final day = studyDayStart(e.reviewedAt, rolloverHour);
    counts[day] = (counts[day] ?? 0) + 1;
  }
  return counts;
}

/// Consecutive study days with a review, ending today (or yesterday if today
/// has none yet).
int currentStreak(Map<int, int> byDay, int now, int rolloverHour) {
  var offset = byDay.containsKey(studyDayStart(now, rolloverHour)) ? 0 : -1;
  var streak = 0;
  while (byDay.containsKey(shiftStudyDay(now, offset, rolloverHour))) {
    streak++;
    offset--;
  }
  return streak;
}

class DeckCardCounts {
  DeckCardCounts(this.deckId);
  final String deckId;
  int newCards = 0;
  int learning = 0;
  int review = 0;
  int suspended = 0;
  int get total => newCards + learning + review + suspended;
}

List<DeckCardCounts> cardCountsByDeck(
  List<StoredDeck> decks,
  Iterable<CardState> states, {
  bool flagPairs = false,
}) {
  final byId = {for (final s in states) s.cardId: s};
  return [
    for (final stored in decks)
      () {
        final c = DeckCardCounts(stored.id);
        for (final card in deriveCards(stored.deck, flagPairs: flagPairs)) {
          final s = byId[card.id];
          if (s != null && s.suspended) {
            c.suspended++;
          } else if (s == null || s.fsrs.phase == CardPhase.newCard) {
            c.newCards++;
          } else if (s.fsrs.phase == CardPhase.review) {
            c.review++;
          } else {
            c.learning++;
          }
        }
        return c;
      }(),
  ];
}

class Retention {
  const Retention(this.passed, this.total);
  final int passed;
  final int total;
  double? get rate => total == 0 ? null : passed / total;
}

/// Of reviews of mature cards in the last [days] study days, the share not
/// rated Again.
Retention trueRetention(
  List<ReviewLogEntry> log,
  int now,
  int rolloverHour, [
  int days = 30,
]) {
  final from = shiftStudyDay(now, -(days - 1), rolloverHour);
  var passed = 0, total = 0;
  for (final e in log) {
    if (e.reviewedAt < from || e.reviewedAt > now) continue;
    final b = e.before;
    if (b == null ||
        b.phase != CardPhase.review ||
        b.scheduledDays < matureIntervalDays) {
      continue;
    }
    total++;
    if (e.rating != Rating.again) passed++;
  }
  return Retention(passed, total);
}

class DayCount {
  const DayCount(this.day, this.count);

  /// Study-day start.
  final int day;
  final int count;
}

/// Cards due on each of the next [days] study days, today first.
List<DayCount> dueForecast(
  List<StoredDeck> decks,
  Iterable<CardState> states,
  int now,
  int rolloverHour, {
  int days = 30,
  bool flagPairs = false,
}) {
  final live = {
    for (final d in decks)
      for (final c in deriveCards(d.deck, flagPairs: flagPairs)) c.id,
  };
  final starts = [
    for (var i = 0; i <= days; i++) shiftStudyDay(now, i, rolloverHour),
  ];
  final counts = List<int>.filled(days, 0);
  for (final s in states) {
    if (s.suspended ||
        s.fsrs.phase == CardPhase.newCard ||
        !live.contains(s.cardId)) {
      continue;
    }
    final due = math.max(s.fsrs.due, starts[0]);
    for (var i = 0; i < days; i++) {
      if (due >= starts[i] && due < starts[i + 1]) {
        counts[i]++;
        break;
      }
    }
  }
  return [for (var i = 0; i < days; i++) DayCount(starts[i], counts[i])];
}

/// Reviews on each of the last [days] study days, oldest first.
List<DayCount> reviewHistory(
  Map<int, int> byDay,
  int now,
  int rolloverHour, [
  int days = 365,
]) {
  return [
    for (var i = 0; i < days; i++)
      () {
        final day = shiftStudyDay(now, i - (days - 1), rolloverHour);
        return DayCount(day, byDay[day] ?? 0);
      }(),
  ];
}

/// Heatmap shade 0–4 for a day's count, relative to the busiest day.
int heatLevel(int count, int max) {
  if (count <= 0 || max <= 0) return 0;
  return ((count / max) * 4).ceil().clamp(1, 4);
}

class Stats {
  const Stats({
    required this.reviewsToday,
    required this.streak,
    required this.cards,
    required this.retention,
    required this.forecast,
    required this.history,
  });
  final int reviewsToday;
  final int streak;
  final List<DeckCardCounts> cards;
  final Retention retention;
  final List<DayCount> forecast;
  final List<DayCount> history;
}

Stats computeStats({
  required List<StoredDeck> decks,
  required List<CardState> states,
  required List<ReviewLogEntry> log,
  required int now,
  required int rolloverHour,
  bool flagPairs = false,
}) {
  final byDay = reviewsByDay(log, rolloverHour);
  return Stats(
    reviewsToday: byDay[studyDayStart(now, rolloverHour)] ?? 0,
    streak: currentStreak(byDay, now, rolloverHour),
    cards: cardCountsByDeck(decks, states, flagPairs: flagPairs),
    retention: trueRetention(log, now, rolloverHour),
    forecast: dueForecast(
      decks,
      states,
      now,
      rolloverHour,
      flagPairs: flagPairs,
    ),
    history: reviewHistory(byDay, now, rolloverHour),
  );
}
