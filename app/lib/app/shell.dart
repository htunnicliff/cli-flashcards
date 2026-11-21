/// The frame around every page: a frosted header with the four destinations,
/// or on phones a floating glass tab bar in the thumb zone.
library;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'onboarding/tour.dart';
import 'theme.dart';

const destinations = [
  (path: '/', label: 'Review', icon: Icons.style_outlined),
  (path: '/decks', label: 'Decks', icon: Icons.layers_outlined),
  (path: '/stats', label: 'Stats', icon: Icons.insights_outlined),
  (path: '/settings', label: 'Settings', icon: Icons.tune),
];

int destinationIndex(String location) {
  for (var i = destinations.length - 1; i > 0; i--) {
    if (location.startsWith(destinations[i].path)) return i;
  }
  return 0;
}

class Shell extends StatelessWidget {
  const Shell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final current = destinationIndex(location);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FrostBackdrop(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  _Header(current: current, narrow: narrow, online: app.online),
                  Expanded(child: child),
                ],
              ),
              if (narrow)
                Positioned(
                  left: Space.s4,
                  right: Space.s4,
                  bottom: Space.s3 + MediaQuery.paddingOf(context).bottom,
                  child: _TabBar(current: current),
                ),
              if (app.tourOpen) const Positioned.fill(child: WelcomeTour()),
            ],
          ),
        ),
      ),
    );
  }
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = TextSizes.lg});
  final double size;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final style = weight(
      context.mono.copyWith(fontSize: size),
      FontWeight.w700,
    );
    return Semantics(
      label: '--recall',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(
              text: '--',
              style: TextStyle(color: f.accent),
            ),
            const TextSpan(text: 'recall'),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.current,
    required this.narrow,
    required this.online,
  });

  final int current;
  final bool narrow;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => context.go('/'),
          borderRadius: BorderRadius.circular(Radii.small),
          child: const Wordmark(),
        ),
        if (!online) ...[
          const SizedBox(width: Space.s3),
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s2,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: f.sunken,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                'Offline',
                style: context.hint.copyWith(fontSize: TextSizes.xs),
              ),
            ),
          ),
        ],
      ],
    );
    if (narrow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, 0),
        child: Align(alignment: Alignment.centerLeft, child: brand),
      );
    }
    return Glass(
      chrome: true,
      radius: 0,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: Space.s8, vertical: 14),
      child: Row(
        children: [
          brand,
          const Spacer(),
          Semantics(
            container: true,
            label: 'Main',
            child: Container(
              padding: const EdgeInsets.all(Space.s1),
              decoration: BoxDecoration(
                color: f.sunken,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, d) in destinations.indexed)
                    _NavLink(
                      label: d.label,
                      selected: i == current,
                      onTap: () => context.go(d.path),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final style = Theme.of(context).textTheme.labelMedium!;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s2,
          ),
          decoration: BoxDecoration(
            color: selected ? f.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.pill),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: f.shadow.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: weight(
              style.copyWith(color: selected ? f.text : f.muted),
              selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    return Glass(
      chrome: true,
      radius: Radii.pill,
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          for (final (i, d) in destinations.indexed)
            Expanded(
              child: Semantics(
                selected: i == current,
                button: true,
                label: d.label,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  onTap: () => context.go(d.path),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    constraints: const BoxConstraints(minHeight: 48),
                    decoration: BoxDecoration(
                      color: i == current ? f.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          d.icon,
                          size: 20,
                          color: i == current ? f.accent : f.muted,
                        ),
                        Text(
                          d.label,
                          style: weight(
                            Theme.of(context).textTheme.labelSmall!.copyWith(
                              color: i == current ? f.text : f.muted,
                              fontSize: 11,
                            ),
                            i == current ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
