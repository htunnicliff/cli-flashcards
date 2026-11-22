// Deck file model, matching `src/schema/deck.ts` and `schemas/deck.schema.json`.
//
// Decks are built and validated by the TypeScript pipeline in `tools/`, so
// decoding here checks shape and required fields, not every schema rule.

import Foundation

/// Bump with `SCHEMA_VERSION` in `src/schema/deck.ts`.
public let deckSchemaVersion = 1

public enum Tier: String, Codable, CaseIterable, Sendable {
    case core, common, obscure
}

/// How the tool reads its command line, which decides which typed answers
/// count as the same flag. See `PARSING_STYLES` in `src/schema/deck.ts`.
public enum ParsingStyle: String, Codable, Sendable {
    case gnu, posix, strict
}

public struct DeckFormatError: Error, CustomStringConvertible, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "DeckFormatError: \(message)" }
}

public struct Argument: Codable, Hashable, Sendable {
    public var name: String
    public var optional: Bool

    public init(name: String, optional: Bool = false) {
        self.name = name
        self.optional = optional
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        optional = try c.decodeIfPresent(Bool.self, forKey: .optional) ?? false
    }
}

public struct Example: Codable, Hashable, Sendable {
    public var command: String
    public var description: String?

    public init(command: String, description: String? = nil) {
        self.command = command
        self.description = description
    }
}

public struct Option: Codable, Hashable, Sendable, Identifiable {
    /// Stable identity, part of card IDs.
    public var id: String
    /// Every spelling, short forms first.
    public var flags: [String]
    /// Overrides the default primary flag; one of `flags`.
    public var primary: String?
    public var argument: Argument?
    /// One line; the front or back of a card.
    public var summary: String
    /// Full text, shown as "more detail".
    public var description: String
    public var tier: Tier
    public var examples: [Example]
    public var tags: [String]
    /// Hidden options stay in the deck but produce no cards.
    public var hidden: Bool
    /// For tools with subcommands (`git log`), the one this option belongs to.
    public var subcommand: String?

    public init(
        id: String, flags: [String], primary: String? = nil, argument: Argument? = nil,
        summary: String, description: String = "", tier: Tier, examples: [Example] = [],
        tags: [String] = [], hidden: Bool = false, subcommand: String? = nil
    ) {
        self.id = id
        self.flags = flags
        self.primary = primary
        self.argument = argument
        self.summary = summary
        self.description = description
        self.tier = tier
        self.examples = examples
        self.tags = tags
        self.hidden = hidden
        self.subcommand = subcommand
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        flags = try c.decode([String].self, forKey: .flags)
        if flags.isEmpty { throw DeckFormatError("An option needs a flag") }
        primary = try c.decodeIfPresent(String.self, forKey: .primary)
        argument = try c.decodeIfPresent(Argument.self, forKey: .argument)
        summary = try c.decode(String.self, forKey: .summary)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        tier = try c.decode(Tier.self, forKey: .tier)
        examples = try c.decodeIfPresent([Example].self, forKey: .examples) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        subcommand = try c.decodeIfPresent(String.self, forKey: .subcommand)
    }
}

public struct SourcePage: Codable, Hashable, Sendable {
    public var name: String
    public var section: String?
    public var path: String?

    public init(name: String, section: String? = nil, path: String? = nil) {
        self.name = name
        self.section = section
        self.path = path
    }
}

public struct Deck: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var tool: String
    /// e.g. `gnu`, `bsd`, `default`.
    public var variant: String
    public var toolVersion: String
    /// Increments whenever the deck's content changes.
    public var deckVersion: Int
    /// `manpage`, `help` or `manual`.
    public var source: String
    public var license: String
    public var attribution: String
    public var sourcePages: [SourcePage]?
    /// Absent means `gnu`.
    public var parsingStyle: ParsingStyle?
    public var options: [Option]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, tool, variant, toolVersion, deckVersion, source, license
        case attribution, sourcePages, parsingStyle, options
    }

    public init(
        id: String, tool: String, variant: String, toolVersion: String, deckVersion: Int,
        source: String, license: String, attribution: String, sourcePages: [SourcePage]? = nil,
        parsingStyle: ParsingStyle? = nil, options: [Option]
    ) {
        self.id = id
        self.tool = tool
        self.variant = variant
        self.toolVersion = toolVersion
        self.deckVersion = deckVersion
        self.source = source
        self.license = license
        self.attribution = attribution
        self.sourcePages = sourcePages
        self.parsingStyle = parsingStyle
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
        guard version == deckSchemaVersion else {
            throw DeckFormatError("Unsupported deck schema version \(version.map(String.init) ?? "null")")
        }
        id = try c.decode(String.self, forKey: .id)
        tool = try c.decode(String.self, forKey: .tool)
        variant = try c.decode(String.self, forKey: .variant)
        toolVersion = try c.decode(String.self, forKey: .toolVersion)
        deckVersion = try c.decode(Int.self, forKey: .deckVersion)
        source = try c.decode(String.self, forKey: .source)
        license = try c.decode(String.self, forKey: .license)
        attribution = try c.decode(String.self, forKey: .attribution)
        sourcePages = try c.decodeIfPresent([SourcePage].self, forKey: .sourcePages)
        parsingStyle = try c.decodeIfPresent(ParsingStyle.self, forKey: .parsingStyle)
        options = try c.decode([Option].self, forKey: .options)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(deckSchemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encode(tool, forKey: .tool)
        try c.encode(variant, forKey: .variant)
        try c.encode(toolVersion, forKey: .toolVersion)
        try c.encode(deckVersion, forKey: .deckVersion)
        try c.encode(source, forKey: .source)
        try c.encode(license, forKey: .license)
        try c.encode(attribution, forKey: .attribution)
        try c.encodeIfPresent(sourcePages, forKey: .sourcePages)
        try c.encodeIfPresent(parsingStyle, forKey: .parsingStyle)
        try c.encode(options, forKey: .options)
    }

    /// Decodes a deck file.
    public static func decode(_ data: Data) throws -> Deck {
        try JSONDecoder().decode(Deck.self, from: data)
    }
}
