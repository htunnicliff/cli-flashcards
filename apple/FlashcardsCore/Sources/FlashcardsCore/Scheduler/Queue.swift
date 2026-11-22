// Picks what to study now. Ported from `src/core/scheduler/queue.ts`.

import Foundation

public enum QueueKind: String, Sendable { case learning, review, new }

public struct QueueItem: Hashable, Sendable {
    public var kind: QueueKind
    public var card: Card
    /// Nil for a new card that has never been graded.
    public var state: CardState?
}

public struct QueueToday: Hashable, Sendable {
    public var reviewsDone: Int
    public var reviewsLeft: Int
    public var newDone: Int
    public var newLeft: Int
}

public struct StudyQueue: Hashable, Sendable {
    /// Learning steps, then due reviews, then new cards.
    public var items: [QueueItem]
    public var today: QueueToday
    /// When the next learning-step card comes due later today, if one does.
    public var nextLearningDue: Millis?
}

private func optionKey(_ deckId: String, _ optionId: String) -> String { "\(deckId)\u{0}\(optionId)" }

private func tierRank(_ tier: Tier) -> Int {
    switch tier {
    case .core: 0
    case .common: 1
    case .obscure: 2
    }
}

/// What a grade counts against, by what the card was before it.
private func countsAs(_ entry: ReviewLogEntry) -> QueueKind {
    guard let before = entry.before, before.phase != .new else { return .new }
    return before.phase == .review ? .review : .learning
}

/// Pure: the caller loads the data and passes `now`. Siblings (other cards of
/// an option graded today) wait until tomorrow, new cards come in tier order,
/// and daily limits cap reviews and new cards.
public func buildQueue(
    decks: [StoredDeck], states: [CardState], todaysLog: [ReviewLogEntry], settings: Settings,
    now: Millis, timeZone: TimeZone = .current
) -> StudyQueue {
    let dayEnd = nextStudyDayStart(now, rolloverHour: settings.dayRolloverHour, timeZone: timeZone)
    var stateById: [String: CardState] = [:]
    for s in states { stateById[s.cardId] = s }

    var gradedToday = Set<String>()
    var optionsGradedToday = Set<String>()
    var reviewsDone = 0
    var newDone = 0
    for entry in todaysLog {
        gradedToday.insert(entry.cardId)
        if let state = stateById[entry.cardId] {
            optionsGradedToday.insert(optionKey(state.deckId, state.optionId))
        } else {
            let parts = entry.cardId.split(separator: ":", omittingEmptySubsequences: false)
            optionsGradedToday.insert(optionKey(entry.deckId, parts.count > 2 ? String(parts[2]) : ""))
        }
        switch countsAs(entry) {
        case .review: reviewsDone += 1
        case .new: newDone += 1
        case .learning: break
        }
    }

    var learning: [QueueItem] = []
    var reviews: [QueueItem] = []
    var fresh: [(item: QueueItem, tier: Int, deck: Int, order: Int)] = []
    var nextLearningDue: Millis?

    for (deckIndex, stored) in decks.enumerated() where !stored.paused {
        var tierByOption: [String: Tier] = [:]
        for o in stored.deck.options { tierByOption[o.id] = o.tier }
        for (order, card) in deriveCards(stored.deck, flagPairs: settings.flagPairs).enumerated() {
            let tier = tierByOption[card.optionId] ?? .common
            let state = stateById[card.id]
            if let state, state.suspended { continue }
            if let buried = state?.buriedUntil, buried > now { continue }
            let siblingSeen = optionsGradedToday.contains(optionKey(card.deckId, card.optionId)) && !gradedToday.contains(card.id)
            if siblingSeen { continue }

            switch state?.fsrs.phase ?? .new {
            case .learning, .relearning:
                let due = state!.fsrs.due
                if due <= now {
                    learning.append(QueueItem(kind: .learning, card: card, state: state))
                } else if due < dayEnd {
                    nextLearningDue = min(nextLearningDue ?? due, due)
                }
            case .review:
                if state!.fsrs.due < dayEnd {
                    reviews.append(QueueItem(kind: .review, card: card, state: state))
                }
            case .new:
                if tier == .obscure && !stored.includeObscure { continue }
                fresh.append((QueueItem(kind: .new, card: card, state: state), tierRank(tier), deckIndex, order))
            }
        }
    }

    func byDue(_ a: QueueItem, _ b: QueueItem) -> Bool {
        let da = a.state!.fsrs.due, db = b.state!.fsrs.due
        return da != db ? da < db : a.card.id < b.card.id
    }
    learning.sort(by: byDue)
    reviews.sort(by: byDue)
    fresh.sort { a, b in
        a.tier != b.tier ? a.tier < b.tier : a.deck != b.deck ? a.deck < b.deck : a.order < b.order
    }

    let reviewsLeft = max(0, settings.maxReviewsPerDay - reviewsDone)
    let newLeft = max(0, settings.newCardsPerDay - newDone)

    var queued = Set(learning.map { optionKey($0.card.deckId, $0.card.optionId) })
    func take(_ candidates: [QueueItem], _ limit: Int) -> [QueueItem] {
        var taken: [QueueItem] = []
        for item in candidates {
            if taken.count >= limit { break }
            if !queued.insert(optionKey(item.card.deckId, item.card.optionId)).inserted { continue }
            taken.append(item)
        }
        return taken
    }
    let dueReviews = take(reviews, reviewsLeft)
    let newCards = take(fresh.map(\.item), newLeft)

    return StudyQueue(
        items: learning + dueReviews + newCards,
        today: QueueToday(reviewsDone: reviewsDone, reviewsLeft: reviewsLeft, newDone: newDone, newLeft: newLeft),
        nextLearningDue: nextLearningDue
    )
}
