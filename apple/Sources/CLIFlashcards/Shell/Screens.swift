// First versions of the four sections. Review (#80), Decks (#81), Stats (#82)
// and Settings (#83) replace these with the full screens.

import SwiftUI
import FlashcardsCore

struct ReviewScreen: View {
    let model: AppModel
    @Environment(\.frost) private var frost

    var body: some View {
        PageBody {
            Wordmark(font: .mono(.largeTitle))
            if let error = model.loadError {
                Text("Couldn’t open saved progress: \(error)")
                    .foregroundStyle(frost.again)
                    .padding(.top, Space.s4)
            }
            if let queue = model.queue {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("\(queue.items.count) cards to study")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(frost.text)
                    Text("\(queue.today.newLeft) new cards left today")
                        .foregroundStyle(frost.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass()
                .padding(.top, Space.s6)
            }
        }
    }
}

struct DecksScreen: View {
    let model: AppModel
    @Environment(\.frost) private var frost

    var body: some View {
        PageBody {
            if let notice = model.notice {
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(frost.muted)
            }
            VStack(spacing: 0) {
                ForEach(model.decks) { stored in
                    HStack {
                        Text(stored.deck.tool)
                            .font(.mono(.body).weight(.semibold))
                            .foregroundStyle(frost.text)
                        Spacer()
                        FrostChip(flavorLabel(stored.deck.variant))
                    }
                    .padding(.vertical, Space.s3)
                }
            }
            .glass(padding: Space.s4)
            .padding(.top, Space.s4)
        }
    }
}

struct StatsScreen: View {
    let model: AppModel
    @Environment(\.frost) private var frost

    var body: some View {
        PageBody {
            Text("\(model.repository?.reviewCount() ?? 0) reviews so far")
                .foregroundStyle(frost.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass()
        }
    }
}

struct SettingsScreen: View {
    let model: AppModel
    @Environment(\.frost) private var frost

    var body: some View {
        let theme = Binding(get: { model.settings.theme }, set: { v in model.updateSettings { $0.theme = v } })
        let motion = Binding(get: { model.settings.motion }, set: { v in model.updateSettings { $0.motion = v } })
        let solid = Binding(
            get: { model.settings.reduceTransparency },
            set: { v in model.updateSettings { $0.reduceTransparency = v } }
        )
        PageBody {
            PageSection(title: "Appearance") {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("Theme").foregroundStyle(frost.text)
                    Segmented(values: AppTheme.allCases, selected: theme) { t in
                        switch t {
                        case .system: "System"
                        case .light: "Light"
                        case .dark: "Dark"
                        }
                    }
                    Text("Motion").foregroundStyle(frost.text)
                    Segmented(values: MotionPreference.allCases, selected: motion) { m in
                        switch m {
                        case .system: "System"
                        case .reduce: "Reduce"
                        case .full: "Full"
                        }
                    }
                    CheckRow(
                        label: "Reduce transparency", isOn: solid,
                        hint: "Solid surfaces instead of frosted glass."
                    )
                }
                .glass()
            }
            if let error = model.saveError {
                Text(error)
                    .foregroundStyle(frost.again)
                    .padding(.top, Space.s4)
            }
        }
    }
}
