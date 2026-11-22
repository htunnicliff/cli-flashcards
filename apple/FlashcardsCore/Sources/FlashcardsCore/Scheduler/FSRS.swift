// FSRS-6 scheduling, a line-by-line port of the parts of ts-fsrs 5.4 the apps
// use (`pipeline/core/fsrs.ts`):
// default weights, learning steps 1m and 10m, relearning step 10m, short-term
// scheduling on, fuzz off.
//
// The parity tests check it against sequences graded by ts-fsrs itself
// (`tools/fixtures-golden.ts`), so the app schedules a card identically.

import Foundation

private let w: [Double] = [
    0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722,
    0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
    0.0912, 0.0658, 0.1542,
]
private let sMin = 0.001
private let sMax = 36500.0
private let maximumInterval = 36500
private let learningStepMinutes = [1, 10]
private let relearningStepMinutes = [10]
private let minute = 60 * 1000
let dayMillis = 24 * 60 * minute

/// JavaScript's `Math.round`: halves round toward positive infinity.
private func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

private func roundTo(_ x: Double, _ decimals: Int) -> Double {
    let factor = pow(10, Double(decimals))
    return jsRound(x * factor) / factor
}

private func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
    min(max(value, lo), hi)
}

private let decay = -w[20]
private let factor = roundTo(exp(pow(decay, -1) * log(0.9)) - 1.0, 8)

private func forgettingCurve(_ elapsedDays: Int, _ stability: Double) -> Double {
    roundTo(pow(1 + (factor * Double(elapsedDays)) / stability, decay), 8)
}

private func intervalModifier(_ retention: Double) -> Double {
    roundTo((pow(retention, 1 / decay) - 1) / factor, 8)
}

private func initStability(_ g: Int) -> Double { max(w[g - 1], 0.1) }

private func initDifficulty(_ g: Int) -> Double {
    roundTo(w[4] - exp(Double(g - 1) * w[5]) + 1, 8)
}

private func nextDifficulty(_ d: Double, _ g: Int) -> Double {
    let delta = -w[6] * Double(g - 3)
    let next = d + roundTo((delta * (10 - d)) / 9, 8)
    let reverted = roundTo(w[7] * initDifficulty(4) + (1 - w[7]) * next, 8)
    return clamp(reverted, 1, 10)
}

private func nextRecallStability(_ d: Double, _ s: Double, _ r: Double, _ g: Int) -> Double {
    let hardPenalty = g == 2 ? w[15] : 1.0
    let easyBonus = g == 4 ? w[16] : 1.0
    // Same evaluation order as the JS expression, so rounding matches.
    let growth = exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1) * hardPenalty * easyBonus
    return roundTo(clamp(s * (1 + growth), sMin, sMax), 8)
}

private func nextForgetStability(_ d: Double, _ s: Double, _ r: Double) -> Double {
    roundTo(
        clamp(w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14]), sMin, sMax),
        8
    )
}

private func nextShortTermStability(_ s: Double, _ g: Int) -> Double {
    let sinc = pow(s, -w[19]) * exp(w[17] * (Double(g) - 3 + w[18]))
    let masked = g >= 2 ? max(sinc, 1.0) : sinc
    return roundTo(clamp(s * masked, sMin, sMax), 8)
}

private struct Memory {
    var difficulty: Double
    var stability: Double
}

private func memory(_ d: Double, _ s: Double, _ t: Int, _ g: Int, _ r: Double?) -> Memory {
    if d == 0 && s == 0 {
        return Memory(difficulty: clamp(initDifficulty(g), 1, 10), stability: initStability(g))
    }
    let recall = r ?? forgettingCurve(t, s)
    let newS: Double
    if t == 0 {
        newS = nextShortTermStability(s, g)
    } else if g == 1 {
        let afterFail = nextForgetStability(d, s, recall)
        let minS = s / exp(w[17] * w[18])
        newS = clamp(roundTo(minS, 8), sMin, afterFail)
    } else {
        newS = nextRecallStability(d, s, recall, g)
    }
    return Memory(difficulty: nextDifficulty(d, g), stability: newS)
}

private func nextInterval(_ s: Double, _ retention: Double) -> Int {
    min(max(1, Int(jsRound(s * intervalModifier(retention)))), maximumInterval)
}

/// Floor division that rounds toward negative infinity, like `Math.floor(a / b)`.
func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}

/// Calendar days between two instants, by UTC date (ts-fsrs `dateDiffInDays`).
private func utcDayDiff(_ from: Millis, _ to: Millis) -> Int {
    floorDiv(to, dayMillis) - floorDiv(from, dayMillis)
}

/// A card that has never been reviewed, due immediately.
public func newFsrsState(_ now: Millis) -> FsrsState {
    FsrsState(
        phase: .new, due: now, stability: 0, difficulty: 0, elapsedDays: 0, scheduledDays: 0,
        learningSteps: 0, reps: 0, lapses: 0
    )
}

/// Minutes and next step for a grade in a learning phase, or nil to graduate.
private func step(_ phase: CardPhase, _ current: Int, _ g: Int) -> (minutes: Int, next: Int)? {
    let steps = phase == .relearning || phase == .review ? relearningStepMinutes : learningStepMinutes
    if steps.isEmpty || current >= steps.count { return nil }
    if phase == .review {
        return g == 1 ? (steps[max(0, current)], 0) : nil
    }
    switch g {
    case 1:
        return (steps[0], 0)
    case 2:
        let hard = steps.count == 1
            ? Int(jsRound(Double(steps[0]) * 1.5))
            : Int(jsRound(Double(steps[0] + steps[1]) / 2))
        return (hard, current)
    case 3:
        return current + 1 < steps.count ? (steps[current + 1], current + 1) : nil
    default:
        return nil
    }
}

/// The state after grading. `before` is nil for a card never seen.
public func nextState(_ before: FsrsState?, _ rating: Rating, now: Millis, desiredRetention: Double) -> FsrsState {
    let last = before ?? newFsrsState(now)
    let g = rating.rawValue
    let elapsed = last.phase != .new && last.lastReview != nil ? utcDayDiff(last.lastReview!, now) : 0
    let reps = last.reps + 1

    func build(_ phase: CardPhase, due: Millis, memory m: Memory, scheduledDays: Int, learningSteps: Int, lapses: Int = 0) -> FsrsState {
        FsrsState(
            phase: phase, due: due, stability: m.stability, difficulty: m.difficulty,
            elapsedDays: elapsed, scheduledDays: scheduledDays, learningSteps: learningSteps,
            reps: reps, lapses: last.lapses + lapses, lastReview: now
        )
    }

    /// ts-fsrs `applyLearningSteps`: a learning step, or graduation to review.
    func withSteps(_ m: Memory, _ toPhase: CardPhase, lapses: Int = 0) -> FsrsState {
        let s = step(last.phase, last.learningSteps, g)
        let minutes = s?.minutes ?? 0
        if minutes > 0 && minutes < 1440 {
            return build(toPhase, due: now + minutes * minute, memory: m, scheduledDays: 0, learningSteps: s!.next, lapses: lapses)
        }
        if minutes >= 1440 {
            return build(.review, due: now + minutes * minute, memory: m, scheduledDays: minutes / 1440, learningSteps: s!.next, lapses: lapses)
        }
        let interval = nextInterval(m.stability, desiredRetention)
        return build(.review, due: now + interval * dayMillis, memory: m, scheduledDays: interval, learningSteps: 0, lapses: lapses)
    }

    switch last.phase {
    case .new:
        return withSteps(memory(last.difficulty, last.stability, elapsed, g, nil), .learning)
    case .learning, .relearning:
        return withSteps(memory(last.difficulty, last.stability, elapsed, g, nil), last.phase)
    case .review:
        let r = forgettingCurve(elapsed, last.stability)
        func m(_ grade: Int) -> Memory { memory(last.difficulty, last.stability, elapsed, grade, r) }
        if g == 1 {
            return withSteps(m(1), .relearning, lapses: 1)
        }
        let hardM = m(2), goodM = m(3), easyM = m(4)
        var hard = nextInterval(hardM.stability, desiredRetention)
        var good = nextInterval(goodM.stability, desiredRetention)
        hard = min(hard, good)
        good = max(good, hard + 1)
        let easy = max(nextInterval(easyM.stability, desiredRetention), good + 1)
        let (chosen, interval): (Memory, Int) = switch g {
        case 2: (hardM, hard)
        case 3: (goodM, good)
        default: (easyM, easy)
        }
        return build(.review, due: now + interval * dayMillis, memory: chosen, scheduledDays: interval, learningSteps: 0)
    }
}

/// Probability the card is recalled at `now`, 0–1. New cards report 0.
public func retrievability(_ state: FsrsState, now: Millis) -> Double {
    if state.phase == .new { return 0 }
    let t = state.lastReview.map { max(floorDiv(now - $0, dayMillis), 0) } ?? 0
    return forgettingCurve(t, roundTo(state.stability, 8))
}

/// Rebuilds a card's state by replaying its grades, oldest first.
public func replay<S: Sequence>(_ reviews: S, desiredRetention: Double) -> FsrsState?
where S.Element == (reviewedAt: Millis, rating: Rating) {
    var state: FsrsState?
    for r in reviews {
        state = nextState(state, r.rating, now: r.reviewedAt, desiredRetention: desiredRetention)
    }
    return state
}
