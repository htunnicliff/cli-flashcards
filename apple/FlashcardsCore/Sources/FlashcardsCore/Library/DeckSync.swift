// Keeps installed decks in line with the decks bundled with the app. Ported
// from `app/lib/core/sync.dart`, minus downloading: decks ship inside the app,
// so a new deck version arrives with an app update and is installed on the
// next launch, keeping progress.

import Foundation

/// Where deck files come from.
public protocol DeckSource: Sendable {
    func manifest() throws -> DeckManifest
    func deck(_ entry: DeckManifestEntry) throws -> Deck
}

/// Deck files in a folder: `index.json` and the files it lists.
public struct DirectoryDeckSource: DeckSource {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func manifest() throws -> DeckManifest {
        try DeckManifest.decode(Data(contentsOf: directory.appendingPathComponent("index.json")))
    }

    public func deck(_ entry: DeckManifestEntry) throws -> Deck {
        try Deck.decode(Data(contentsOf: directory.appendingPathComponent(entry.file)))
    }
}

public struct DeckUpdate: Sendable {
    public var entry: DeckManifestEntry
    public var changes: DeckChanges
}

public struct SyncResult: Sendable {
    public var installed: [DeckManifestEntry] = []
    public var restored: [PendingDeckInstall] = []
    public var updated: [DeckUpdate] = []
    /// Decks swapped for another flavor of the same tool: `from` is removed.
    public var switched: [(from: String, to: DeckManifestEntry)] = []
    /// Deck IDs that couldn't be read; the next sync tries again.
    public var failed: [String] = []

    public var changed: Bool { !installed.isEmpty || !updated.isEmpty || !switched.isEmpty }
}

private struct Step {
    var entry: DeckManifestEntry
    var includeObscure = false
    var paused = false
    var typeAnswers = false
    var pending: PendingDeckInstall?
    var previous: StoredDeck?
    var replaces: StoredDeck?
}

/// Installs every tool with no deck here yet (in the user's flavor), updates
/// decks with a newer version, installs decks a backup queued, and once the
/// user has picked a flavor, swaps decks of the other flavor for it.
@discardableResult
public func syncDecks(
    _ repository: Repository, _ source: DeckSource, platformFlavor: DeckFlavor, now: () -> Millis
) throws -> SyncResult {
    let manifest = try source.manifest()
    let installed = repository.listDecks()
    let settings = repository.settings()
    let pending = settings.pendingDeckInstalls
    let chosen = settings.deckFlavor
    var byId: [String: StoredDeck] = [:]
    for d in installed { byId[d.id] = d }
    var entries: [String: DeckManifestEntry] = [:]
    for e in manifest.decks { entries[e.id] = e }
    let flavor = resolveFlavor(chosen, installed.map(\.deck.variant), platformFlavor)
    // A tool new to this install starts paused if the person already studies
    // other decks, so it doesn't flood their queue.
    let startPaused = installed.contains { !$0.paused }

    var steps: [Step] = []
    var extras: [(deck: StoredDeck, to: DeckManifestEntry)] = []
    var planned = Set<String>()
    func plan(_ step: Step) {
        steps.append(step)
        planned.insert(step.entry.id)
    }

    var queued: [PendingDeckInstall] = []
    for item in pending where byId[item.id] == nil {
        queued.append(item)
        if let entry = entries[item.id] {
            plan(Step(entry: entry, includeObscure: item.includeObscure, pending: item))
        }
    }

    for group in groupByTool(manifest.decks) {
        let here = group.variants.filter { byId[$0.id] != nil || planned.contains($0.id) }
        for entry in here {
            if let stored = byId[entry.id], isUpdateAvailable(stored.deckVersion, entry) {
                plan(Step(
                    entry: entry, includeObscure: stored.includeObscure, paused: stored.paused,
                    typeAnswers: stored.typeAnswers, previous: stored
                ))
            }
        }
        let wantedName = variantForFlavor(group.variants.map(\.variant), flavor)
        guard let wanted = group.variants.first(where: { $0.variant == wantedName }) else { continue }
        if here.isEmpty {
            plan(Step(entry: wanted, paused: startPaused))
        } else if chosen != nil, byId[wanted.id] != nil {
            for v in here where v.id != wanted.id {
                if let other = byId[v.id] { extras.append((other, wanted)) }
            }
        } else if chosen != nil, !here.contains(wanted) {
            if let old = here.compactMap({ byId[$0.id] }).first {
                plan(Step(
                    entry: wanted, includeObscure: old.includeObscure, paused: old.paused,
                    typeAnswers: old.typeAnswers, replaces: old
                ))
            }
        }
    }

    var result = SyncResult()
    var restoredIds = Set<String>()
    for step in steps {
        do {
            let deck = try source.deck(step.entry)
            guard deck.id == step.entry.id else {
                throw DeckFormatError("\(step.entry.file) contains deck \"\(deck.id)\", not \"\(step.entry.id)\"")
            }
            try repository.installDeck(
                deck, now: now(), includeObscure: step.includeObscure, paused: step.paused,
                typeAnswers: step.typeAnswers
            )
            if let previous = step.previous {
                result.updated.append(DeckUpdate(entry: step.entry, changes: diffDecks(previous.deck, deck)))
            } else {
                result.installed.append(step.entry)
            }
            if let p = step.pending {
                result.restored.append(p)
                restoredIds.insert(p.id)
            }
            if let replaces = step.replaces {
                try repository.removeDeck(replaces.id)
                result.switched.append((replaces.id, step.entry))
            }
        } catch {
            result.failed.append(step.entry.id)
        }
    }

    for extra in extras {
        try repository.removeDeck(extra.deck.id)
        result.switched.append((extra.deck.id, extra.to))
    }

    let remaining = queued.filter { !restoredIds.contains($0.id) }
    if remaining.count != pending.count {
        try repository.updateSettings { $0.pendingDeckInstalls = remaining }
    }
    return result
}

/// One line for a status message, or nil when nothing worth saying changed.
/// A first install says nothing; switching flavor and updates do.
public func describeSync(_ result: SyncResult) -> String? {
    var parts: [String] = []
    if !result.switched.isEmpty {
        let tools = result.switched.map(\.to.tool)
        let list = tools.count > 1 ? tools.dropLast().joined(separator: ", ") + " and " + tools.last! : tools[0]
        parts.append("Switched \(list) to \(flavorLabel(result.switched[0].to.variant)).")
    }
    for u in result.updated {
        parts.append("Updated \(u.entry.tool) to version \(u.entry.deckVersion): \(describeChanges(u.changes)).")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
}
