import Foundation
import Observation
import SkipFuse
import FlashcardsCore

/// The four places the app goes, in tab and sidebar order.
enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case review, decks, stats, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .review: "Review"
        case .decks: "Decks"
        case .stats: "Stats"
        case .settings: "Settings"
        }
    }

    /// Android maps only some symbol names to Material icons, so it gets
    /// ones from that set.
    var systemImage: String {
        #if os(Android)
        switch self {
        case .review: "play"
        case .decks: "list.bullet"
        case .stats: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
        #else
        switch self {
        case .review: "rectangle.stack"
        case .decks: "square.stack.3d.up"
        case .stats: "chart.bar"
        case .settings: "gearshape"
        }
        #endif
    }
}

/// App-wide state: storage, settings, installed decks and the current
/// section. Ports the role of `app/lib/app/app_state.dart`. There is one per
/// process, so every window and the Mac menu commands share it.
@MainActor @Observable final class AppModel {
    static let shared = AppModel()

    /// Set once storage has opened and the bundled decks are installed.
    private(set) var repository: Repository?
    private(set) var scheduler: Scheduler?
    private(set) var settings = Settings()
    private(set) var decks: [StoredDeck] = []
    private(set) var queue: StudyQueue?
    /// Every deck bundled with the app, installed or not.
    private(set) var manifest: DeckManifest?
    /// Goes up whenever progress or decks change, so screens that read
    /// storage directly know to read it again.
    private(set) var revision = 0
    /// A one-line note after decks change, like "Updated rg to version 2".
    var notice: String?
    private(set) var loadError: String?
    /// The last change that failed to save, shown until dismissed.
    var saveError: String?

    var section: AppSection = .review

    /// Whether the welcome tour should open (#84).
    var tourOpen = false

    init() {}

    var now: Millis { Millis(Date().timeIntervalSince1970 * 1000) }

    /// Opens storage and brings installed decks in line with the ones bundled
    /// with this version of the app.
    func start() {
        guard repository == nil, loadError == nil else { return }
        do {
            let repository = try Repository(backend: FileBackend(directory: try Self.storageDirectory()))
            manifest = try? BundledDecks().manifest()
            try sync(repository)
            self.repository = repository
            self.scheduler = Scheduler(repository: repository)
            settings = repository.settings()
            if !settings.onboardingDone {
                if repository.reviewCount() > 0 {
                    settings = try repository.updateSettings { $0.onboardingDone = true }
                } else {
                    tourOpen = true
                }
            }
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
        revision += 1
    }

    private func sync(_ repository: Repository) throws {
        let result = try syncDecks(repository, BundledDecks(), platformFlavor: platformFlavor, now: { [now] in now })
        if !result.failed.isEmpty {
            logger.error("Bundled decks failed to load: \(result.failed.joined(separator: ", "))")
        }
        notice = describeSync(result)
    }

    /// Runs a change to storage, then refreshes. A failure is shown, not thrown.
    private func change(_ what: String, _ work: (Repository) throws -> Void) {
        guard let repository else { return }
        do {
            try work(repository)
        } catch {
            logger.error("\(what) failed: \(error)")
            saveError = "Couldn’t \(what): \(error)"
        }
        refresh()
    }

    func setDeckPrefs(_ id: String, paused: Bool? = nil, includeObscure: Bool? = nil, typeAnswers: Bool? = nil) {
        change("save the deck") {
            try $0.updateDeck(id, includeObscure: includeObscure, paused: paused, typeAnswers: typeAnswers)
        }
    }

    func resetProgress(_ deckId: String) {
        change("reset progress") { try $0.resetProgress(deckId: deckId) }
    }

    func unsuspend(_ cardIds: [String]) {
        guard let scheduler else { return }
        change("unsuspend") { _ in try scheduler.unsuspend(cardIds) }
    }

    /// The GNU or BSD decks, for tools whose flags differ. Switching swaps
    /// the installed decks and keeps their settings.
    var deckFlavor: DeckFlavor {
        resolveFlavor(settings.deckFlavor, decks.map(\.deck.variant), platformFlavor)
    }

    func setDeckFlavor(_ flavor: DeckFlavor) {
        guard flavor != deckFlavor else { return }
        change("switch decks") { repository in
            settings = try repository.updateSettings { $0.deckFlavor = flavor }
            try sync(repository)
        }
    }

    /// Changes and saves settings. A failed save keeps the old settings.
    func updateSettings(_ change: (inout Settings) -> Void) {
        guard let repository else {
            change(&settings)
            return
        }
        do {
            settings = try repository.updateSettings(change)
            refresh()
        } catch {
            logger.error("Settings failed to save: \(error)")
            saveError = "Couldn’t save settings: \(error)"
        }
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
