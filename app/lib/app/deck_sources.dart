/// Where the app gets decks: the published site, or the copies it ships with.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/sync.dart';
import '../schema/deck.dart';
import '../schema/manifest.dart';
import 'app_state.dart';

/// The published deck files, built by `pnpm deck:build` and deployed with the
/// web app. Override with `--dart-define=DECKS_URL=...`.
const decksUrl = String.fromEnvironment(
  'DECKS_URL',
  defaultValue: 'https://htunnicliff.github.io/cli-flashcards/data/decks/',
);

Map<String, dynamic> _object(String text) =>
    jsonDecode(text) as Map<String, dynamic>;

class NetworkDeckSource implements DeckSource {
  NetworkDeckSource({http.Client? client, this.baseUrl = decksUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<String> _get(String file) async {
    final response = await _client
        // No custom headers: on the web they would force a CORS preflight.
        .get(Uri.parse('$baseUrl$file'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw http.ClientException(
        "Couldn't load $file (HTTP ${response.statusCode}).",
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  @override
  Future<DeckManifest> manifest() async =>
      DeckManifest.fromJson(_object(await _get('index.json')));

  @override
  Future<Deck> deck(DeckManifestEntry entry) async {
    final text = await _get(entry.file);
    return compute((t) => Deck.fromJson(_object(t)), text);
  }
}

class BundledDeckSource implements DeckSource {
  const BundledDeckSource();

  @override
  Future<DeckManifest> manifest() async => DeckManifest.fromJson(
    _object(await rootBundle.loadString('assets/decks/index.json')),
  );

  @override
  Future<Deck> deck(DeckManifestEntry entry) async => Deck.fromJson(
    _object(await rootBundle.loadString('assets/decks/${entry.file}')),
  );
}

/// The network when it answers, otherwise the bundled copies, so a first
/// launch with no connection still has decks.
class FallbackDeckSource implements DeckSource, OnlineAware {
  FallbackDeckSource(this.primary, this.fallback);

  final DeckSource primary;
  final DeckSource fallback;
  DeckSource? _chosen;

  /// Whether the last manifest came from the network.
  @override
  bool get online => identical(_chosen, primary);

  @override
  Future<DeckManifest> manifest() async {
    try {
      final m = await primary.manifest();
      _chosen = primary;
      return m;
    } catch (_) {
      _chosen = fallback;
      return fallback.manifest();
    }
  }

  @override
  Future<Deck> deck(DeckManifestEntry entry) async {
    final source = _chosen ?? primary;
    try {
      return await source.deck(entry);
    } catch (_) {
      if (identical(source, fallback)) rethrow;
      return fallback.deck(entry);
    }
  }
}
