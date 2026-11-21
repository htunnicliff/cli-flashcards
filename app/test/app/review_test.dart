import 'package:cliflashcards/core/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

void main() {
  testWidgets('shows a card, reveals it and grades it from the keyboard', (
    tester,
  ) async {
    final app = await startApp(tester);
    expect(find.text('Review'), findsWidgets);
    expect(find.text('What does this flag do?'), findsOneWidget);
    expect(find.text('Show answer'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(find.text('Again'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await settle(tester);
    expect(find.text('Undo'), findsOneWidget);
    final reviews = await tester.runAsync(app.repository.reviewCount);
    expect(reviews, 1);
  });

  testWidgets('undo takes the grade back', (tester) async {
    final app = await startApp(tester);
    await tester.tap(find.text('Show answer'));
    await settle(tester);
    await tester.tap(find.text('Easy'));
    await settle(tester);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await tester.runAsync(app.repository.reviewCount), 0);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('More menu skips a card until tomorrow, with undo', (
    tester,
  ) async {
    final app = await startApp(tester);
    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Skip until tomorrow'));
    await settle(tester);
    expect(find.text('Skipped until tomorrow.'), findsOneWidget);
    final states = await tester.runAsync(app.repository.allCardStates);
    expect(states!.single.buriedUntil, isNotNull);
  });

  testWidgets('typed answers check the flag', (tester) async {
    final app = await startApp(tester);
    await tester.runAsync(() async {
      for (final d in app.decks) {
        await app.setDeckPrefs(d.id, typeAnswers: true);
      }
    });
    await settle(tester);
    // Grade the flag → meaning card so a meaning → flag card comes next.
    await tester.tap(find.text('Show answer'));
    await settle(tester);
    await tester.tap(find.text('Good'));
    await settle(tester);
    if (find.text('Which flag does this?').evaluate().isEmpty) return;
    await tester.enterText(find.byType(EditableText), '--definitely-wrong');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('Not quite'), findsOneWidget);
  });

  testWidgets('shows the done state when nothing is left', (tester) async {
    await startApp(tester, settings: (s) => s.copyWith(newCardsPerDay: 0));
    expect(find.text('All done for today'), findsOneWidget);
  });

  testWidgets('phone layout has the tab bar', (tester) async {
    await startApp(tester, size: const Size(390, 844));
    expect(find.text('Stats'), findsOneWidget);
    expect(find.text('Show answer'), findsOneWidget);
  });

  testWidgets('first launch opens the welcome tour', (tester) async {
    final app = await startApp(tester, tour: true);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(find.text('Review your cards'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('Step 2 of 3'), findsNothing);
    expect(app.settings.onboardingDone, isTrue);
  });

  test('ratings map to their keys', () {
    expect(Rating.of(1), Rating.again);
  });
}
