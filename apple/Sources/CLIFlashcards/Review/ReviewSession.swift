// The review session's state, ported from `app/lib/app/review/review_session.dart`.
// Storage is in memory with a quick file write, so grading runs inline.

import Foundation
import Observation
import FlashcardsCore

/// A typed answer and how it scored.
struct TypedResult: Equatable {
    var typed: String
    var result: AnswerResult
}

/// A short message under the card, like "Card suspended.", with Undo when the
/// action can be taken back.
struct ReviewNotice: Equatable, Identifiable {
    var id: Int
    var message: String
    var undoable = true
}

let cardPrompts: [CardType: String] = [
    .flagToMeaning: "What does this flag do?",
    .meaningToFlag: "Which flag does this?",
    .cloze: "Fill in the blank.",
    .shortToLong: "What’s the long form?",
    .longToShort: "What’s the short form?",
]

let ratingLabels: [Rating: String] = [.again: "Again", .hard: "Hard", .good: "Good", .easy: "Easy"]

/// The flag to name a card by on screen. A flag pair card goes by the form its
/// front shows, so a label never gives the answer away.
func frontFlag(_ card: Card) -> String { card.isFlagPair ? (card.shown ?? card.flag) : card.flag }

@MainActor @Observable final class ReviewSession {
    private enum History {
        case graded(QueueItem, GradeResult)
        case aside(QueueItem, [PreviousState])

        var item: QueueItem {
            switch self {
            case .graded(let item, _), .aside(let item, _): item
            }
        }
    }

    let model: AppModel

    private(set) var items: [QueueItem] = []
    private(set) var decks: [String: Deck] = [:]
    private var typedDecks: Set<String> = []
    private(set) var revealed = false
    private(set) var answer: TypedResult?
    private(set) var gradedThisSession = 0
    private(set) var notice: ReviewNotice?
    private(set) var nextDue: Millis?
    private(set) var error: String?
    private var history: [History] = []
    private var shownAt: Millis = 0
    private var noticeId = 0

    init(model: AppModel) {
        self.model = model
        refresh()
    }

    var current: QueueItem? { items.first }
    var done: Bool { items.isEmpty }
    var canUndo: Bool { !history.isEmpty }
    var hasDecks: Bool { !decks.isEmpty }

    var counts: (new: Int, learning: Int, review: Int) {
        var n = 0, l = 0, r = 0
        for item in items {
            switch item.kind {
            case .new: n += 1
            case .learning: l += 1
            case .review: r += 1
            }
        }
        return (n, l, r)
    }

    var deck: Deck? { current.flatMap { decks[$0.card.deckId] } }

    var option: Option? {
        guard let card = current?.card else { return nil }
        return decks[card.deckId]?.options.first { $0.id == card.optionId }
    }

    /// `git log` for a subcommand option, otherwise the tool alone.
    var command: String {
        let tool = deck?.tool ?? ""
        if let sub = option?.subcommand { return "\(tool) \(sub)" }
        return tool
    }

    /// Whether the card on screen asks for its flag to be typed.
    var typing: Bool {
        guard let card = current?.card else { return false }
        return card.type != .flagToMeaning && typedDecks.contains(card.deckId)
    }

    /// Good when a typed answer was right, Again when wrong.
    var suggestedRating: Rating? {
        answer.map { $0.result.correct ? .good : .again }
    }

    /// The next interval for each rating, like "10m" or "3d".
    var intervals: [Rating: String] {
        guard let item = current else { return [:] }
        let now = model.now
        let before = item.state.flatMap { $0.fsrs.phase != .new ? $0.fsrs : nil }
        let retention = model.settings.desiredRetention
        var out: [Rating: String] = [:]
        for rating in Rating.allCases {
            out[rating] = formatInterval(nextState(before, rating, now: now, desiredRetention: retention).due - now)
        }
        return out
    }

    /// Reloads the queue, keeping the card on screen in front if still due.
    func refresh() {
        guard let repository = model.repository, let scheduler = model.scheduler else { return }
        let now = model.now
        let queue = scheduler.queue(now: now)
        let stored = repository.listDecks()
        decks = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.deck) })
        typedDecks = Set(stored.filter(\.typeAnswers).map(\.id))
        nextDue = scheduler.nextDue(now: now)
        var next = queue.items
        if let onScreen = items.first, let index = next.firstIndex(where: { $0.card.id == onScreen.card.id }) {
            let fresh = next.remove(at: index)
            next.insert(fresh, at: 0)
        } else if items.first != nil {
            revealed = false
            answer = nil
        }
        items = next
        if shownAt == 0 { shownAt = now }
        model.refresh()
    }

    func reveal() {
        guard current != nil, !revealed else { return }
        revealed = true
    }

    /// Checks a typed answer against the card on screen and reveals the back.
    func submit(_ typed: String) {
        guard let item = current, let target = option, !revealed else { return }
        answer = TypedResult(
            typed: typed,
            result: checkAnswer(
                typed, option: target, options: deck?.options ?? [target], style: deck?.parsingStyle,
                only: item.card.isFlagPair ? item.card.targets : nil
            )
        )
        revealed = true
    }

    private func advance(removing ids: Set<String>) {
        items.removeAll { ids.contains($0.card.id) }
        revealed = false
        answer = nil
        shownAt = model.now
    }

    func grade(_ rating: Rating) {
        guard let item = current, revealed, let scheduler = model.scheduler else { return }
        let now = model.now
        do {
            let result = try scheduler.grade(item.card.id, rating, now: now, durationMs: now - shownAt)
            history.append(.graded(item, result))
            gradedThisSession += 1
            advance(removing: [item.card.id])
            if result.becameLeech {
                show(
                    "Forgotten \(result.state.fsrs.lapses) times, so this card is now suspended as a leech.",
                    undoable: false
                )
            } else {
                notice = nil
            }
            refresh()
        } catch {
            self.error = "Couldn’t save that grade: \(error)"
        }
    }

    /// Takes back the last grade or set-aside: the card returns, unrevealed.
    func undo() {
        guard let last = history.popLast(), let scheduler = model.scheduler else { return }
        do {
            switch last {
            case .graded(_, let result):
                try scheduler.undo(result)
                gradedThisSession = max(0, gradedThisSession - 1)
            case .aside(_, let previous):
                try scheduler.restore(previous)
            }
            notice = nil
            items.removeAll { $0.card.id == last.item.card.id }
            items.insert(last.item, at: 0)
            revealed = false
            answer = nil
            shownAt = model.now
            refresh()
        } catch {
            self.error = "Couldn’t undo: \(error)"
        }
    }

    /// Suspends the card on screen (or every card for its option), or buries it
    /// until tomorrow.
    func setAside(_ how: SetAside, wholeOption: Bool = false) {
        guard let item = current, let scheduler = model.scheduler else { return }
        var ids = [item.card.id]
        if wholeOption, let deck = decks[item.card.deckId] {
            ids = deriveCards(deck, flagPairs: true).filter { $0.optionId == item.card.optionId }.map(\.id)
        }
        do {
            let previous = try scheduler.setAside(ids, how, now: model.now)
            history.append(.aside(item, previous))
            advance(removing: Set(ids))
            switch (how, wholeOption) {
            case (.bury, _): show("Skipped until tomorrow.")
            case (.suspend, true): show("Suspended every card for \(frontFlag(item.card)).")
            case (.suspend, false): show("Card suspended.")
            }
            refresh()
        } catch {
            self.error = "Couldn’t set the card aside: \(error)"
        }
    }

    private func show(_ message: String, undoable: Bool = true) {
        noticeId += 1
        notice = ReviewNotice(id: noticeId, message: message, undoable: undoable)
    }

    func dismissNotice() { notice = nil }
}
