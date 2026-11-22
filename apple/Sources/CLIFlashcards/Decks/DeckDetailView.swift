// One deck: its settings, progress, set-aside cards and license. Ports the
// deck tile of `decks_screen.dart` and the top of `deck_browse_screen.dart`.

import SwiftUI
import FlashcardsCore

struct DeckDetailView: View {
    let model: AppModel
    let deckId: String
    @State var confirmingReset = false

    var body: some View {
        if let stored = model.decks.first(where: { $0.id == deckId }) {
            content(stored)
                .navigationTitle(stored.deck.tool)
        } else {
            EmptyState(title: "Deck Not Found", message: "This deck isn’t installed.", systemImage: "questionmark.folder")
        }
    }

    func content(_ stored: StoredDeck) -> some View {
        let progress = DeckProgress(model: model, stored: stored)
        return List {
            Section {
                Toggle("Study This Deck", isOn: binding(stored.paused == false) { model.setDeckPrefs(deckId, paused: !$0) })
                Toggle("Include Rarely Used Flags", isOn: binding(stored.includeObscure) { model.setDeckPrefs(deckId, includeObscure: $0) })
                Toggle("Type Answers", isOn: binding(stored.typeAnswers) { model.setDeckPrefs(deckId, typeAnswers: $0) })
            } header: {
                Text(sizeSummary(stored.deck))
            } footer: {
                Text("Typed answers ask you to type the flag instead of revealing it.")
            }

            Section("Options") {
                NavigationLink(value: DeckRoute.browse(deckId)) {
                    Label("Browse \(visibleOptions(stored)) Options", systemImage: "magnifyingglass")
                }
                ForEach(Tier.allCases, id: \.self) { tier in
                    if let n = progress.tiers[tier], n > 0 {
                        ValueRow(title: tierLabels[tier] ?? tier.rawValue, value: "\(n)")
                    }
                }
            }

            Section("Progress") {
                ValueRow(title: "New", value: "\(progress.statuses[.new] ?? 0)")
                ValueRow(title: "Learning", value: "\(progress.statuses[.learning] ?? 0)")
                ValueRow(title: "Learned", value: "\(progress.statuses[.review] ?? 0)")
                if let suspended = progress.statuses[.suspended], suspended > 0 {
                    ValueRow(title: "Suspended", value: "\(suspended)")
                }
                Button("Reset Progress…", role: .destructive) { confirmingReset = true }
                    .disabled(progress.states.isEmpty)
            }

            if !progress.leeches.isEmpty {
                Section {
                    ForEach(progress.leeches, id: \.state.cardId) { item in
                        SetAsideRow(model: model, item: item, detail: "Forgotten \(item.state.fsrs.lapses) times")
                    }
                } header: {
                    Text("Leeches")
                } footer: {
                    Text("These cards keep slipping away. Read the full description, then picture when you’d use the flag.")
                }
            }

            if !progress.suspended.isEmpty {
                Section {
                    ForEach(progress.suspended, id: \.state.cardId) { item in
                        SetAsideRow(model: model, item: item, detail: cardTypeLabels[item.card.type] ?? "")
                    }
                    if progress.suspended.count > 1 {
                        Button("Unsuspend All") { model.unsuspend(progress.suspended.map(\.state.cardId)) }
                    }
                } header: {
                    Text("Suspended")
                }
            }

            Section {
                ValueRow(title: "Tool Version", value: stored.deck.toolVersion)
                if stored.deck.variant != "default" {
                    ValueRow(title: "Flavor", value: flavorLabel(stored.deck.variant))
                }
                ValueRow(title: "Deck Version", value: "\(stored.deck.deckVersion)")
                ValueRow(title: "License", value: stored.deck.license)
            } header: {
                Text("About")
            } footer: {
                Text(stored.deck.attribution)
            }
        }
        .confirmationDialog(Text("Reset your progress on \(stored.deck.tool)?"), isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Progress", role: .destructive) { model.resetProgress(deckId) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its cards start over as new. This can’t be undone.")
        }
    }

    func binding(_ value: Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { value }, set: set)
    }
}

/// A card's state alongside the card and option it belongs to.
struct CardProgress {
    var state: CardState
    var option: Option
    var card: Card
}

/// What a deck's cards look like in storage, read once per change.
struct DeckProgress {
    var states: [CardState]
    var statuses: [OptionStatus: Int]
    var tiers: [Tier: Int]
    var leeches: [CardProgress]
    var suspended: [CardProgress]

    @MainActor init(model: AppModel, stored: StoredDeck) {
        _ = model.revision
        let deck = stored.deck
        states = model.repository?.cardStates(forDeck: stored.id) ?? []
        var statuses: [OptionStatus: Int] = [:]
        let visible = deck.options.filter { !$0.hidden }
        let byOption = optionStatuses(deck, states, flagPairs: model.settings.flagPairs)
        for option in visible { statuses[byOption[option.id] ?? .new, default: 0] += 1 }
        self.statuses = statuses
        var tiers: [Tier: Int] = [:]
        for option in visible { tiers[option.tier, default: 0] += 1 }
        self.tiers = tiers
        let options = Dictionary(uniqueKeysWithValues: deck.options.map { ($0.id, $0) })
        let cards = Dictionary(uniqueKeysWithValues: deriveCards(deck, flagPairs: true).map { ($0.id, $0) })
        let live = states.compactMap { s -> CardProgress? in
            guard let card = cards[s.cardId], let option = options[s.optionId] else { return nil }
            return CardProgress(state: s, option: option, card: card)
        }
        leeches = live.filter(\.state.leech)
        suspended = live.filter { $0.state.suspended && !$0.state.leech }
    }
}

let cardTypeLabels: [CardType: String] = [
    .flagToMeaning: "Flag → meaning",
    .meaningToFlag: "Meaning → flag",
    .cloze: "Fill in the blank",
    .shortToLong: "Short → long",
    .longToShort: "Long → short",
]

/// A leech or suspended card, with Unsuspend.
struct SetAsideRow: View {
    let model: AppModel
    let item: CardProgress
    let detail: String
    @Environment(\.frost) var frost

    var body: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(frontFlag(item.card)).font(.mono(.body).weight(.semibold)).foregroundStyle(frost.tint)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if item.state.suspended {
                Button("Unsuspend") { model.unsuspend([item.state.cardId]) }
                    .buttonStyle(.bordered)
            }
        }
    }
}
