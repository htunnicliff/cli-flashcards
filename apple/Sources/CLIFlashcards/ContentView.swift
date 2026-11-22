import SwiftUI
import FlashcardsCore

/// A placeholder until the real screens land (#79 onward): shows that storage
/// opened and the bundled decks installed.
struct ContentView: View {
    @State var model = AppModel()

    var body: some View {
        NavigationStack {
            List {
                if let error = model.loadError {
                    Text("Couldn’t open saved progress: \(error)")
                }
                if let queue = model.queue {
                    Section("Today") {
                        Text("\(queue.items.count) cards to study")
                        Text("\(queue.today.newLeft) new cards left today")
                    }
                }
                Section("Decks") {
                    ForEach(model.decks) { stored in
                        HStack {
                            Text(stored.deck.tool)
                            Spacer()
                            Text(flavorLabel(stored.deck.variant))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("CLI Flashcards")
        }
        .task { model.start() }
    }
}
