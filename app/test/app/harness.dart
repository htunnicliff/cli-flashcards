import 'dart:convert';
import 'dart:io';

import 'package:cliflashcards/app/app_state.dart';
import 'package:cliflashcards/app/router.dart';
import 'package:cliflashcards/core/models.dart';
import 'package:cliflashcards/core/sync.dart';
import 'package:cliflashcards/main.dart';
import 'package:cliflashcards/schema/deck.dart';
import 'package:cliflashcards/schema/manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../core/helpers.dart';

/// Reads the built decks from disk, or fails like a network outage.
class FileDeckSource implements DeckSource, OnlineAware {
  FileDeckSource({this.only, this.offline = false});

  /// Deck IDs to list; all when null.
  final Set<String>? only;
  bool offline;

  @override
  bool get online => !offline;

  Map<String, dynamic> _read(String file) =>
      jsonDecode(File('assets/decks/$file').readAsStringSync())
          as Map<String, dynamic>;

  @override
  Future<DeckManifest> manifest() async {
    if (offline) throw const SocketException('offline');
    final m = DeckManifest.fromJson(_read('index.json'));
    return DeckManifest([
      for (final e in m.decks)
        if (only == null || only!.contains(e.id)) e,
    ]);
  }

  @override
  Future<Deck> deck(DeckManifestEntry entry) async {
    if (offline) throw const SocketException('offline');
    return Deck.fromJson(_read(entry.file));
  }
}

/// A fixed clock: 2026-03-02 12:00 local, advanced by tests.
class Clock {
  int now = noon;
}

Future<AppController> startApp(
  WidgetTester tester, {
  FileDeckSource? source,
  bool tour = false,
  Settings Function(Settings)? settings,
  Clock? clock,
  String location = '/',
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = await tester.runAsync(memoryRepository);
  final time = clock ?? Clock();
  final app = AppController(
    repository: repo!,
    source: source ?? FileDeckSource(only: {'rg-default', 'grep-gnu'}),
    clock: () => time.now,
    flavor: DeckFlavor.gnu,
  );
  await tester.runAsync(() async {
    await repo.updateSettings(
      (s) => (settings ?? (s) => s)(s.copyWith(onboardingDone: !tour)),
    );
    await app.load();
    await app.syncDecks().catchError((_) => SyncResult());
  });
  await tester.pumpWidget(
    CliFlashcardsApp(
      controller: app,
      router: buildRouter(initialLocation: location),
    ),
  );
  await settle(tester);
  return app;
}

/// Lets storage work (real async) finish, then settles animations.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }
}
