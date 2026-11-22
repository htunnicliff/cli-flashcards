// The deck library, ported from `app/lib/app/decks/decks_screen.dart` in a
// native list. Every deck is bundled with the app, so there is nothing to
// download: the library lists them and keeps each deck's settings.

import SwiftUI
import FlashcardsCore

struct DecksScreen: View {
    let model: AppModel

    var body: some View {
        List {
            if !flavoredTools.isEmpty {
                Section {
                    Picker("Flavor", selection: flavorBinding) {
                        ForEach(DeckFlavor.allCases, id: \.self) { flavor in
                            Text(flavorLabel(flavor.rawValue)).tag(flavor)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Flavor")
                } footer: {
                    Text("For \(listOf(flavoredTools)), whose flags differ.")
                }
            }
            if !studying.isEmpty {
                Section {
                    ForEach(studying) { stored in deckLink(stored) }
                } header: {
                    Text("Studying")
                } footer: {
                    if paused.isEmpty { Text(footer) }
                }
            }
            if !paused.isEmpty {
                Section {
                    ForEach(paused) { stored in deckLink(stored) }
                } header: {
                    Text("Not Studying")
                } footer: {
                    Text(footer)
                }
            }
        }
        .navigationDestination(for: DeckRoute.self) { route in
            switch route {
            case .deck(let id): DeckDetailView(model: model, deckId: id)
            case .browse(let id): DeckBrowserView(model: model, deckId: id)
            case .option(let id, let optionId): OptionDetailView(model: model, deckId: id, optionId: optionId)
            }
        }
    }

    func deckLink(_ stored: StoredDeck) -> some View {
        NavigationLink(value: DeckRoute.deck(stored.id)) {
            DeckRow(stored: stored, counts: counts[stored.id] ?? DeckCounts())
        }
        .swipeActions(edge: .trailing) {
            Button(stored.paused ? "Study" : "Pause") {
                model.setDeckPrefs(stored.id, paused: !stored.paused)
            }
            .tint(stored.paused ? Color.green : Color.orange)
        }
        .contextMenu {
            Button(stored.paused ? "Study This Deck" : "Pause This Deck") {
                model.setDeckPrefs(stored.id, paused: !stored.paused)
            }
        }
    }

    var studying: [StoredDeck] { model.decks.filter { !$0.paused }.sorted { $0.deck.tool < $1.deck.tool } }
    var paused: [StoredDeck] { model.decks.filter(\.paused).sorted { $0.deck.tool < $1.deck.tool } }

    var footer: String {
        model.notice ?? "Swipe a deck to start or pause it. Decks come with the app and work offline."
    }

    /// Tools with both a GNU and a BSD deck.
    var flavoredTools: [String] {
        groupByTool(model.manifest?.decks ?? []).filter { $0.variants.count > 1 }.map(\.tool)
    }

    var flavorBinding: Binding<DeckFlavor> {
        Binding(get: { model.deckFlavor }, set: { model.setDeckFlavor($0) })
    }

    var counts: [String: DeckCounts] {
        var result: [String: DeckCounts] = [:]
        for item in model.queue?.items ?? [] {
            var c = result[item.card.deckId] ?? DeckCounts()
            if item.kind == .new { c.new += 1 } else { c.due += 1 }
            result[item.card.deckId] = c
        }
        return result
    }
}

/// Where the Decks tab can go.
enum DeckRoute: Hashable {
    case deck(String)
    case browse(String)
    case option(String, String)
}

struct DeckCounts {
    var new = 0
    var due = 0
}

struct DeckRow: View {
    let stored: StoredDeck
    let counts: DeckCounts

    var body: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stored.deck.tool)
                    .font(.mono(.body).weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !stored.paused {
                if counts.due > 0 { CountBadge(value: counts.due, color: .green, label: "due") }
                if counts.new > 0 { CountBadge(value: counts.new, color: .blue, label: "new") }
            }
        }
        .padding(.vertical, 2)
    }

    var subtitle: String {
        var parts = ["\(visibleOptions(stored)) options"]
        if stored.deck.variant != "default" { parts.insert(flavorLabel(stored.deck.variant), at: 0) }
        if stored.paused { parts.append("Paused") }
        return parts.joined(separator: " · ")
    }
}

/// A small coloured count, like the ones on a review row.
struct CountBadge: View {
    let value: Int
    let color: Color
    let label: String

    var body: some View {
        Text("\(value)")
            .font(.subheadline.weight(.semibold))
            .tabularDigits()
            .foregroundStyle(color)
            .accessibilityLabel(Text("\(value) \(label)"))
    }
}

func visibleOptions(_ stored: StoredDeck) -> Int {
    stored.deck.options.filter { !$0.hidden }.count
}

/// "255 options, starting with the 19 most used".
func sizeSummary(_ deck: Deck) -> String {
    let visible = deck.options.filter { !$0.hidden }
    let core = visible.filter { $0.tier == .core }.count
    if core == 0 || core >= visible.count { return "\(visible.count) options" }
    return "\(visible.count) options, starting with the \(core) most used"
}

let tierLabels: [Tier: String] = [.core: "Core", .common: "Common", .obscure: "Rarely Used"]
