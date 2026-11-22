// The study session, ported from `app/lib/app/review/review_screen.dart`, in
// a native layout: the card scrolls, and the answer and grade controls stay
// pinned at the bottom so they never fall off a small phone screen.

import SwiftUI
import FlashcardsCore

struct StudyView: View {
    @State var session: ReviewSession
    @Environment(\.reducedMotion) var reducedMotion
    @Environment(\.frost) var frost
    @State var drag: CGFloat = 0
    @FocusState var typedFocused: Bool
    @State var typed = ""

    init(model: AppModel) {
        _session = State(initialValue: ReviewSession(model: model))
    }

    var body: some View {
        Group {
            if let item = session.current {
                cardPage(item)
            } else {
                DoneView(session: session)
            }
        }
        .navigationTitle(session.done ? "Review" : "\(session.items.count) left")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar }
        .background(groupedBackground.ignoresSafeArea())
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                session.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            #if !os(Android)
            .keyboardShortcut("z", modifiers: .command)
            #endif
            .disabled(!session.canUndo)

            if let item = session.current {
                Menu {
                    Button {
                        session.setAside(.bury)
                    } label: {
                        Label("Skip Until Tomorrow", systemImage: "moon")
                    }
                    Button {
                        session.setAside(.suspend)
                    } label: {
                        Label("Suspend Card", systemImage: "pause.circle")
                    }
                    Button {
                        session.setAside(.suspend, wholeOption: true)
                    } label: {
                        Label("Suspend All \(frontFlag(item.card)) Cards", systemImage: "pause.circle.fill")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    func cardPage(_ item: QueueItem) -> some View {
        cardLayout(item)
            .animation(reducedMotion ? nil : .easeOut(duration: 0.25), value: session.revealed)
            .animation(reducedMotion ? nil : .easeOut(duration: 0.25), value: item.card.id)
    }

    @ViewBuilder func cardLayout(_ item: QueueItem) -> some View {
        #if os(Android)
        VStack(spacing: 0) {
            cardScroll(item)
            controlBar(item)
        }
        #else
        cardScroll(item).safeAreaInset(edge: .bottom) { controlBar(item) }
        #endif
    }

    func controlBar(_ item: QueueItem) -> some View {
        controls(item)
            .frame(maxWidth: contentWidth)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity)
            .background(barBackground.ignoresSafeArea(edges: .bottom))
    }

    func cardScroll(_ item: QueueItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                ProgressCounts(session: session)
                ReviewCardView(
                    card: item.card, option: session.option, command: session.command,
                    revealed: session.revealed, flagPairs: model.settings.flagPairs
                )
                .offset(x: session.revealed ? drag : 0)
                .rotationEffect(.degrees(session.revealed && !reducedMotion ? Double(drag) / 40 : 0))
                .gesture(swipe)
                .id(item.card.id)
                .transition(reducedMotion ? .opacity : .asymmetric(
                    insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)
                ))
                if let notice = session.notice {
                    NoticeBar(notice: notice, onUndo: { session.undo() }, onDismiss: { session.dismissNotice() })
                }
                if let error = session.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: contentWidth)
            .padding(Space.s4)
            .frame(maxWidth: .infinity)
        }
    }

    var model: AppModel { session.model }

    @ViewBuilder func controls(_ item: QueueItem) -> some View {
        VStack(spacing: Space.s3) {
            if session.typing {
                TypedAnswerField(
                    command: session.command, text: $typed, result: session.answer,
                    focused: $typedFocused,
                    onSubmit: { session.submit(typed) }
                )
            }
            if session.revealed {
                GradeButtons(session: session)
            } else if session.typing {
                Button {
                    session.submit(typed)
                } label: {
                    Text("Check").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                #if !os(Android)
                .controlSize(.large)
                #endif
            } else {
                Button {
                    session.reveal()
                } label: {
                    Text("Show Answer").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                #if !os(Android)
                .controlSize(.large)
                #endif
                #if !os(Android)
                .keyboardShortcut(.space, modifiers: [])
                #endif
            }
        }
        .onChange(of: item.card.id) { _, _ in
            typed = ""
            typedFocused = session.typing
        }
        .onAppear { typedFocused = session.typing }
    }

    /// A revealed card swipes right for Good and left for Again.
    var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard session.revealed else { return }
                drag = value.translation.width
            }
            .onEnded { value in
                guard session.revealed else { return }
                let width = value.translation.width
                drag = 0
                if width > swipeThreshold {
                    session.grade(.good)
                } else if width < -swipeThreshold {
                    session.grade(.again)
                }
            }
    }
}

/// Swipes past this many points grade the card.
let swipeThreshold: CGFloat = 96

/// New, learning and due counts above the card.
struct ProgressCounts: View {
    let session: ReviewSession

    var body: some View {
        let c = session.counts
        HStack(spacing: Space.s4) {
            count("New", c.new, .blue)
            count("Learning", c.learning, .orange)
            count("Due", c.review, .green)
            Spacer()
        }
        .font(.subheadline)
        #if !os(Android)
        .accessibilityElement(children: .combine)
        #endif
    }

    func count(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: Space.s1) {
            Text("\(value)").fontWeight(.semibold).foregroundStyle(color).monospacedDigit()
            Text(label).foregroundStyle(.secondary)
        }
    }
}

/// Again, Hard, Good and Easy with their next intervals. 1 to 4 grade from
/// a keyboard.
struct GradeButtons: View {
    let session: ReviewSession

    var body: some View {
        let intervals = session.intervals
        let suggested = session.suggestedRating
        HStack(spacing: Space.s2) {
            ForEach(Rating.allCases, id: \.self) { rating in
                Button {
                    session.grade(rating)
                } label: {
                    VStack(spacing: 2) {
                        Text(ratingLabels[rating] ?? "").font(.subheadline.weight(.semibold))
                        Text(intervals[rating] ?? "").font(.caption).monospacedDigit().opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.bordered)
                #if !os(Android)
                .controlSize(.large)
                #endif
                .tint(rating == .again ? .red : nil)
                .overlay {
                    if rating == suggested {
                        RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                #if !os(Android)
                .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue)")), modifiers: [])
                #endif
                .accessibilityLabel(Text("\(ratingLabels[rating] ?? ""), next review in \(intervals[rating] ?? "")"))
            }
        }
    }
}

/// A short message with Undo, shown after a skip, suspend or leech.
struct NoticeBar: View {
    let notice: ReviewNotice
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Text(notice.message).font(.subheadline)
            Spacer()
            if notice.undoable {
                Button("Undo", action: onUndo).font(.subheadline.weight(.semibold))
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
    }
}

/// Shown when the queue is empty: done for today, or no decks.
struct DoneView: View {
    let session: ReviewSession

    var body: some View {
        if !session.hasDecks {
            EmptyState(
                title: "No Decks Yet",
                message: "Turn on a deck in Decks to start learning.",
                systemImage: "square.stack.3d.up"
            )
        } else {
            let next = session.nextDue.map { formatNextDue($0, now: session.model.now) }
            EmptyState(
                title: "All Done for Today",
                message: next.map { "Your next review is \($0)." }
                    ?? "Nothing else is scheduled. Turn on more decks in Decks for more to learn.",
                systemImage: "checkmark.circle"
            )
        }
    }
}

/// The bar behind the pinned controls: the system bar material where there is
/// one, otherwise the grouped background.
var barBackground: some View {
    #if os(Android)
    groupedBackground
    #else
    Rectangle().fill(.bar)
    #endif
}
