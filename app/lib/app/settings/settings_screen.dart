/// The Settings page, ported from `src/app/views/SettingsView.vue` and the
/// settings components.
library;

import 'package:material_ui/material_ui.dart';

import '../../core/backup.dart';
import '../../core/models.dart';
import '../../core/setting_limits.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'backup_files.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    return PageBody(
      children: [
        Semantics(
          header: true,
          child: Text(
            'Settings',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        _Choice<AppTheme>(
          title: 'Theme',
          values: AppTheme.values,
          selected: s.theme,
          label: (v) => switch (v) {
            AppTheme.system => 'System',
            AppTheme.light => 'Light',
            AppTheme.dark => 'Dark',
          },
          hint: "System follows your device's light or dark setting.",
          onChanged: (v) => app.updateSettings((s) => s.copyWith(theme: v)),
        ),
        _Choice<TextSize>(
          title: 'Text size',
          values: TextSize.values,
          selected: s.textSize,
          label: (v) => switch (v) {
            TextSize.s => 'Small',
            TextSize.m => 'Medium',
            TextSize.l => 'Large',
          },
          onChanged: (v) => app.updateSettings((s) => s.copyWith(textSize: v)),
        ),
        _Choice<MotionPreference>(
          title: 'Reduce motion',
          values: MotionPreference.values,
          selected: s.motion,
          label: (v) => switch (v) {
            MotionPreference.system => 'System',
            MotionPreference.reduce => 'On',
            MotionPreference.full => 'Off',
          },
          hint:
              "On keeps fades but drops movement. System follows your device's "
              'reduced motion setting.',
          onChanged: (v) => app.updateSettings((s) => s.copyWith(motion: v)),
        ),
        Section(
          title: 'Glass',
          children: [
            CheckRow(
              label: 'Reduce transparency',
              value: s.reduceTransparency,
              onChanged: (v) =>
                  app.updateSettings((s) => s.copyWith(reduceTransparency: v)),
              hint: const Text(
                'Solid surfaces instead of frosted glass. Also turns on when your '
                'device asks for higher contrast.',
              ),
            ),
          ],
        ),
        Section(
          title: 'Practice',
          children: [
            CheckRow(
              label: 'Flag pair practice',
              value: s.flagPairs,
              onChanged: (v) =>
                  app.updateSettings((s) => s.copyWith(flagPairs: v)),
              hint: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Adds cards that show one form of a flag, like ',
                    ),
                    TextSpan(
                      text: '-r',
                      style: context.mono.copyWith(fontSize: TextSizes.sm),
                    ),
                    const TextSpan(text: ', and ask for the other, like '),
                    TextSpan(
                      text: '--recursive',
                      style: context.mono.copyWith(fontSize: TextSizes.sm),
                    ),
                    const TextSpan(
                      text: '. Turning it off pauses those cards and keeps their progress.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const _SchedulingSettings(),
        const _BackupSettings(),
        Section(
          title: 'Help',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FrostButton(
                onPressed: app.startTour,
                child: const Text('Replay the welcome tour'),
              ),
            ),
            const SizedBox(height: Space.s2),
            Text(
              'A quick walk through decks, grading and offline use.',
              style: context.casual,
            ),
          ],
        ),
      ],
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.hint,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Section(
      title: title,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Segmented<T>(
            values: values,
            selected: selected,
            label: label,
            onChanged: onChanged,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: Space.s2),
          Text(hint!, style: context.casual),
        ],
      ],
    );
  }
}

class _Field {
  const _Field(this.label, this.hint, this.limits, this.read, this.write);
  final String label;
  final String hint;
  final SettingLimits limits;
  final num Function(Settings) read;
  final Settings Function(Settings, num) write;
}

final _main = _Field(
  'New cards per day',
  'Across all decks. Lower it for shorter daily sessions.',
  newCardsPerDayLimits,
  (s) => s.newCardsPerDay,
  (s, v) => s.copyWith(newCardsPerDay: v.toInt()),
);

final _advanced = [
  _Field(
    'Desired retention',
    'How likely you should be to remember a card when it comes up. Higher means more reviews.',
    desiredRetentionLimits,
    (s) => s.desiredRetention,
    (s, v) => s.copyWith(desiredRetention: v.toDouble()),
  ),
  _Field(
    'Maximum reviews per day',
    'Reviews past this wait for tomorrow.',
    maxReviewsPerDayLimits,
    (s) => s.maxReviewsPerDay,
    (s, v) => s.copyWith(maxReviewsPerDay: v.toInt()),
  ),
  _Field(
    'New day starts at',
    'Hour of the day (0–23), so late-night study counts toward the day before.',
    dayRolloverHourLimits,
    (s) => s.dayRolloverHour,
    (s, v) => s.copyWith(dayRolloverHour: v.toInt()),
  ),
  _Field(
    'Suspend hard cards after',
    "Times you can forget a card before it's suspended so it stops slowing you "
        "down. Find these cards in the deck's options.",
    leechThresholdLimits,
    (s) => s.leechThreshold,
    (s, v) => s.copyWith(leechThreshold: v.toInt()),
  ),
];

class _SchedulingSettings extends StatelessWidget {
  const _SchedulingSettings();

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Scheduling',
      children: [
        _NumberField(field: _main),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Advanced',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            children: [for (final f in _advanced) _NumberField(field: f)],
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({required this.field});
  final _Field field;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  String _text(num v) => v is double && v != v.roundToDouble()
      ? v.toStringAsFixed(2)
      : '${v.round()}';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_focus.hasFocus) {
      _controller.text = _text(
        widget.field.read(AppScope.of(context).settings),
      );
    }
  }

  void _save() {
    final app = AppScope.read(context);
    final parsed = num.tryParse(_controller.text.trim());
    final current = widget.field.read(app.settings);
    if (parsed == null) {
      _controller.text = _text(current);
      return;
    }
    final value = widget.field.limits.normalize(parsed);
    _controller.text = _text(value);
    if (value != current) {
      app.updateSettings((s) => widget.field.write(s, value));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.field.limits;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.field.label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: Space.s1),
          SizedBox(
            width: 140,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              style: context.mono,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                isDense: true,
                helperText: '${l.min}–${l.max}',
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
          const SizedBox(height: Space.s1),
          Text(widget.field.hint, style: context.hint),
        ],
      ),
    );
  }
}

class _BackupSettings extends StatefulWidget {
  const _BackupSettings();

  @override
  State<_BackupSettings> createState() => _BackupSettingsState();
}

class _BackupSettingsState extends State<_BackupSettings> {
  bool _busy = false;
  String? _exportMessage;
  ({String name, Backup backup})? _pending;
  String? _importError;
  String? _importMessage;
  final _exportKey = GlobalKey();

  Future<void> _export() async {
    final app = AppScope.read(context);
    final box = _exportKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _exportMessage = null;
    });
    try {
      final now = app.now();
      final backup = await exportBackup(app.repository, now);
      final saved = await saveBackupFile(
        backupFileName(now),
        backup.encode(),
        origin: origin,
      );
      await app.updateSettings((s) => s);
      setState(() {
        _exportMessage = saved
            ? 'Exported ${backup.reviewLog.length} reviews and '
                  '${backup.cardStates.length} cards.'
            : null;
      });
    } catch (e) {
      setState(() => _exportMessage = "Couldn't export: $e");
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _choose() async {
    setState(() {
      _importError = null;
      _importMessage = null;
    });
    try {
      final file = await openBackupFile();
      if (file == null) return;
      setState(
        () => _pending = (name: file.name, backup: parseBackup(file.text)),
      );
    } on BackupException catch (e) {
      setState(() => _importError = e.message);
    } catch (e) {
      setState(() => _importError = "Couldn't read that file: $e");
    }
  }

  Future<void> _import(ImportMode mode) async {
    final app = AppScope.read(context);
    final pending = _pending!;
    setState(() => _busy = true);
    try {
      final result = await importBackup(app.repository, pending.backup, mode);
      app.settings = await app.repository.settings();
      app.progressChanged();
      final waiting = result.pendingDecks.length;
      setState(() {
        _pending = null;
        _importMessage =
            '${mode == ImportMode.merge ? 'Merged' : 'Restored'} '
            '${result.addedReviews} reviews.'
            '${waiting > 0 ? ' $waiting deck${waiting == 1 ? '' : 's'} will download when online.' : ''}';
      });
      app.syncAfterChange().ignore();
    } catch (e) {
      setState(() => _importError = "Couldn't import: $e");
    } finally {
      setState(() => _busy = false);
    }
  }

  String _day(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final f = Frost.of(context);
    final days = daysSinceBackup(app.settings.lastBackupAt, app.now());
    final last = days == null
        ? 'You haven’t exported a backup yet.'
        : days == 0
        ? 'Last backup: today.'
        : 'Last backup: $days day${days == 1 ? '' : 's'} ago.';
    final pending = _pending;
    final summary = pending == null ? null : summarizeBackup(pending.backup);
    return Section(
      title: 'Backup',
      children: [
        Text(
          'Your progress lives only on this device. Export a backup to keep it '
          'safe or move it to another device. Backups work with the web app too.',
          style: context.hint,
        ),
        const SizedBox(height: Space.s2),
        Text(last, style: context.hint),
        const SizedBox(height: Space.s3),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: [
            FrostButton(
              key: _exportKey,
              onPressed: _busy ? null : _export,
              child: const Text('Export backup'),
            ),
            FrostButton(
              onPressed: _busy ? null : _choose,
              child: const Text('Import backup…'),
            ),
          ],
        ),
        if (_exportMessage != null) ...[
          const SizedBox(height: Space.s2),
          Semantics(
            liveRegion: true,
            child: Text(_exportMessage!, style: context.hint),
          ),
        ],
        if (pending != null && summary != null) ...[
          const SizedBox(height: Space.s4),
          Glass(
            padding: const EdgeInsets.all(Space.s5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: pending.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: ', exported ${_day(summary.exportedAt)}'),
                    ],
                  ),
                ),
                const SizedBox(height: Space.s2),
                Text(
                  'Decks: ${summary.decks.isEmpty ? 'none' : summary.decks.join(', ')}',
                ),
                Text('Cards: ${summary.cards}'),
                Text(
                  'History: ${summary.reviews} reviews'
                  '${summary.firstReview == null ? '' : ', ${_day(summary.firstReview!)} to ${_day(summary.lastReview!)}'}',
                ),
                const SizedBox(height: Space.s3),
                Text(
                  'Merge adds reviews this device doesn’t have and keeps the newer '
                  'progress for each card. Replace discards this device’s progress first.',
                  style: context.hint,
                ),
                const SizedBox(height: Space.s3),
                Wrap(
                  spacing: Space.s2,
                  runSpacing: Space.s2,
                  children: [
                    FrostButton(
                      variant: ButtonVariant.primary,
                      onPressed: _busy ? null : () => _import(ImportMode.merge),
                      child: const Text('Merge'),
                    ),
                    FrostButton(
                      variant: ButtonVariant.again,
                      onPressed: _busy
                          ? null
                          : () => _import(ImportMode.replace),
                      child: const Text('Replace'),
                    ),
                    FrostButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _pending = null),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (_importError != null) ...[
          const SizedBox(height: Space.s2),
          Text(_importError!, style: TextStyle(color: f.again)),
        ],
        if (_importMessage != null) ...[
          const SizedBox(height: Space.s2),
          Semantics(liveRegion: true, child: Text(_importMessage!)),
        ],
      ],
    );
  }
}
