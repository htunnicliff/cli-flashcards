/// The review screen. Ported from `src/app/views/ReviewView.vue`.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../core/review_format.dart';
import '../../core/scheduler.dart';
import '../app_state.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets.dart';
import 'review_card.dart';
import 'review_session.dart';
import 'typed_answer.dart';

const _ratingLabels = {
  Rating.again: 'Again',
  Rating.hard: 'Hard',
  Rating.good: 'Good',
  Rating.easy: 'Easy',
};

/// Swipes past this many pixels grade the card.
const swipeThreshold = 96.0;

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  ReviewSession? _session;
  AppController? _app;
  int _revision = 0;
  bool _helpOpen = false;
  bool _moreOpen = false;
  double _swipeX = 0;
  Timer? _noticeTimer;
  int? _noticeShown;
  final _focus = FocusNode(debugLabel: 'review');
  final _typedFocus = FocusNode(debugLabel: 'typed answer');
  final _revealFocus = FocusNode(debugLabel: 'show answer');
  final _gradeFocus = {for (final r in Rating.values) r: FocusNode()};
  String? _focusedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (_session == null) {
      _app = app;
      _revision = app.revision;
      _session = ReviewSession(app)..addListener(_onSession);
    } else if (app.revision != _revision) {
      // Decks downloaded, settings changed or a backup was imported.
      _revision = app.revision;
      _session!.refresh();
    }
  }

  void _onSession() {
    final notice = _session!.notice;
    if (notice != null && notice.id != _noticeShown) {
      _noticeShown = notice.id;
      _noticeTimer?.cancel();
      _noticeTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) _session!.dismissNotice();
      });
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _moveFocus());
  }

  /// Focus follows the flow: the suggested (or Good) grade once revealed,
  /// otherwise the answer field or Show answer.
  void _moveFocus() {
    if (!mounted) return;
    final s = _session!;
    final key = '${s.current?.card.id}:${s.revealed}';
    if (key == _focusedFor) return;
    _focusedFor = key;
    if (s.current == null) {
      _focus.requestFocus();
    } else if (s.revealed) {
      _gradeFocus[s.suggestedRating ?? Rating.good]!.requestFocus();
    } else if (s.typing) {
      _typedFocus.requestFocus();
    } else {
      _revealFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _session?.removeListener(_onSession);
    _session?.dispose();
    _focus.dispose();
    _typedFocus.dispose();
    _revealFocus.dispose();
    for (final f in _gradeFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _editing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (_editing) return KeyEventResult.ignored;
    final s = _session!;
    final char = event.character;
    if (char == '?') {
      setState(() => _helpOpen = !_helpOpen);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _helpOpen) {
      setState(() => _helpOpen = false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      s.reveal();
      return KeyEventResult.handled;
    }
    switch (char) {
      case 'u' || 'U':
        if (s.canUndo) s.undo();
        return KeyEventResult.handled;
      case 's':
        s.setAside(SetAside.suspend, wholeOption: keys.isShiftPressed);
        return KeyEventResult.handled;
      case 'S':
        s.setAside(SetAside.suspend, wholeOption: true);
        return KeyEventResult.handled;
      case 'b':
        s.setAside(SetAside.bury);
        return KeyEventResult.handled;
      case '1' || '2' || '3' || '4':
        _grade(Rating.of(int.parse(char!)));
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _grade(Rating rating) {
    final s = _session!;
    if (s.current == null || !s.revealed) return;
    setState(() {
      _swipeX = 0;
      _moreOpen = false;
    });
    s.grade(rating);
  }

  void _setAside(SetAside how, {bool wholeOption = false}) {
    setState(() => _moreOpen = false);
    _session!.setAside(how, wholeOption: wholeOption);
  }

  @override
  Widget build(BuildContext context) {
    final s = _session!;
    final app = _app!;
    final reduceMotion = reducedMotion(context);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          PageBody(
            children: [
              _Header(
                session: s,
                helpOpen: _helpOpen,
                onHelp: () => setState(() => _helpOpen = !_helpOpen),
              ),
              AnimatedSize(
                duration: motionDuration(context, 200),
                child: _helpOpen ? const _Help() : const SizedBox.shrink(),
              ),
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s4),
                  child: Text(
                    s.error!,
                    style: TextStyle(color: Frost.of(context).again),
                  ),
                ),
              const SizedBox(height: Space.s6),
              if (s.loading)
                Text('Loading your cards…', style: context.hint)
              else if (s.done)
                _Done(session: s, app: app)
              else ...[
                _stage(s, reduceMotion),
                const SizedBox(height: Space.s6),
                _controls(s),
              ],
            ],
          ),
          if (s.notice != null)
            Positioned(
              left: Space.s4,
              right: Space.s4,
              bottom:
                  (MediaQuery.sizeOf(context).width < 600 ? 96 : Space.s6) +
                  MediaQuery.paddingOf(context).bottom,
              child: Center(child: _Snackbar(session: s)),
            ),
        ],
      ),
    );
  }

  Widget _stage(ReviewSession s, bool reduceMotion) {
    final item = s.current!;
    final hint = s.leaveHint;
    final swipeLabel = _swipeX <= -swipeThreshold
        ? 'Again'
        : _swipeX >= swipeThreshold
        ? 'Good'
        : null;
    final card = GestureDetector(
      key: ValueKey(item.card.id),
      behavior: HitTestBehavior.opaque,
      onTap: s.reveal,
      onHorizontalDragUpdate: s.revealed
          ? (d) => setState(() => _swipeX += d.delta.dx)
          : null,
      onHorizontalDragEnd: s.revealed
          ? (_) {
              final dx = _swipeX;
              setState(() => _swipeX = 0);
              if (dx <= -swipeThreshold) _grade(Rating.again);
              if (dx >= swipeThreshold) _grade(Rating.good);
            }
          : null,
      onHorizontalDragCancel: () => setState(() => _swipeX = 0),
      child: AnimatedContainer(
        duration: _swipeX == 0 ? motionDuration(context, 200) : Duration.zero,
        transform: Matrix4.identity()
          ..translateByDouble(_swipeX, 0, 0, 1)
          ..rotateZ(_swipeX / 40 * 3.14159 / 180),
        transformAlignment: Alignment.center,
        child: ReviewCard(
          card: item.card,
          option: s.option,
          tool: s.deck?.tool ?? '',
          revealed: s.revealed,
          flagPairs: s.flagPairs,
          reduceMotion: reduceMotion,
        ),
      ),
    );
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        AnimatedSwitcher(
          duration: motionDuration(context, 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, animation) {
            final leaving = child.key != ValueKey(item.card.id);
            Offset end = const Offset(0, 0.03);
            if (leaving && !reduceMotion) {
              end = switch (hint) {
                AsideHint() => const Offset(0, 0.25),
                GradedHint(rating: Rating.again) => const Offset(-0.08, 0),
                GradedHint(rating: Rating.hard) => const Offset(0, 0.1),
                GradedHint(rating: Rating.good) => const Offset(0.08, 0),
                GradedHint(rating: Rating.easy) => const Offset(0, -0.1),
                null => Offset.zero,
              };
            }
            if (reduceMotion) end = Offset.zero;
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: end,
                  end: Offset.zero,
                ).animate(animation),
                child: ScaleTransition(
                  scale: Tween(
                    begin: leaving && hint is AsideHint && !reduceMotion
                        ? 0.94
                        : 1.0,
                    end: 1.0,
                  ).animate(animation),
                  child: child,
                ),
              ),
            );
          },
          child: card,
        ),
        if (swipeLabel != null)
          Positioned(
            top: Space.s3,
            child: ExcludeSemantics(
              child: FrostChip(swipeLabel, color: Frost.of(context).accent),
            ),
          ),
      ],
    );
  }

  Widget _controls(ReviewSession s) {
    final f = Frost.of(context);
    final item = s.current!;
    final intervals = s.intervals;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.typing) ...[
          TypedAnswer(
            key: ValueKey('typed:${item.card.id}'),
            command: s.command,
            result: s.answer,
            focusNode: _typedFocus,
            onSubmit: s.submitAnswer,
          ),
          const SizedBox(height: Space.s4),
        ],
        if (!s.revealed && !s.typing)
          FrostButton(
            focusNode: _revealFocus,
            variant: ButtonVariant.primary,
            block: true,
            onPressed: s.reveal,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text('Show answer'), Kbd('Space', onPrimary: true)],
            ),
          ),
        if (s.revealed)
          Semantics(
            label: 'Grade this card',
            container: true,
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: narrow ? 2 : 4,
              crossAxisSpacing: Space.s2,
              mainAxisSpacing: Space.s2,
              childAspectRatio: narrow ? 2.6 : 1.9,
              children: [
                for (final r in Rating.values)
                  FrostButton(
                    focusNode: _gradeFocus[r],
                    highlighted: s.suggestedRating == r,
                    variant: switch (r) {
                      Rating.again => ButtonVariant.again,
                      Rating.good => ButtonVariant.primary,
                      _ => ButtonVariant.neutral,
                    },
                    semanticsLabel:
                        '${_ratingLabels[r]}, next in ${intervals[r]}',
                    onPressed: () => _grade(r),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_ratingLabels[r]!),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              intervals[r] ?? '',
                              style: context.mono.copyWith(
                                fontSize: TextSizes.xs,
                                color: r == Rating.good ? f.onPrimary : f.muted,
                              ),
                            ),
                            Kbd('${r.value}', onPrimary: r == Rating.good),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: Space.s4),
        _MoreMenu(
          open: _moreOpen,
          flag: frontFlag(item.card),
          onToggle: () => setState(() => _moreOpen = !_moreOpen),
          onBury: () => _setAside(SetAside.bury),
          onSuspend: () => _setAside(SetAside.suspend),
          onSuspendAll: () => _setAside(SetAside.suspend, wholeOption: true),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.helpOpen,
    required this.onHelp,
  });

  final ReviewSession session;
  final bool helpOpen;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final counts = s.counts;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.s3,
            runSpacing: Space.s2,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Review',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              if (!s.done)
                Semantics(
                  label: 'Cards left',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Count('New', counts.newCards),
                      _Count('Learning', counts.learning),
                      _Count('Due', counts.review),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (s.canUndo)
              FrostButton(
                onPressed: s.undo,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('Undo'), Kbd('u')],
                ),
              ),
            if (showsKeyHints) ...[
              const SizedBox(width: Space.s2),
              FrostButton(
                semanticsLabel: 'Keyboard shortcuts',
                onPressed: onHelp,
                highlighted: helpOpen,
                child: const Kbd('?'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value);
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final color = switch (label) {
      'New' => f.accent,
      'Learning' => f.again,
      _ => f.arg,
    };
    return Padding(
      padding: const EdgeInsets.only(right: Space.s5),
      child: MergeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label, style: context.hint),
            const SizedBox(width: Space.s2),
            AnimatedSwitcher(
              duration: motionDuration(context, 180),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: reducedMotion(context)
                    ? child
                    : SlideTransition(
                        position: Tween(
                          begin: const Offset(0, -0.3),
                          end: Offset.zero,
                        ).animate(a),
                        child: child,
                      ),
              ),
              child: Text(
                '$value',
                key: ValueKey(value),
                style: weight(
                  context.mono.copyWith(fontSize: TextSizes.sm, color: color),
                  FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Help extends StatelessWidget {
  const _Help();

  @override
  Widget build(BuildContext context) {
    const rows = [
      (['Space'], 'Show the answer'),
      (['1', '2', '3', '4'], 'Again, Hard, Good, Easy'),
      (['u'], 'Undo the last grade, skip or suspend'),
      (['s'], 'Suspend this card'),
      (['S'], 'Suspend every card for this flag'),
      (['b'], 'Skip this card until tomorrow'),
      (['?'], 'Show or hide this list'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Space.s4),
      child: Glass(
        padding: const EdgeInsets.all(Space.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (keys, what) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Row(children: [for (final k in keys) Kbd(k)]),
                    ),
                    Expanded(child: Text(what)),
                  ],
                ),
              ),
            const SizedBox(height: Space.s2),
            Text(
              'On a phone, swipe a revealed card left for Again or right for Good.',
              style: context.hint,
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.open,
    required this.flag,
    required this.onToggle,
    required this.onBury,
    required this.onSuspend,
    required this.onSuspendAll,
  });

  final bool open;
  final String flag;
  final VoidCallback onToggle;
  final VoidCallback onBury;
  final VoidCallback onSuspend;
  final VoidCallback onSuspendAll;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    Widget action(String label, String key, VoidCallback onTap) => TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: f.text,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label)),
          Kbd(key),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: onToggle,
          style: TextButton.styleFrom(foregroundColor: f.muted),
          iconAlignment: IconAlignment.end,
          icon: AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: motionDuration(context, 150),
            child: const Icon(Icons.arrow_drop_down),
          ),
          label: const Text('More'),
        ),
        AnimatedSize(
          duration: motionDuration(context, 200),
          child: !open
              ? const SizedBox(width: double.infinity)
              : Semantics(
                  label: 'Set this card aside',
                  container: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      action('Skip until tomorrow', 'b', onBury),
                      action('Suspend this card', 's', onSuspend),
                      action('Suspend all $flag cards', 'S', onSuspendAll),
                      Padding(
                        padding: const EdgeInsets.all(Space.s2),
                        child: Text(
                          "Suspended cards stop coming up until you unsuspend "
                          "them from the deck's options.",
                          style: context.hint,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.session, required this.app});
  final ReviewSession session;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final due = s.nextLearningDue ?? s.nextDue;
    final dueText = due == null ? null : formatNextDue(due, app.now());
    final (String title, String body, bool link) = s.hasDecks
        ? (
            'All done for today',
            s.nextLearningDue != null
                ? "A card you're learning comes back $dueText. It will show up here on its own."
                : dueText != null
                ? 'Your next review is $dueText.'
                : 'Nothing else is scheduled. Turn on more decks in Decks for more to learn.',
            false,
          )
        : app.sync.running
        ? (
            'Getting your decks ready',
            'Every deck downloads on its own, once. Your first cards appear here in a moment.',
            false,
          )
        : (
            'No decks yet',
            app.online
                ? "The decks haven't downloaded yet. Decks shows what's happening."
                : "Decks download the first time you're online, then work offline.",
            app.online,
          );
    return Semantics(
      liveRegion: true,
      child: Glass(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: Space.s2),
            Text(body, style: context.hint),
            if (link) ...[
              const SizedBox(height: Space.s4),
              FrostButton(
                onPressed: () => context.go('/decks'),
                child: const Text('Open Decks'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Snackbar extends StatelessWidget {
  const _Snackbar({required this.session});
  final ReviewSession session;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final notice = session.notice!;
    final onDark = TextStyle(color: f.bg);
    return Semantics(
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          color: f.text,
          elevation: 6,
          borderRadius: BorderRadius.circular(Radii.button),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              Space.s2,
              Space.s1,
              Space.s2,
            ),
            child: Row(
              children: [
                Expanded(child: Text(notice.message, style: onDark)),
                if (notice.link != null)
                  TextButton(
                    onPressed: () => context.go(notice.link!.to),
                    child: Text(
                      notice.link!.label,
                      style: TextStyle(
                        color: f.bg,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                if (notice.undoable && session.canUndo)
                  TextButton(
                    onPressed: session.undo,
                    child: Text('Undo', style: weight(onDark, FontWeight.w700)),
                  ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: session.dismissNotice,
                  icon: Icon(Icons.close, color: f.bg, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
