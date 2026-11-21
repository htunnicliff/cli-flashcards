/// JSON backups, ported from `src/core/backup/backup.ts`. The file format is
/// shared with the web app, so either one can read the other's backups.
library;

import 'dart:convert';

import 'models.dart';
import 'repository.dart';

const backupVersion = 1;
const backupFormat = 'recall-backup';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupDeck {
  const BackupDeck(this.id, this.deckVersion, this.includeObscure);
  final String id;
  final int deckVersion;
  final bool includeObscure;
  Map<String, dynamic> toJson() => {
    'id': id,
    'deckVersion': deckVersion,
    'includeObscure': includeObscure,
  };
}

/// Settings that travel with a backup.
const _backupSettingKeys = [
  'desiredRetention',
  'newCardsPerDay',
  'maxReviewsPerDay',
  'dayRolloverHour',
  'leechThreshold',
  'flagPairs',
];

class Backup {
  const Backup({
    required this.exportedAt,
    required this.decks,
    required this.cardStates,
    required this.reviewLog,
    required this.settings,
  });

  final int exportedAt;
  final List<BackupDeck> decks;
  final List<CardState> cardStates;

  /// Oldest first.
  final List<ReviewLogEntry> reviewLog;

  /// Only the keys in [_backupSettingKeys] that the file had.
  final Map<String, dynamic> settings;

  Map<String, dynamic> toJson() => {
    'format': backupFormat,
    'backupVersion': backupVersion,
    'exportedAt': exportedAt,
    'decks': [for (final d in decks) d.toJson()],
    'cardStates': [for (final s in cardStates) s.toJson()],
    'reviewLog': [for (final e in reviewLog) e.toJson()],
    'settings': settings,
  };

  String encode() => jsonEncode(toJson());
}

/// Snapshot of everything worth keeping. Also records `lastBackupAt`.
Future<Backup> exportBackup(Repository repository, int now) async {
  final backup = await repository.atomically((repo) async {
    final decks = await repo.listDecks();
    final states = await repo.allCardStates();
    final log = await repo.allReviews();
    final settings = (await repo.settings()).toJson();
    return Backup(
      exportedAt: now,
      decks: [
        for (final d in decks)
          BackupDeck(d.id, d.deckVersion, d.includeObscure),
      ]..sort((a, b) => a.id.compareTo(b.id)),
      cardStates: states..sort((a, b) => a.cardId.compareTo(b.cardId)),
      reviewLog: log,
      settings: {for (final k in _backupSettingKeys) k: settings[k]},
    );
  });
  await repository.updateSettings((s) => s.copyWith(lastBackupAt: () => now));
  return backup;
}

Never _damaged(String path, String message) =>
    throw BackupException('This backup is damaged ($path: $message).');

T _field<T>(Map<String, dynamic> json, String key, String path) {
  final v = json[key];
  if (v is! T) _damaged('$path$key', 'expected ${T.toString().toLowerCase()}');
  return v;
}

/// Validates a backup file's text, with a readable error.
Backup parseBackup(String input) {
  Object? data;
  try {
    data = jsonDecode(input);
  } on FormatException {
    throw BackupException('This file isn’t valid JSON.');
  }
  if (data is! Map<String, dynamic> || data['format'] != backupFormat) {
    throw BackupException('This file isn’t a --recall backup.');
  }
  final version = data['backupVersion'];
  if (version is num && version > backupVersion) {
    throw BackupException(
      'This backup was made by a newer version of the app. Update and try again.',
    );
  }
  if (version != backupVersion) _damaged('backupVersion', 'unsupported');

  List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) {
    final items = _field<List<dynamic>>(data as Map<String, dynamic>, key, '');
    return [
      for (final (i, item) in items.indexed)
        () {
          if (item is! Map<String, dynamic>) {
            _damaged('$key.$i', 'expected object');
          }
          try {
            return parse(item);
          } on BackupException {
            rethrow;
          } catch (e) {
            _damaged('$key.$i', 'invalid');
          }
        }(),
    ];
  }

  final settings = data['settings'];
  if (settings is! Map<String, dynamic>) {
    _damaged('settings', 'expected object');
  }
  return Backup(
    exportedAt: _field<num>(data, 'exportedAt', '').toInt(),
    decks: list('decks', (d) {
      final v = d['deckVersion'];
      if (d['id'] is! String ||
          v is! int ||
          v < 1 ||
          d['includeObscure'] is! bool) {
        throw const FormatException();
      }
      return BackupDeck(d['id'] as String, v, d['includeObscure'] as bool);
    }),
    cardStates: list('cardStates', CardState.fromJson),
    reviewLog: list('reviewLog', (e) {
      final rating = e['rating'];
      if (rating is! int || rating < 1 || rating > 4) {
        throw const FormatException();
      }
      return ReviewLogEntry.fromJson(e)._withoutId();
    }),
    settings: {
      for (final k in _backupSettingKeys)
        if (settings[k] != null) k: settings[k],
    },
  );
}

extension on ReviewLogEntry {
  ReviewLogEntry _withoutId() => ReviewLogEntry(
    cardId: cardId,
    deckId: deckId,
    reviewedAt: reviewedAt,
    rating: rating,
    durationMs: durationMs,
    before: before,
    after: after,
  );
}

class BackupSummary {
  const BackupSummary(
    this.decks,
    this.cards,
    this.reviews,
    this.firstReview,
    this.lastReview,
    this.exportedAt,
  );
  final List<String> decks;
  final int cards;
  final int reviews;
  final int? firstReview;
  final int? lastReview;
  final int exportedAt;
}

BackupSummary summarizeBackup(Backup b) {
  final times = b.reviewLog.map((e) => e.reviewedAt);
  return BackupSummary(
    [for (final d in b.decks) d.id],
    b.cardStates.length,
    b.reviewLog.length,
    times.isEmpty ? null : times.reduce((a, c) => a < c ? a : c),
    times.isEmpty ? null : times.reduce((a, c) => a > c ? a : c),
    b.exportedAt,
  );
}

enum ImportMode { replace, merge }

class ImportResult {
  const ImportResult(this.pendingDecks, this.addedReviews);

  /// Decks the backup used that aren't installed here, queued to install.
  final List<PendingDeckInstall> pendingDecks;
  final int addedReviews;
}

String _logKey(ReviewLogEntry e) =>
    '${e.cardId}\u0000${e.reviewedAt}\u0000${e.rating.value}';

/// Loads a backup. `replace` wipes progress and takes the backup's settings;
/// `merge` adds missing reviews and keeps the more recently reviewed state.
Future<ImportResult> importBackup(
  Repository repository,
  Backup backup,
  ImportMode mode,
) {
  return repository.atomically((repo) async {
    var added = 0;
    if (mode == ImportMode.replace) {
      await repo.resetProgress();
      await repo.putCardStates(backup.cardStates);
      for (final e in backup.reviewLog) {
        await repo.appendReview(e);
      }
      added = backup.reviewLog.length;
      final current = (await repo.settings()).toJson();
      final defaults = const Settings().toJson();
      for (final k in _backupSettingKeys) {
        current[k] = backup.settings[k] ?? defaults[k];
      }
      await repo.saveSettings(Settings.fromJson(current));
    } else {
      final existing = {for (final e in await repo.allReviews()) _logKey(e)};
      for (final e in backup.reviewLog) {
        if (!existing.add(_logKey(e))) continue;
        await repo.appendReview(e);
        added++;
      }
      final local = await repo.getCardStates([
        for (final s in backup.cardStates) s.cardId,
      ]);
      await repo.putCardStates([
        for (final (i, incoming) in backup.cardStates.indexed)
          if (local[i] == null ||
              (incoming.fsrs.lastReview ?? -1) >
                  (local[i]!.fsrs.lastReview ?? -1))
            incoming,
      ]);
    }

    final settings = await repo.settings();
    final pending = {for (final p in settings.pendingDeckInstalls) p.id: p};
    for (final deck in backup.decks) {
      final installed = await repo.getDeck(deck.id);
      if (installed != null) {
        if (mode == ImportMode.replace || deck.includeObscure) {
          await repo.updateDeck(deck.id, includeObscure: deck.includeObscure);
        }
      } else {
        pending[deck.id] = PendingDeckInstall(
          id: deck.id,
          deckVersion: deck.deckVersion,
          includeObscure: deck.includeObscure,
        );
      }
    }
    final pendingList = pending.values.toList();
    await repo.saveSettings(
      settings.copyWith(pendingDeckInstalls: pendingList),
    );
    final ids = {for (final d in backup.decks) d.id};
    return ImportResult([
      for (final p in pendingList)
        if (ids.contains(p.id)) p,
    ], added);
  });
}

/// `recall-backup-2026-01-31.json`, by local date.
String backupFileName(int now) {
  final d = DateTime.fromMillisecondsSinceEpoch(now);
  String pad(int n) => n.toString().padLeft(2, '0');
  return 'recall-backup-${d.year}-${pad(d.month)}-${pad(d.day)}.json';
}

/// Whole days since the last backup, or null if there has never been one.
int? daysSinceBackup(int? lastBackupAt, int now) => lastBackupAt == null
    ? null
    : ((now - lastBackupAt) / 86400000).floor().clamp(0, 1 << 31);
