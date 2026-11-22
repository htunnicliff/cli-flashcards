import Foundation
import Testing
@testable import FlashcardsCore

private struct GoldenAnswer: Decodable {
    var deck: String
    var option: String
    var input: String
    var correct: Bool
    var expected: String
    var matched: String?
    var preferred: String?
}

private struct AnswersGolden: Decodable {
    var answers: [GoldenAnswer]
}

@Suite struct AnswerParityTests {
    @Test func checksTypedAnswersTheSameWayAsTheTypeScriptApp() throws {
        let golden = try Repo.fixture("answers_golden.json", as: AnswersGolden.self).answers
        let decks = try Repo.decks()
        #expect(golden.count > 100)
        for g in golden {
            let deck = try #require(decks[g.deck])
            let option = try #require(deck.options.first { $0.id == g.option })
            let result = checkAnswer(g.input, option: option, options: deck.options, style: deck.parsingStyle)
            let expected = AnswerResult(correct: g.correct, expected: g.expected, matched: g.matched, preferred: g.preferred)
            #expect(result == expected, "\(g.deck) \(g.option) \"\(g.input)\"")
        }
    }

    @Test func flagPairAnswersAcceptOnlyTheListedSpellings() throws {
        let deck = try Repo.firstDeck()
        let card = try #require(deriveCards(deck, flagPairs: true).first { $0.type == .shortToLong })
        let option = try #require(deck.options.first { $0.id == card.optionId })
        let targets = try #require(card.targets)
        #expect(checkAnswer(targets[0], option: option, options: deck.options, only: targets).correct)
        #expect(!checkAnswer(card.shown!, option: option, options: deck.options, only: targets).correct)
    }

    @Test func diffCharsMarksWhatWasTypedAgainstWhatWasExpected() {
        let parts = diffChars("--ignor-case", "--ignore-case").map { "\($0.kind.rawValue):\($0.text)" }
        #expect(parts == ["same:--ignor", "added:e", "same:-case"])
    }
}
