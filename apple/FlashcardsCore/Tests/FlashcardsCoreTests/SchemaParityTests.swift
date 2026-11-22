import Foundation
import Testing
@testable import FlashcardsCore

private struct GoldenCard: Decodable, Equatable {
    var id: String
    var flag: String
    var answers: [String]
    var cloze: String?
    var blanked: String?
    var shown: String?
    var targets: [String]?
}

private struct CardsGolden: Decodable {
    var cards: [String: [GoldenCard]]
}

@Suite struct SchemaParityTests {
    @Test func parsesEveryBuiltDeckListedInTheManifest() throws {
        let manifest = try Repo.manifest()
        let decks = try Repo.decks()
        #expect(!decks.isEmpty)
        for entry in manifest.decks {
            let deck = try #require(decks[entry.id])
            #expect(deck.deckVersion == entry.deckVersion)
            #expect(deck.options.filter { !$0.hidden }.count == entry.optionCount, "\(entry.id)")
        }
    }

    @Test func derivesTheSameCardsAsTheTypeScriptPipeline() throws {
        let golden = try Repo.fixture("cards_golden.json", as: CardsGolden.self).cards
        let decks = try Repo.decks()
        #expect(Set(golden.keys) == Set(decks.keys))
        for (id, expected) in golden {
            let actual = deriveCards(try #require(decks[id]), flagPairs: true).map {
                GoldenCard(
                    id: $0.id, flag: $0.flag, answers: $0.answers, cloze: $0.cloze,
                    blanked: $0.cloze == nil ? nil : $0.blanked, shown: $0.shown,
                    targets: $0.shown == nil ? nil : $0.targets
                )
            }
            #expect(actual.count == expected.count, "\(id)")
            for (a, e) in zip(actual, expected) where a != e {
                Issue.record("\(id): \(a) != \(e)")
                break
            }
        }
    }

    @Test func flagPairCardsOnlyAppearWhenAskedFor() throws {
        let deck = try Repo.firstDeck()
        #expect(!deriveCards(deck).contains { $0.isFlagPair })
        #expect(deriveCards(deck, flagPairs: true).contains { $0.isFlagPair })
    }

    @Test func decksRoundTripThroughJSON() throws {
        for deck in try Repo.decks().values {
            let again = try Deck.decode(JSONEncoder().encode(deck))
            #expect(again == deck)
        }
    }

    @Test func rejectsAnUnknownSchemaVersion() {
        let json = #"{"schemaVersion":2,"id":"x","tool":"x","variant":"x","toolVersion":"1","deckVersion":1,"source":"help","license":"MIT","attribution":"","options":[]}"#
        #expect(throws: DeckFormatError.self) { try Deck.decode(Data(json.utf8)) }
    }

    @Test func clozeSplitsLikeJavaScript() {
        #expect(splitKeepingSpace("a  b") == ["a", "  ", "b"])
        #expect(splitKeepingSpace(" a") == ["", " ", "a"])
        #expect(splitKeepingSpace("a ") == ["a", " ", ""])
        #expect(splitKeepingSpace("") == [""])
    }
}
