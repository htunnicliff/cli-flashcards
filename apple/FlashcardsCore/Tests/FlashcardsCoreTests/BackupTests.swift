import Foundation
import Testing
@testable import FlashcardsCore

@Suite struct BackupTests {
    let testDeck = deck([option("ignore-case", ["-i", "--ignore-case"]), option("count", ["-c", "--count"])])

    @Test func exportThenReplaceImportRoundTripsProgressAndSettings() throws {
        let source = Repository.inMemory()
        try source.installDeck(testDeck, now: noon, includeObscure: true)
        try source.updateSettings { $0.newCardsPerDay = 7 }
        let scheduler = Scheduler(repository: source, timeZone: testZone)
        try scheduler.grade("rg:default:ignore-case:flag-to-meaning", .good, now: noon)
        try scheduler.grade("rg:default:count:meaning-to-flag", .again, now: noon)

        let backup = try exportBackup(source, now: noon + day)
        #expect(source.settings().lastBackupAt == noon + day)

        let target = Repository.inMemory()
        let result = try importBackup(target, parseBackup(backup.encode()), mode: .replace)
        #expect(result.addedReviews == 2)
        #expect(result.pendingDecks.map(\.id) == ["rg-default"])
        #expect(target.settings().newCardsPerDay == 7)
        #expect(target.reviewCount() == 2)
        #expect(target.allCardStates() == source.allCardStates())
    }

    @Test func mergeAddsOnlyMissingReviewsAndKeepsNewerStates() throws {
        let repo = Repository.inMemory()
        try repo.installDeck(testDeck, now: noon)
        let scheduler = Scheduler(repository: repo, timeZone: testZone)
        let id = "rg:default:ignore-case:flag-to-meaning"
        try scheduler.grade(id, .good, now: noon)
        let backup = try parseBackup(exportBackup(repo, now: noon).encode())
        try scheduler.grade(id, .good, now: noon + 11 * minute)
        let result = try importBackup(repo, backup, mode: .merge)
        #expect(result.addedReviews == 0)
        #expect(repo.cardState(id)?.fsrs.lastReview == noon + 11 * minute)
    }

    static let webBackup = """
    {"format":"recall-backup","backupVersion":1,"exportedAt":1767225600000,
    "decks":[{"id":"rg-default","deckVersion":2,"includeObscure":false}],
    "cardStates":[{"cardId":"rg:default:ignore-case:cloze","deckId":"rg-default","optionId":"ignore-case",
    "fsrs":{"phase":"review","due":1767830400000,"stability":7.2,"difficulty":5.1,"elapsedDays":0,
    "scheduledDays":7,"learningSteps":0,"reps":3,"lapses":0,"lastReview":1767225600000},"suspended":false}],
    "reviewLog":[{"cardId":"rg:default:ignore-case:cloze","deckId":"rg-default","reviewedAt":1767225600000,
    "rating":3,"durationMs":1200,"before":null,"after":{"phase":"learning","due":1767226200000,"stability":2.3,
    "difficulty":2.1,"elapsedDays":0,"scheduledDays":0,"learningSteps":1,"reps":1,"lapses":0,"lastReview":1767225600000}}],
    "settings":{"desiredRetention":0.85,"flagPairs":false}}
    """

    @Test func readsABackupWrittenByTheWebApp() throws {
        let backup = try parseBackup(Data(Self.webBackup.utf8))
        #expect(backup.cardStates.first?.fsrs.phase == .review)
        #expect(backup.reviewLog.first?.rating == .good)
        #expect(backup.settings == ["desiredRetention": .number(0.85), "flagPairs": .bool(false)])
        #expect(summarizeBackup(backup).reviews == 1)
        let again = try JSONSerialization.jsonObject(with: backup.encode()) as? [String: Any]
        #expect(again?["format"] as? String == "recall-backup")
    }

    /// The Swift app writes what the other apps read: the same keys, with
    /// `before: null` kept and no stored IDs.
    @Test func writesTheSharedFormat() throws {
        let backup = try parseBackup(Data(Self.webBackup.utf8))
        let json = String(decoding: try backup.encode(), as: UTF8.self)
        #expect(json.contains(#""before":null"#))
        #expect(!json.contains(#""id":1"#))
        let reparsed = try parseBackup(backup.encode())
        #expect(reparsed.cardStates == backup.cardStates)
        #expect(reparsed.reviewLog == backup.reviewLog)
    }

    @Test func rejectsFilesThatAreNotBackupsWithAReadableMessage() {
        #expect(throws: BackupError("This file isn’t valid JSON.")) { try parseBackup(Data("nope".utf8)) }
        #expect(throws: BackupError("This file isn’t a --recall backup.")) { try parseBackup(Data(#"{"format":"other"}"#.utf8)) }
        do {
            _ = try parseBackup(Data(#"{"format":"recall-backup","backupVersion":9}"#.utf8))
            Issue.record("expected an error")
        } catch let error as BackupError {
            #expect(error.message.contains("newer version"))
        } catch {
            Issue.record("wrong error \(error)")
        }
        #expect(throws: BackupError("This backup is damaged (reviewLog.0: invalid).")) {
            try parseBackup(Data(Self.webBackup.replacingOccurrences(of: #""rating":3"#, with: #""rating":7"#).utf8))
        }
    }

    @Test func backupFileNameUsesTheLocalDate() {
        #expect(backupFileName(now: 1_769_868_000_000, timeZone: testZone) == "recall-backup-2026-01-31.json")
    }
}
