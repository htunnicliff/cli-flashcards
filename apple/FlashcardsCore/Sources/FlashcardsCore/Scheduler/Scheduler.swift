// The app's entry point to scheduling, ported from
// `src/core/scheduler/scheduler.ts`. The clock is passed in.

import Foundation

public struct GradeResult: Sendable {
    public var state: CardState
    /// Carries its stored ID.
    public var entry: ReviewLogEntry
    /// True when this grade made the card a leech, which also suspended it.
    public var becameLeech: Bool
    /// The card's state before the grade, for undo.
    public var previous: CardState?
}

/// A card's state before a suspend or bury, so it can be put back.
public struct PreviousState: Sendable {
    public var cardId: String
    public var state: CardState?
}

public enum SetAside: Sendable { case suspend, bury }

public final class Scheduler: Sendable {
    public let repository: Repository
    public let timeZone: TimeZone

    public init(repository: Repository, timeZone: TimeZone = .current) {
        self.repository = repository
        self.timeZone = timeZone
    }

    private func findCard(_ cardId: String) throws -> Card {
        for stored in repository.listDecks() {
            // Every card type, so a card can be graded whatever the settings.
            if let card = deriveCards(stored.deck, flagPairs: true).first(where: { $0.id == cardId }) {
                return card
            }
        }
        throw StorageError("No installed deck has card \"\(cardId)\"")
    }

    /// What to study at `now`, across every installed deck.
    public func queue(now: Millis) -> StudyQueue {
        let settings = repository.settings()
        let day = studyDay(now, rolloverHour: settings.dayRolloverHour, timeZone: timeZone)
        return buildQueue(
            decks: repository.listDecks(), states: repository.allCardStates(),
            todaysLog: repository.reviews(from: day.start, to: day.end), settings: settings,
            now: now, timeZone: timeZone
        )
    }

    /// When the next card studied before comes due after `now`, or nil.
    public func nextDue(now: Millis) -> Millis? {
        let settings = repository.settings()
        let live = Set(repository.listDecks().filter { !$0.paused }.flatMap {
            deriveCards($0.deck, flagPairs: settings.flagPairs).map(\.id)
        })
        var next: Millis?
        for state in repository.allCardStates() {
            guard live.contains(state.cardId), !state.suspended, state.fsrs.phase != .new else { continue }
            let due = max(state.fsrs.due, state.buriedUntil ?? 0)
            if due > now && (next == nil || due < next!) { next = due }
        }
        return next
    }

    /// Grades a card: stores its next FSRS state and a review log entry.
    @discardableResult
    public func grade(_ cardId: String, _ rating: Rating, now: Millis, durationMs: Int = 0) throws -> GradeResult {
        let settings = repository.settings()
        let previous = repository.cardState(cardId)
        let deckId: String, optionId: String
        if let previous {
            (deckId, optionId) = (previous.deckId, previous.optionId)
        } else {
            let card = try findCard(cardId)
            (deckId, optionId) = (card.deckId, card.optionId)
        }
        let before = previous.flatMap { $0.fsrs.phase != .new ? $0.fsrs : nil }
        let after = nextState(before, rating, now: now, desiredRetention: settings.desiredRetention)
        let lapsed = after.lapses > (before?.lapses ?? 0)
        let wasLeech = previous?.leech ?? false
        let becameLeech = lapsed && after.lapses >= settings.leechThreshold && !wasLeech
        let state = CardState(
            cardId: cardId, deckId: deckId, optionId: optionId, fsrs: after,
            suspended: becameLeech || (previous?.suspended ?? false),
            buriedUntil: previous?.buriedUntil, leech: becameLeech || wasLeech
        )
        let entry = ReviewLogEntry(
            cardId: cardId, deckId: deckId, reviewedAt: now, rating: rating, durationMs: durationMs,
            before: before, after: after
        )
        let id = try repository.recordReview(state, entry)
        return GradeResult(state: state, entry: entry.withId(id), becameLeech: becameLeech, previous: previous)
    }

    /// Takes back a grade returned by `grade`.
    public func undo(_ result: GradeResult) throws {
        guard let id = result.entry.id else { return }
        try repository.undoReview(entryId: id, cardId: result.entry.cardId, previous: result.previous)
    }

    /// Sets cards aside without grading: suspend until unsuspended, bury until
    /// the next study day. Returns their earlier states for `restore`.
    @discardableResult
    public func setAside(_ cardIds: [String], _ how: SetAside, now: Millis) throws -> [PreviousState] {
        let settings = repository.settings()
        let current = repository.cardStates(cardIds)
        var updated: [CardState] = []
        for (i, cardId) in cardIds.enumerated() {
            var base: CardState
            if let existing = current[i] {
                base = existing
            } else {
                let card = try findCard(cardId)
                base = CardState(cardId: cardId, deckId: card.deckId, optionId: card.optionId, fsrs: newFsrsState(now))
            }
            switch how {
            case .suspend: base.suspended = true
            case .bury: base.buriedUntil = nextStudyDayStart(now, rolloverHour: settings.dayRolloverHour, timeZone: timeZone)
            }
            updated.append(base)
        }
        try repository.putCardStates(updated)
        return cardIds.enumerated().map { PreviousState(cardId: $1, state: current[$0]) }
    }

    /// Puts back states returned by `setAside`.
    public func restore(_ previous: [PreviousState]) throws {
        try repository.atomically { repo in
            try repo.putCardStates(previous.compactMap(\.state))
            try repo.deleteCardStates(previous.filter { $0.state == nil }.map(\.cardId))
        }
    }

    public func unsuspend(_ cardIds: [String]) throws {
        try repository.putCardStates(repository.cardStates(cardIds).compactMap { s in
            guard var s, s.suspended else { return nil }
            s.suspended = false
            return s
        })
    }
}
