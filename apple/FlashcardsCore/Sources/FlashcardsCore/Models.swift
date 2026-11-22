// Stored records, ported from `src/core/storage/types.ts`. JSON shapes match
// the other apps' so backups move between them unchanged. Times are epoch
// milliseconds.

import Foundation

/// Epoch milliseconds, as the other apps store times.
public typealias Millis = Int

/// Where a card is in the FSRS life cycle.
public enum CardPhase: String, Codable, Sendable {
    case new, learning, review, relearning
}

/// 1 = Again, 2 = Hard, 3 = Good, 4 = Easy.
public enum Rating: Int, Codable, CaseIterable, Sendable {
    case again = 1, hard, good, easy
}

public struct FsrsState: Codable, Hashable, Sendable {
    public var phase: CardPhase
    /// When the card is next due.
    public var due: Millis
    public var stability: Double
    public var difficulty: Double
    /// Days between the previous review and the last one.
    public var elapsedDays: Int
    /// Days the last review scheduled the card out by.
    public var scheduledDays: Int
    /// Index into the learning or relearning steps.
    public var learningSteps: Int
    public var reps: Int
    public var lapses: Int
    public var lastReview: Millis?

    public init(
        phase: CardPhase, due: Millis, stability: Double, difficulty: Double, elapsedDays: Int,
        scheduledDays: Int, learningSteps: Int, reps: Int, lapses: Int, lastReview: Millis? = nil
    ) {
        self.phase = phase
        self.due = due
        self.stability = stability
        self.difficulty = difficulty
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
        self.learningSteps = learningSteps
        self.reps = reps
        self.lapses = lapses
        self.lastReview = lastReview
    }

    enum CodingKeys: String, CodingKey {
        case phase, due, stability, difficulty, elapsedDays, scheduledDays, learningSteps, reps
        case lapses, lastReview
    }

    // Integers may arrive as JSON numbers with a fraction (`1.0`) from the web
    // app, so they're read as doubles and truncated, as the Dart app does.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decode(CardPhase.self, forKey: .phase)
        due = try c.decodeInt(.due)
        stability = try c.decode(Double.self, forKey: .stability)
        difficulty = try c.decode(Double.self, forKey: .difficulty)
        elapsedDays = try c.decodeInt(.elapsedDays)
        scheduledDays = try c.decodeInt(.scheduledDays)
        learningSteps = try c.decodeInt(.learningSteps)
        reps = try c.decodeInt(.reps)
        lapses = try c.decodeInt(.lapses)
        lastReview = try c.decodeIntIfPresent(.lastReview)
    }
}

extension KeyedDecodingContainer {
    func decodeInt(_ key: Key) throws -> Int {
        if let int = try? decode(Int.self, forKey: key) { return int }
        return Int(try decode(Double.self, forKey: key))
    }

    func decodeIntIfPresent(_ key: Key) throws -> Int? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeInt(key)
    }
}

/// Scheduling state for one card. Never removed when a deck changes.
public struct CardState: Codable, Hashable, Sendable {
    public var cardId: String
    public var deckId: String
    public var optionId: String
    public var fsrs: FsrsState
    public var suspended: Bool
    /// Buried cards are skipped until this time.
    public var buriedUntil: Millis?
    /// Forgotten `leechThreshold` times.
    public var leech: Bool

    public init(
        cardId: String, deckId: String, optionId: String, fsrs: FsrsState, suspended: Bool = false,
        buriedUntil: Millis? = nil, leech: Bool = false
    ) {
        self.cardId = cardId
        self.deckId = deckId
        self.optionId = optionId
        self.fsrs = fsrs
        self.suspended = suspended
        self.buriedUntil = buriedUntil
        self.leech = leech
    }

    enum CodingKeys: String, CodingKey { case cardId, deckId, optionId, fsrs, suspended, buriedUntil, leech }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardId = try c.decode(String.self, forKey: .cardId)
        deckId = try c.decode(String.self, forKey: .deckId)
        optionId = try c.decode(String.self, forKey: .optionId)
        fsrs = try c.decode(FsrsState.self, forKey: .fsrs)
        suspended = try c.decode(Bool.self, forKey: .suspended)
        buriedUntil = try c.decodeIntIfPresent(.buriedUntil)
        leech = try c.decodeIfPresent(Bool.self, forKey: .leech) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cardId, forKey: .cardId)
        try c.encode(deckId, forKey: .deckId)
        try c.encode(optionId, forKey: .optionId)
        try c.encode(fsrs, forKey: .fsrs)
        try c.encode(suspended, forKey: .suspended)
        try c.encodeIfPresent(buriedUntil, forKey: .buriedUntil)
        if leech { try c.encode(true, forKey: .leech) }
    }
}

/// One grade, appended and never edited (except by undo).
public struct ReviewLogEntry: Codable, Hashable, Sendable {
    /// Assigned when stored.
    public var id: Int?
    public var cardId: String
    public var deckId: String
    public var reviewedAt: Millis
    public var rating: Rating
    public var durationMs: Int
    /// Nil for the card's first review.
    public var before: FsrsState?
    public var after: FsrsState

    public init(
        id: Int? = nil, cardId: String, deckId: String, reviewedAt: Millis, rating: Rating,
        durationMs: Int, before: FsrsState?, after: FsrsState
    ) {
        self.id = id
        self.cardId = cardId
        self.deckId = deckId
        self.reviewedAt = reviewedAt
        self.rating = rating
        self.durationMs = durationMs
        self.before = before
        self.after = after
    }

    enum CodingKeys: String, CodingKey { case id, cardId, deckId, reviewedAt, rating, durationMs, before, after }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIntIfPresent(.id)
        cardId = try c.decode(String.self, forKey: .cardId)
        deckId = try c.decode(String.self, forKey: .deckId)
        reviewedAt = try c.decodeInt(.reviewedAt)
        let value = try c.decode(Int.self, forKey: .rating)
        guard let rating = Rating(rawValue: value) else {
            throw DecodingError.dataCorruptedError(forKey: .rating, in: c, debugDescription: "rating must be 1 to 4")
        }
        self.rating = rating
        durationMs = try c.decodeInt(.durationMs)
        before = try c.decodeIfPresent(FsrsState.self, forKey: .before)
        after = try c.decode(FsrsState.self, forKey: .after)
    }

    /// Backups leave the ID out; storage keeps it.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if encoder.userInfo[.includeReviewIds] as? Bool == true { try c.encodeIfPresent(id, forKey: .id) }
        try c.encode(cardId, forKey: .cardId)
        try c.encode(deckId, forKey: .deckId)
        try c.encode(reviewedAt, forKey: .reviewedAt)
        try c.encode(rating, forKey: .rating)
        try c.encode(durationMs, forKey: .durationMs)
        if let before { try c.encode(before, forKey: .before) } else { try c.encodeNil(forKey: .before) }
        try c.encode(after, forKey: .after)
    }

    func withId(_ id: Int?) -> ReviewLogEntry {
        var copy = self
        copy.id = id
        return copy
    }
}

extension CodingUserInfoKey {
    static let includeReviewIds = CodingUserInfoKey(rawValue: "includeReviewIds")!
}

/// An installed deck with per-deck preferences.
public struct StoredDeck: Hashable, Sendable, Identifiable {
    public var deck: Deck
    public var installedAt: Millis
    public var updatedAt: Millis
    /// Obscure-tier options are left out of new cards unless this is on.
    public var includeObscure: Bool
    /// Paused decks show no cards until resumed (the per-deck study switch).
    public var paused: Bool
    /// Meaning → flag and cloze cards ask for the flag to be typed.
    public var typeAnswers: Bool

    public var id: String { deck.id }
    public var deckVersion: Int { deck.deckVersion }

    public init(
        deck: Deck, installedAt: Millis, updatedAt: Millis, includeObscure: Bool = false,
        paused: Bool = false, typeAnswers: Bool = false
    ) {
        self.deck = deck
        self.installedAt = installedAt
        self.updatedAt = updatedAt
        self.includeObscure = includeObscure
        self.paused = paused
        self.typeAnswers = typeAnswers
    }
}

/// Implementation families of tools whose flags differ.
public enum DeckFlavor: String, Codable, CaseIterable, Sendable {
    case gnu, bsd
}

public struct PendingDeckInstall: Codable, Hashable, Sendable {
    public var id: String
    public var deckVersion: Int
    public var includeObscure: Bool

    public init(id: String, deckVersion: Int, includeObscure: Bool) {
        self.id = id
        self.deckVersion = deckVersion
        self.includeObscure = includeObscure
    }
}

public enum AppTheme: String, Codable, CaseIterable, Sendable { case system, light, dark }

public enum TextSize: String, Codable, CaseIterable, Sendable {
    case s, m, l
    public var scale: Double {
        switch self {
        case .s: 0.875
        case .m: 1
        case .l: 1.125
        }
    }
}

public enum MotionPreference: String, Codable, CaseIterable, Sendable { case system, reduce, full }

/// Every stored setting. Defaults match `SETTING_DEFAULTS` in the web app.
public struct Settings: Codable, Hashable, Sendable {
    /// Probability of recall FSRS aims for.
    public var desiredRetention = 0.9
    /// New cards per day, across all decks.
    public var newCardsPerDay = 20
    /// Review (not learning) cards per day, across all decks.
    public var maxReviewsPerDay = 200
    /// Local hour at which a new study day starts.
    public var dayRolloverHour = 4
    /// Lapses after which a card is tagged a leech and suspended.
    public var leechThreshold = 6
    /// When a backup was last exported.
    public var lastBackupAt: Millis?
    /// Adds short → long and long → short cards.
    public var flagPairs = true
    /// Decks an imported backup used that aren't installed yet.
    public var pendingDeckInstalls: [PendingDeckInstall] = []
    /// The flavor the user picked, or nil to follow what's installed.
    public var deckFlavor: DeckFlavor?
    /// Whether the welcome tour has been finished or skipped.
    public var onboardingDone = false
    /// Solid surfaces instead of frosted glass.
    public var reduceTransparency = false
    public var theme: AppTheme = .system
    public var textSize: TextSize = .m
    /// `reduce` keeps fades but drops movement; `system` follows the device.
    public var motion: MotionPreference = .system

    public init() {}

    enum CodingKeys: String, CodingKey {
        case desiredRetention, newCardsPerDay, maxReviewsPerDay, dayRolloverHour, leechThreshold
        case lastBackupAt, flagPairs, pendingDeckInstalls, deckFlavor, onboardingDone
        case reduceTransparency, theme, textSize, motion
    }

    /// Lenient, like the other apps: a missing or unknown value falls back to its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        desiredRetention = (try? c.decode(Double.self, forKey: .desiredRetention)) ?? d.desiredRetention
        newCardsPerDay = (try? c.decodeInt(.newCardsPerDay)) ?? d.newCardsPerDay
        maxReviewsPerDay = (try? c.decodeInt(.maxReviewsPerDay)) ?? d.maxReviewsPerDay
        dayRolloverHour = (try? c.decodeInt(.dayRolloverHour)) ?? d.dayRolloverHour
        leechThreshold = (try? c.decodeInt(.leechThreshold)) ?? d.leechThreshold
        lastBackupAt = (try? c.decodeIntIfPresent(.lastBackupAt)) ?? nil
        flagPairs = (try? c.decode(Bool.self, forKey: .flagPairs)) ?? d.flagPairs
        pendingDeckInstalls = (try? c.decode([PendingDeckInstall].self, forKey: .pendingDeckInstalls)) ?? []
        deckFlavor = (try? c.decodeIfPresent(DeckFlavor.self, forKey: .deckFlavor)) ?? nil
        onboardingDone = (try? c.decode(Bool.self, forKey: .onboardingDone)) ?? false
        reduceTransparency = (try? c.decode(Bool.self, forKey: .reduceTransparency)) ?? false
        theme = (try? c.decode(AppTheme.self, forKey: .theme)) ?? d.theme
        textSize = (try? c.decode(TextSize.self, forKey: .textSize)) ?? d.textSize
        motion = (try? c.decode(MotionPreference.self, forKey: .motion)) ?? d.motion
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(desiredRetention, forKey: .desiredRetention)
        try c.encode(newCardsPerDay, forKey: .newCardsPerDay)
        try c.encode(maxReviewsPerDay, forKey: .maxReviewsPerDay)
        try c.encode(dayRolloverHour, forKey: .dayRolloverHour)
        try c.encode(leechThreshold, forKey: .leechThreshold)
        if let lastBackupAt { try c.encode(lastBackupAt, forKey: .lastBackupAt) } else { try c.encodeNil(forKey: .lastBackupAt) }
        try c.encode(flagPairs, forKey: .flagPairs)
        try c.encode(pendingDeckInstalls, forKey: .pendingDeckInstalls)
        if let deckFlavor { try c.encode(deckFlavor, forKey: .deckFlavor) } else { try c.encodeNil(forKey: .deckFlavor) }
        try c.encode(onboardingDone, forKey: .onboardingDone)
        try c.encode(reduceTransparency, forKey: .reduceTransparency)
        try c.encode(theme, forKey: .theme)
        try c.encode(textSize, forKey: .textSize)
        try c.encode(motion, forKey: .motion)
    }
}

/// Allowed ranges for scheduling settings, from `src/core/scheduler/settings.ts`.
public struct SettingLimits: Sendable {
    public var min: Double
    public var max: Double
    public var step: Double

    /// Brings a value into range and onto its step.
    public func normalize(_ value: Double) -> Double {
        let stepped = (value / step).rounded(.toNearestOrAwayFromZero) * step
        let clamped = Swift.min(Swift.max(stepped, min), max)
        return (clamped * 100).rounded() / 100
    }

    public static let desiredRetention = SettingLimits(min: 0.7, max: 0.99, step: 0.01)
    public static let newCardsPerDay = SettingLimits(min: 0, max: 999, step: 1)
    public static let maxReviewsPerDay = SettingLimits(min: 0, max: 9999, step: 1)
    public static let dayRolloverHour = SettingLimits(min: 0, max: 23, step: 1)
    public static let leechThreshold = SettingLimits(min: 2, max: 99, step: 1)
}
