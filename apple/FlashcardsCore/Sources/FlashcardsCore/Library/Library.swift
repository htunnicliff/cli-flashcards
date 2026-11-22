// Deck library logic, ported from `src/core/library/index.ts`.

import Foundation

public struct ToolDecks: Hashable, Sendable {
    public var tool: String
    /// Every variant in the manifest, sorted by name.
    public var variants: [DeckManifestEntry]
}

/// Groups manifest entries by tool, tools in alphabetical order.
public func groupByTool<S: Sequence>(_ entries: S) -> [ToolDecks] where S.Element == DeckManifestEntry {
    let groups = Dictionary(grouping: entries, by: \.tool)
    return groups.keys.sorted().map { tool in
        ToolDecks(tool: tool, variants: groups[tool]!.sorted { $0.variant < $1.variant })
    }
}

/// The variant of a tool that matches a flavor, else its first variant.
public func variantForFlavor(_ variants: [String], _ flavor: DeckFlavor) -> String? {
    let preferred = flavor == .bsd ? ["bsd", "macos"] : ["gnu", "linux"]
    return preferred.first(where: variants.contains) ?? variants.first
}

private func isGnu(_ v: String) -> Bool { v == "gnu" || v == "linux" }
private func isBsd(_ v: String) -> Bool { v == "bsd" || v == "macos" }

/// The flavor for tools: the user's pick, else the one most installed decks
/// use, else the platform's.
public func resolveFlavor<S: Sequence>(_ chosen: DeckFlavor?, _ installedVariants: S, _ platform: DeckFlavor) -> DeckFlavor
where S.Element == String {
    if let chosen { return chosen }
    let variants = Array(installedVariants)
    let gnu = variants.filter(isGnu).count, bsd = variants.filter(isBsd).count
    if gnu != bsd { return gnu > bsd ? .gnu : .bsd }
    return platform
}

/// BSD on Apple platforms, GNU elsewhere.
public var platformFlavor: DeckFlavor {
    #if os(macOS) || os(iOS)
    .bsd
    #else
    .gnu
    #endif
}

public func isUpdateAvailable(_ installedVersion: Int, _ entry: DeckManifestEntry) -> Bool {
    entry.deckVersion > installedVersion
}

public struct DeckChanges: Hashable, Sendable {
    public var added: [Option]
    public var removed: [Option]
}

/// Visible options added and removed between two versions of a deck.
public func diffDecks(_ before: Deck, _ after: Deck) -> DeckChanges {
    let old = Set(before.options.filter { !$0.hidden }.map(\.id))
    let next = Set(after.options.filter { !$0.hidden }.map(\.id))
    return DeckChanges(
        added: after.options.filter { !$0.hidden && !old.contains($0.id) },
        removed: before.options.filter { !$0.hidden && !next.contains($0.id) }
    )
}

/// "2 options added, 1 removed".
public func describeChanges(_ changes: DeckChanges) -> String {
    var parts: [String] = []
    let a = changes.added.count, r = changes.removed.count
    if a > 0 { parts.append("\(a) option\(a == 1 ? "" : "s") added") }
    if r > 0 { parts.append(a > 0 ? "\(r) removed" : "\(r) option\(r == 1 ? "" : "s") removed") }
    return parts.isEmpty ? "No options added or removed" : parts.joined(separator: ", ")
}

public enum OptionStatus: String, Sendable { case new, learning, review, suspended }

/// Learning status per option, from its cards' states.
public func optionStatuses(_ deck: Deck, _ states: [CardState], flagPairs: Bool = false) -> [String: OptionStatus] {
    var byCard: [String: CardState] = [:]
    for s in states { byCard[s.cardId] = s }
    let cardsByOption = Dictionary(grouping: deriveCards(deck, flagPairs: flagPairs), by: \.optionId)
    var result: [String: OptionStatus] = [:]
    for option in deck.options {
        let cards = cardsByOption[option.id] ?? []
        let cardStates = cards.compactMap { byCard[$0.id] }
        var status = OptionStatus.new
        if !cards.isEmpty && cardStates.count == cards.count && cardStates.allSatisfy(\.suspended) {
            status = .suspended
        } else if cardStates.contains(where: { $0.fsrs.phase == .learning || $0.fsrs.phase == .relearning }) {
            status = .learning
        } else if cardStates.contains(where: { $0.fsrs.phase == .review }) {
            status = .review
        }
        result[option.id] = status
    }
    return result
}

/// Flags match by prefix and sort first; everything else by substring.
public func searchOptions(_ options: [Option], _ query: String) -> [Option] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty { return options }
    var flagHits: [Option] = [], textHits: [Option] = []
    for option in options {
        if option.flags.contains(where: { $0.lowercased().hasPrefix(q) }) {
            flagHits.append(option)
            continue
        }
        let haystack = ([option.summary, option.argument?.name ?? "", option.subcommand ?? ""] + option.tags + option.flags)
            .joined(separator: " ").lowercased()
        if haystack.contains(q) { textHits.append(option) }
    }
    return flagHits + textHits
}

private let flavorLabels = ["gnu": "GNU / Linux", "bsd": "BSD / macOS"]

/// Variant names are implementation families; say where people meet them.
public func flavorLabel(_ variant: String) -> String { flavorLabels[variant] ?? variant }
