/// FSRS-6 scheduling, a line-by-line port of the parts of ts-fsrs 5.4 the web
/// app uses (`src/core/scheduler/fsrs.ts`): default weights, learning steps
/// 1m and 10m, relearning step 10m, short-term scheduling on, fuzz off.
///
/// `test/fsrs_test.dart` checks it against sequences graded by ts-fsrs itself
/// (`tools/fsrs-golden.ts`), so both apps schedule a card identically.
library;

import 'dart:math' as math;

import 'models.dart';

const _w = <double>[
  0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, //
  0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
  0.0912, 0.0658, 0.1542,
];
const _sMin = 0.001;
const _sMax = 36500.0;
const _maximumInterval = 36500;
const _learningSteps = [1, 10]; // minutes
const _relearningSteps = [10];
const _minute = 60 * 1000;
const _day = 24 * 60 * _minute;

/// JavaScript's `Math.round`: halves round toward positive infinity.
double _jsRound(double x) => (x + 0.5).floorToDouble();

double _roundTo(double x, int decimals) {
  final factor = math.pow(10, decimals).toDouble();
  return _jsRound(x * factor) / factor;
}

double _clamp(double value, double min, double max) =>
    math.min(math.max(value, min), max);

final double _decay = -_w[20];
final double _factor = _roundTo(
  math.exp(math.pow(_decay, -1) * math.log(0.9)) - 1.0,
  8,
);

double _forgettingCurve(num elapsedDays, double stability) => _roundTo(
  math.pow(1 + (_factor * elapsedDays) / stability, _decay).toDouble(),
  8,
);

final _modifiers = <double, double>{};

double _intervalModifier(double retention) => _modifiers[retention] ??=
    _roundTo((math.pow(retention, 1 / _decay) - 1) / _factor, 8);

double _initStability(int g) => math.max(_w[g - 1], 0.1);

double _initDifficulty(int g) =>
    _roundTo(_w[4] - math.exp((g - 1) * _w[5]) + 1, 8);

double _nextDifficulty(double d, int g) {
  final delta = -_w[6] * (g - 3);
  final next = d + _roundTo((delta * (10 - d)) / 9, 8);
  final reverted = _roundTo(_w[7] * _initDifficulty(4) + (1 - _w[7]) * next, 8);
  return _clamp(reverted, 1, 10);
}

double _nextRecallStability(double d, double s, double r, int g) {
  final hardPenalty = g == 2 ? _w[15] : 1.0;
  final easyBonus = g == 4 ? _w[16] : 1.0;
  return _roundTo(
    _clamp(
      s *
          (1 +
              math.exp(_w[8]) *
                  (11 - d) *
                  math.pow(s, -_w[9]) *
                  (math.exp((1 - r) * _w[10]) - 1) *
                  hardPenalty *
                  easyBonus),
      _sMin,
      _sMax,
    ),
    8,
  );
}

double _nextForgetStability(double d, double s, double r) => _roundTo(
  _clamp(
    _w[11] *
        math.pow(d, -_w[12]) *
        (math.pow(s + 1, _w[13]) - 1) *
        math.exp((1 - r) * _w[14]),
    _sMin,
    _sMax,
  ),
  8,
);

double _nextShortTermStability(double s, int g) {
  final sinc = math.pow(s, -_w[19]) * math.exp(_w[17] * (g - 3 + _w[18]));
  final masked = g >= 2 ? math.max(sinc, 1.0) : sinc;
  return _roundTo(_clamp(s * masked, _sMin, _sMax), 8);
}

({double difficulty, double stability}) _memory(
  double d,
  double s,
  int t,
  int g,
  double? r,
) {
  if (d == 0 && s == 0) {
    return (
      difficulty: _clamp(_initDifficulty(g), 1, 10),
      stability: _initStability(g),
    );
  }
  final recall = r ?? _forgettingCurve(t, s);
  double newS;
  if (t == 0) {
    newS = _nextShortTermStability(s, g);
  } else if (g == 1) {
    final afterFail = _nextForgetStability(d, s, recall);
    final minS = s / math.exp(_w[17] * _w[18]);
    newS = _clamp(_roundTo(minS, 8), _sMin, afterFail);
  } else {
    newS = _nextRecallStability(d, s, recall, g);
  }
  return (difficulty: _nextDifficulty(d, g), stability: newS);
}

int _nextInterval(double s, double retention) => math.min(
  math.max(1, _jsRound(s * _intervalModifier(retention)).toInt()),
  _maximumInterval,
);

/// Calendar days between two instants, by UTC date (ts-fsrs `dateDiffInDays`).
int _utcDayDiff(int from, int to) {
  final a = DateTime.fromMillisecondsSinceEpoch(from, isUtc: true);
  final b = DateTime.fromMillisecondsSinceEpoch(to, isUtc: true);
  final ua = DateTime.utc(a.year, a.month, a.day).millisecondsSinceEpoch;
  final ub = DateTime.utc(b.year, b.month, b.day).millisecondsSinceEpoch;
  return ((ub - ua) / _day).floor();
}

/// A card that has never been reviewed, due immediately.
FsrsState newFsrsState(int now) => FsrsState(
  phase: CardPhase.newCard,
  due: now,
  stability: 0,
  difficulty: 0,
  elapsedDays: 0,
  scheduledDays: 0,
  learningSteps: 0,
  reps: 0,
  lapses: 0,
);

/// Minutes and next step for a grade in a learning phase, or null to graduate.
({int minutes, int next})? _step(CardPhase phase, int current, int g) {
  final steps = phase == CardPhase.relearning || phase == CardPhase.review
      ? _relearningSteps
      : _learningSteps;
  if (steps.isEmpty || current >= steps.length) return null;
  if (phase == CardPhase.review) {
    return g == 1 ? (minutes: steps[math.max(0, current)], next: 0) : null;
  }
  switch (g) {
    case 1:
      return (minutes: steps.first, next: 0);
    case 2:
      final hard = steps.length == 1
          ? _jsRound(steps.first * 1.5).toInt()
          : _jsRound((steps[0] + steps[1]) / 2).toInt();
      return (minutes: hard, next: current);
    case 3:
      return current + 1 < steps.length
          ? (minutes: steps[current + 1], next: current + 1)
          : null;
    default:
      return null;
  }
}

/// The state after grading. [before] is null for a card never seen.
FsrsState nextState(
  FsrsState? before,
  Rating rating,
  int now,
  double desiredRetention,
) {
  final last = before ?? newFsrsState(now);
  final g = rating.value;
  final elapsed = last.phase != CardPhase.newCard && last.lastReview != null
      ? _utcDayDiff(last.lastReview!, now)
      : 0;
  final reps = last.reps + 1;

  FsrsState build({
    required CardPhase phase,
    required int due,
    required ({double difficulty, double stability}) memory,
    required int scheduledDays,
    required int learningSteps,
    int lapses = 0,
  }) => FsrsState(
    phase: phase,
    due: due,
    stability: memory.stability,
    difficulty: memory.difficulty,
    elapsedDays: elapsed,
    scheduledDays: scheduledDays,
    learningSteps: learningSteps,
    reps: reps,
    lapses: last.lapses + lapses,
    lastReview: now,
  );

  /// ts-fsrs `applyLearningSteps`: a learning step, or graduation to review.
  FsrsState withSteps(
    ({double difficulty, double stability}) memory,
    CardPhase toPhase, {
    int lapses = 0,
  }) {
    final step = _step(last.phase, last.learningSteps, g);
    final minutes = step?.minutes ?? 0;
    if (minutes > 0 && minutes < 1440) {
      return build(
        phase: toPhase,
        due: now + minutes * _minute,
        memory: memory,
        scheduledDays: 0,
        learningSteps: step!.next,
        lapses: lapses,
      );
    }
    if (minutes >= 1440) {
      return build(
        phase: CardPhase.review,
        due: now + minutes * _minute,
        memory: memory,
        scheduledDays: minutes ~/ 1440,
        learningSteps: step!.next,
        lapses: lapses,
      );
    }
    final interval = _nextInterval(memory.stability, desiredRetention);
    return build(
      phase: CardPhase.review,
      due: now + interval * _day,
      memory: memory,
      scheduledDays: interval,
      learningSteps: 0,
      lapses: lapses,
    );
  }

  switch (last.phase) {
    case CardPhase.newCard:
      return withSteps(
        _memory(last.difficulty, last.stability, elapsed, g, null),
        CardPhase.learning,
      );
    case CardPhase.learning:
    case CardPhase.relearning:
      return withSteps(
        _memory(last.difficulty, last.stability, elapsed, g, null),
        last.phase,
      );
    case CardPhase.review:
      final r = _forgettingCurve(elapsed, last.stability);
      ({double difficulty, double stability}) m(int grade) =>
          _memory(last.difficulty, last.stability, elapsed, grade, r);
      if (g == 1) {
        return withSteps(m(1), CardPhase.relearning, lapses: 1);
      }
      final hardM = m(2), goodM = m(3), easyM = m(4);
      var hard = _nextInterval(hardM.stability, desiredRetention);
      var good = _nextInterval(goodM.stability, desiredRetention);
      hard = math.min(hard, good);
      good = math.max(good, hard + 1);
      final easy = math.max(
        _nextInterval(easyM.stability, desiredRetention),
        good + 1,
      );
      final (memory, interval) = switch (g) {
        2 => (hardM, hard),
        3 => (goodM, good),
        _ => (easyM, easy),
      };
      return build(
        phase: CardPhase.review,
        due: now + interval * _day,
        memory: memory,
        scheduledDays: interval,
        learningSteps: 0,
      );
  }
}

/// Probability the card is recalled at [now], 0–1. New cards report 0.
double retrievability(FsrsState state, int now) {
  if (state.phase == CardPhase.newCard) return 0;
  final last = state.lastReview;
  final t = last == null ? 0 : math.max(((now - last) / _day).floor(), 0);
  return _forgettingCurve(t, _roundTo(state.stability, 8));
}

/// Rebuilds a card's state by replaying its grades, oldest first.
FsrsState? replay(
  Iterable<({int reviewedAt, Rating rating})> reviews,
  double desiredRetention,
) {
  FsrsState? state;
  for (final r in reviews) {
    state = nextState(state, r.rating, r.reviewedAt, desiredRetention);
  }
  return state;
}
