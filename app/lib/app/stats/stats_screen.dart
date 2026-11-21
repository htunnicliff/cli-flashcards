/// The Stats page, ported from `src/app/views/StatsView.vue`.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/stats.dart';
import '../app_state.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_weekdays[d.weekday - 1]} ${_months[d.month - 1]} ${d.day}';
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Stats? _stats;
  int _revision = -1;

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
    final decks = await app.repository.listDecks();
    final states = await app.repository.allCardStates();
    final log = await app.repository.allReviews();
    final settings = await app.repository.settings();
    if (!mounted) return;
    setState(() {
      _stats = computeStats(
        decks: decks,
        states: states,
        log: log,
        now: app.now(),
        rolloverHour: settings.dayRolloverHour,
        flagPairs: settings.flagPairs,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final app = AppScope.of(context);
    final names = {for (final d in app.decks) d.id: d.deck.tool};
    return PageBody(
      children: [
        Semantics(
          header: true,
          child: Text(
            'Stats',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: Space.s6),
        if (stats == null)
          Text('Adding things up…', style: context.hint)
        else ...[
          LayoutBuilder(
            builder: (context, c) {
              final tiles = [
                _Tile(
                  label: 'Reviews today',
                  value: stats.reviewsToday.toDouble(),
                ),
                _Tile(label: 'Day streak', value: stats.streak.toDouble()),
                _Tile(
                  label: 'Retention, 30 days',
                  value: stats.retention.rate,
                  percent: true,
                  note: stats.retention.total > 0
                      ? '${stats.retention.passed} of ${stats.retention.total} mature reviews passed'
                      : 'No mature cards reviewed yet',
                ),
              ];
              if (c.maxWidth < 520) {
                return Column(
                  children: [
                    for (final t in tiles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.s3),
                        child: SizedBox(width: double.infinity, child: t),
                      ),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, t) in tiles.indexed) ...[
                      if (i > 0) const SizedBox(width: Space.s3),
                      Expanded(child: t),
                    ],
                  ],
                ),
              );
            },
          ),
          Section(
            title: 'Due forecast',
            children: [Glass(child: _ForecastChart(stats.forecast))],
          ),
          Section(
            title: 'Past year',
            children: [Glass(child: _Heatmap(stats.history))],
          ),
          Section(
            title: 'Cards',
            children: [
              if (stats.cards.isEmpty)
                Text('Study a deck to see its cards here.', style: context.hint)
              else
                Glass(
                  padding: const EdgeInsets.all(Space.s4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingTextStyle: weight(
                        Theme.of(context).textTheme.labelMedium!,
                        FontWeight.w600,
                      ),
                      columnSpacing: Space.s6,
                      columns: const [
                        DataColumn(label: Text('Deck')),
                        DataColumn(label: Text('New'), numeric: true),
                        DataColumn(label: Text('Learning'), numeric: true),
                        DataColumn(label: Text('Learned'), numeric: true),
                        DataColumn(label: Text('Suspended'), numeric: true),
                      ],
                      rows: [
                        for (final d in stats.cards)
                          DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  names[d.deckId] ?? d.deckId,
                                  style: context.mono,
                                ),
                              ),
                              DataCell(Text('${d.newCards}')),
                              DataCell(Text('${d.learning}')),
                              DataCell(Text('${d.review}')),
                              DataCell(Text('${d.suspended}')),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.percent = false,
    this.note,
  });

  final String label;
  final double? value;
  final bool percent;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final big = weight(
      context.mono.copyWith(fontSize: TextSizes.x2l),
      FontWeight.w700,
    );
    String format(double v) =>
        percent ? '${(v * 100).round()}%' : '${v.round()}';
    return MergeSemantics(
      child: Glass(
        padding: const EdgeInsets.all(Space.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (value == null)
              Text('–', style: big)
            else
              TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: reducedMotion(context) ? value : 0,
                  end: value,
                ),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) =>
                    Text(format(v), style: big, semanticsLabel: format(value!)),
              ),
            Text(label, style: context.hint),
            if (note != null)
              Text(note!, style: context.hint.copyWith(fontSize: TextSizes.xs)),
          ],
        ),
      ),
    );
  }
}

class _ForecastChart extends StatelessWidget {
  const _ForecastChart(this.days);
  final List<DayCount> days;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final max = days.fold(0, (m, d) => math.max(m, d.count));
    final total = days.fold(0, (s, d) => s + d.count);
    if (total == 0) {
      return Text('Nothing is due in the next 30 days.', style: context.hint);
    }
    return Semantics(
      label:
          'Due forecast: $total reviews over 30 days, ${days.first.count} today, busiest day $max.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, d) in days.indexed)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${i == 0 ? 'Today' : _date(d.day)}: ${d.count} due',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0,
                            end: max == 0 ? 0 : d.count / max,
                          ),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          builder: (context, h, _) => FractionallySizedBox(
                            heightFactor: math.max(
                              h,
                              d.count > 0 ? 0.03 : 0.01,
                            ),
                            alignment: Alignment.bottomCenter,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: d.count == 0
                                    ? f.sunken
                                    : i == 0
                                    ? f.accent
                                    : f.accent.withValues(alpha: 0.55),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.s2),
          Row(
            children: [
              Text(
                'Today',
                style: context.hint.copyWith(fontSize: TextSizes.xs),
              ),
              const Spacer(),
              Text(
                'In 30 days',
                style: context.hint.copyWith(fontSize: TextSizes.xs),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap(this.days);
  final List<DayCount> days;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final max = days.fold(0, (m, d) => math.max(m, d.count));
    final total = days.fold(0, (s, d) => s + d.count);
    final active = days.where((d) => d.count > 0).length;
    // Columns are weeks, Monday first; pad the first week.
    final firstWeekday = DateTime.fromMillisecondsSinceEpoch(days.first.day)
        .weekday;
    final cells = <DayCount?>[
      for (var i = 1; i < firstWeekday; i++) null,
      ...days,
    ];
    final weeks = (cells.length / 7).ceil();
    Color shade(int level) => switch (level) {
      0 => f.sunken,
      1 => f.accent.withValues(alpha: 0.3),
      2 => f.accent.withValues(alpha: 0.5),
      3 => f.accent.withValues(alpha: 0.75),
      _ => f.accent,
    };
    return Semantics(
      label: '$total reviews on $active days in the past year.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              children: [
                for (var w = 0; w < weeks; w++)
                  Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        () {
                          final i = w * 7 + d;
                          final cell = i < cells.length ? cells[i] : null;
                          return Tooltip(
                            message: cell == null
                                ? ''
                                : '${_date(cell.day)}: ${cell.count} reviews',
                            child: Container(
                              width: 11,
                              height: 11,
                              margin: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                color: cell == null
                                    ? Colors.transparent
                                    : shade(heatLevel(cell.count, max)),
                                borderRadius: BorderRadius.circular(2.5),
                              ),
                            ),
                          );
                        }(),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.s2),
          Text(
            '$total reviews on $active days',
            style: context.hint.copyWith(fontSize: TextSizes.xs),
          ),
        ],
      ),
    );
  }
}
