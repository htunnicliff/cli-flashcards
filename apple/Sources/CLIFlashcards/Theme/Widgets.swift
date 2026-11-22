// Shared controls in the Frost style, ported from `app/lib/app/widgets.dart`:
// buttons, keycaps, chips, command lines, segmented choices and page layout.

import SwiftUI
import FlashcardsCore

/// Whether this device has a keyboard worth advertising shortcuts for.
var showsKeyHints: Bool {
    #if os(macOS)
    true
    #else
    false
    #endif
}

enum ButtonVariant { case neutral, primary, again }

/// The Frost button: neutral glass, the blue primary gradient, or the red
/// "Again" tint. `highlighted` rings the suggested choice.
struct FrostButtonStyle: ButtonStyle {
    var variant: ButtonVariant = .neutral
    var block = false
    var highlighted = false
    @Environment(\.frost) var frost
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radii.button, style: .continuous)
        let (fg, border): (Color, Color) = switch variant {
        case .primary: (frost.onPrimary, .clear)
        case .again: (frost.again, frost.againBorder)
        case .neutral: (frost.text, frost.rim)
        }
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2 + 2)
            .frame(maxWidth: block ? .infinity : nil, minHeight: 44)
            .background { background(shape) }
            .overlay {
                shape.stroke(highlighted ? frost.accent : border, lineWidth: highlighted ? 2 : 1)
            }
            .shadow(
                color: variant == .primary ? frost.primaryShadow : frost.shadow.opacity(0.06),
                radius: variant == .primary ? 9 : 4, x: 0, y: variant == .primary ? 6 : 2
            )
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }

    @ViewBuilder private func background(_ shape: RoundedRectangle) -> some View {
        switch variant {
        case .primary:
            shape.fill(LinearGradient(colors: [frost.primaryTop, frost.primaryBottom], startPoint: .top, endPoint: .bottom))
        case .again:
            shape.fill(frost.againTint)
        case .neutral:
            shape.fill(frost.card)
        }
    }
}

extension ButtonStyle where Self == FrostButtonStyle {
    static func frost(_ variant: ButtonVariant = .neutral, block: Bool = false, highlighted: Bool = false) -> FrostButtonStyle {
        FrostButtonStyle(variant: variant, block: block, highlighted: highlighted)
    }
}

/// A keycap, shown only where there is a keyboard.
struct Kbd: View {
    var label: String
    var onPrimary = false
    @Environment(\.frost) var frost

    init(_ label: String, onPrimary: Bool = false) {
        self.label = label
        self.onPrimary = onPrimary
    }

    var body: some View {
        if showsKeyHints {
            Text(label)
                .font(.mono(.caption))
                .foregroundStyle(onPrimary ? frost.onPrimary : frost.muted)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: Radii.kbd)
                        .fill(onPrimary ? Color.white.opacity(0.14) : frost.kbd)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.kbd)
                        .stroke(onPrimary ? Color.clear : frost.border, lineWidth: 1)
                )
                .padding(.leading, Space.s2)
                .accessibilityHidden(true)
        }
    }
}

/// A small rounded label, like a deck's flavor or a card's state.
struct FrostChip: View {
    var label: String
    var mono = false
    var color: Color?
    @Environment(\.frost) var frost

    init(_ label: String, mono: Bool = false, color: Color? = nil) {
        self.label = label
        self.mono = mono
        self.color = color
    }

    var body: some View {
        Text(label)
            .font(mono ? .mono(.caption) : .caption)
            .foregroundStyle(color ?? frost.muted)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 2)
            .background(Capsule().fill(frost.sunken))
    }
}

/// A command with the tool, flags, arguments and a cloze blank styled apart.
struct CommandLineView: View {
    var parts: [CommandPart]
    var large = false
    @Environment(\.frost) var frost

    init(_ parts: [CommandPart], large: Bool = false) {
        self.parts = parts
        self.large = large
    }

    var body: some View {
        styled
            .font(.mono(large ? .title3 : .subheadline))
            .foregroundStyle(frost.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(RoundedRectangle(cornerRadius: Radii.code).fill(frost.sunken))
            .accessibilityLabel(accessibleText)
    }

    private var styled: Text {
        var text = Text("$ ").foregroundColor(frost.muted)
        for (i, part) in parts.enumerated() {
            if i > 0 { text = text + Text(" ") }
            switch part.kind {
            case .tool:
                text = text + Text(part.text)
            case .flag:
                text = text + Text(part.text).foregroundColor(frost.accent).bold()
            case .arg:
                text = text + Text(part.text).foregroundColor(frost.arg).italic()
            case .blank:
                text = text + Text("\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}").underline(color: frost.accent)
                    + Text(part.text)
            }
        }
        return text
    }

    private var accessibleText: String {
        parts.map { $0.kind == .blank ? "blank\($0.text)" : $0.text }.joined(separator: " ")
    }
}

/// A row of mutually exclusive choices, in a sunken pill.
struct Segmented<T: Hashable>: View {
    var values: [T]
    @Binding var selected: T
    var label: (T) -> String
    @Environment(\.frost) var frost

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(values, id: \.self) { value in
                let isSelected = value == selected
                Button {
                    selected = value
                } label: {
                    Text(label(value))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? frost.text : frost.muted)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s2)
                        .background(Capsule().fill(isSelected ? frost.surface : Color.clear))
                        .shadow(color: isSelected ? frost.shadow.opacity(0.08) : .clear, radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(Space.s1)
        .background(Capsule().fill(frost.sunken))
    }
}

/// A labelled switch with an optional hint underneath.
struct CheckRow: View {
    var label: String
    @Binding var isOn: Bool
    var hint: String?
    var strong = false
    @Environment(\.frost) var frost

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(label)
                    .font(strong ? .body.weight(.semibold) : .body)
                    .foregroundStyle(frost.text)
                if let hint {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(frost.muted)
                }
            }
        }
        .tint(frost.accent)
    }
}

/// A page's content column: scrolling, centred, at most `contentWidth` wide.
struct PageBody<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.horizontalSizeClass) var sizeClass

    var body: some View {
        let compact = sizeClass == .compact
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, compact ? Space.s4 : Space.s6)
            .padding(.top, compact ? Space.s4 : Space.s10)
            .padding(.bottom, Space.s12)
            .frame(maxWidth: .infinity)
        }
    }
}

/// A section heading followed by its content.
struct PageSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.frost) var frost

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(frost.text)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Space.s8)
    }
}

/// "a, b and c".
func listOf(_ names: [String]) -> String {
    switch names.count {
    case 0: ""
    case 1: names[0]
    default: names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
}
