import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app_state.dart';
import 'app/deck_sources.dart';
import 'app/platform/database.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final repository = await openAppRepository();
  final app = AppController(
    repository: repository,
    source: FallbackDeckSource(NetworkDeckSource(), const BundledDeckSource()),
  );
  await app.load();
  // Lists decks at once, before the network answers.
  app.manifest = await const BundledDeckSource().manifest();
  runApp(CliFlashcardsApp(controller: app));
  app.syncDecks().ignore();
}

class CliFlashcardsApp extends StatefulWidget {
  const CliFlashcardsApp({super.key, required this.controller, this.router});

  final AppController controller;
  final GoRouter? router;

  @override
  State<CliFlashcardsApp> createState() => _CliFlashcardsAppState();
}

class _CliFlashcardsAppState extends State<CliFlashcardsApp> {
  late final GoRouter _router = widget.router ?? buildRouter();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // A newer deck may have shipped while the app sat in the background.
    _lifecycle = AppLifecycleListener(
      onResume: () => widget.controller.syncDecks().ignore(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: Builder(
        builder: (context) {
          final settings = AppScope.of(context).settings;
          final highContrast = MediaQuery.highContrastOf(context);
          final solid = settings.reduceTransparency || highContrast;
          return MaterialApp.router(
            title: '--recall',
            debugShowCheckedModeBanner: false,
            routerConfig: _router,
            themeMode: switch (settings.theme) {
              AppTheme.system => ThemeMode.system,
              AppTheme.light => ThemeMode.light,
              AppTheme.dark => ThemeMode.dark,
            },
            theme: buildTheme(Frost.light.withSolid(solid)),
            darkTheme: buildTheme(Frost.dark.withSolid(solid)),
            builder: (context, child) {
              final media = MediaQuery.of(context);
              final frost = Frost.of(context);
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle(frost),
                child: MediaQuery(
                  data: media.copyWith(
                    textScaler: TextScaler.linear(
                      media.textScaler.scale(1) * settings.textSize.scale,
                    ),
                  ),
                  child: child!,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
