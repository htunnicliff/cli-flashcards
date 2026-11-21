/// The app's only way into storage, ported from `src/core/storage/repository.ts`.
///
/// Backed by sembast: IndexedDB on the web, a file on iOS, Android and macOS,
/// and memory in tests. Everything else goes through [Repository].
library;

import 'package:sembast/sembast.dart';

import '../schema/deck.dart';
import 'models.dart';

/// Bump when stored record shapes change, and migrate in [Repository.open].
const storageVersion = 1;

final _decks = stringMapStoreFactory.store('decks');
final _cardStates = stringMapStoreFactory.store('cardStates');
final _reviewLog = intMapStoreFactory.store('reviewLog');
final _settings = StoreRef<String, Object?>('settings');
const _settingsKey = 'settings';

class Repository {
  Repository._(this._db, this._client);

  final Database _db;
  final DatabaseClient _client;

  static Future<Repository> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(path, version: storageVersion);
    return Repository._(db, db);
  }

  /// Runs [work] in one transaction, so a multi-step change lands completely
  /// or not at all. [work] gets a repository bound to the transaction.
  Future<T> atomically<T>(Future<T> Function(Repository repo) work) {
    if (_client is Transaction) return work(this);
    return _db.transaction((txn) => work(Repository._(_db, txn)));
  }

  Future<void> close() => _db.close();

  // Decks.

  /// Installs a deck or replaces it with a newer version, keeping its
  /// preferences. [initial] sets the preferences of a deck not installed yet.
  Future<StoredDeck> installDeck(
    Deck deck, {
    required int now,
    bool includeObscure = false,
    bool paused = false,
    bool typeAnswers = false,
  }) {
    return atomically((repo) async {
      final existing = await repo.getDeck(deck.id);
      final stored = existing != null
          ? existing.copyWith(deck: deck, updatedAt: now)
          : StoredDeck(
              deck: deck,
              installedAt: now,
              updatedAt: now,
              includeObscure: includeObscure,
              paused: paused,
              typeAnswers: typeAnswers,
            );
      await _decks.record(deck.id).put(repo._client, stored.toJson());
      return stored;
    });
  }

  Future<StoredDeck?> getDeck(String id) async {
    final json = await _decks.record(id).get(_client);
    return json == null ? null : StoredDeck.fromJson(json);
  }

  /// Installed decks, in deck ID order.
  Future<List<StoredDeck>> listDecks() async {
    final records = await _decks.find(
      _client,
      finder: Finder(sortOrders: [SortOrder(Field.key)]),
    );
    return [for (final r in records) StoredDeck.fromJson(r.value)];
  }

  Future<void> updateDeck(
    String id, {
    bool? includeObscure,
    bool? paused,
    bool? typeAnswers,
  }) async {
    await atomically((repo) async {
      final existing = await repo.getDeck(id);
      if (existing == null) throw StateError('Deck "$id" is not installed');
      final updated = existing.copyWith(
        includeObscure: includeObscure,
        paused: paused,
        typeAnswers: typeAnswers,
      );
      await _decks.record(id).put(repo._client, updated.toJson());
    });
  }

  /// Uninstalls the deck. Its progress stays.
  Future<void> removeDeck(String id) => _decks.record(id).delete(_client);

  // Card states.

  Future<CardState?> getCardState(String cardId) async {
    final json = await _cardStates.record(cardId).get(_client);
    return json == null ? null : CardState.fromJson(json);
  }

  /// Same order as [cardIds], null for cards never reviewed.
  Future<List<CardState?>> getCardStates(List<String> cardIds) async {
    final values = await _cardStates.records(cardIds).get(_client);
    return [for (final v in values) v == null ? null : CardState.fromJson(v)];
  }

  Future<List<CardState>> allCardStates() async {
    final records = await _cardStates.find(
      _client,
      finder: Finder(sortOrders: [SortOrder(Field.key)]),
    );
    return [for (final r in records) CardState.fromJson(r.value)];
  }

  /// Every stored state for a deck, including ones for removed options.
  Future<List<CardState>> cardStatesForDeck(String deckId) async {
    final records = await _cardStates.find(
      _client,
      finder: Finder(filter: Filter.equals('deckId', deckId)),
    );
    return [for (final r in records) CardState.fromJson(r.value)];
  }

  Future<void> putCardStates(Iterable<CardState> states) async {
    final list = states.toList();
    if (list.isEmpty) return;
    await _cardStates.records([for (final s in list) s.cardId]).put(_client, [
      for (final s in list) s.toJson(),
    ]);
  }

  Future<void> deleteCardStates(Iterable<String> cardIds) async {
    final ids = cardIds.toList();
    if (ids.isEmpty) return;
    await _cardStates.records(ids).delete(_client);
  }

  // Review log.

  /// Adds an entry under a fresh ID, ignoring any ID it carries.
  Future<int> appendReview(ReviewLogEntry entry) =>
      _reviewLog.add(_client, entry.toJson());

  Future<List<ReviewLogEntry>> _findLog(Filter? filter) async {
    final records = await _reviewLog.find(
      _client,
      finder: Finder(
        filter: filter,
        sortOrders: [SortOrder('reviewedAt'), SortOrder(Field.key)],
      ),
    );
    return [
      for (final r in records) ReviewLogEntry.fromJson(r.value, id: r.key),
    ];
  }

  /// Every review, oldest first.
  Future<List<ReviewLogEntry>> allReviews() => _findLog(null);

  /// Reviews with `from <= reviewedAt < to`, oldest first.
  Future<List<ReviewLogEntry>> reviewsBetween(int from, int to) => _findLog(
    Filter.and([
      Filter.greaterThanOrEquals('reviewedAt', from),
      Filter.lessThan('reviewedAt', to),
    ]),
  );

  Future<List<ReviewLogEntry>> reviewsForDeck(String deckId) =>
      _findLog(Filter.equals('deckId', deckId));

  Future<List<ReviewLogEntry>> reviewsForCard(String cardId) =>
      _findLog(Filter.equals('cardId', cardId));

  Future<int> reviewCount() => _reviewLog.count(_client);

  /// Writes a grade's new state and its log entry together. Returns the
  /// entry's ID.
  Future<int> recordReview(CardState state, ReviewLogEntry entry) =>
      atomically((repo) async {
        await repo.putCardStates([state]);
        return repo.appendReview(entry);
      });

  /// Takes back a grade: removes its log entry and restores the previous
  /// state (or removes it). The one exception to the append-only log.
  Future<void> undoReview(int entryId, String cardId, CardState? previous) =>
      atomically((repo) async {
        await _reviewLog.record(entryId).delete(repo._client);
        if (previous != null) {
          await repo.putCardStates([previous]);
        } else {
          await repo.deleteCardStates([cardId]);
        }
      });

  /// Deletes card states and review log entries, for one deck or all.
  Future<void> resetProgress([String? deckId]) => atomically((repo) async {
    if (deckId == null) {
      await _cardStates.delete(repo._client);
      await _reviewLog.delete(repo._client);
    } else {
      final filter = Finder(filter: Filter.equals('deckId', deckId));
      await _cardStates.delete(repo._client, finder: filter);
      await _reviewLog.delete(repo._client, finder: filter);
    }
  });

  // Settings.

  Future<Settings> settings() async {
    final json = await _settings.record(_settingsKey).get(_client);
    return json == null
        ? const Settings()
        : Settings.fromJson((json as Map).cast<String, dynamic>());
  }

  Future<void> saveSettings(Settings settings) =>
      _settings.record(_settingsKey).put(_client, settings.toJson());

  Future<Settings> updateSettings(Settings Function(Settings) change) =>
      atomically((repo) async {
        final next = change(await repo.settings());
        await repo.saveSettings(next);
        return next;
      });
}
