// First versions of the four sections, built from standard lists and forms so
// they look native on each platform (and map to Material on Android). Review
// (#80), Decks (#81), Stats (#82) and Settings (#83) fill them out.

import SwiftUI
import FlashcardsCore

struct ReviewScreen: View {
    let model: AppModel

    var body: some View {
        List {
            if let error = model.loadError {
                Section {
                    Text("Couldn’t open saved progress: \(error)")
                        .foregroundStyle(.red)
                }
            }
            if let queue = model.queue {
                Section {
                    ReviewSummary(queue: queue)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: Space.s2, leading: 0, bottom: Space.s2, trailing: 0))
                }
                let today = todayRows(queue)
                if !today.isEmpty {
                    Section("Today") {
                        ForEach(today, id: \.0) { row in
                            ValueRow(title: row.0, value: "\(row.1)")
                        }
                    }
                }
            }
        }
    }

    /// The breakdown under the summary, leaving out what's zero.
    private func todayRows(_ queue: StudyQueue) -> [(String, Int)] {
        let rows = [
            ("Learning", queue.items.filter { $0.kind == .learning }.count),
            ("Reviews due", queue.items.filter { $0.kind == .review }.count),
            ("New", queue.items.filter { $0.kind == .new }.count),
            ("Done today", queue.today.reviewsDone + queue.today.newDone),
        ].filter { $0.1 > 0 }
        // A breakdown with one line only repeats the total.
        return rows.count > 1 ? rows : []
    }
}

/// The count of cards to study and the button that starts a session, set on
/// the list background rather than in a cell.
struct ReviewSummary: View {
    let queue: StudyQueue

    var body: some View {
        let total = queue.items.count
        VStack(spacing: Space.s4) {
            VStack(spacing: Space.s1) {
                Text("\(total)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(total == 1 ? "card to study" : "cards to study")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                // The review session lands in #80.
            } label: {
                Text(total == 0 ? "All caught up" : "Start Review")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s1)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(total == 0)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DecksScreen: View {
    let model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(model.decks) { stored in
                    NavigationLink(value: stored.id) {
                        DeckRow(stored: stored)
                    }
                }
            } footer: {
                Text(model.notice ?? "\(model.decks.count) decks, bundled with the app.")
            }
        }
        .navigationDestination(for: String.self) { id in
            if let stored = model.decks.first(where: { $0.id == id }) {
                // The deck browser lands in #81.
                List {
                    ValueRow(title: "Options", value: "\(visibleOptions(stored))")
                    if stored.deck.variant != "default" {
                        ValueRow(title: "Platform", value: flavorLabel(stored.deck.variant))
                    }
                }
                .navigationTitle(stored.deck.tool)
            }
        }
    }
}

func visibleOptions(_ stored: StoredDeck) -> Int {
    stored.deck.options.filter { !$0.hidden }.count
}

struct DeckRow: View {
    let stored: StoredDeck

    var body: some View {
        HStack {
            Text(stored.deck.tool)
                .font(.mono(.body).weight(.medium))
            if stored.deck.variant != "default" {
                Text(flavorLabel(stored.deck.variant))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(visibleOptions(stored)) options")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct StatsScreen: View {
    let model: AppModel

    var body: some View {
        let reviews = model.repository?.reviewCount() ?? 0
        if reviews == 0 {
            EmptyState(
                title: "No Reviews Yet",
                message: "Your streak, retention and forecast appear here after your first review.",
                systemImage: "chart.bar"
            )
            // The same background as the grouped lists on the other tabs.
            .background(groupedBackground.ignoresSafeArea())
        } else {
            List {
                ValueRow(title: "Reviews", value: "\(reviews)")
            }
        }
    }
}

/// The background grouped lists sit on.
var groupedBackground: Color {
    #if os(iOS)
    Color(uiColor: .systemGroupedBackground)
    #elseif os(macOS)
    Color(nsColor: .windowBackgroundColor)
    #else
    Color.clear
    #endif
}

struct SettingsScreen: View {
    let model: AppModel

    var body: some View {
        let theme = Binding(get: { model.settings.theme }, set: { v in model.updateSettings { $0.theme = v } })
        let motion = Binding(get: { model.settings.motion }, set: { v in model.updateSettings { $0.motion = v } })
        Form {
            Section {
                Picker("Theme", selection: theme) {
                    Text("System").tag(AppTheme.system)
                    Text("Light").tag(AppTheme.light)
                    Text("Dark").tag(AppTheme.dark)
                }
                Picker("Motion", selection: motion) {
                    Text("System").tag(MotionPreference.system)
                    Text("Reduce").tag(MotionPreference.reduce)
                    Text("Full").tag(MotionPreference.full)
                }
            } header: {
                Text("Appearance")
            } footer: {
                if let error = model.saveError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
    }
}

/// A row with a label on the left and a value on the right.
struct ValueRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// A centred placeholder for a screen with nothing to show yet, like
/// `ContentUnavailableView` (which Skip doesn't provide).
struct EmptyState: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s8)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
