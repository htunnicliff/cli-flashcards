import 'package:cliflashcards/core/backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

void main() {
  testWidgets('Decks lists downloaded decks and pauses one', (tester) async {
    final app = await startApp(tester, location: '/decks');
    expect(find.text('rg'), findsOneWidget);
    expect(find.text('grep'), findsOneWidget);
    expect(find.text('Study this deck'), findsNWidgets(2));
    await tester.tap(find.text('Study this deck').first);
    await settle(tester);
    expect(app.decks.where((d) => d.paused), hasLength(1));
    expect(find.textContaining('Its progress is kept'), findsOneWidget);
  });

  testWidgets('browsing a deck searches its options', (tester) async {
    await startApp(tester, location: '/decks/rg-default');
    expect(find.textContaining('options · rg'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '--ignore-case');
    await settle(tester);
    expect(find.textContaining(RegExp(r'^1 of \d+ options$')), findsOneWidget);
  });

  testWidgets('Stats adds things up', (tester) async {
    await startApp(tester, location: '/stats');
    expect(find.text('Reviews today'), findsOneWidget);
    expect(find.text('Due forecast'), findsOneWidget);
    expect(find.text('Past year'), findsOneWidget);
  });

  testWidgets('Settings saves scheduling and appearance', (tester) async {
    final app = await startApp(tester, location: '/settings');
    await tester.tap(find.text('Dark'));
    await settle(tester);
    expect(app.settings.theme.name, 'dark');
    await tester.enterText(find.byType(TextField).first, '35');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(app.settings.newCardsPerDay, 35);
    expect(find.text('Export backup'), findsOneWidget);
  });

  testWidgets('offline first launch still has decks', (tester) async {
    final app = await startApp(tester, source: FileDeckSource(offline: true));
    expect(app.online, isFalse);
    expect(app.decks, isEmpty);
    expect(find.text('No decks yet'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
  });

  test('backup file names', () {
    expect(
      backupFileName(DateTime(2026, 5, 4).millisecondsSinceEpoch),
      'recall-backup-2026-05-04.json',
    );
  });
}
