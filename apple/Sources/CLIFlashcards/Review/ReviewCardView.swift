// One flashcard, front and back, ported from `app/lib/app/review/review_card.dart`.

import SwiftUI
import FlashcardsCore

struct ReviewCardView: View {
    let card: Card
    let option: Option?
    /// The tool, with its subcommand when the option has one.
    let command: String
    let revealed: Bool
    /// The front shows one form of a flag, never both.
    let flagPairs: Bool
    @Environment(\.frost) var frost
    @State var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(cardPrompts[card.type] ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            front
            if revealed {
                Divider().padding(.vertical, Space.s2)
                back
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .padding(Space.s5)
        .background(
            RoundedRectangle(cornerRadius: Radii.card, style: .continuous)
                .fill(cardBackground)
        )
        #if !os(Android)
        .accessibilityElement(children: .contain)
        #endif
        .accessibilityLabel(Text(cardPrompts[card.type] ?? ""))
    }

    @ViewBuilder var front: some View {
        switch card.type {
        case .flagToMeaning:
            toolLine
            flags([card.flag] + (flagPairs ? [] : Array(card.answers.dropFirst())), front: true)
        case .shortToLong, .longToShort:
            toolLine
            flags([card.shown ?? card.flag], front: true)
        case .meaningToFlag:
            toolLine
            inlineMarkdown(card.summary).font(.title3.weight(.semibold))
        case .cloze:
            CommandLineView(highlight(card.cloze ?? ""), large: true)
            if let description = card.exampleDescription {
                inlineMarkdown(description).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder var back: some View {
        flags(card.answers)
        // The front of a meaning card already shows the summary.
        if card.type != .meaningToFlag {
            inlineMarkdown(card.summary).font(.body)
        }
        if let example = example {
            CommandLineView(highlight(example.command))
            if let description = example.description, card.type != .cloze {
                inlineMarkdown(description).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        if !card.detail.isEmpty && card.detail != card.summary {
            DisclosureGroup("Full Description", isExpanded: $showDetail) {
                inlineMarkdown(card.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    #if !os(Android)
                    .textSelection(.enabled)
                    #endif
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Space.s2)
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    var toolLine: some View {
        Text(command).font(.system(.title3, design: .monospaced).weight(.medium)).foregroundStyle(.secondary)
    }

    var argument: String? {
        guard let arg = option?.argument else { return nil }
        return arg.optional ? "[\(arg.name)]" : arg.name
    }

    var example: (command: String, description: String?)? {
        if card.type == .cloze, let command = card.command {
            return (command, card.exampleDescription)
        }
        guard let first = option?.examples.first else { return nil }
        return (first.command, first.description)
    }

    func flags(_ spellings: [String], front: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(spellings.first ?? "")
                .font(front ? .system(.largeTitle, design: .monospaced).weight(.semibold)
                    : .system(.title2, design: .monospaced).weight(.semibold))
                .foregroundStyle(frost.tint)
            if !front, let argument {
                Text(argument).font(.mono(.body)).italic().foregroundStyle(frost.arg)
            }
            ForEach(Array(spellings.dropFirst()), id: \.self) { alias in
                Text(alias).font(.mono(.body)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(2)
        #if !os(Android)
        .minimumScaleFactor(0.6)
        #endif
    }

    /// Highlights every spelling of the card's option in a command, and only
    /// those.
    func highlight(_ text: String) -> [CommandPart] {
        let answers = Set(card.answers)
        return commandParts(text).map { part in
            let name = String(part.text.split(separator: "=", maxSplits: 1).first ?? "")
            switch part.kind {
            case .flag where !answers.contains(name): return CommandPart(kind: .tool, text: part.text)
            case .tool where answers.contains(name): return CommandPart(kind: .flag, text: part.text)
            default: return part
            }
        }
    }

    var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        frost.surface
        #endif
    }
}

/// A terminal-style field for typing the flag, ported from `typed_answer.dart`.
struct TypedAnswerField: View {
    let command: String
    @Binding var text: String
    let result: TypedResult?
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    @Environment(\.frost) var frost

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("$ \(command)")
                    .font(.mono(.body))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("type the flag", text: $text)
                    .font(.mono(.body))
                    .focused(focused)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    #endif
                    .submitLabel(.done)
                    .onSubmit { if result == nil { onSubmit() } }
                    .disabled(result != nil)
                    .accessibilityLabel(Text("Answer for \(command)"))
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2 + 2)
            .background(RoundedRectangle(cornerRadius: Radii.code).fill(Color.secondary.opacity(0.12)))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.code)
                    .stroke(borderColor, lineWidth: result == nil ? 0 : 2)
            )
            if let result {
                ResultLine(result: result)
            }
        }
    }

    var borderColor: Color {
        guard let result else { return .clear }
        return result.result.correct ? .green : .red
    }
}

/// "Correct" or "Not quite · expected --flag", with a character diff.
struct ResultLine: View {
    let result: TypedResult

    var body: some View {
        let r = result.result
        var runs: [TextRun]
        if r.correct {
            runs = [TextRun("Correct", color: .green, bold: true)]
            if let preferred = r.preferred { runs += [TextRun(" · preferred: "), TextRun(preferred)] }
        } else {
            runs = [TextRun("Not quite", color: .red, bold: true), TextRun(" · expected "), TextRun(r.expected)]
            let typed = result.typed.trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty {
                runs.append(TextRun("   "))
                for part in diffChars(typed, r.expected) {
                    switch part.kind {
                    case .same: runs.append(TextRun(part.text, color: .secondary))
                    case .added: runs.append(TextRun(part.text, color: .green, underline: .green))
                    case .removed: runs.append(TextRun(part.text, color: .red, strikethrough: true))
                    }
                }
            }
        }
        return styledText(runs)
            .font(.system(.body, design: .monospaced))
    }
}


/// Deck text with its inline Markdown, such as `code`, rendered. Android shows
/// the text with the backticks taken out.
func inlineMarkdown(_ text: String) -> Text {
    #if os(Android)
    return Text(text.replacingOccurrences(of: "`", with: ""))
    #else
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    if let attributed = try? AttributedString(markdown: text, options: options) {
        return Text(attributed)
    }
    return Text(text)
    #endif
}
