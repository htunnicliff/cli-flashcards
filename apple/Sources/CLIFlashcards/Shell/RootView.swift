// The frame around every page, ported from `app/lib/app/shell.dart` and
// `router.dart`: a tab bar on iPhone and Android, a sidebar on iPad and Mac
// (`.sidebarAdaptable`), over the Frost backdrop.

import SwiftUI
import FlashcardsCore

/// Resolves the theme from the settings and the device, then shows the
/// sections.
struct RootView: View {
    @State var model = AppModel.shared
    @Environment(\.colorScheme) var systemScheme
    @Environment(\.accessibilityReduceTransparency) var systemReduceTransparency
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        let settings = model.settings
        let dark = switch settings.theme {
        case .light: false
        case .dark: true
        case .system: systemScheme == .dark
        }
        // Increase Contrast also gets solid surfaces, as on the web.
        let solid = settings.reduceTransparency || systemReduceTransparency || contrast == .increased
        let frost = Frost.resolve(dark: dark, solid: solid)

        Sections(model: model)
            .environment(\.frost, frost)
            .environment(\.reducedMotion, reducedMotion(settings.motion, system: systemReduceMotion))
            .tint(frost.accent)
            .preferredColorScheme(settings.theme == .system ? nil : (dark ? .dark : .light))
            #if os(macOS)
            .frame(minWidth: 640, minHeight: 480)
            #endif
            .task { model.start() }
    }
}

struct Sections: View {
    let model: AppModel

    var body: some View {
        let selection = Binding(get: { model.section }, set: { model.section = $0 })
        TabView(selection: selection) {
            Tab(AppSection.review.title, systemImage: AppSection.review.systemImage, value: AppSection.review) {
                Page(.review) { ReviewScreen(model: model) }
            }
            Tab(AppSection.decks.title, systemImage: AppSection.decks.systemImage, value: AppSection.decks) {
                Page(.decks) { DecksScreen(model: model) }
            }
            Tab(AppSection.stats.title, systemImage: AppSection.stats.systemImage, value: AppSection.stats) {
                Page(.stats) { StatsScreen(model: model) }
            }
            Tab(AppSection.settings.title, systemImage: AppSection.settings.systemImage, value: AppSection.settings) {
                Page(.settings) { SettingsScreen(model: model) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// One section: its own navigation stack over the backdrop.
struct Page<Content: View>: View {
    var section: AppSection
    @ViewBuilder var content: () -> Content

    init(_ section: AppSection, @ViewBuilder content: @escaping () -> Content) {
        self.section = section
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle(section.title)
                .background(FrostBackdrop())
        }
    }
}

/// The `--recall` wordmark, with the dashes in the accent colour.
struct Wordmark: View {
    var font: Font = .mono(.title3)
    @Environment(\.frost) var frost

    var body: some View {
        (Text("--").foregroundColor(frost.accent) + Text("recall").foregroundColor(frost.text))
            .font(font.weight(.bold))
            .accessibilityLabel("--recall")
    }
}

#if os(macOS)
/// Mac menu commands: ⌘1 to ⌘4 go to a section and ⌘, opens Settings.
public struct CLIFlashcardsCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppModel.shared.section = .settings }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu("Go") {
            Button("Review") { AppModel.shared.section = .review }
                .keyboardShortcut("1", modifiers: .command)
            Button("Decks") { AppModel.shared.section = .decks }
                .keyboardShortcut("2", modifiers: .command)
            Button("Stats") { AppModel.shared.section = .stats }
                .keyboardShortcut("3", modifiers: .command)
            Button("Settings") { AppModel.shared.section = .settings }
                .keyboardShortcut("4", modifiers: .command)
        }
    }
}
#endif
