import Foundation
import Observation
import SkipFuse
import FlashcardsCore

/// App-wide state: storage, the scheduler, and what the screens show.
@MainActor @Observable final class AppModel {
    /// Set once storage has opened and the bundled decks are installed.
    private(set) var repository: Repository?
    private(set) var scheduler: Scheduler?
    private(set) var decks: [StoredDeck] = []
    private(set) var queue: StudyQueue?
    /// A one-line note after decks change, like "Updated rg to version 2".
    var notice: String?
    private(set) var loadError: String?

    init() {}

    var now: Millis { Millis(Date().timeIntervalSince1970 * 1000) }

    /// Opens storage and brings installed decks in line with the ones bundled
    /// with this version of the app.
    func start() {
        guard repository == nil else { return }
        do {
            let repository = try Repository(backend: FileBackend(directory: try Self.storageDirectory()))
            let result = try syncDecks(repository, BundledDecks(), platformFlavor: platformFlavor, now: { [now] in now })
            if !result.failed.isEmpty {
                logger.error("Bundled decks failed to load: \(result.failed.joined(separator: ", "))")
            }
            notice = describeSync(result)
            self.repository = repository
            self.scheduler = Scheduler(repository: repository)
            refresh()
        } catch {
            logger.error("Storage failed to open: \(error)")
            loadError = "\(error)"
        }
    }

    /// Reloads what the screens show.
    func refresh() {
        guard let repository, let scheduler else { return }
        decks = repository.listDecks()
        queue = scheduler.queue(now: now)
    }

    /// Application Support/CLI Flashcards, created if needed. Kept across app
    /// updates.
    static func storageDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = base.appendingPathComponent("CLI Flashcards", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// The decks built by the TypeScript pipeline (`public/data/decks/`), bundled
/// as resources through the `Resources/Decks` link.
struct BundledDecks: DeckSource {
    private var directory: URL {
        get throws {
            guard let index = Bundle.module.url(forResource: "index", withExtension: "json") else {
                throw StorageError("The app has no bundled decks")
            }
            return index.deletingLastPathComponent()
        }
    }

    func manifest() throws -> DeckManifest { try DirectoryDeckSource(directory: directory).manifest() }
    func deck(_ entry: DeckManifestEntry) throws -> Deck { try DirectoryDeckSource(directory: directory).deck(entry) }
}
