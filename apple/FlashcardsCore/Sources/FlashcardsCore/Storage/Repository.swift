// The app's only way into storage, ported from `src/core/storage/repository.ts`.
//
// Everything lives in memory and is written to a folder of JSON files after
// each change (or kept in memory only, for tests and previews):
//
//   state.json      settings, installed decks' preferences, card states
//   decks/<id>.json the installed version of each deck
//   reviews.jsonl   the review log, one entry per line, appended to
//
// The data is small (thousands of card states, a review log that grows by a
// few hundred lines a day), so plain files beat a database: no dependency,
// and the same code runs and is tested on every platform.

import Foundation

/// Bump when stored shapes change, and migrate in `Repository.load`.
public let storageVersion = 1

public struct StorageError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Everything stored, as one value. A transaction edits a copy.
public struct StoredData: Sendable {
    public var decks: [String: StoredDeck] = [:]
    public var cardStates: [String: CardState] = [:]
    /// Oldest first by insertion; IDs ascend.
    public var reviewLog: [ReviewLogEntry] = []
    public var nextReviewId = 1
    public var settings = Settings()

    public init() {}
}

/// Where stored data goes. Writes describe what changed so files can be
/// appended to or skipped.
public protocol StorageBackend: Sendable {
    func load() throws -> StoredData
    func save(_ data: StoredData, _ changes: Changes) throws
}

/// What a transaction touched.
public struct Changes: Sendable {
    public var state = false
    public var decks: Set<String> = []
    public var removedDecks: Set<String> = []
    /// Entries appended to the end of the log.
    public var appendedReviews: [ReviewLogEntry] = []
    /// The log changed some other way, so it's rewritten.
    public var rewroteLog = false

    var isEmpty: Bool {
        !state && decks.isEmpty && removedDecks.isEmpty && appendedReviews.isEmpty && !rewroteLog
    }
}

/// Keeps nothing on disk.
public struct MemoryBackend: StorageBackend {
    public init() {}
    public func load() throws -> StoredData { StoredData() }
    public func save(_ data: StoredData, _ changes: Changes) throws {}
}

/// A folder of JSON files, written atomically.
public struct FileBackend: StorageBackend {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private struct StateFile: Codable {
        var storageVersion: Int
        var settings: Settings
        var decks: [DeckPrefs]
        var cardStates: [CardState]
        var nextReviewId: Int
    }

    private struct DeckPrefs: Codable {
        var id: String
        var installedAt: Millis
        var updatedAt: Millis
        var includeObscure: Bool
        var paused: Bool
        var typeAnswers: Bool
    }

    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    private var reviewsURL: URL { directory.appendingPathComponent("reviews.jsonl") }
    private var decksURL: URL { directory.appendingPathComponent("decks", isDirectory: true) }
    private func deckURL(_ id: String) -> URL { decksURL.appendingPathComponent("\(id).json") }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.userInfo[.includeReviewIds] = true
        return e
    }

    public func load() throws -> StoredData {
        var data = StoredData()
        let fm = FileManager.default
        guard fm.fileExists(atPath: stateURL.path) else { return data }
        let state = try JSONDecoder().decode(StateFile.self, from: Data(contentsOf: stateURL))
        guard state.storageVersion <= storageVersion else {
            throw StorageError("Saved data is from a newer version of the app.")
        }
        data.settings = state.settings
        data.nextReviewId = state.nextReviewId
        for s in state.cardStates { data.cardStates[s.cardId] = s }
        for p in state.decks {
            let deck = try Deck.decode(Data(contentsOf: deckURL(p.id)))
            data.decks[p.id] = StoredDeck(
                deck: deck, installedAt: p.installedAt, updatedAt: p.updatedAt,
                includeObscure: p.includeObscure, paused: p.paused, typeAnswers: p.typeAnswers
            )
        }
        if fm.fileExists(atPath: reviewsURL.path) {
            let text = try String(contentsOf: reviewsURL, encoding: .utf8)
            let decoder = JSONDecoder()
            for line in text.split(separator: "\n") where !line.isEmpty {
                // A torn last line from a crash mid-append is dropped.
                guard let entry = try? decoder.decode(ReviewLogEntry.self, from: Data(line.utf8)) else { continue }
                data.reviewLog.append(entry)
            }
            if let last = data.reviewLog.last?.id { data.nextReviewId = max(data.nextReviewId, last + 1) }
        }
        return data
    }

    public func save(_ data: StoredData, _ changes: Changes) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: decksURL, withIntermediateDirectories: true)
        let encoder = Self.encoder()
        for id in changes.decks {
            guard let stored = data.decks[id] else { continue }
            try encoder.encode(stored.deck).write(to: deckURL(id), options: .atomic)
        }
        for id in changes.removedDecks where data.decks[id] == nil {
            try? fm.removeItem(at: deckURL(id))
        }
        if changes.rewroteLog {
            try logLines(data.reviewLog, encoder).write(to: reviewsURL, options: .atomic)
        } else if !changes.appendedReviews.isEmpty {
            let lines = try logLines(changes.appendedReviews, encoder)
            if let handle = try? FileHandle(forWritingTo: reviewsURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: lines)
            } else {
                try lines.write(to: reviewsURL, options: .atomic)
            }
        }
        if changes.state || !changes.decks.isEmpty || !changes.removedDecks.isEmpty || !changes.appendedReviews.isEmpty || changes.rewroteLog {
            let state = StateFile(
                storageVersion: storageVersion,
                settings: data.settings,
                decks: data.decks.values.sorted { $0.id < $1.id }.map {
                    DeckPrefs(
                        id: $0.id, installedAt: $0.installedAt, updatedAt: $0.updatedAt,
                        includeObscure: $0.includeObscure, paused: $0.paused, typeAnswers: $0.typeAnswers
                    )
                },
                cardStates: data.cardStates.values.sorted { $0.cardId < $1.cardId },
                nextReviewId: data.nextReviewId
            )
            try encoder.encode(state).write(to: stateURL, options: .atomic)
        }
    }

    private func logLines(_ entries: [ReviewLogEntry], _ encoder: JSONEncoder) throws -> Data {
        var out = Data()
        for e in entries {
            out.append(try encoder.encode(e))
            out.append(0x0A)
        }
        return out
    }
}

/// Reads and writes stored data. Thread-safe; every method is synchronous and
/// cheap, since the data is in memory.
public final class Repository: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var data: StoredData
    private let backend: StorageBackend
    /// Set while a transaction runs: the copy being edited and what changed.
    private var pendingData: StoredData?
    private var pendingChanges: Changes?

    public init(backend: StorageBackend) throws {
        self.backend = backend
        self.data = try backend.load()
    }

    /// A repository that keeps nothing on disk.
    public static func inMemory() -> Repository {
        try! Repository(backend: MemoryBackend())
    }

    /// Runs `work` as one transaction: its changes are saved together, or,
    /// if it throws, not at all.
    @discardableResult
    public func atomically<T>(_ work: (Repository) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if pendingData != nil { return try work(self) }
        pendingData = data
        pendingChanges = Changes()
        defer {
            pendingData = nil
            pendingChanges = nil
        }
        let result = try work(self)
        let next = pendingData!, changes = pendingChanges!
        if !changes.isEmpty { try backend.save(next, changes) }
        data = next
        return result
    }

    private func read<T>(_ body: (StoredData) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(pendingData ?? data)
    }

    private func write<T>(_ body: (inout StoredData, inout Changes) throws -> T) throws -> T {
        try atomically { _ in
            // Take the copy out while editing it, so it isn't copied again.
            var d = pendingData!, c = pendingChanges!
            pendingData = nil
            defer {
                pendingData = d
                pendingChanges = c
            }
            return try body(&d, &c)
        }
    }

    // MARK: Decks

    /// Installs a deck or replaces it with a newer version, keeping its
    /// preferences. The flags set the preferences of a deck not installed yet.
    @discardableResult
    public func installDeck(
        _ deck: Deck, now: Millis, includeObscure: Bool = false, paused: Bool = false, typeAnswers: Bool = false
    ) throws -> StoredDeck {
        try write { data, changes in
            var stored: StoredDeck
            if let existing = data.decks[deck.id] {
                stored = existing
                stored.deck = deck
                stored.updatedAt = now
            } else {
                stored = StoredDeck(
                    deck: deck, installedAt: now, updatedAt: now, includeObscure: includeObscure,
                    paused: paused, typeAnswers: typeAnswers
                )
            }
            data.decks[deck.id] = stored
            changes.decks.insert(deck.id)
            return stored
        }
    }

    public func deck(_ id: String) -> StoredDeck? { read { $0.decks[id] } }

    /// Installed decks, in deck ID order.
    public func listDecks() -> [StoredDeck] { read { $0.decks.values.sorted { $0.id < $1.id } } }

    public func updateDeck(_ id: String, includeObscure: Bool? = nil, paused: Bool? = nil, typeAnswers: Bool? = nil) throws {
        try write { data, changes in
            guard var stored = data.decks[id] else { throw StorageError("Deck \"\(id)\" is not installed") }
            if let includeObscure { stored.includeObscure = includeObscure }
            if let paused { stored.paused = paused }
            if let typeAnswers { stored.typeAnswers = typeAnswers }
            data.decks[id] = stored
            changes.state = true
        }
    }

    /// Uninstalls the deck. Its progress stays.
    public func removeDeck(_ id: String) throws {
        try write { data, changes in
            data.decks[id] = nil
            changes.removedDecks.insert(id)
        }
    }

    // MARK: Card states

    public func cardState(_ cardId: String) -> CardState? { read { $0.cardStates[cardId] } }

    /// Same order as `cardIds`, nil for cards never reviewed.
    public func cardStates(_ cardIds: [String]) -> [CardState?] { read { d in cardIds.map { d.cardStates[$0] } } }

    public func allCardStates() -> [CardState] { read { $0.cardStates.values.sorted { $0.cardId < $1.cardId } } }

    /// Every stored state for a deck, including ones for removed options.
    public func cardStates(forDeck deckId: String) -> [CardState] {
        read { $0.cardStates.values.filter { $0.deckId == deckId }.sorted { $0.cardId < $1.cardId } }
    }

    public func putCardStates<S: Sequence>(_ states: S) throws where S.Element == CardState {
        let list = Array(states)
        guard !list.isEmpty else { return }
        try write { data, changes in
            for s in list { data.cardStates[s.cardId] = s }
            changes.state = true
        }
    }

    public func deleteCardStates<S: Sequence>(_ cardIds: S) throws where S.Element == String {
        let ids = Array(cardIds)
        guard !ids.isEmpty else { return }
        try write { data, changes in
            for id in ids { data.cardStates[id] = nil }
            changes.state = true
        }
    }

    // MARK: Review log

    /// Adds an entry under a fresh ID, ignoring any ID it carries.
    @discardableResult
    public func appendReview(_ entry: ReviewLogEntry) throws -> Int {
        try write { data, changes in
            let stored = entry.withId(data.nextReviewId)
            data.nextReviewId += 1
            data.reviewLog.append(stored)
            changes.appendedReviews.append(stored)
            return stored.id!
        }
    }

    private func sortedLog(_ filter: (ReviewLogEntry) -> Bool) -> [ReviewLogEntry] {
        read { d in
            d.reviewLog.filter(filter).sorted {
                $0.reviewedAt != $1.reviewedAt ? $0.reviewedAt < $1.reviewedAt : ($0.id ?? 0) < ($1.id ?? 0)
            }
        }
    }

    /// Every review, oldest first.
    public func allReviews() -> [ReviewLogEntry] { sortedLog { _ in true } }

    /// Reviews with `from <= reviewedAt < to`, oldest first.
    public func reviews(from: Millis, to: Millis) -> [ReviewLogEntry] {
        sortedLog { $0.reviewedAt >= from && $0.reviewedAt < to }
    }

    public func reviews(forDeck deckId: String) -> [ReviewLogEntry] { sortedLog { $0.deckId == deckId } }

    public func reviews(forCard cardId: String) -> [ReviewLogEntry] { sortedLog { $0.cardId == cardId } }

    public func reviewCount() -> Int { read { $0.reviewLog.count } }

    /// Writes a grade's new state and its log entry together. Returns the entry's ID.
    @discardableResult
    public func recordReview(_ state: CardState, _ entry: ReviewLogEntry) throws -> Int {
        try atomically { repo in
            try repo.putCardStates([state])
            return try repo.appendReview(entry)
        }
    }

    /// Takes back a grade: removes its log entry and restores the previous
    /// state (or removes it). The one exception to the append-only log.
    public func undoReview(entryId: Int, cardId: String, previous: CardState?) throws {
        try write { data, changes in
            data.reviewLog.removeAll { $0.id == entryId }
            changes.rewroteLog = true
            if let previous { data.cardStates[cardId] = previous } else { data.cardStates[cardId] = nil }
            changes.state = true
        }
    }

    /// Deletes card states and review log entries, for one deck or all.
    public func resetProgress(deckId: String? = nil) throws {
        try write { data, changes in
            if let deckId {
                data.cardStates = data.cardStates.filter { $0.value.deckId != deckId }
                data.reviewLog.removeAll { $0.deckId == deckId }
            } else {
                data.cardStates = [:]
                data.reviewLog = []
            }
            changes.state = true
            changes.rewroteLog = true
        }
    }

    // MARK: Settings

    public func settings() -> Settings { read { $0.settings } }

    public func saveSettings(_ settings: Settings) throws {
        try write { data, changes in
            data.settings = settings
            changes.state = true
        }
    }

    @discardableResult
    public func updateSettings(_ change: (inout Settings) -> Void) throws -> Settings {
        try write { data, changes in
            change(&data.settings)
            changes.state = true
            return data.settings
        }
    }
}
