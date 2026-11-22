// JSON backups, ported from `src/core/backup/backup.ts`. The file format is
// shared with the web and Flutter apps, so any of them can read the others'
// backups.

import Foundation

public let backupVersion = 1
public let backupFormat = "recall-backup"

public struct BackupError: Error, CustomStringConvertible, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public struct BackupDeck: Codable, Hashable, Sendable {
    public var id: String
    public var deckVersion: Int
    public var includeObscure: Bool
}

/// Settings that travel with a backup.
let backupSettingKeys = [
    "desiredRetention", "newCardsPerDay", "maxReviewsPerDay", "dayRolloverHour", "leechThreshold", "flagPairs",
]

/// A JSON scalar, for the backup's settings.
public enum JSONScalar: Codable, Hashable, Sendable {
    case number(Double), bool(Bool)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) } else { self = .number(try c.decode(Double.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int(n)) } else { try c.encode(n) }
        case .bool(let b): try c.encode(b)
        }
    }

    var number: Double? { if case .number(let n) = self { n } else { nil } }
    var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
}

public struct Backup: Sendable {
    public var exportedAt: Millis
    public var decks: [BackupDeck]
    public var cardStates: [CardState]
    /// Oldest first.
    public var reviewLog: [ReviewLogEntry]
    /// Only the keys in `backupSettingKeys` that the file had.
    public var settings: [String: JSONScalar]

    private struct File: Encodable {
        var format = backupFormat
        var backupVersion = FlashcardsCore.backupVersion
        var exportedAt: Millis
        var decks: [BackupDeck]
        var cardStates: [CardState]
        var reviewLog: [ReviewLogEntry]
        var settings: [String: JSONScalar]
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(File(
            exportedAt: exportedAt, decks: decks, cardStates: cardStates, reviewLog: reviewLog, settings: settings
        ))
    }
}

private func settingsJSON(_ s: Settings) -> [String: JSONScalar] {
    [
        "desiredRetention": .number(s.desiredRetention),
        "newCardsPerDay": .number(Double(s.newCardsPerDay)),
        "maxReviewsPerDay": .number(Double(s.maxReviewsPerDay)),
        "dayRolloverHour": .number(Double(s.dayRolloverHour)),
        "leechThreshold": .number(Double(s.leechThreshold)),
        "flagPairs": .bool(s.flagPairs),
    ]
}

/// Snapshot of everything worth keeping. Also records `lastBackupAt`.
public func exportBackup(_ repository: Repository, now: Millis) throws -> Backup {
    let backup = try repository.atomically { repo in
        Backup(
            exportedAt: now,
            decks: repo.listDecks().map { BackupDeck(id: $0.id, deckVersion: $0.deckVersion, includeObscure: $0.includeObscure) },
            cardStates: repo.allCardStates(),
            reviewLog: repo.allReviews().map { $0.withId(nil) },
            settings: settingsJSON(repo.settings())
        )
    }
    try repository.updateSettings { $0.lastBackupAt = now }
    return backup
}

private func damaged(_ path: String, _ message: String) -> BackupError {
    BackupError("This backup is damaged (\(path): \(message)).")
}

/// Any JSON value, for validating a backup before decoding its parts.
indirect enum JSONValue: Codable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { o[key] } else { nil }
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }
}

/// Validates a backup file's contents, with a readable error.
public func parseBackup(_ input: Data) throws -> Backup {
    guard let data = try? JSONDecoder().decode(JSONValue.self, from: input) else {
        throw BackupError("This file isn’t valid JSON.")
    }
    guard case .object = data, case .string(backupFormat)? = data["format"] else {
        throw BackupError("This file isn’t a --recall backup.")
    }
    if case .number(let v)? = data["backupVersion"], v > Double(backupVersion) {
        throw BackupError("This backup was made by a newer version of the app. Update and try again.")
    }
    guard case .number(Double(backupVersion))? = data["backupVersion"] else {
        throw damaged("backupVersion", "unsupported")
    }
    guard case .number(let exportedAt)? = data["exportedAt"] else { throw damaged("exportedAt", "expected num") }

    func list<T>(_ key: String, _ parse: (JSONValue) throws -> T) throws -> [T] {
        guard case .array(let items)? = data[key] else { throw damaged(key, "expected list<dynamic>") }
        return try items.enumerated().map { i, item in
            guard case .object = item else { throw damaged("\(key).\(i)", "expected object") }
            do { return try parse(item) } catch { throw damaged("\(key).\(i)", "invalid") }
        }
    }

    guard case .object(let settings)? = data["settings"] else { throw damaged("settings", "expected object") }
    var kept: [String: JSONScalar] = [:]
    for key in backupSettingKeys {
        switch settings[key] {
        case .number(let n)?: kept[key] = .number(n)
        case .bool(let b)?: kept[key] = .bool(b)
        default: break
        }
    }

    return Backup(
        exportedAt: Millis(exportedAt),
        decks: try list("decks") { d in
            guard case .string? = d["id"], case .number(let v)? = d["deckVersion"], v >= 1, v == v.rounded(),
                  case .bool? = d["includeObscure"]
            else { throw BackupError("invalid") }
            return try d.decode(BackupDeck.self)
        },
        cardStates: try list("cardStates") { try $0.decode(CardState.self) },
        reviewLog: try list("reviewLog") { try $0.decode(ReviewLogEntry.self).withId(nil) },
        settings: kept
    )
}

public struct BackupSummary: Hashable, Sendable {
    public var decks: [String]
    public var cards: Int
    public var reviews: Int
    public var firstReview: Millis?
    public var lastReview: Millis?
    public var exportedAt: Millis
}

public func summarizeBackup(_ b: Backup) -> BackupSummary {
    let times = b.reviewLog.map(\.reviewedAt)
    return BackupSummary(
        decks: b.decks.map(\.id), cards: b.cardStates.count, reviews: b.reviewLog.count,
        firstReview: times.min(), lastReview: times.max(), exportedAt: b.exportedAt
    )
}

public enum ImportMode: Sendable { case replace, merge }

public struct ImportResult: Sendable {
    /// Decks the backup used that aren't installed here, queued to install.
    public var pendingDecks: [PendingDeckInstall]
    public var addedReviews: Int
}

private func logKey(_ e: ReviewLogEntry) -> String { "\(e.cardId)\u{0}\(e.reviewedAt)\u{0}\(e.rating.rawValue)" }

/// Loads a backup. `replace` wipes progress and takes the backup's settings;
/// `merge` adds missing reviews and keeps the more recently reviewed state.
@discardableResult
public func importBackup(_ repository: Repository, _ backup: Backup, mode: ImportMode) throws -> ImportResult {
    try repository.atomically { repo in
        var added = 0
        switch mode {
        case .replace:
            try repo.resetProgress()
            try repo.putCardStates(backup.cardStates)
            for e in backup.reviewLog { try repo.appendReview(e) }
            added = backup.reviewLog.count
            try repo.updateSettings { s in
                let d = Settings()
                let get = { (key: String) in backup.settings[key] }
                s.desiredRetention = get("desiredRetention")?.number ?? d.desiredRetention
                s.newCardsPerDay = get("newCardsPerDay")?.number.map { Int($0) } ?? d.newCardsPerDay
                s.maxReviewsPerDay = get("maxReviewsPerDay")?.number.map { Int($0) } ?? d.maxReviewsPerDay
                s.dayRolloverHour = get("dayRolloverHour")?.number.map { Int($0) } ?? d.dayRolloverHour
                s.leechThreshold = get("leechThreshold")?.number.map { Int($0) } ?? d.leechThreshold
                s.flagPairs = get("flagPairs")?.bool ?? d.flagPairs
            }
        case .merge:
            var existing = Set(repo.allReviews().map(logKey))
            for e in backup.reviewLog where existing.insert(logKey(e)).inserted {
                try repo.appendReview(e)
                added += 1
            }
            let local = repo.cardStates(backup.cardStates.map(\.cardId))
            try repo.putCardStates(zip(backup.cardStates, local).compactMap { incoming, current in
                guard let current else { return incoming }
                return (incoming.fsrs.lastReview ?? -1) > (current.fsrs.lastReview ?? -1) ? incoming : nil
            })
        }

        var settings = repo.settings()
        var pending: [String: PendingDeckInstall] = [:]
        var order: [String] = []
        for p in settings.pendingDeckInstalls {
            pending[p.id] = p
            order.append(p.id)
        }
        for deck in backup.decks {
            if repo.deck(deck.id) != nil {
                if mode == .replace || deck.includeObscure {
                    try repo.updateDeck(deck.id, includeObscure: deck.includeObscure)
                }
            } else {
                if pending[deck.id] == nil { order.append(deck.id) }
                pending[deck.id] = PendingDeckInstall(id: deck.id, deckVersion: deck.deckVersion, includeObscure: deck.includeObscure)
            }
        }
        let pendingList = order.compactMap { pending[$0] }
        settings = repo.settings()
        settings.pendingDeckInstalls = pendingList
        try repo.saveSettings(settings)
        let ids = Set(backup.decks.map(\.id))
        return ImportResult(pendingDecks: pendingList.filter { ids.contains($0.id) }, addedReviews: added)
    }
}

/// `recall-backup-2026-01-31.json`, by local date.
public func backupFileName(now: Millis, timeZone: TimeZone = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let d = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(now) / 1000))
    return String(format: "recall-backup-%04d-%02d-%02d.json", d.year!, d.month!, d.day!)
}

/// Whole days since the last backup, or nil if there has never been one.
public func daysSinceBackup(_ lastBackupAt: Millis?, now: Millis) -> Int? {
    lastBackupAt.map { max(0, floorDiv(now - $0, 86_400_000)) }
}
