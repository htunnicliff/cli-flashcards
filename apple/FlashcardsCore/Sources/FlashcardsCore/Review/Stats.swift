// Stats page numbers, ported from `src/core/stats/stats.ts`.

import Foundation

/// A card is mature once its interval reaches three weeks.
public let matureIntervalDays = 21

/// Review counts keyed by study-day start.
public func reviewsByDay(_ log: [ReviewLogEntry], rolloverHour: Int, timeZone: TimeZone = .current) -> [Millis: Int] {
    var counts: [Millis: Int] = [:]
    for e in log {
        counts[studyDayStart(e.reviewedAt, rolloverHour: rolloverHour, timeZone: timeZone), default: 0] += 1
    }
    return counts
}

/// Consecutive study days with a review, ending today (or yesterday if today
/// has none yet).
public func currentStreak(_ byDay: [Millis: Int], now: Millis, rolloverHour: Int, timeZone: TimeZone = .current) -> Int {
    var offset = byDay[studyDayStart(now, rolloverHour: rolloverHour, timeZone: timeZone)] != nil ? 0 : -1
    var streak = 0
    while byDay[shiftStudyDay(now, offset: offset, rolloverHour: rolloverHour, timeZone: timeZone)] != nil {
        streak += 1
        offset -= 1
    }
    return streak
}

public struct DeckCardCounts: Hashable, Sendable {
    public var deckId: String
    public var new = 0
    public var learning = 0
    public var review = 0
    public var suspended = 0
    public var total: Int { new + learning + review + suspended }
}

public func cardCountsByDeck(_ decks: [StoredDeck], _ states: [CardState], flagPairs: Bool = false) -> [DeckCardCounts] {
    var byId: [String: CardState] = [:]
    for s in states { byId[s.cardId] = s }
    return decks.map { stored in
        var c = DeckCardCounts(deckId: stored.id)
        for card in deriveCards(stored.deck, flagPairs: flagPairs) {
            let s = byId[card.id]
            if let s, s.suspended {
                c.suspended += 1
            } else if s == nil || s!.fsrs.phase == .new {
                c.new += 1
            } else if s!.fsrs.phase == .review {
                c.review += 1
            } else {
                c.learning += 1
            }
        }
        return c
    }
}

public struct Retention: Hashable, Sendable {
    public var passed: Int
    public var total: Int
    public var rate: Double? { total == 0 ? nil : Double(passed) / Double(total) }
}

/// Of reviews of mature cards in the last `days` study days, the share not rated Again.
public func trueRetention(
    _ log: [ReviewLogEntry], now: Millis, rolloverHour: Int, days: Int = 30, timeZone: TimeZone = .current
) -> Retention {
    let from = shiftStudyDay(now, offset: -(days - 1), rolloverHour: rolloverHour, timeZone: timeZone)
    var passed = 0, total = 0
    for e in log where e.reviewedAt >= from && e.reviewedAt <= now {
        guard let b = e.before, b.phase == .review, b.scheduledDays >= matureIntervalDays else { continue }
        total += 1
        if e.rating != .again { passed += 1 }
    }
    return Retention(passed: passed, total: total)
}

public struct DayCount: Hashable, Sendable {
    /// Study-day start.
    public var day: Millis
    public var count: Int
}

/// Cards due on each of the next `days` study days, today first.
public func dueForecast(
    _ decks: [StoredDeck], _ states: [CardState], now: Millis, rolloverHour: Int, days: Int = 30,
    flagPairs: Bool = false, timeZone: TimeZone = .current
) -> [DayCount] {
    let live = Set(decks.flatMap { deriveCards($0.deck, flagPairs: flagPairs).map(\.id) })
    let starts = (0...days).map { shiftStudyDay(now, offset: $0, rolloverHour: rolloverHour, timeZone: timeZone) }
    var counts = Array(repeating: 0, count: days)
    for s in states where !s.suspended && s.fsrs.phase != .new && live.contains(s.cardId) {
        let due = max(s.fsrs.due, starts[0])
        for i in 0..<days where due >= starts[i] && due < starts[i + 1] {
            counts[i] += 1
            break
        }
    }
    return (0..<days).map { DayCount(day: starts[$0], count: counts[$0]) }
}

/// Reviews on each of the last `days` study days, oldest first.
public func reviewHistory(
    _ byDay: [Millis: Int], now: Millis, rolloverHour: Int, days: Int = 365, timeZone: TimeZone = .current
) -> [DayCount] {
    (0..<days).map { i in
        let day = shiftStudyDay(now, offset: i - (days - 1), rolloverHour: rolloverHour, timeZone: timeZone)
        return DayCount(day: day, count: byDay[day] ?? 0)
    }
}

/// Heatmap shade 0–4 for a day's count, relative to the busiest day.
public func heatLevel(_ count: Int, max: Int) -> Int {
    if count <= 0 || max <= 0 { return 0 }
    return Swift.min(Swift.max(Int((Double(count) / Double(max) * 4).rounded(.up)), 1), 4)
}

public struct Stats: Hashable, Sendable {
    public var reviewsToday: Int
    public var streak: Int
    public var cards: [DeckCardCounts]
    public var retention: Retention
    public var forecast: [DayCount]
    public var history: [DayCount]
}

public func computeStats(
    decks: [StoredDeck], states: [CardState], log: [ReviewLogEntry], now: Millis, rolloverHour: Int,
    flagPairs: Bool = false, timeZone: TimeZone = .current
) -> Stats {
    let byDay = reviewsByDay(log, rolloverHour: rolloverHour, timeZone: timeZone)
    return Stats(
        reviewsToday: byDay[studyDayStart(now, rolloverHour: rolloverHour, timeZone: timeZone)] ?? 0,
        streak: currentStreak(byDay, now: now, rolloverHour: rolloverHour, timeZone: timeZone),
        cards: cardCountsByDeck(decks, states, flagPairs: flagPairs),
        retention: trueRetention(log, now: now, rolloverHour: rolloverHour, timeZone: timeZone),
        forecast: dueForecast(decks, states, now: now, rolloverHour: rolloverHour, flagPairs: flagPairs, timeZone: timeZone),
        history: reviewHistory(byDay, now: now, rolloverHour: rolloverHour, timeZone: timeZone)
    )
}
