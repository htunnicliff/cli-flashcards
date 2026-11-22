import Foundation
import Testing
@testable import FlashcardsCore

@Suite struct StorageTests {
    let testDeck = deck([option("ignore-case", ["-i", "--ignore-case"]), option("count", ["-c", "--count"])])

    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("flashcards-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func everythingSurvivesAReopen() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = try Repository(backend: FileBackend(directory: dir))
        try repo.installDeck(testDeck, now: noon, includeObscure: true)
        try repo.updateDeck("rg-default", paused: true)
        try repo.updateSettings { $0.newCardsPerDay = 9; $0.deckFlavor = .bsd }
        let scheduler = Scheduler(repository: repo, timeZone: testZone)
        try scheduler.grade("rg:default:ignore-case:flag-to-meaning", .good, now: noon)
        let second = try scheduler.grade("rg:default:count:meaning-to-flag", .again, now: noon + minute)
        try scheduler.grade("rg:default:ignore-case:meaning-to-flag", .easy, now: noon + 2 * minute)
        try scheduler.undo(second)

        let reopened = try Repository(backend: FileBackend(directory: dir))
        #expect(reopened.listDecks() == repo.listDecks())
        #expect(reopened.settings() == repo.settings())
        #expect(reopened.allCardStates() == repo.allCardStates())
        #expect(reopened.allReviews() == repo.allReviews())
        #expect(reopened.reviewCount() == 2)
        // New entries keep getting fresh IDs after a reopen.
        let id = try reopened.appendReview(repo.allReviews()[0])
        #expect(id > repo.allReviews().compactMap(\.id).max()!)
    }

    @Test func aFailedTransactionChangesNothing() throws {
        let repo = Repository.inMemory()
        try repo.installDeck(testDeck, now: noon)
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try repo.atomically { r in
                try r.updateSettings { $0.newCardsPerDay = 1 }
                try r.removeDeck("rg-default")
                throw Boom()
            }
        }
        #expect(repo.settings().newCardsPerDay == 20)
        #expect(repo.deck("rg-default") != nil)
    }

    @Test func aTornLastLineOfTheLogIsDropped() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = try Repository(backend: FileBackend(directory: dir))
        try repo.installDeck(testDeck, now: noon)
        try Scheduler(repository: repo, timeZone: testZone).grade("rg:default:count:meaning-to-flag", .good, now: noon)
        let log = dir.appendingPathComponent("reviews.jsonl")
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"cardId":"rg:def"#.utf8))
        try handle.close()
        #expect(try Repository(backend: FileBackend(directory: dir)).reviewCount() == 1)
    }

    @Test func resetProgressForOneDeck() throws {
        let repo = Repository.inMemory()
        try repo.installDeck(testDeck, now: noon)
        try repo.installDeck(deck([option("x", ["-x"])], tool: "jq"), now: noon)
        let scheduler = Scheduler(repository: repo, timeZone: testZone)
        try scheduler.grade("rg:default:count:meaning-to-flag", .good, now: noon)
        try scheduler.grade("jq:default:x:flag-to-meaning", .good, now: noon)
        try repo.resetProgress(deckId: "rg-default")
        #expect(repo.allCardStates().map(\.deckId) == ["jq-default"])
        #expect(repo.allReviews().map(\.deckId) == ["jq-default"])
    }
}

/// A deck source in memory, standing in for the decks bundled with the app.
struct FakeSource: DeckSource {
    var decks: [Deck]
    func manifest() throws -> DeckManifest {
        let entries = try decks.map { d -> DeckManifestEntry in
            let json = """
            {"id":"\(d.id)","tool":"\(d.tool)","variant":"\(d.variant)","toolVersion":"1","deckVersion":\(d.deckVersion),
            "source":"manual","license":"MIT","file":"\(d.id).json","bytes":1,"optionCount":\(d.options.count),
            "tiers":{"core":\(d.options.count),"common":0,"obscure":0}}
            """
            return try JSONDecoder().decode(DeckManifestEntry.self, from: Data(json.utf8))
        }
        return DeckManifest(decks: entries)
    }
    func deck(_ entry: DeckManifestEntry) throws -> Deck { decks.first { $0.id == entry.id }! }
}

@Suite struct DeckSyncTests {
    let grepGnu = deck([option("count", ["-c", "--count"])], tool: "grep", variant: "gnu")
    let grepBsd = deck([option("count", ["-c", "--count"])], tool: "grep", variant: "bsd")
    let rg = deck([option("count", ["-c", "--count"])], tool: "rg")

    @Test func aFreshInstallGetsOneFlavorOfEveryTool() throws {
        let repo = Repository.inMemory()
        let result = try syncDecks(repo, FakeSource(decks: [grepGnu, grepBsd, rg]), platformFlavor: .bsd, now: { noon })
        #expect(repo.listDecks().map(\.id) == ["grep-bsd", "rg-default"])
        #expect(result.installed.count == 2)
        #expect(repo.listDecks().allSatisfy { !$0.paused })
        #expect(describeSync(result) == nil)
    }

    @Test func aNewerBundledDeckReplacesTheOldOneAndKeepsProgress() throws {
        let repo = Repository.inMemory()
        try syncDecks(repo, FakeSource(decks: [rg]), platformFlavor: .bsd, now: { noon })
        try repo.updateDeck("rg-default", includeObscure: true)
        let scheduler = Scheduler(repository: repo, timeZone: testZone)
        try scheduler.grade("rg:default:count:flag-to-meaning", .good, now: noon)

        let v2 = deck([option("count", ["-c", "--count"]), option("files", ["--files"])], tool: "rg", version: 2)
        let result = try syncDecks(repo, FakeSource(decks: [v2]), platformFlavor: .bsd, now: { noon + day })
        #expect(repo.deck("rg-default")?.deckVersion == 2)
        #expect(repo.deck("rg-default")?.includeObscure == true)
        #expect(repo.cardState("rg:default:count:flag-to-meaning") != nil)
        #expect(describeSync(result) == "Updated rg to version 2: 1 option added.")

        // Nothing to do the second time.
        #expect(try !syncDecks(repo, FakeSource(decks: [v2]), platformFlavor: .bsd, now: { noon }).changed)
    }

    @Test func pickingAFlavorSwitchesTools() throws {
        let repo = Repository.inMemory()
        let source = FakeSource(decks: [grepGnu, grepBsd])
        try syncDecks(repo, source, platformFlavor: .bsd, now: { noon })
        try repo.updateSettings { $0.deckFlavor = .gnu }
        let result = try syncDecks(repo, source, platformFlavor: .bsd, now: { noon })
        #expect(repo.listDecks().map(\.id) == ["grep-gnu"])
        #expect(describeSync(result) == "Switched grep to GNU / Linux.")
    }

    @Test func decksABackupQueuedAreInstalled() throws {
        let repo = Repository.inMemory()
        try syncDecks(repo, FakeSource(decks: [grepBsd]), platformFlavor: .bsd, now: { noon })
        try repo.updateSettings {
            $0.pendingDeckInstalls = [PendingDeckInstall(id: "grep-gnu", deckVersion: 1, includeObscure: true)]
        }
        let result = try syncDecks(repo, FakeSource(decks: [grepGnu, grepBsd]), platformFlavor: .bsd, now: { noon })
        #expect(result.restored.map(\.id) == ["grep-gnu"])
        #expect(repo.deck("grep-gnu")?.includeObscure == true)
        #expect(repo.settings().pendingDeckInstalls.isEmpty)
    }

    @Test func installsEveryDeckBuiltByThePipeline() throws {
        let repo = Repository.inMemory()
        let source = DirectoryDeckSource(directory: Repo.root.appendingPathComponent(Repo.decksDir))
        let result = try syncDecks(repo, source, platformFlavor: .bsd, now: { noon })
        #expect(result.failed.isEmpty)
        let tools = Set(try source.manifest().decks.map(\.tool))
        #expect(Set(repo.listDecks().map(\.deck.tool)) == tools)
        // BSD where a tool has both; tools with only a GNU deck still get one.
        for tool in ["find", "grep", "sed"] {
            #expect(repo.listDecks().first { $0.deck.tool == tool }?.deck.variant == "bsd")
        }
    }
}
