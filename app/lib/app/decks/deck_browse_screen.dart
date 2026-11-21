/// Browse one deck's options, leeches and suspended cards. Ported from
/// `src/app/views/DeckBrowseView.vue`.
library;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import '../../core/library.dart';
import '../../core/models.dart';
import '../../schema/cards.dart';
import '../../schema/deck.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';

const _tierLabels = {
  Tier.core: 'Core',
  Tier.common: 'Common',
  Tier.obscure: 'Rarely used',
};

const _statusLabels = {
  OptionStatus.newOption: 'New',
  OptionStatus.learning: 'Learning',
  OptionStatus.review: 'Learned',
  OptionStatus.suspended: 'Suspended',
};

const _typeLabels = {
  CardType.flagToMeaning: 'Flag → meaning',
  CardType.meaningToFlag: 'Meaning → flag',
  CardType.cloze: 'Fill in the blank',
  CardType.shortToLong: 'Short → long',
  CardType.longToShort: 'Long → short',
};

class DeckBrowseScreen extends StatefulWidget {
  const DeckBrowseScreen({super.key, required this.deckId, this.openOption});

  final String deckId;

  /// An option to scroll to and expand, such as a leech's.
  final String? openOption;

  @override
  State<DeckBrowseScreen> createState() => _DeckBrowseScreenState();
}

class _DeckBrowseScreenState extends State<DeckBrowseScreen> {
  Deck? _deck;
  bool _installed = false;
  bool _loading = true;
  String? _error;
  List<CardState> _states = const [];
  String _query = '';
  String? _open;
  int _revision = -1;
  final _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _open = widget.openOption;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (app.revision != _revision) {
      _revision = app.revision;
      _load(app);
    }
  }

  Future<void> _load(AppController app) async {
    try {
      final stored = await app.repository.getDeck(widget.deckId);
      Deck? deck = stored?.deck;
      if (deck == null) {
        final entry = app.manifest?.decks
            .where((e) => e.id == widget.deckId)
            .firstOrNull;
        if (entry != null) deck = await app.source.deck(entry);
      }
      final states = await app.repository.cardStatesForDeck(widget.deckId);
      if (!mounted) return;
      setState(() {
        _deck = deck;
        _installed = stored != null;
        _states = states;
        _loading = false;
      });
      if (_open != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(_open!));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _scrollTo(String optionId) {
    final ctx = _keys[optionId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.1,
      );
    }
  }

  Future<void> _unsuspend(List<String> ids) async {
    final app = AppScope.read(context);
    await app.scheduler.unsuspend(ids);
    app.progressChanged();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final f = Frost.of(context);
    final deck = _deck;
    final back = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => context.go('/decks'),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('All decks'),
      ),
    );
    if (deck == null) {
      return PageBody(
        children: [
          back,
          if (_error != null)
            Text(_error!, style: TextStyle(color: f.again))
          else if (_loading)
            Text('Loading…', style: context.hint)
          else
            Text(
              'Deck not found',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
        ],
      );
    }

    final visible = [
      for (final o in deck.options)
        if (!o.hidden) o,
    ];
    final results = searchOptions(visible, _query);
    final statuses = optionStatuses(
      deck,
      _states,
      flagPairs: app.settings.flagPairs,
    );
    final optionsById = {for (final o in deck.options) o.id: o};
    final cards = {for (final c in deriveCards(deck, flagPairs: true)) c.id: c};
    final live = [
      for (final s in _states)
        if (cards.containsKey(s.cardId) && optionsById.containsKey(s.optionId))
          (state: s, option: optionsById[s.optionId]!, card: cards[s.cardId]!),
    ];
    final leeches = [
      for (final l in live)
        if (l.state.leech) l,
    ];
    final suspended = [
      for (final l in live)
        if (l.state.suspended && !l.state.leech) l,
    ];

    Widget flagCode(Option o) => Text(
      answerFlags(o).first,
      style: weight(context.mono.copyWith(color: f.accent), FontWeight.w600),
    );

    return PageBody(
      children: [
        back,
        const SizedBox(height: Space.s2),
        Semantics(
          header: true,
          child: Text.rich(
            TextSpan(
              style: weight(
                context.mono.copyWith(fontSize: TextSizes.x2l),
                FontWeight.w700,
              ),
              children: [
                TextSpan(text: '${deck.tool} '),
                TextSpan(
                  text: deck.variant,
                  style: TextStyle(color: f.muted, fontSize: TextSizes.lg),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.s1),
        Text(
          '${visible.length} options · ${deck.tool} ${deck.toolVersion} · '
          'deck v${deck.deckVersion}${_installed ? '' : ' · not downloaded yet'}',
          style: context.hint,
        ),
        if (leeches.isNotEmpty)
          Section(
            title: 'Leeches',
            children: [
              Text(
                "These cards keep slipping away. Try rewriting the meaning in your "
                "own words: read the full description, then picture when you'd use "
                'the flag.',
                style: context.hint,
              ),
              const SizedBox(height: Space.s2),
              for (final l in leeches)
                _SetAsideRow(
                  flag: flagCode(l.option),
                  detail:
                      '${_typeLabels[l.card.type]} · forgotten ${l.state.fsrs.lapses} times',
                  actions: [
                    TextButton(
                      onPressed: () {
                        setState(() => _open = l.option.id);
                        _scrollTo(l.option.id);
                      },
                      child: const Text('Full description'),
                    ),
                    if (l.state.suspended)
                      FrostButton(
                        onPressed: () => _unsuspend([l.state.cardId]),
                        child: const Text('Unsuspend'),
                      ),
                  ],
                ),
            ],
          ),
        if (suspended.isNotEmpty)
          Section(
            title: 'Suspended',
            children: [
              for (final l in suspended)
                _SetAsideRow(
                  flag: flagCode(l.option),
                  detail: _typeLabels[l.card.type]!,
                  actions: [
                    FrostButton(
                      onPressed: () => _unsuspend([l.state.cardId]),
                      child: const Text('Unsuspend'),
                    ),
                  ],
                ),
              if (suspended.length > 1)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FrostButton(
                    onPressed: () =>
                        _unsuspend([for (final l in suspended) l.state.cardId]),
                    child: const Text('Unsuspend all'),
                  ),
                ),
            ],
          ),
        const SizedBox(height: Space.s6),
        TextField(
          style: context.mono,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            hintText: 'Search flags or descriptions…',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: Space.s2),
        Semantics(
          liveRegion: true,
          child: Text(
            results.length == visible.length
                ? '${visible.length} options'
                : '${results.length} of ${visible.length} options',
            style: context.hint,
          ),
        ),
        const SizedBox(height: Space.s4),
        for (final o in results)
          Padding(
            key: _keys.putIfAbsent(o.id, GlobalKey.new),
            padding: const EdgeInsets.only(bottom: Space.s3),
            child: _OptionTile(
              option: o,
              status: _installed ? statuses[o.id] : null,
              open: _open == o.id,
            ),
          ),
      ],
    );
  }
}

class _SetAsideRow extends StatelessWidget {
  const _SetAsideRow({
    required this.flag,
    required this.detail,
    required this.actions,
  });

  final Widget flag;
  final String detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Wrap(
        spacing: Space.s3,
        runSpacing: Space.s1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          flag,
          Text(detail, style: context.hint),
          ...actions,
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.status,
    required this.open,
  });

  final Option option;
  final OptionStatus? status;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final flags = answerFlags(option);
    final arg = option.argument;
    final hasDetail =
        option.description.isNotEmpty && option.description != option.summary;
    return Glass(
      padding: const EdgeInsets.all(Space.s4),
      radius: Radii.button,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.s3,
            runSpacing: Space.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                flags.first,
                style: weight(
                  context.mono.copyWith(color: f.accent),
                  FontWeight.w600,
                ),
              ),
              for (final flag in flags.skip(1))
                Text(flag, style: context.mono.copyWith(color: f.muted)),
              if (arg != null)
                Text(
                  arg.optional ? '[${arg.name}]' : arg.name,
                  style: context.monoCasual,
                ),
              if (option.subcommand != null)
                FrostChip(option.subcommand!, mono: true),
              FrostChip(_tierLabels[option.tier]!),
              if (status != null)
                FrostChip(
                  _statusLabels[status]!,
                  color: status == OptionStatus.review ? f.accent : null,
                ),
            ],
          ),
          const SizedBox(height: Space.s2),
          Text(option.summary),
          if (hasDetail)
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: open,
                tilePadding: EdgeInsets.zero,
                expandedAlignment: Alignment.centerLeft,
                title: Text(
                  'Full description',
                  style: Theme.of(context).textTheme.labelLarge!
                      .copyWith(color: f.accent),
                ),
                children: [
                  SelectableText(option.description, style: context.hint),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
