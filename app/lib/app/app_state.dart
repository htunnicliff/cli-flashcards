/// App-wide state: storage, settings, installed decks and deck syncing.
/// Screens read it through [AppScope] and rebuild when it changes.
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../core/repository.dart';
import '../core/scheduler.dart';
import '../core/sync.dart';
import '../schema/deck.dart';
import '../schema/manifest.dart';

/// BSD on Apple platforms, GNU elsewhere (the flavor of the tools people have).
DeckFlavor get platformFlavor => switch (defaultTargetPlatform) {
  TargetPlatform.iOS || TargetPlatform.macOS => DeckFlavor.bsd,
  _ => DeckFlavor.gnu,
};

class SyncProgress {
  const SyncProgress({this.running = false, this.done = 0, this.total = 0});
  final bool running;
  final int done;
  final int total;
}

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.source,
    int Function()? clock,
    this.flavor,
  }) : now = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       scheduler = Scheduler(repository);

  final Repository repository;
  final Scheduler scheduler;
  final DeckSource source;
  final int Function() now;

  /// Overrides [platformFlavor], for tests.
  final DeckFlavor? flavor;

  Settings settings = const Settings();
  List<StoredDeck> decks = const [];
  DeckManifest? manifest;
  bool loaded = false;

  /// False once the deck list couldn't be reached.
  bool online = true;
  SyncProgress sync = const SyncProgress();

  /// The most recent sync's summary, for the Decks page.
  String? syncMessage;

  /// Why the last sync couldn't finish, if it couldn't.
  String? syncError;

  /// Bumps whenever stored decks or progress change outside a screen, so
  /// screens that loaded data reload it.
  int revision = 0;

  /// Whether the welcome tour should open.
  bool tourOpen = false;

  /// True when Settings replayed the tour.
  bool tourReplay = false;

  Future<SyncResult>? _syncing;

  Future<void> load() async {
    settings = await repository.settings();
    decks = await repository.listDecks();
    loaded = true;
    if (!settings.onboardingDone) {
      if (await repository.reviewCount() > 0) {
        settings = await repository.updateSettings(
          (s) => s.copyWith(onboardingDone: true),
        );
      } else {
        tourOpen = true;
      }
    }
    notifyListeners();
  }

  Future<void> reloadDecks() async {
    decks = await repository.listDecks();
    revision++;
    notifyListeners();
  }

  Future<void> updateSettings(Settings Function(Settings) change) async {
    settings = await repository.updateSettings(change);
    revision++;
    notifyListeners();
  }

  /// Downloads and updates decks. Concurrent calls share one run.
  Future<SyncResult> syncDecks() => _syncing ??= _sync().whenComplete(() {
    _syncing = null;
  });

  /// Like [syncDecks], but never joins a run that started before a change.
  Future<SyncResult> syncAfterChange() async {
    await _syncing?.catchError((_) => SyncResult());
    return syncDecks();
  }

  Future<SyncResult> _sync() async {
    sync = const SyncProgress(running: true);
    notifyListeners();
    try {
      final result = await syncDecksWith(
        repository,
        _ManifestTap(source, (m, isOnline) {
          manifest = m;
          online = isOnline;
        }),
        platformFlavor: flavor ?? platformFlavor,
        now: now,
        onProgress: (done, total) {
          sync = SyncProgress(running: true, done: done, total: total);
          notifyListeners();
        },
      );
      syncMessage = describeSync(result) ?? syncMessage;
      syncError = result.failed.isNotEmpty && online
          ? "Couldn't download ${result.failed.join(', ')}. The app will try again later."
          : null;
      settings = await repository.settings();
      if (result.changed) {
        decks = await repository.listDecks();
        revision++;
      }
      return result;
    } catch (e) {
      online = false;
      syncError = "Couldn't load the deck list. The app will try again later.";
      rethrow;
    } finally {
      sync = const SyncProgress();
      notifyListeners();
    }
  }

  Future<void> setDeckFlavor(DeckFlavor flavor) async {
    await updateSettings((s) => s.copyWith(deckFlavor: () => flavor));
    await syncAfterChange();
  }

  Future<void> setDeckPrefs(
    String id, {
    bool? includeObscure,
    bool? paused,
    bool? typeAnswers,
  }) async {
    await repository.updateDeck(
      id,
      includeObscure: includeObscure,
      paused: paused,
      typeAnswers: typeAnswers,
    );
    await reloadDecks();
  }

  Future<void> resetProgress([String? deckId]) async {
    await repository.resetProgress(deckId);
    revision++;
    notifyListeners();
  }

  /// Called after something changed progress wholesale (a backup import).
  void progressChanged() {
    revision++;
    notifyListeners();
  }

  void startTour() {
    tourReplay = true;
    tourOpen = true;
    notifyListeners();
  }

  Future<void> finishTour() async {
    tourOpen = false;
    notifyListeners();
    await updateSettings((s) => s.copyWith(onboardingDone: true));
  }
}

/// Indirection so tests can swap the sync function.
Future<SyncResult> Function(
  Repository,
  DeckSource, {
  required DeckFlavor platformFlavor,
  required int Function() now,
  void Function(int, int)? onProgress,
})
syncDecksWith = syncDecks;

/// Reports which manifest a sync used, and whether it came from the network.
class _ManifestTap implements DeckSource {
  _ManifestTap(this.inner, this.onManifest);
  final DeckSource inner;
  final void Function(DeckManifest, bool online) onManifest;

  @override
  Future<DeckManifest> manifest() async {
    final m = await inner.manifest();
    final source = inner;
    final isOnline = source is OnlineAware
        ? (source as OnlineAware).online
        : true;
    onManifest(m, isOnline);
    return m;
  }

  @override
  Future<Deck> deck(DeckManifestEntry entry) => inner.deck(entry);
}

/// A source that knows whether it reached the network.
abstract interface class OnlineAware {
  bool get online;
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Without subscribing to changes, for callbacks.
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Runs [work] and reports failures in a snackbar.
Future<void> guarded(BuildContext context, Future<void> Function() work) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await work();
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('$e')));
  }
}
