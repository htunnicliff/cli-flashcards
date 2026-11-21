import 'package:cliflashcards/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lists the bundled decks', (tester) async {
    await tester.pumpWidget(const CliFlashcardsApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('rg'), findsWidgets);
  });
}
