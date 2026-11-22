import Foundation
@testable import FlashcardsCore

/// Files from the rest of the repository: the built decks and the parity
/// fixtures that `pnpm fixtures:golden` writes from the TypeScript code.
enum Repo {
    /// The repository root, two levels above this file's package.
    static let root: URL = {
        if let override = ProcessInfo.processInfo.environment["CLI_FLASHCARDS_ROOT"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FlashcardsCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // FlashcardsCore
            .deletingLastPathComponent() // apple
            .deletingLastPathComponent() // repo
    }()

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    static let decksDir = "public/data/decks"
    static let fixturesDir = "apple/FlashcardsCore/Tests/Fixtures"

    static func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: data("\(fixturesDir)/\(name)"))
    }

    static func manifest() throws -> DeckManifest {
        try DeckManifest.decode(data("\(decksDir)/index.json"))
    }

    /// The first deck in manifest order.
    static func firstDeck() throws -> Deck {
        let entry = try manifest().decks[0]
        return try Deck.decode(data("\(decksDir)/\(entry.file)"))
    }

    static func decks() throws -> [String: Deck] {
        var decks: [String: Deck] = [:]
        for entry in try manifest().decks {
            decks[entry.id] = try Deck.decode(data("\(decksDir)/\(entry.file)"))
        }
        return decks
    }
}
