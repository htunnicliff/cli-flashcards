/// Deck library logic, ported from `src/core/library/index.ts`.
library;

import '../schema/cards.dart';
import '../schema/deck.dart';
import '../schema/manifest.dart';
import 'models.dart';

class ToolDecks {
  const ToolDecks(this.tool, this.variants);
  final String tool;

  /// Every variant in the manifest, sorted by name.
  final List<DeckManifestEntry> variants;
}

/// Groups manifest entries by tool, tools in alphabetical order.
List<ToolDecks> groupByTool(Iterable<DeckManifestEntry> entries) {
  final groups = <String, List<DeckManifestEntry>>{};
  for (final e in entries) {
    (groups[e.tool] ??= []).add(e);
  }
  final tools = groups.keys.toList()..sort();
  return [
    for (final tool in tools)
      ToolDecks(
        tool,
        [...groups[tool]!]..sort((a, b) => a.variant.compareTo(b.variant)),
      ),
  ];
}

/// The variant of a tool that matches a flavor, else its first variant.
String? variantForFlavor(List<String> variants, DeckFlavor flavor) {
  final preferred = flavor == DeckFlavor.bsd
      ? ['bsd', 'macos']
      : ['gnu', 'linux'];
  for (final name in preferred) {
    if (variants.contains(name)) return name;
  }
  return variants.firstOrNull;
}

bool _isGnu(String v) => v == 'gnu' || v == 'linux';
bool _isBsd(String v) => v == 'bsd' || v == 'macos';

/// The flavor to download new tools in: the user's pick, else the one most
/// downloaded decks use, else the platform's.
DeckFlavor resolveFlavor(
  DeckFlavor? chosen,
  Iterable<String> installedVariants,
  DeckFlavor platform,
) {
  if (chosen != null) return chosen;
  final gnu = installedVariants.where(_isGnu).length;
  final bsd = installedVariants.where(_isBsd).length;
  if (gnu != bsd) return gnu > bsd ? DeckFlavor.gnu : DeckFlavor.bsd;
  return platform;
}

bool isUpdateAvailable(int installedVersion, DeckManifestEntry entry) =>
    entry.deckVersion > installedVersion;

class DeckChanges {
  const DeckChanges(this.added, this.removed);
  final List<Option> added;
  final List<Option> removed;
}

/// Visible options added and removed between two versions of a deck.
DeckChanges diffDecks(Deck before, Deck after) {
  Map<String, Option> visible(Deck d) => {
    for (final o in d.options)
      if (!o.hidden) o.id: o,
  };
  final old = visible(before), next = visible(after);
  return DeckChanges(
    [
      for (final o in next.values)
        if (!old.containsKey(o.id)) o,
    ],
    [
      for (final o in old.values)
        if (!next.containsKey(o.id)) o,
    ],
  );
}

/// "2 options added, 1 removed".
String describeChanges(DeckChanges changes) {
  final parts = <String>[];
  final a = changes.added.length, r = changes.removed.length;
  if (a > 0) parts.add('$a option${a == 1 ? '' : 's'} added');
  if (r > 0) {
    parts.add(a > 0 ? '$r removed' : '$r option${r == 1 ? '' : 's'} removed');
  }
  return parts.isEmpty ? 'No options added or removed' : parts.join(', ');
}

enum OptionStatus { newOption, learning, review, suspended }

/// Learning status per option, from its cards' states.
Map<String, OptionStatus> optionStatuses(
  Deck deck,
  Iterable<CardState> states, {
  bool flagPairs = false,
}) {
  final byCard = {for (final s in states) s.cardId: s};
  final cardsByOption = <String, List<String>>{};
  for (final card in deriveCards(deck, flagPairs: flagPairs)) {
    (cardsByOption[card.optionId] ??= []).add(card.id);
  }
  final result = <String, OptionStatus>{};
  for (final option in deck.options) {
    final cards = cardsByOption[option.id] ?? const [];
    final cardStates = [
      for (final id in cards)
        if (byCard[id] != null) byCard[id]!,
    ];
    var status = OptionStatus.newOption;
    bool learningPhase(CardState s) =>
        s.fsrs.phase == CardPhase.learning ||
        s.fsrs.phase == CardPhase.relearning;
    if (cards.isNotEmpty &&
        cardStates.length == cards.length &&
        cardStates.every((s) => s.suspended)) {
      status = OptionStatus.suspended;
    } else if (cardStates.any(learningPhase)) {
      status = OptionStatus.learning;
    } else if (cardStates.any((s) => s.fsrs.phase == CardPhase.review)) {
      status = OptionStatus.review;
    }
    result[option.id] = status;
  }
  return result;
}

/// Flags match by prefix and sort first; everything else by substring.
List<Option> searchOptions(List<Option> options, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [...options];
  final flagHits = <Option>[], textHits = <Option>[];
  for (final option in options) {
    if (option.flags.any((f) => f.toLowerCase().startsWith(q))) {
      flagHits.add(option);
      continue;
    }
    final haystack = [
      option.summary,
      option.argument?.name ?? '',
      option.subcommand ?? '',
      ...option.tags,
      ...option.flags,
    ].join(' ').toLowerCase();
    if (haystack.contains(q)) textHits.add(option);
  }
  return [...flagHits, ...textHits];
}
