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
                    Label("Couldn’t open saved progress: \(error)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            if let queue = model.queue {
                Section {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("\(queue.items.count)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(queue.items.count == 1 ? "card to study" : "cards to study")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Space.s2)
                    Button {
                        // The review session lands in #80.
                    } label: {
                        Text("Start review")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s1)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(queue.items.isEmpty)
                }
                Section("Today") {
                    ValueRow(title: "New cards left", value: "\(queue.today.newLeft)", systemImage: "sparkles")
                }
            }
        }
    }
}

struct DecksScreen: View {
    let model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(model.decks) { stored in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stored.deck.tool)
                            .font(.mono(.body).weight(.semibold))
                        Text(flavorLabel(stored.deck.variant))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                if let notice = model.notice {
                    Text(notice)
                }
            }
        }
    }
}

struct StatsScreen: View {
    let model: AppModel

    var body: some View {
        List {
            Section("All time") {
                ValueRow(
                    title: "Reviews", value: "\(model.repository?.reviewCount() ?? 0)",
                    systemImage: "checkmark.circle"
                )
            }
        }
    }
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
    var systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
