/// The Decks page, ported from `src/app/views/DecksView.vue`. Decks download
/// on their own; this lists them and keeps each deck's settings.
library;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/library.dart';
import '../../core/models.dart';
import '../../core/sync.dart';
import '../../schema/deck.dart';
import '../../schema/manifest.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class ToolRow {
  const ToolRow(this.tool, this.variants, this.entry, this.stored);
  final String tool;
  final List<DeckManifestEntry> variants;

  /// The deck in use, or the one that will download.
  final DeckManifestEntry entry;
  final StoredDeck? stored;
  bool get studying => stored != null && !stored!.paused;
}

/// Studied tools first, then downloaded ones, then by name.
List<ToolRow> toolRows(AppController app) {
  final byId = {for (final d in app.decks) d.id: d};
  final flavor = resolveFlavor(app.settings.deckFlavor, [
    for (final d in app.decks) d.deck.variant,
  ], app.flavor ?? platformFlavor);
  final rows = [
    for (final group in groupByTool(app.manifest?.decks ?? const []))
      () {
        final wanted = variantForFlavor([
          for (final v in group.variants) v.variant,
        ], flavor);
        final here = [
          for (final v in group.variants)
            if (byId.containsKey(v.id)) v,
        ];
        final entry =
            here.where((v) => v.variant == wanted).firstOrNull ??
            here.firstOrNull ??
            group.variants.firstWhere((v) => v.variant == wanted);
        return ToolRow(group.tool, group.variants, entry, byId[entry.id]);
      }(),
  ];
  int rank(ToolRow r) => r.studying ? 0 : (r.stored != null ? 1 : 2);
  rows.sort((a, b) {
    final d = rank(a) - rank(b);
    return d != 0 ? d : a.tool.compareTo(b.tool);
  });
  return rows;
}

/// "255 options, starting with the 19 most used".
String sizeSummary(DeckManifestEntry entry) {
  final core = entry.tiers[Tier.core] ?? 0;
  if (core == 0 || core >= entry.optionCount) {
    return '${entry.optionCount} options';
  }
  return '${entry.optionCount} options, starting with the $core most used';
}

class DecksScreen extends StatefulWidget {
  const DecksScreen({super.key});

  @override
  State<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends State<DecksScreen> {
  String? _status;
  String? _justStarted;
  String? _confirmingReset;

  @override
  void initState() {
    super.initState();
    // Opening Decks checks for new and updated decks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).syncDecks().ignore();
    });
  }

  Future<void> _toggleStudy(ToolRow row, bool on) async {
    await AppScope.read(context).setDeckPrefs(row.entry.id, paused: !on);
    setState(() {
      _justStarted = on ? row.tool : null;
      _status = on
          ? 'Studying ${row.tool}.'
          : 'Paused ${row.tool}. Its progress is kept.';
    });
  }

  Future<void> _reset(ToolRow row) async {
    setState(() => _confirmingReset = null);
    await AppScope.read(context).resetProgress(row.entry.id);
    setState(() => _status = 'Reset your progress on ${row.tool}.');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final f = Frost.of(context);
    final rows = toolRows(app);
    final flavored = [
      for (final r in rows)
        if (r.variants.length > 1) r.tool,
    ];
    final flavor = resolveFlavor(app.settings.deckFlavor, [
      for (final d in app.decks) d.deck.variant,
    ], app.flavor ?? platformFlavor);
    final status = _status ?? app.syncMessage;
    return PageBody(
      children: [
        Semantics(
          header: true,
          child: Text(
            'Decks',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: Space.s2),
        Text(
          'Every deck downloads on its own and works offline. Turn on the ones '
          'you want to study.',
          style: context.casual,
        ),
        if (flavored.isNotEmpty) ...[
          const SizedBox(height: Space.s6),
          Text('Flavor', style: context.hint),
          const SizedBox(height: Space.s2),
          Align(
            alignment: Alignment.centerLeft,
            child: Segmented<DeckFlavor>(
              values: DeckFlavor.values,
              selected: flavor,
              label: (v) => flavorLabel(v.name),
              onChanged: !app.online || app.sync.running
                  ? null
                  : (v) => app.setDeckFlavor(v),
            ),
          ),
          const SizedBox(height: Space.s2),
          Text(
            'For ${listOf(flavored)}, whose flags differ.',
            style: context.hint,
          ),
        ],
        if (app.sync.running && app.sync.total > 0) ...[
          const SizedBox(height: Space.s4),
          Text(
            'Downloading decks… ${app.sync.done} of ${app.sync.total}',
            style: context.hint,
          ),
          const SizedBox(height: Space.s2),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: app.sync.done / app.sync.total),
              duration: const Duration(milliseconds: 250),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: f.sunken,
                color: f.accent,
                semanticsLabel: 'Downloading decks',
              ),
            ),
          ),
        ],
        if (status != null || _justStarted != null) ...[
          const SizedBox(height: Space.s4),
          Semantics(
            liveRegion: true,
            child: Wrap(
              spacing: Space.s3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (status != null) Text(status),
                if (_justStarted != null)
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Start reviewing'),
                  ),
              ],
            ),
          ),
        ],
        if (!app.online) ...[
          const SizedBox(height: Space.s3),
          Text(
            "You're offline. Downloaded decks still work; new decks and updates "
            "download when you're back online.",
            style: context.hint,
          ),
        ],
        if (app.syncError != null) ...[
          const SizedBox(height: Space.s3),
          Text(app.syncError!, style: TextStyle(color: f.again)),
        ],
        const SizedBox(height: Space.s6),
        if (rows.isEmpty) Text('Loading decks…', style: context.hint),
        for (final row in rows) ...[
          _DeckTile(
            row: row,
            online: app.online,
            confirmingReset: _confirmingReset == row.entry.id,
            onStudy: (v) => _toggleStudy(row, v),
            onObscure: (v) => app.setDeckPrefs(row.entry.id, includeObscure: v),
            onTyped: (v) => app.setDeckPrefs(row.entry.id, typeAnswers: v),
            onAskReset: () => setState(() => _confirmingReset = row.entry.id),
            onCancelReset: () => setState(() => _confirmingReset = null),
            onReset: () => _reset(row),
          ),
          const SizedBox(height: Space.s4),
        ],
      ],
    );
  }
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({
    required this.row,
    required this.online,
    required this.confirmingReset,
    required this.onStudy,
    required this.onObscure,
    required this.onTyped,
    required this.onAskReset,
    required this.onCancelReset,
    required this.onReset,
  });

  final ToolRow row;
  final bool online;
  final bool confirmingReset;
  final ValueChanged<bool> onStudy;
  final ValueChanged<bool> onObscure;
  final ValueChanged<bool> onTyped;
  final VoidCallback onAskReset;
  final VoidCallback onCancelReset;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final stored = row.stored;
    return Glass(
      padding: const EdgeInsets.all(Space.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.s3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                header: true,
                child: Text(
                  row.tool,
                  style: weight(
                    context.mono.copyWith(fontSize: TextSizes.xl),
                    FontWeight.w700,
                  ),
                ),
              ),
              if (stored?.paused ?? false) const FrostChip('Paused'),
              if (stored == null)
                FrostChip(
                  online ? 'Downloading soon' : 'Downloads when online',
                ),
            ],
          ),
          const SizedBox(height: Space.s1),
          Text(
            [
              if (row.variants.length > 1) flavorLabel(row.entry.variant),
              sizeSummary(row.entry),
            ].join(' · '),
            style: context.hint,
          ),
          if (stored != null) ...[
            const SizedBox(height: Space.s2),
            CheckRow(
              label: 'Study this deck',
              strong: true,
              value: !stored.paused,
              onChanged: onStudy,
            ),
            CheckRow(
              label: 'Include rarely used flags',
              value: stored.includeObscure,
              onChanged: onObscure,
            ),
            CheckRow(
              label: 'Type answers',
              value: stored.typeAnswers,
              onChanged: onTyped,
            ),
          ],
          const SizedBox(height: Space.s3),
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              FrostButton(
                onPressed: () => context.go('/decks/${row.entry.id}'),
                child: const Text('Browse options'),
              ),
              if (stored != null && !confirmingReset)
                FrostButton(
                  onPressed: onAskReset,
                  child: const Text('Reset progress'),
                ),
            ],
          ),
          if (confirmingReset) ...[
            const SizedBox(height: Space.s3),
            Text(
              'Reset your progress on ${row.tool}? Its cards start over as new.',
            ),
            const SizedBox(height: Space.s2),
            Wrap(
              spacing: Space.s2,
              children: [
                FrostButton(
                  variant: ButtonVariant.again,
                  onPressed: onReset,
                  child: const Text('Reset progress'),
                ),
                FrostButton(
                  onPressed: onCancelReset,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
