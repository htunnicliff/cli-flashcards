/// The review screen's state, ported from `src/app/review/useReviewSession.ts`.
/// Grading and undo update the screen at once; storage writes run one after
/// another in the background, so fast grading never waits on storage.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/answers.dart';
import '../../core/fsrs.dart';
import '../../core/models.dart';
import '../../core/queue.dart';
import '../../core/review_format.dart';
import '../../core/scheduler.dart';
import '../../schema/cards.dart';
import '../../schema/deck.dart';
import '../app_state.dart';

sealed class _History {
  const _History(this.item);
  final QueueItem item;
}

class _Graded extends _History {
  const _Graded(super.item, this.previous, this.entryId);
  final CardState? previous;
  final int entryId;
}

class _Aside extends _History {
  const _Aside(super.item, this.previous);
  final List<PreviousState> previous;
}

/// How the last card left the screen, so it animates the right way.
sealed class LeaveHint {
  const LeaveHint();
}

class GradedHint extends LeaveHint {
  const GradedHint(this.rating);
  final Rating rating;
}

class AsideHint extends LeaveHint {
  const AsideHint();
}

class ReviewNotice {
  const ReviewNotice(this.id, this.message, {this.undoable = true, this.link});
  final int id;
  final String message;
  final bool undoable;

  /// A route and label, such as a leech's full description.
  final ({String to, String label})? link;
}

class TypedResult {
  const TypedResult(this.typed, this.result);
  final String typed;
  final AnswerResult result;
}

/// The flag to name a card by on screen. A flag pair card goes by the form its
/// front shows, so a label never gives the answer away.
String frontFlag(Card card) => card.isFlagPair ? card.shown! : card.flag;

class ReviewSession extends ChangeNotifier {
  ReviewSession(this.app) {
    _shownAt = app.now();
    _enqueue(_refresh);
  }

  final AppController app;
  Scheduler get _scheduler => app.scheduler;

  List<QueueItem> items = const [];
  QueueToday? today;
  int? nextLearningDue;
  int? nextDue;
  Map<String, Deck> decks = const {};
  Set<String> _typedDecks = const {};
  bool loading = true;
  bool revealed = false;
  double desiredRetention = 0.9;
  bool flagPairs = false;
  int gradedThisSession = 0;
  LeaveHint? leaveHint;
  ReviewNotice? notice;
  int _undoable = 0;
  int _noticeId = 0;
  String? error;
  TypedResult? answer;

  final _history = <_History>[];
  final _pending = <String>{};
  late int _shownAt;
  Future<void> _writes = Future.value();
  Timer? _learningTimer;
  bool _disposed = false;

  QueueItem? get current => items.firstOrNull;
  bool get done => !loading && items.isEmpty;
  bool get canUndo => _undoable > 0;
  bool get hasDecks => decks.isNotEmpty;

  ({int newCards, int learning, int review}) get counts {
    var n = 0, l = 0, r = 0;
    for (final item in items) {
      switch (item.kind) {
        case QueueKind.newCard:
          n++;
        case QueueKind.learning:
          l++;
        case QueueKind.review:
          r++;
      }
    }
    return (newCards: n, learning: l, review: r);
  }

  Deck? get deck => current == null ? null : decks[current!.card.deckId];

  Option? get option {
    final card = current?.card;
    if (card == null) return null;
    return decks[card.deckId]?.options
        .where((o) => o.id == card.optionId)
        .firstOrNull;
  }

  /// `git log` for a subcommand option, otherwise the tool alone.
  String get command {
    final tool = deck?.tool ?? '';
    final sub = option?.subcommand;
    return sub == null ? tool : '$tool $sub';
  }

  /// Whether the card on screen asks for its flag to be typed.
  bool get typing {
    final card = current?.card;
    return card != null &&
        card.type != CardType.flagToMeaning &&
        _typedDecks.contains(card.deckId);
  }

  /// Good when a typed answer was right, Again when wrong.
  Rating? get suggestedRating => answer == null
      ? null
      : answer!.result.correct
      ? Rating.good
      : Rating.again;

  /// Next interval label for each rating.
  Map<Rating, String> get intervals {
    final item = current;
    if (item == null) return const {};
    final at = app.now();
    final state = item.state;
    final before = state != null && state.fsrs.phase != CardPhase.newCard
        ? state.fsrs
        : null;
    return {
      for (final r in Rating.values)
        r: formatInterval(nextState(before, r, at, desiredRetention).due - at),
    };
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() work) {
    _writes = _writes.then((_) => work()).catchError((Object e) {
      error = '$e';
      _notify();
    });
    return _writes;
  }

  /// Reloads the queue, keeping the card on screen in front if still due.
  Future<void> _refresh() async {
    final now = app.now();
    final queue = await _scheduler.queue(now);
    final stored = await app.repository.listDecks();
    final settings = await app.repository.settings();
    final upcoming = await _scheduler.nextDue(now);
    if (_disposed) return;
    flagPairs = settings.flagPairs;
    decks = {for (final s in stored) s.id: s.deck};
    _typedDecks = {
      for (final s in stored)
        if (s.typeAnswers) s.id,
    };
    desiredRetention = settings.desiredRetention;
    today = queue.today;
    nextLearningDue = queue.nextLearningDue;
    nextDue = upcoming;
    final onScreen = items.firstOrNull;
    var next = [
      for (final i in queue.items)
        if (!_pending.contains(i.card.id)) i,
    ];
    if (onScreen != null && !loading) {
      final fresh = next
          .where((i) => i.card.id == onScreen.card.id)
          .firstOrNull;
      next = [
        fresh ?? onScreen,
        ...next.where((i) => i.card.id != onScreen.card.id),
      ];
    }
    items = next;
    loading = false;
    _scheduleLearningRefresh();
    _notify();
  }

  Future<void> refresh() => _enqueue(_refresh);

  /// When only learning cards remain for later today, come back when one is due.
  void _scheduleLearningRefresh() {
    _learningTimer?.cancel();
    _learningTimer = null;
    final due = nextLearningDue;
    if (items.isNotEmpty || due == null) return;
    final wait = math.max(0, due - app.now()) + 50;
    _learningTimer = Timer(
      Duration(milliseconds: math.min(wait, 1 << 31)),
      () => _enqueue(_refresh),
    );
  }

  void reveal() {
    if (current == null || revealed) return;
    revealed = true;
    _notify();
  }

  /// Checks a typed answer against the card on screen and reveals the back.
  void submitAnswer(String typed) {
    final item = current;
    final target = option;
    if (item == null || target == null || revealed) return;
    final d = deck;
    answer = TypedResult(
      typed,
      checkAnswer(
        typed,
        option: target,
        options: d?.options ?? [target],
        style: d?.parsingStyle,
        only: item.card.isFlagPair ? item.card.targets : null,
      ),
    );
    revealed = true;
    _notify();
  }

  void _advance(QueueItem item, Iterable<String> removed) {
    _undoable++;
    final gone = removed.toSet();
    items = [
      for (final i in items)
        if (!gone.contains(i.card.id)) i,
    ];
    revealed = false;
    answer = null;
    _shownAt = app.now();
  }

  /// Grades the card on screen and moves on at once; the write follows.
  void grade(Rating rating) {
    final item = current;
    if (item == null || !revealed) return;
    final at = app.now();
    final durationMs = at - _shownAt;
    leaveHint = GradedHint(rating);
    _advance(item, [item.card.id]);
    gradedThisSession++;
    _pending.add(item.card.id);
    _notify();
    _enqueue(() async {
      final previous = await app.repository.getCardState(item.card.id);
      try {
        final result = await _scheduler.grade(
          item.card.id,
          rating,
          at,
          durationMs: durationMs,
        );
        _history.add(_Graded(item, previous, result.entry.id!));
        if (result.becameLeech) {
          _showNotice(
            'Forgotten ${result.state.fsrs.lapses} times, so this card is now '
            'suspended as a leech.',
            undoable: false,
            link: (
              to: '/decks/${item.card.deckId}?option=${item.card.optionId}',
              label: 'Read the full description',
            ),
          );
        }
      } finally {
        _pending.remove(item.card.id);
      }
      await _refresh();
    });
  }

  /// Takes back the last action: the card returns, unrevealed.
  Future<void> undo() => _enqueue(() async {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    switch (last) {
      case _Graded(:final entryId, :final previous):
        await app.repository.undoReview(entryId, last.item.card.id, previous);
        gradedThisSession = math.max(0, gradedThisSession - 1);
      case _Aside(:final previous):
        await _scheduler.restore(previous);
    }
    _undoable = math.max(0, _undoable - 1);
    notice = null;
    leaveHint = null;
    items = [last.item, ...items.where((i) => i.card.id != last.item.card.id)];
    revealed = false;
    answer = null;
    _shownAt = app.now();
    await _refresh();
  });

  /// Suspends the card on screen (or every card for its option), or buries it
  /// until tomorrow.
  void setAside(SetAside how, {bool wholeOption = false}) {
    final item = current;
    if (item == null) return;
    final at = app.now();
    final cardIds = wholeOption
        ? [
            for (final c in deriveCards(
              decks[item.card.deckId]!,
              flagPairs: true,
            ))
              if (c.optionId == item.card.optionId) c.id,
          ]
        : [item.card.id];
    leaveHint = const AsideHint();
    _advance(item, cardIds);
    _pending.addAll(cardIds);
    _showNotice(switch ((how, wholeOption)) {
      (SetAside.bury, _) => 'Skipped until tomorrow.',
      (SetAside.suspend, true) =>
        'Suspended every card for ${frontFlag(item.card)}.',
      (SetAside.suspend, false) => 'Card suspended.',
    });
    _enqueue(() async {
      try {
        final previous = await _scheduler.setAside(cardIds, how, at);
        _history.add(_Aside(item, previous));
      } finally {
        _pending.removeAll(cardIds);
      }
      await _refresh();
    });
  }

  void _showNotice(
    String message, {
    bool undoable = true,
    ({String to, String label})? link,
  }) {
    notice = ReviewNotice(++_noticeId, message, undoable: undoable, link: link);
    _notify();
  }

  void dismissNotice() {
    notice = null;
    _notify();
  }

  /// Resolves once every queued write has finished.
  @visibleForTesting
  Future<void> settled() => _writes;

  @override
  void dispose() {
    _disposed = true;
    _learningTimer?.cancel();
    super.dispose();
  }
}
