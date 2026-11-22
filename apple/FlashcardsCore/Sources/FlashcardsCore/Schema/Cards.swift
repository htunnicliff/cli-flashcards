// Cards derived from deck options at runtime, ported from `src/schema/cards.ts`
// (by way of `app/lib/schema/cards.dart`). Card IDs must match the other apps'
// exactly, so progress and backups carry over.

import Foundation

/// A flag spelling is **short** when it's one dash and one character (`-i`).
/// Anything else is **long**: `--ignore-case`, or `-name` as `find` spells it.
public func isShortFlag(_ flag: String) -> Bool {
    flag.utf16.count == 2 && flag.hasPrefix("-") && flag != "--"
}

public func isLongFlag(_ flag: String) -> Bool { !isShortFlag(flag) }

/// Orders flags short forms first, keeping the order within each group.
public func normalizeFlags<S: Sequence>(_ flags: S) -> [String] where S.Element == String {
    let all = Array(flags)
    return all.filter(isShortFlag) + all.filter(isLongFlag)
}

public enum CardType: String, Codable, CaseIterable, Sendable {
    case flagToMeaning = "flag-to-meaning"
    case meaningToFlag = "meaning-to-flag"
    case cloze = "cloze"
    case shortToLong = "short-to-long"
    case longToShort = "long-to-short"

    public var isFlagPair: Bool { self == .shortToLong || self == .longToShort }
}

/// Shown in place of the flag on cloze cards.
public let clozeBlank = "____"

public struct Card: Hashable, Sendable, Identifiable {
    /// `{tool}:{variant}:{optionId}:{cardType}`.
    public var id: String
    public var type: CardType
    public var deckId: String
    public var optionId: String
    /// The option's primary flag.
    public var flag: String
    /// Every accepted spelling, primary first.
    public var answers: [String]
    public var summary: String
    public var detail: String

    // Cloze cards.
    public var cloze: String?
    public var command: String?
    public var blanked: String?
    public var exampleDescription: String?

    // Flag pair cards.
    /// The one spelling the front shows.
    public var shown: String?
    /// The spellings of the other form that count, the expected one first.
    public var targets: [String]?

    public var isFlagPair: Bool { type.isFlagPair }
}

public func cardId(_ deck: Deck, _ optionId: String, _ type: CardType) -> String {
    "\(deck.tool):\(deck.variant):\(optionId):\(type.rawValue)"
}

/// `primary` when set, otherwise the first flag.
public func primaryFlag(_ option: Option) -> String {
    option.primary ?? option.flags[0]
}

/// All spellings with the primary flag first.
public func answerFlags(_ option: Option) -> [String] {
    let primary = primaryFlag(option)
    return [primary] + option.flags.filter { $0 != primary }
}

public struct ClozeMatch: Hashable, Sendable {
    public var command: String
    public var cloze: String
    public var blanked: String
    public var description: String?
}

/// JavaScript's `\s`: whitespace and line terminators, plus the BOM.
func isJSWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    scalar.properties.isWhitespace || scalar == "\u{FEFF}"
}

/// Splits like JS `str.split(/(\s+)/)`: words and the whitespace runs between
/// them, always starting and ending with a word (possibly empty).
func splitKeepingSpace(_ s: String) -> [String] {
    var parts: [String] = []
    var current = String.UnicodeScalarView()
    var inSpace = false
    for scalar in s.unicodeScalars {
        let space = isJSWhitespace(scalar)
        if space != inSpace {
            parts.append(String(current))
            current = String.UnicodeScalarView()
            inSpace = space
        }
        current.append(scalar)
    }
    parts.append(String(current))
    if inSpace { parts.append("") }
    return parts
}

/// The first example that spells one of the option's flags as its own token,
/// preferring the primary flag.
public func findCloze(_ option: Option) -> ClozeMatch? {
    for flag in answerFlags(option) {
        for example in option.examples {
            var tokens = splitKeepingSpace(example.command)
            guard let index = tokens.firstIndex(where: { $0 == flag || $0.hasPrefix(flag + "=") }) else {
                continue
            }
            let token = tokens[index]
            tokens[index] = clozeBlank + String(token.unicodeScalars.dropFirst(flag.unicodeScalars.count))
            return ClozeMatch(
                command: example.command,
                cloze: tokens.joined(),
                blanked: flag,
                description: example.description
            )
        }
    }
    return nil
}

/// The option's short and long spellings, or nil when it lacks one form.
public func flagPair(_ option: Option) -> (short: [String], long: [String])? {
    let flags = answerFlags(option)
    let short = flags.filter(isShortFlag)
    let long = flags.filter(isLongFlag)
    return !short.isEmpty && !long.isEmpty ? (short, long) : nil
}

private func optionCards(_ deck: Deck, _ option: Option, flagPairs: Bool) -> [Card] {
    func make(
        _ type: CardType, cloze: String? = nil, command: String? = nil, blanked: String? = nil,
        exampleDescription: String? = nil, shown: String? = nil, targets: [String]? = nil
    ) -> Card {
        Card(
            id: cardId(deck, option.id, type),
            type: type,
            deckId: deck.id,
            optionId: option.id,
            flag: primaryFlag(option),
            answers: answerFlags(option),
            summary: option.summary,
            detail: option.description,
            cloze: cloze,
            command: command,
            blanked: blanked,
            exampleDescription: exampleDescription,
            shown: shown,
            targets: targets
        )
    }

    var cards = [make(.flagToMeaning), make(.meaningToFlag)]
    if let match = findCloze(option) {
        cards.append(make(
            .cloze, cloze: match.cloze, command: match.command, blanked: match.blanked,
            exampleDescription: match.description
        ))
    }
    if flagPairs, let pair = flagPair(option) {
        cards.append(make(.shortToLong, shown: pair.short[0], targets: pair.long))
        cards.append(make(.longToShort, shown: pair.long[0], targets: pair.short))
    }
    return cards
}

/// Every card for a deck: each visible option × each card type that applies.
public func deriveCards(_ deck: Deck, flagPairs: Bool = false) -> [Card] {
    deck.options.filter { !$0.hidden }.flatMap { optionCards(deck, $0, flagPairs: flagPairs) }
}
