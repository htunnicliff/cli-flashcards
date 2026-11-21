import 'dart:convert';

import 'package:cliflashcards/core/backup.dart';
import 'package:cliflashcards/core/models.dart';
import 'package:cliflashcards/core/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final testDeck = deck([
    option('ignore-case', ['-i', '--ignore-case']),
    option('count', ['-c', '--count']),
  ]);

  test(
    'export then replace-import round-trips progress and settings',
    () async {
      final source = await memoryRepository();
      await source.installDeck(testDeck, now: noon, includeObscure: true);
      await source.updateSettings((s) => s.copyWith(newCardsPerDay: 7));
      final scheduler = Scheduler(source);
      await scheduler.grade(
        'rg:default:ignore-case:flag-to-meaning',
        Rating.good,
        noon,
      );
      await scheduler.grade(
        'rg:default:count:meaning-to-flag',
        Rating.again,
        noon,
      );

      final backup = await exportBackup(source, noon + day);
      expect((await source.settings()).lastBackupAt, noon + day);
      final text = backup.encode();

      final target = await memoryRepository();
      final parsed = parseBackup(text);
      final result = await importBackup(target, parsed, ImportMode.replace);
      expect(result.addedReviews, 2);
      expect(result.pendingDecks.single.id, 'rg-default');
      expect((await target.settings()).newCardsPerDay, 7);
      expect(await target.reviewCount(), 2);
      expect(
        (await target.allCardStates()).map((s) => s.toJson()),
        (await source.allCardStates()).map((s) => s.toJson()),
      );
    },
  );

  test('merge adds only missing reviews and keeps newer states', () async {
    final repo = await memoryRepository();
    await repo.installDeck(testDeck, now: noon);
    final scheduler = Scheduler(repo);
    await scheduler.grade(
      'rg:default:ignore-case:flag-to-meaning',
      Rating.good,
      noon,
    );
    final backup = parseBackup((await exportBackup(repo, noon)).encode());
    await scheduler.grade(
      'rg:default:ignore-case:flag-to-meaning',
      Rating.good,
      noon + 11 * minute,
    );
    final result = await importBackup(repo, backup, ImportMode.merge);
    expect(result.addedReviews, 0);
    final state = await repo.getCardState(
      'rg:default:ignore-case:flag-to-meaning',
    );
    expect(state!.fsrs.lastReview, noon + 11 * minute);
  });

  test('reads a backup written by the web app', () {
    const web = '''{"format":"recall-backup","backupVersion":1,"exportedAt":1767225600000,
"decks":[{"id":"rg-default","deckVersion":2,"includeObscure":false}],
"cardStates":[{"cardId":"rg:default:ignore-case:cloze","deckId":"rg-default","optionId":"ignore-case",
"fsrs":{"phase":"review","due":1767830400000,"stability":7.2,"difficulty":5.1,"elapsedDays":0,
"scheduledDays":7,"learningSteps":0,"reps":3,"lapses":0,"lastReview":1767225600000},"suspended":false}],
"reviewLog":[{"cardId":"rg:default:ignore-case:cloze","deckId":"rg-default","reviewedAt":1767225600000,
"rating":3,"durationMs":1200,"before":null,"after":{"phase":"learning","due":1767226200000,"stability":2.3,
"difficulty":2.1,"elapsedDays":0,"scheduledDays":0,"learningSteps":1,"reps":1,"lapses":0,"lastReview":1767225600000}}],
"settings":{"desiredRetention":0.85,"flagPairs":false}}''';
    final backup = parseBackup(web);
    expect(backup.cardStates.single.fsrs.phase, CardPhase.review);
    expect(backup.reviewLog.single.rating, Rating.good);
    expect(backup.settings, {'desiredRetention': 0.85, 'flagPairs': false});
    final summary = summarizeBackup(backup);
    expect(summary.reviews, 1);
    expect(jsonDecode(backup.encode())['format'], 'recall-backup');
  });

  test('rejects files that are not backups, with a readable message', () {
    expect(
      () => parseBackup('nope'),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          'This file isn’t valid JSON.',
        ),
      ),
    );
    expect(
      () => parseBackup('{"format":"other"}'),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          'This file isn’t a --recall backup.',
        ),
      ),
    );
    expect(
      () => parseBackup('{"format":"recall-backup","backupVersion":9}'),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('newer version'),
        ),
      ),
    );
  });

  test('backup file name uses the local date', () {
    expect(
      backupFileName(DateTime(2026, 1, 31, 9).millisecondsSinceEpoch),
      'recall-backup-2026-01-31.json',
    );
  });
}
