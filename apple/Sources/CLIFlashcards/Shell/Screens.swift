// First versions of the four sections, built from standard lists and forms so
// they look native on each platform (and map to Material on Android). Review
// (#80), Decks (#81), Stats (#82) and Settings (#83) fill them out.

import SwiftUI
import FlashcardsCore

struct ReviewScreen: View {
    let model: AppModel
    @State var studying = false

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
                    ReviewSummary(queue: queue) { studying = true }
                        .listRowBackground(Color.clear)
                        #if !os(Android)
                        .listRowInsets(EdgeInsets(top: Space.s2, leading: 0, bottom: Space.s2, trailing: 0))
                        #endif
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
        .navigationDestination(isPresented: $studying) {
            StudyView(model: model)
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
    let start: () -> Void

    var body: some View {
        let total = queue.items.count
        VStack(spacing: Space.s4) {
            VStack(spacing: Space.s1) {
                Text("\(total)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    #if !os(Android)
                    .monospacedDigit()
                    #endif
                Text(total == 1 ? "card to study" : "cards to study")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(action: start) {
                Text(total == 0 ? "All caught up" : "Start Review")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s1)
            }
            #if os(macOS)
            .frame(maxWidth: 360)
            #endif
            .buttonStyle(.borderedProminent)
            #if !os(Android)
            .controlSize(.large)
            #endif
            .disabled(total == 0)
        }
        .frame(maxWidth: .infinity)
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
                #if !os(Android)
                .monospacedDigit()
                #endif
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
