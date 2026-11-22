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
