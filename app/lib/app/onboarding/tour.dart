/// The three-step welcome tour, ported from `OnboardingTour.vue`. Opens on a
/// first launch and can be replayed from Settings.
library;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../motion.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

class WelcomeTour extends StatefulWidget {
  const WelcomeTour({super.key});

  @override
  State<WelcomeTour> createState() => _WelcomeTourState();
}

class _WelcomeTourState extends State<WelcomeTour> {
  int _step = 0;
  static const _count = 3;

  void _next() {
    if (_step < _count - 1) {
      setState(() => _step++);
      return;
    }
    final app = AppScope.read(context);
    final replay = app.tourReplay;
    app.finishTour();
    if (!replay) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final app = AppScope.of(context);
    final touch = !showsKeyHints;
    final body = Theme.of(context).textTheme.bodyLarge!;
    final code = context.mono.copyWith(fontSize: TextSizes.md);

    final (Widget title, List<Widget> paragraphs) = switch (_step) {
      0 => (
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Welcome to ',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Wordmark(size: TextSizes.xl),
          ],
        ),
        [
          const Text(
            'Learn the flags of the command-line tools you use, one flashcard at '
            "a time. Each card comes back just before you'd forget it, so a few "
            'minutes a day is enough.',
          ),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Each deck covers one tool, such as '),
                TextSpan(text: 'grep', style: code),
                const TextSpan(text: ' or '),
                TextSpan(text: 'jq', style: code),
                const TextSpan(
                  text:
                      ', and starts with its most useful flags. Every deck '
                      "downloads on its own, so there's nothing to set up.",
                ),
              ],
            ),
          ),
        ],
      ),
      1 => (
        Text(
          'Review your cards',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Each card asks about a flag. Recall the answer, then choose ',
                ),
                TextSpan(
                  text: 'Show answer',
                  style: weight(body, FontWeight.w700),
                ),
                const TextSpan(
                  text:
                      ' and grade yourself honestly. Your grade decides when '
                      'the card comes back.',
                ),
              ],
            ),
          ),
          Wrap(
            spacing: Space.s2,
            children: [
              for (final (label, color) in [
                ('Again', f.again),
                ('Hard', f.text),
                ('Good', f.accent),
                ('Easy', f.text),
              ])
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s3,
                    vertical: Space.s1,
                  ),
                  decoration: BoxDecoration(
                    color: f.sunken,
                    borderRadius: BorderRadius.circular(Radii.small),
                  ),
                  child: Text(label, style: TextStyle(color: color)),
                ),
            ],
          ),
          Text(
            touch
                ? 'Swipe a revealed card left for Again or right for Good, or tap a grade.'
                : 'On a keyboard, Space shows the answer, 1–4 grade it, and ? lists every shortcut.',
            style: context.hint,
          ),
        ],
      ),
      _ => (
        Text('Works offline', style: Theme.of(context).textTheme.headlineSmall),
        [
          const Text(
            'Decks download once and keep themselves up to date, so everything '
            'works without a connection.',
          ),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Your progress stays on this device, so export a backup from ',
                ),
                TextSpan(
                  text: 'Settings',
                  style: weight(body, FontWeight.w700),
                ),
                const TextSpan(text: ' now and then.'),
              ],
            ),
          ),
          Text.rich(
            TextSpan(
              style: context.casual,
              children: [
                const TextSpan(
                  text: 'Only care about some tools? Pause the rest in ',
                ),
                TextSpan(
                  text: 'Decks',
                  style: weight(context.casual, FontWeight.w700),
                ),
                const TextSpan(text: ', where you can also turn on '),
                TextSpan(
                  text: 'Type answers',
                  style: weight(context.casual, FontWeight.w700),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ],
      ),
    };

    final last = _step == _count - 1;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.35),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: 'Welcome tour',
              child: Glass(
                color: f.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Step ${_step + 1} of $_count',
                          style: context.hint,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => app.finishTour(),
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
                    AnimatedSwitcher(
                      duration: motionDuration(context, 200),
                      child: Column(
                        key: ValueKey(_step),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(header: true, child: title),
                          const SizedBox(height: Space.s4),
                          for (final p in paragraphs) ...[
                            DefaultTextStyle.merge(style: body, child: p),
                            const SizedBox(height: Space.s3),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.s3),
                    Row(
                      children: [
                        for (var i = 0; i < _count; i++)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _step ? f.accent : f.border,
                            ),
                          ),
                        const Spacer(),
                        if (_step > 0) ...[
                          FrostButton(
                            onPressed: () => setState(() => _step--),
                            child: const Text('Back'),
                          ),
                          const SizedBox(width: Space.s2),
                        ],
                        FrostButton(
                          autofocus: true,
                          variant: ButtonVariant.primary,
                          onPressed: _next,
                          child: Text(
                            !last
                                ? 'Next'
                                : app.tourReplay
                                ? 'Done'
                                : 'Start reviewing',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
