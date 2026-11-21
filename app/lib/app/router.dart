/// Routes, matching the web app's paths so links keep working.
library;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'decks/deck_browse_screen.dart';
import 'decks/decks_screen.dart';
import 'review/review_screen.dart';
import 'settings/settings_screen.dart';
import 'shell.dart';
import 'stats/stats_screen.dart';

Page<void> _page(GoRouterState state, Widget child) =>
    NoTransitionPage(key: state.pageKey, child: child);

GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          Shell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => _page(state, const ReviewScreen()),
        ),
        GoRoute(
          path: '/decks',
          pageBuilder: (context, state) => _page(state, const DecksScreen()),
          routes: [
            GoRoute(
              path: ':id',
              pageBuilder: (context, state) => _page(
                state,
                DeckBrowseScreen(
                  key: ValueKey(state.uri.toString()),
                  deckId: state.pathParameters['id']!,
                  openOption: state.uri.queryParameters['option'],
                ),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/stats',
          pageBuilder: (context, state) => _page(state, const StatsScreen()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => _page(state, const SettingsScreen()),
        ),
      ],
    ),
  ],
);
