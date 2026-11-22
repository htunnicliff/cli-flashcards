// The built deck list, `public/data/decks/index.json` (see `src/schema/manifest.ts`).

import Foundation

public let manifestVersion = 1

public struct DeckManifestEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var tool: String
    public var variant: String
    public var toolVersion: String
    public var deckVersion: Int
    public var source: String
    public var license: String
    /// Deck file path relative to the manifest.
    public var file: String
    public var bytes: Int
    /// Options that produce cards.
    public var optionCount: Int
    public var tiers: [Tier: Int]

    enum CodingKeys: String, CodingKey {
        case id, tool, variant, toolVersion, deckVersion, source, license, file, bytes
        case optionCount, tiers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        tool = try c.decode(String.self, forKey: .tool)
        variant = try c.decode(String.self, forKey: .variant)
        toolVersion = try c.decode(String.self, forKey: .toolVersion)
        deckVersion = try c.decode(Int.self, forKey: .deckVersion)
        source = try c.decode(String.self, forKey: .source)
        license = try c.decode(String.self, forKey: .license)
        file = try c.decode(String.self, forKey: .file)
        bytes = try c.decode(Int.self, forKey: .bytes)
        optionCount = try c.decode(Int.self, forKey: .optionCount)
        let raw = try c.decode([String: Int].self, forKey: .tiers)
        var tiers: [Tier: Int] = [:]
        for (key, value) in raw {
            guard let tier = Tier(rawValue: key) else { throw DeckFormatError("Unknown tier \(key)") }
            tiers[tier] = value
        }
        self.tiers = tiers
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tool, forKey: .tool)
        try c.encode(variant, forKey: .variant)
        try c.encode(toolVersion, forKey: .toolVersion)
        try c.encode(deckVersion, forKey: .deckVersion)
        try c.encode(source, forKey: .source)
        try c.encode(license, forKey: .license)
        try c.encode(file, forKey: .file)
        try c.encode(bytes, forKey: .bytes)
        try c.encode(optionCount, forKey: .optionCount)
        try c.encode(Dictionary(uniqueKeysWithValues: tiers.map { ($0.key.rawValue, $0.value) }), forKey: .tiers)
    }
}

public struct DeckManifest: Codable, Hashable, Sendable {
    public var decks: [DeckManifestEntry]

    enum CodingKeys: String, CodingKey { case manifestVersion, decks }

    public init(decks: [DeckManifestEntry]) { self.decks = decks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .manifestVersion)
        guard version == manifestVersion else {
            throw DeckFormatError("Unsupported manifest version \(version.map(String.init) ?? "null")")
        }
        decks = try c.decode([DeckManifestEntry].self, forKey: .decks)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(manifestVersion, forKey: .manifestVersion)
        try c.encode(decks, forKey: .decks)
    }

    public static func decode(_ data: Data) throws -> DeckManifest {
        try JSONDecoder().decode(DeckManifest.self, from: data)
    }
}
