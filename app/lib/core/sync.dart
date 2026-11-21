/// Keeps installed decks in line with the published deck list. Ported from
/// `src/app/decks/sync.ts`; see there for the rules.
library;

import '../schema/deck.dart';
import '../schema/manifest.dart';
import 'library.dart';
import 'models.dart';
import 'repository.dart';

/// Where deck files come from: the published site, or the copies bundled
/// with the app.
abstract class DeckSource {
  Future<DeckManifest> manifest();
  Future<Deck> deck(DeckManifestEntry entry);
}

class DeckUpdate {
  const DeckUpdate(this.entry, this.changes);
  final DeckManifestEntry entry;
  final DeckChanges changes;
}

class SyncResult {
  final downloaded = <DeckManifestEntry>[];
  final restored = <PendingDeckInstall>[];
  final updated = <DeckUpdate>[];

  /// Decks swapped for another flavor of the same tool: `from` is removed.
  final switched = <({String from, DeckManifestEntry to})>[];

  /// Deck IDs whose download failed; the next sync tries again.
  final failed = <String>[];

  bool get changed =>
      downloaded.isNotEmpty || updated.isNotEmpty || switched.isNotEmpty;
}

class _Step {
  _Step(
    this.entry, {
    this.includeObscure = false,
    this.paused = false,
    this.typeAnswers = false,
    this.pending,
    this.previous,
    this.replaces,
  });
  final DeckManifestEntry entry;
  final bool includeObscure;
  final bool paused;
  final bool typeAnswers;
  final PendingDeckInstall? pending;
  final StoredDeck? previous;
  final StoredDeck? replaces;
}

/// Downloads every tool with no deck here yet (in the user's flavor),
/// updates decks with a newer version, installs decks a backup queued, and
/// once the user has picked a flavor, swaps decks of the other flavor for it.
Future<SyncResult> syncDecks(
  Repository repository,
  DeckSource source, {
  required DeckFlavor platformFlavor,
  required int Function() now,
  void Function(int done, int total)? onProgress,
}) async {
  final manifest = await source.manifest();
  final installed = await repository.listDecks();
  final settings = await repository.settings();
  final pending = settings.pendingDeckInstalls;
  final chosen = settings.deckFlavor;
  final byId = {for (final d in installed) d.id: d};
  final entries = {for (final e in manifest.decks) e.id: e};
  final flavor = resolveFlavor(chosen, [
    for (final d in installed) d.deck.variant,
  ], platformFlavor);
  final startPaused = installed.any((d) => !d.paused);

  final steps = <_Step>[];
  final extras = <({StoredDeck deck, DeckManifestEntry to})>[];
  final planned = <String>{};
  void plan(_Step step) {
    steps.add(step);
    planned.add(step.entry.id);
  }

  final queued = <PendingDeckInstall>[];
  for (final item in pending) {
    if (byId.containsKey(item.id)) continue;
    queued.add(item);
    final entry = entries[item.id];
    if (entry != null) {
      plan(_Step(entry, includeObscure: item.includeObscure, pending: item));
    }
  }

  for (final group in groupByTool(manifest.decks)) {
    final here = [
      for (final v in group.variants)
        if (byId.containsKey(v.id) || planned.contains(v.id)) v,
    ];
    for (final entry in here) {
      final stored = byId[entry.id];
      if (stored != null && isUpdateAvailable(stored.deckVersion, entry)) {
        plan(
          _Step(
            entry,
            previous: stored,
            includeObscure: stored.includeObscure,
            paused: stored.paused,
            typeAnswers: stored.typeAnswers,
          ),
        );
      }
    }
    final wantedName = variantForFlavor([
      for (final v in group.variants) v.variant,
    ], flavor);
    final wanted = group.variants.firstWhere((v) => v.variant == wantedName);
    if (here.isEmpty) {
      plan(_Step(wanted, paused: startPaused));
    } else if (chosen != null && byId.containsKey(wanted.id)) {
      for (final v in here) {
        final other = byId[v.id];
        if (v.id != wanted.id && other != null) {
          extras.add((deck: other, to: wanted));
        }
      }
    } else if (chosen != null && !here.contains(wanted)) {
      final old = [for (final v in here) byId[v.id]].nonNulls.firstOrNull;
      if (old != null) {
        plan(
          _Step(
            wanted,
            includeObscure: old.includeObscure,
            paused: old.paused,
            typeAnswers: old.typeAnswers,
            replaces: old,
          ),
        );
      }
    }
  }

  final result = SyncResult();
  final restoredIds = <String>{};
  var done = 0;
  onProgress?.call(done, steps.length);
  for (final step in steps) {
    try {
      final deck = await source.deck(step.entry);
      if (deck.id != step.entry.id) {
        throw DeckFormatException(
          '${step.entry.file} contains deck "${deck.id}", not "${step.entry.id}"',
        );
      }
      await repository.installDeck(
        deck,
        now: now(),
        includeObscure: step.includeObscure,
        paused: step.paused,
        typeAnswers: step.typeAnswers,
      );
      if (step.previous != null) {
        result.updated.add(
          DeckUpdate(step.entry, diffDecks(step.previous!.deck, deck)),
        );
      } else {
        result.downloaded.add(step.entry);
      }
      if (step.pending != null) {
        result.restored.add(step.pending!);
        restoredIds.add(step.pending!.id);
      }
      if (step.replaces != null) {
        await repository.removeDeck(step.replaces!.id);
        result.switched.add((from: step.replaces!.id, to: step.entry));
      }
    } catch (_) {
      result.failed.add(step.entry.id);
    } finally {
      onProgress?.call(++done, steps.length);
    }
  }

  for (final extra in extras) {
    await repository.removeDeck(extra.deck.id);
    result.switched.add((from: extra.deck.id, to: extra.to));
  }

  final remaining = [
    for (final item in queued)
      if (!restoredIds.contains(item.id)) item,
  ];
  if (remaining.length != pending.length) {
    await repository.updateSettings(
      (s) => s.copyWith(pendingDeckInstalls: remaining),
    );
  }
  return result;
}

const _flavorLabels = {'gnu': 'GNU / Linux', 'bsd': 'BSD / macOS'};

/// Variant names are implementation families; say where people meet them.
String flavorLabel(String variant) => _flavorLabels[variant] ?? variant;

/// One line for a status message, or null when nothing changed.
String? describeSync(SyncResult result) {
  final parts = <String>[];
  final fresh = [
    for (final d in result.downloaded)
      if (!result.switched.any((s) => s.to.id == d.id)) d,
  ];
  if (fresh.length == 1) parts.add('Downloaded ${fresh.single.tool}.');
  if (fresh.length > 1) parts.add('Downloaded ${fresh.length} decks.');
  if (result.switched.isNotEmpty) {
    final tools = [for (final s in result.switched) s.to.tool];
    final list = tools.length > 1
        ? '${tools.sublist(0, tools.length - 1).join(', ')} and ${tools.last}'
        : tools.single;
    parts.add(
      'Switched $list to ${flavorLabel(result.switched.first.to.variant)}.',
    );
  }
  for (final u in result.updated) {
    parts.add(
      'Updated ${u.entry.tool} to version ${u.entry.deckVersion}: '
      '${describeChanges(u.changes)}.',
    );
  }
  return parts.isEmpty ? null : parts.join(' ');
}
