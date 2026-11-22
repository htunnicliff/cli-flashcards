// Checks a typed flag against the option a card asks for, accepting every way
// the tool itself would read it. Ported from `src/core/answers/index.ts`.

import Foundation

public struct AnswerResult: Hashable, Sendable {
    public var correct: Bool
    /// The flag the card expects.
    public var expected: String
    /// The full spelling the answer was read as.
    public var matched: String?
    /// Set when the answer was right but not spelled as the primary flag.
    public var preferred: String?

    public init(correct: Bool, expected: String, matched: String? = nil, preferred: String? = nil) {
        self.correct = correct
        self.expected = expected
        self.matched = matched
        self.preferred = preferred
    }
}

public struct NamedOption: Hashable, Sendable {
    public var option: Option
    public var flag: String
}

/// The part of a word before its first `=`, like JS `word.split('=')[0]`.
private func flagName(_ word: String) -> String {
    if let i = word.firstIndex(of: "=") { return String(word[..<i]) }
    return word
}

/// The options a single command-line word names, in the order the tool reads them.
public func optionsNamedBy(_ word: String, _ options: [Option], style: ParsingStyle = .gnu) -> [NamedOption] {
    if !word.hasPrefix("-") || word == "-" || word == "--" { return [] }
    let name = flagName(word)
    for option in options where option.flags.contains(name) {
        return [NamedOption(option: option, flag: name)]
    }

    if word.hasPrefix("--") {
        // JS string length counts UTF-16 code units.
        if style != .gnu || name.utf16.count < 3 { return [] }
        var matches: [NamedOption] = []
        for option in options {
            if let f = option.flags.first(where: { $0.hasPrefix("--") && $0.unicodeScalars.starts(with: name.unicodeScalars) }) {
                matches.append(NamedOption(option: option, flag: f))
            }
        }
        return matches.count == 1 ? matches : []
    }

    if style == .strict { return [] }
    var named: [NamedOption] = []
    for scalar in word.unicodeScalars.dropFirst() {
        let flag = "-" + String(scalar)
        guard let found = options.first(where: { $0.flags.contains(flag) }) else { return [] }
        named.append(NamedOption(option: found, flag: flag))
        if found.argument != nil { break }
    }
    return named
}

/// Splits like JS `s.split(/\s+/)` on an already trimmed string.
private func splitOnSpaces(_ s: String) -> [String] {
    var words: [String] = []
    var current = String.UnicodeScalarView()
    var lastWasSpace = false
    for scalar in s.unicodeScalars {
        if isJSWhitespace(scalar) {
            if !lastWasSpace {
                words.append(String(current))
                current = String.UnicodeScalarView()
            }
            lastWasSpace = true
        } else {
            current.append(scalar)
            lastWasSpace = false
        }
    }
    words.append(String(current))
    return words
}

/// JS `String.prototype.trim`.
private func jsTrim(_ s: String) -> String {
    let scalars = s.unicodeScalars
    guard let start = scalars.firstIndex(where: { !isJSWhitespace($0) }) else { return "" }
    let end = scalars.lastIndex(where: { !isJSWhitespace($0) })!
    return String(scalars[start...end])
}

/// Whether `input` names `option`. The answer must hold exactly one flag word.
/// `only` accepts just these exact spellings (flag pair cards).
public func checkAnswer(
    _ input: String, option: Option, options: [Option], style: ParsingStyle? = nil, only: [String]? = nil
) -> AnswerResult {
    let expected = only?.first ?? primaryFlag(option)
    let scope = options.filter { $0.subcommand == option.subcommand }
    let flagWords = splitOnSpaces(jsTrim(input)).filter { $0.hasPrefix("-") }
    guard flagWords.count == 1 else { return AnswerResult(correct: false, expected: expected) }
    let word = flagWords[0]
    let name = flagName(word)

    if let only {
        guard only.contains(name) else { return AnswerResult(correct: false, expected: expected) }
        return AnswerResult(correct: true, expected: expected, matched: name)
    }

    let named = optionsNamedBy(word, scope, style: style ?? .gnu)
    guard let hit = named.first(where: { $0.option.id == option.id }) else {
        return AnswerResult(correct: false, expected: expected)
    }
    let typedAsPrimary = named.count == 1 && name == expected
    return AnswerResult(
        correct: true, expected: expected, matched: hit.flag,
        preferred: typedAsPrimary ? nil : expected
    )
}

/// Whether a short form exists, so the result can call the primary "short form".
public func hasShortForm(_ option: Option) -> Bool { option.flags.contains(where: isShortFlag) }

public enum DiffKind: String, Sendable { case same, added, removed }

public struct DiffPart: Hashable, Sendable {
    public var kind: DiffKind
    public var text: String
}

/// A character diff from `from` to `to` (longest common subsequence).
public func diffChars(_ from: String, _ to: String) -> [DiffPart] {
    let a = Array(from.unicodeScalars)
    let b = Array(to.unicodeScalars)
    var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    if !a.isEmpty && !b.isEmpty {
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lengths[i][j] = a[i] == b[j]
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
    }
    var parts: [DiffPart] = []
    func push(_ kind: DiffKind, _ scalar: Unicode.Scalar) {
        if let last = parts.last, last.kind == kind {
            parts[parts.count - 1].text.unicodeScalars.append(scalar)
        } else {
            parts.append(DiffPart(kind: kind, text: String(scalar)))
        }
    }
    var i = 0, j = 0
    while i < a.count || j < b.count {
        if i < a.count && j < b.count && a[i] == b[j] {
            push(.same, a[i]); i += 1; j += 1
        } else if j < b.count && (i == a.count || lengths[i][j + 1] >= lengths[i + 1][j]) {
            push(.added, b[j]); j += 1
        } else {
            push(.removed, a[i]); i += 1
        }
    }
    return parts
}
