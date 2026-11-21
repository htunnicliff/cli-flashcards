/// Deck file model, matching `src/schema/deck.ts` and `schemas/deck.schema.json`.
///
/// Decks are built and validated by the TypeScript pipeline in `tools/`, so
/// parsing here checks shape and required fields, not every schema rule.
library;

/// Bump with `SCHEMA_VERSION` in `src/schema/deck.ts`.
const deckSchemaVersion = 1;

enum Tier { core, common, obscure }

/// How the tool reads its command line, which decides which typed answers
/// count as the same flag. See `PARSING_STYLES` in `src/schema/deck.ts`.
enum ParsingStyle { gnu, posix, strict }

class DeckFormatException implements Exception {
  DeckFormatException(this.message);
  final String message;
  @override
  String toString() => 'DeckFormatException: $message';
}

T _req<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! T) {
    throw DeckFormatException('"$key" is missing or not a $T');
  }
  return value;
}

T? _opt<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! T) throw DeckFormatException('"$key" is not a $T');
  return value;
}

class Argument {
  const Argument({required this.name, this.optional = false});

  factory Argument.fromJson(Map<String, dynamic> json) => Argument(
    name: _req<String>(json, 'name'),
    optional: _opt<bool>(json, 'optional') ?? false,
  );

  final String name;
  final bool optional;

  Map<String, dynamic> toJson() => {'name': name, 'optional': optional};
}

class Example {
  const Example({required this.command, this.description});

  factory Example.fromJson(Map<String, dynamic> json) => Example(
    command: _req<String>(json, 'command'),
    description: _opt<String>(json, 'description'),
  );

  final String command;
  final String? description;

  Map<String, dynamic> toJson() => {
    'command': command,
    if (description != null) 'description': description,
  };
}

class Option {
  const Option({
    required this.id,
    required this.flags,
    this.primary,
    this.argument,
    required this.summary,
    this.description = '',
    required this.tier,
    this.examples = const [],
    this.tags = const [],
    this.hidden = false,
    this.subcommand,
  });

  factory Option.fromJson(Map<String, dynamic> json) {
    final flags = _req<List<dynamic>>(json, 'flags').cast<String>();
    if (flags.isEmpty) throw DeckFormatException('An option needs a flag');
    final argument = _opt<Map<String, dynamic>>(json, 'argument');
    return Option(
      id: _req<String>(json, 'id'),
      flags: List.unmodifiable(flags),
      primary: _opt<String>(json, 'primary'),
      argument: argument == null ? null : Argument.fromJson(argument),
      summary: _req<String>(json, 'summary'),
      description: _opt<String>(json, 'description') ?? '',
      tier: Tier.values.byName(_req<String>(json, 'tier')),
      examples: List.unmodifiable(
        (_opt<List<dynamic>>(json, 'examples') ?? const []).map(
          (e) => Example.fromJson(e as Map<String, dynamic>),
        ),
      ),
      tags: List.unmodifiable(
        (_opt<List<dynamic>>(json, 'tags') ?? const []).cast<String>(),
      ),
      hidden: _opt<bool>(json, 'hidden') ?? false,
      subcommand: _opt<String>(json, 'subcommand'),
    );
  }

  /// Stable identity, part of card IDs.
  final String id;

  /// Every spelling, short forms first.
  final List<String> flags;

  /// Overrides the default primary flag; one of [flags].
  final String? primary;
  final Argument? argument;

  /// One line; the front or back of a card.
  final String summary;

  /// Full text, shown as "more detail".
  final String description;
  final Tier tier;
  final List<Example> examples;
  final List<String> tags;

  /// Hidden options stay in the deck but produce no cards.
  final bool hidden;

  /// For tools with subcommands (`git log`), the one this option belongs to.
  final String? subcommand;

  Map<String, dynamic> toJson() => {
    'id': id,
    'flags': flags,
    if (primary != null) 'primary': primary,
    if (argument != null) 'argument': argument!.toJson(),
    'summary': summary,
    'description': description,
    'tier': tier.name,
    'examples': [for (final e in examples) e.toJson()],
    'tags': tags,
    'hidden': hidden,
    if (subcommand != null) 'subcommand': subcommand,
  };
}

class SourcePage {
  const SourcePage({required this.name, this.section, this.path});

  factory SourcePage.fromJson(Map<String, dynamic> json) => SourcePage(
    name: _req<String>(json, 'name'),
    section: _opt<String>(json, 'section'),
    path: _opt<String>(json, 'path'),
  );

  final String name;
  final String? section;
  final String? path;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (section != null) 'section': section,
    if (path != null) 'path': path,
  };
}

class Deck {
  const Deck({
    required this.id,
    required this.tool,
    required this.variant,
    required this.toolVersion,
    required this.deckVersion,
    required this.source,
    required this.license,
    required this.attribution,
    this.sourcePages,
    this.parsingStyle,
    required this.options,
  });

  factory Deck.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version != deckSchemaVersion) {
      throw DeckFormatException('Unsupported deck schema version $version');
    }
    final style = _opt<String>(json, 'parsingStyle');
    final pages = _opt<List<dynamic>>(json, 'sourcePages');
    return Deck(
      id: _req<String>(json, 'id'),
      tool: _req<String>(json, 'tool'),
      variant: _req<String>(json, 'variant'),
      toolVersion: _req<String>(json, 'toolVersion'),
      deckVersion: _req<int>(json, 'deckVersion'),
      source: _req<String>(json, 'source'),
      license: _req<String>(json, 'license'),
      attribution: _req<String>(json, 'attribution'),
      sourcePages: pages == null
          ? null
          : List.unmodifiable(
              pages.map((p) => SourcePage.fromJson(p as Map<String, dynamic>)),
            ),
      parsingStyle: style == null ? null : ParsingStyle.values.byName(style),
      options: List.unmodifiable(
        _req<List<dynamic>>(
          json,
          'options',
        ).map((o) => Option.fromJson(o as Map<String, dynamic>)),
      ),
    );
  }

  final String id;
  final String tool;

  /// e.g. `gnu`, `bsd`, `default`.
  final String variant;
  final String toolVersion;

  /// Increments whenever the deck's content changes.
  final int deckVersion;

  /// `manpage`, `help` or `manual`.
  final String source;
  final String license;
  final String attribution;
  final List<SourcePage>? sourcePages;

  /// Absent means `gnu`.
  final ParsingStyle? parsingStyle;
  final List<Option> options;

  Map<String, dynamic> toJson() => {
    'schemaVersion': deckSchemaVersion,
    'id': id,
    'tool': tool,
    'variant': variant,
    'toolVersion': toolVersion,
    'deckVersion': deckVersion,
    'source': source,
    'license': license,
    'attribution': attribution,
    if (sourcePages != null)
      'sourcePages': [for (final p in sourcePages!) p.toJson()],
    if (parsingStyle != null) 'parsingStyle': parsingStyle!.name,
    'options': [for (final o in options) o.toJson()],
  };
}
