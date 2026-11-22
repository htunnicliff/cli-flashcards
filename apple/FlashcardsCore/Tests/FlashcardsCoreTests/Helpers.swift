import Foundation
@testable import FlashcardsCore

/// Tests run in one fixed time zone, so study days don't depend on the machine.
let testZone = TimeZone(identifier: "America/New_York")!
/// 2026-03-02 12:00 in `testZone`.
let noon: Millis = 1_772_470_800_000
let minute = 60_000
let day = 86_400_000

func option(_ id: String, _ flags: [String], tier: Tier = .core, examples: [Example] = [], sub: String? = nil) -> Option {
    Option(id: id, flags: flags, summary: "Summary of \(id)", tier: tier, examples: examples, subcommand: sub)
}

func deck(_ options: [Option], tool: String = "rg", variant: String = "default", version: Int = 1) -> Deck {
    Deck(
        id: "\(tool)-\(variant)", tool: tool, variant: variant, toolVersion: "1.0", deckVersion: version,
        source: "manual", license: "MIT", attribution: "test", options: options
    )
}

let anyFsrs = FsrsState(
    phase: .review, due: 0, stability: 1, difficulty: 5, elapsedDays: 0, scheduledDays: 1, learningSteps: 0,
    reps: 1, lapses: 0
)
