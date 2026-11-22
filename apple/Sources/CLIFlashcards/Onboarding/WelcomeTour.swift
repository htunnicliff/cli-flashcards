// The three-step welcome tour, ported from `app/lib/app/onboarding/tour.dart`.
// It opens on first launch and can be replayed from Settings. A sheet on
// iPhone and Android; a centred sheet on iPad and Mac.

import SwiftUI
import FlashcardsCore

struct WelcomeTour: View {
    let model: AppModel
    @State var step = 0
    @Environment(\.frost) var frost
    @Environment(\.reducedMotion) var reducedMotion

    static let count = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("Step \(step + 1) of \(Self.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    page
                        .id(step)
                        .transition(reducedMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(Space.s6)
                .frame(maxWidth: .infinity)
            }
            .animation(reducedMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.25), value: step)
                HStack(spacing: Space.s3) {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button {
                        if step < Self.count - 1 { step += 1 } else { model.finishTour() }
                    } label: {
                        Text(nextLabel).font(.headline).padding(.horizontal, Space.s2)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(Space.s4)
                .frame(maxWidth: 560)
            }
            .toolbar {
                if step < Self.count - 1 {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") { model.finishTour() }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 440, idealHeight: 480)
        #endif
    }

    var nextLabel: String {
        if step < Self.count - 1 { return "Next" }
        return model.tourReplay ? "Done" : "Start Reviewing"
    }

    @ViewBuilder var page: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Welcome to").font(.largeTitle.weight(.bold))
                    Wordmark(font: .system(.largeTitle, design: .monospaced))
                }
                Text("Learn the flags of the command-line tools you use, one flashcard at a time. Each card comes back just before you’d forget it, so a few minutes a day is enough.")
                Text("Each deck covers one tool, such as `grep` or `git`, and starts with its most useful flags. Every deck comes with the app, so there’s nothing to set up.")
            }
        case 1:
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Review Your Cards").font(.largeTitle.weight(.bold))
                Text("Each card asks about a flag. Recall the answer, then choose **Show Answer** and grade yourself honestly. Your grade decides when the card comes back.")
                HStack(spacing: Space.s2) {
                    GradeChip(label: "Again", color: frost.again)
                    GradeChip(label: "Hard", color: .secondary)
                    GradeChip(label: "Good", color: frost.tint)
                    GradeChip(label: "Easy", color: .secondary)
                }
                Text(inputHint).foregroundStyle(.secondary)
            }
        default:
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Works Offline").font(.largeTitle.weight(.bold))
                Text("Every deck is built into the app and updates with it, so everything works without a connection.")
                Text("Your progress stays on this device, so export a backup from **Settings** now and then.")
                Text("Only care about some tools? Pause the rest in **Decks**, where you can also turn on **Type Answers**.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    var inputHint: String {
        #if os(macOS)
        "On a keyboard, Space shows the answer and 1–4 grade it."
        #else
        "Swipe a revealed card left for Again or right for Good, or tap a grade. On a keyboard, Space shows the answer and 1–4 grade it."
        #endif
    }
}

struct GradeChip: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s1 + 2)
            .background(Capsule().stroke(Color.secondary.opacity(0.35)))
    }
}
