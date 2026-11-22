// Settings, ported from `app/lib/app/settings/settings_screen.dart` and
// `backup_files.dart`. The web-only renderer setting is gone.

import SwiftUI
import FlashcardsCore
#if os(Android)
import SkipKit
#else
import UniformTypeIdentifiers
#endif

struct SettingsScreen: View {
    let model: AppModel
    @State var exporting = false
    @State var importing = false
    @State var exportDocument: BackupDocument?
    @State var shareURL: URL?
    @State var pendingImport: Backup?
    @State var confirmingImport = false
    @State var confirmingReset = false
    @State var backupMessage: String?
    #if os(Android)
    @State var pickedURL: URL?
    @State var pickedName: String?
    @State var pickedType: String?
    #endif

    var body: some View {
        Form {
            appearance
            practice
            scheduling
            if !flavoredTools.isEmpty { decks }
            backup
            Section {
                Button("Replay the Welcome Tour") { model.tourOpen = true }
                Button("Reset All Progress…", role: .destructive) { confirmingReset = true }
            } footer: {
                Text("Resetting starts every card over as new. Your decks and settings stay.")
            }
            about
        }
        .confirmationDialog(Text("Reset all progress?"), isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset All Progress", role: .destructive) { model.resetAllProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every card in every deck starts over as new. This can’t be undone, so export a backup first if you might want it back.")
        }
        .confirmationDialog(Text("Import this backup?"), isPresented: $confirmingImport, titleVisibility: .visible) {
            Button("Merge") { finishImport(.merge) }
            Button("Replace", role: .destructive) { finishImport(.replace) }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text(importSummary)
        }
        #if !os(Android)
        .fileExporter(
            isPresented: $exporting, document: exportDocument, contentType: .json,
            defaultFilename: backupFileName(now: model.now)
        ) { result in
            if case .failure(let error) = result { backupMessage = "Couldn’t save the backup: \(error.localizedDescription)" }
            else { backupMessage = "Backup saved." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): readImport(url)
            case .failure(let error): backupMessage = "Couldn’t open the file: \(error.localizedDescription)"
            }
        }
        #else
        // Android's picker copies the chosen file into the app's cache.
        .withDocumentPicker(
            isPresented: $importing, allowedContentTypes: [.json],
            selectedDocumentURL: $pickedURL, selectedFilename: $pickedName, selectedFileMimeType: $pickedType
        )
        .onChange(of: pickedURL) { _, url in
            guard let url else { return }
            pickedURL = nil
            readImport(url)
        }
        #endif
    }

    // MARK: Sections

    var appearance: some View {
        Section {
            Picker("Theme", selection: setting(\.theme)) {
                Text("System").tag(AppTheme.system)
                Text("Light").tag(AppTheme.light)
                Text("Dark").tag(AppTheme.dark)
            }
            Picker("Animations", selection: setting(\.motion)) {
                Text("Match System").tag(MotionPreference.system)
                Text("Fades Only").tag(MotionPreference.reduce)
                Text("Full").tag(MotionPreference.full)
            }
        } header: {
            Text("Appearance")
        } footer: {
            if let error = model.saveError {
                Text(error).foregroundStyle(.red)
            } else {
                Text("Fades Only keeps cards from sliding and tilting. Match System follows Reduce Motion.")
            }
        }
    }

    var practice: some View {
        Section {
            Toggle("Flag Pair Practice", isOn: setting(\.flagPairs))
        } header: {
            Text("Practice")
        } footer: {
            Text("Adds cards that show one form of a flag, like -i, and ask for the other, like --ignore-case.")
        }
    }

    var scheduling: some View {
        Section {
            Stepper(value: setting(\.newCardsPerDay), in: 0...200, step: 5) {
                ValueRow(title: "New Cards per Day", value: "\(model.settings.newCardsPerDay)")
            }
            Stepper(value: setting(\.maxReviewsPerDay), in: 10...2000, step: 10) {
                ValueRow(title: "Reviews per Day", value: "\(model.settings.maxReviewsPerDay)")
            }
            Picker("Desired Retention", selection: setting(\.desiredRetention)) {
                ForEach([0.8, 0.85, 0.9, 0.93, 0.95, 0.97], id: \.self) { value in
                    Text("\(Int((value * 100).rounded()))%").tag(value)
                }
            }
            Picker("New Day Starts At", selection: setting(\.dayRolloverHour)) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(hourLabel(hour)).tag(hour)
                }
            }
            Stepper(value: setting(\.leechThreshold), in: 2...20) {
                ValueRow(title: "Leech Threshold", value: "\(model.settings.leechThreshold) lapses")
            }
        } header: {
            Text("Scheduling")
        } footer: {
            Text("A card is suspended as a leech after that many lapses. Limits count across all decks. Higher retention means more reviews. A late new-day hour lets late-night study count toward the day before.")
        }
    }

    var decks: some View {
        Section {
            Picker("Flavor", selection: Binding(get: { model.deckFlavor }, set: { model.setDeckFlavor($0) })) {
                ForEach(DeckFlavor.allCases, id: \.self) { flavor in
                    Text(flavorLabel(flavor.rawValue)).tag(flavor)
                }
            }
        } header: {
            Text("Decks")
        } footer: {
            Text("For \(listOf(flavoredTools)), whose flags differ between GNU and BSD.")
        }
    }

    var backup: some View {
        Section {
            #if !os(Android)
            Button("Export Backup…") { startExport() }
            #endif
            Button("Import Backup…") { importing = true }
            #if !os(macOS)
            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Share \(shareURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                }
            } else {
                Button("Prepare a Backup to Share") { prepareShare() }
            }
            #endif
        } header: {
            Text("Backup")
        } footer: {
            Text(backupFooter)
        }
    }

    var about: some View {
        Section {
            ValueRow(title: "Version", value: appVersion)
            NavigationLink("Sources and Licenses") {
                LicensesView(decks: model.decks)
            }
        } header: {
            Text("About")
        } footer: {
            Text("Decks are generated from the tools’ manual pages, with examples adapted from tldr-pages.")
        }
    }

    // MARK: Helpers

    func setting<T>(_ key: WritableKeyPath<FlashcardsCore.Settings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: key] }, set: { value in model.updateSettings { $0[keyPath: key] = value } })
    }

    var flavoredTools: [String] {
        groupByTool(model.manifest?.decks ?? []).filter { $0.variants.count > 1 }.map(\.tool)
    }

    var backupFooter: String {
        if let backupMessage { return backupMessage }
        let last: String
        switch daysSinceBackup(model.settings.lastBackupAt, now: model.now) {
        case nil: last = "You haven’t exported a backup yet."
        case 0: last = "Last backup: today."
        case let days?: last = "Last backup: \(days) day\(days == 1 ? "" : "s") ago."
        }
        return "Your progress lives only on this device. Export a backup to keep it safe or move it to another device. " + last
    }

    var importSummary: String {
        guard let backup = pendingImport else { return "" }
        let s = summarizeBackup(backup)
        let decks = s.decks.isEmpty ? "none" : s.decks.joined(separator: ", ")
        return "Decks: \(decks). Cards: \(s.cards). History: \(s.reviews) reviews.\n\n"
            + "Merge adds reviews this device doesn’t have and keeps the newer state of each card. "
            + "Replace swaps your progress and settings for the backup’s."
    }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        if let build = info?["CFBundleVersion"] as? String, build != version { return "\(version) (\(build))" }
        return version
    }

    func startExport() {
        do {
            let url = try model.exportBackupFile()
            exportDocument = BackupDocument(data: try Data(contentsOf: url))
            exporting = true
        } catch {
            backupMessage = "Couldn’t export: \(error)"
        }
    }

    func prepareShare() {
        do {
            shareURL = try model.exportBackupFile()
        } catch {
            backupMessage = "Couldn’t export: \(error)"
        }
    }

    func readImport(_ url: URL) {
        #if !os(Android)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            pendingImport = try parseBackup(try Data(contentsOf: url))
            confirmingImport = true
        } catch {
            backupMessage = "That file isn’t a backup this app can read: \(error)"
        }
    }

    func finishImport(_ mode: ImportMode) {
        guard let backup = pendingImport else { return }
        pendingImport = nil
        backupMessage = model.importBackup(backup, mode: mode)
    }
}

/// "4 AM", "Midnight", "Noon".
func hourLabel(_ hour: Int) -> String {
    switch hour {
    case 0: "Midnight"
    case 12: "Noon"
    case 1..<12: "\(hour) AM"
    default: "\(hour - 12) PM"
    }
}

/// Every installed deck's source and license, from the deck's own metadata.
struct LicensesView: View {
    let decks: [StoredDeck]

    var body: some View {
        List {
            ForEach(decks.sorted { $0.id < $1.id }) { stored in
                Section {
                    ValueRow(title: "License", value: stored.deck.license)
                    ValueRow(title: "Source", value: "\(stored.deck.source) \(stored.deck.toolVersion)")
                    Text(stored.deck.attribution)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(stored.deck.variant == "default" ? stored.deck.tool : "\(stored.deck.tool) (\(flavorLabel(stored.deck.variant)))")
                }
            }
        }
        .navigationTitle("Sources and Licenses")
    }
}

#if !os(Android)
/// A backup file for `.fileExporter`.
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#else
struct BackupDocument {
    var data: Data
}
#endif
