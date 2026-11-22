// Search and browse one deck's options, ported from `deck_browse_screen.dart`.

import SwiftUI
import FlashcardsCore

struct DeckBrowserView: View {
    let model: AppModel
    let deckId: String
    @State var query = ""
    @State var tier: Tier?

    var body: some View {
        if let stored = model.decks.first(where: { $0.id == deckId }) {
            list(stored)
                .navigationTitle("\(stored.deck.tool) Options")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }

    func list(_ stored: StoredDeck) -> some View {
        let visible = stored.deck.options.filter { !$0.hidden }
        let tiers = Tier.allCases.filter { t in visible.contains { $0.tier == t } }
        let results = searchOptions(visible.filter { tier == nil || $0.tier == tier }, query)
        let statuses = statusesFor(stored)
        return List {
            if tiers.count > 1 {
                Section {
                    Picker("Tier", selection: $tier) {
                        Text("All").tag(Tier?.none)
                        ForEach(tiers, id: \.self) { t in
                            Text(tierLabels[t] ?? t.rawValue).tag(Tier?.some(t))
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            Section {
                ForEach(results) { option in
                    NavigationLink(value: DeckRoute.option(deckId, option.id)) {
                        OptionRow(option: option, status: statuses[option.id])
                    }
                }
            } footer: {
                Text(results.count == visible.count
                    ? "\(visible.count) options"
                    : "\(results.count) of \(visible.count) options")
            }
        }
        .searchable(text: $query, prompt: Text("Flags or descriptions"))
    }

    func statusesFor(_ stored: StoredDeck) -> [String: OptionStatus] {
        _ = model.revision
        let states = model.repository?.cardStates(forDeck: stored.id) ?? []
        return optionStatuses(stored.deck, states, flagPairs: model.settings.flagPairs)
    }
}

let optionStatusLabels: [OptionStatus: String] = [
    .new: "New", .learning: "Learning", .review: "Learned", .suspended: "Suspended",
]

struct OptionRow: View {
    let option: Option
    let status: OptionStatus?
    @Environment(\.frost) var frost

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                FlagsLine(option: option)
                Spacer()
                if let status, status != .new {
                    Text(optionStatusLabels[status] ?? "")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(status == .review ? frost.tint : .secondary)
                }
            }
            inlineMarkdown(option.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

/// An option's flags and argument: `-i --ignore-case PATTERN`.
struct FlagsLine: View {
    let option: Option
    var large = false
    @Environment(\.frost) var frost

    var body: some View {
        let flags = answerFlags(option)
        var runs = [TextRun(flags.first ?? "", color: frost.tint, bold: true)]
        for alias in flags.dropFirst() { runs.append(TextRun("  " + alias, color: .secondary)) }
        if let arg = option.argument {
            runs.append(TextRun("  " + (arg.optional ? "[\(arg.name)]" : arg.name), color: frost.arg, italic: true))
        }
        return styledText(runs)
            .font(.mono(large ? .title3 : .body))
            .accessibilityLabel(Text(flags.joined(separator: ", ")))
    }
}

/// One option: its description, examples, and the state of each card.
struct OptionDetailView: View {
    let model: AppModel
    let deckId: String
    let optionId: String

    var body: some View {
        if let stored = model.decks.first(where: { $0.id == deckId }),
           let option = stored.deck.options.first(where: { $0.id == optionId }) {
            content(stored, option)
                .navigationTitle(answerFlags(option).first ?? option.id)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }

    func content(_ stored: StoredDeck, _ option: Option) -> some View {
        let cards = deriveCards(stored.deck, flagPairs: model.settings.flagPairs).filter { $0.optionId == option.id }
        _ = model.revision
        var stateById: [String: CardState] = [:]
        for state in model.repository?.cardStates(forDeck: deckId) ?? [] where state.optionId == option.id {
            stateById[state.cardId] = state
        }
        let now = model.now
        return List {
            Section {
                VStack(alignment: .leading, spacing: Space.s2) {
                    FlagsLine(option: option, large: true)
                    inlineMarkdown(option.summary)
                    HStack(spacing: Space.s2) {
                        Text(tierLabels[option.tier] ?? "")
                        if let sub = option.subcommand { Text("· \(stored.deck.tool) \(sub)") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, Space.s1)
            }
            if !option.description.isEmpty && option.description != option.summary {
                Section("Description") {
                    inlineMarkdown(option.description)
                        .font(.subheadline)
                        #if !os(Android)
                        .textSelection(.enabled)
                        #endif
                }
            }
            if !option.examples.isEmpty {
                Section("Examples") {
                    ForEach(option.examples, id: \.command) { example in
                        VStack(alignment: .leading, spacing: Space.s1) {
                            CommandLineView(commandParts(example.command))
                            if let description = example.description {
                                inlineMarkdown(description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Cards") {
                ForEach(cards) { card in
                    let state = stateById[card.id]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cardTypeLabels[card.type] ?? card.type.rawValue)
                            Text(cardStatus(state, now: now))
                                .font(.subheadline)
                                .foregroundStyle(state?.leech == true ? .red : .secondary)
                        }
                        Spacer()
                        if state?.suspended == true {
                            Button("Unsuspend") { model.unsuspend([card.id]) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
}

/// "New", "Learning · due in 5 minutes", "Due tomorrow at 9:00 AM", "Suspended".
func cardStatus(_ state: CardState?, now: Millis) -> String {
    guard let state else { return "New" }
    var parts: [String] = []
    if state.leech { parts.append("Leech") }
    if state.suspended {
        parts.append("Suspended")
    } else if let buried = state.buriedUntil, buried > now {
        parts.append("Skipped until \(formatNextDue(buried, now: now))")
    } else {
        switch state.fsrs.phase {
        case .new: parts.append("New")
        case .learning, .relearning:
            parts.append(state.fsrs.due <= now ? "Learning · due now" : "Learning · due \(formatNextDue(state.fsrs.due, now: now))")
        case .review:
            parts.append(state.fsrs.due <= now ? "Due now" : "Due \(formatNextDue(state.fsrs.due, now: now))")
        }
    }
    return parts.joined(separator: " · ")
}
