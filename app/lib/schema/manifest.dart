/// The built deck list, `public/data/decks/index.json` (see `src/schema/manifest.ts`).
library;

import 'deck.dart';

const manifestVersion = 1;

class DeckManifestEntry {
  const DeckManifestEntry({
    required this.id,
    required this.tool,
    required this.variant,
    required this.toolVersion,
    required this.deckVersion,
    required this.source,
    required this.license,
    required this.file,
    required this.bytes,
    required this.optionCount,
    required this.tiers,
  });

  factory DeckManifestEntry.fromJson(Map<String, dynamic> json) =>
      DeckManifestEntry(
        id: json['id'] as String,
        tool: json['tool'] as String,
        variant: json['variant'] as String,
        toolVersion: json['toolVersion'] as String,
        deckVersion: json['deckVersion'] as int,
        source: json['source'] as String,
        license: json['license'] as String,
        file: json['file'] as String,
        bytes: json['bytes'] as int,
        optionCount: json['optionCount'] as int,
        tiers: {
          for (final MapEntry(:key, :value)
              in (json['tiers'] as Map<String, dynamic>).entries)
            Tier.values.byName(key): value as int,
        },
      );

  final String id;
  final String tool;
  final String variant;
  final String toolVersion;
  final int deckVersion;
  final String source;
  final String license;

  /// Deck file path relative to the manifest.
  final String file;
  final int bytes;

  /// Options that produce cards.
  final int optionCount;
  final Map<Tier, int> tiers;
}

class DeckManifest {
  const DeckManifest(this.decks);

  factory DeckManifest.fromJson(Map<String, dynamic> json) {
    if (json['manifestVersion'] != manifestVersion) {
      throw DeckFormatException(
        'Unsupported manifest version ${json['manifestVersion']}',
      );
    }
    return DeckManifest(
      List.unmodifiable(
        (json['decks'] as List<dynamic>).map(
          (e) => DeckManifestEntry.fromJson(e as Map<String, dynamic>),
        ),
      ),
    );
  }

  final List<DeckManifestEntry> decks;
}
