# CLI Flashcards (Flutter)

The cross-platform app: web, iOS, iPadOS, Android and macOS from one Dart codebase. It is replacing the Vue web app in `src/`, which stays live until this app reaches feature parity.

## Setup

Install Flutter 3.50 (the version CI uses is pinned in `.github/workflows/ci.yml`), then:

```sh
cd app
flutter pub get
flutter run -d chrome     # or: -d macos, an iOS simulator, an Android emulator
```

## Layout

```
lib/
  schema/   Deck, card and manifest models (ports of src/schema/)
  core/     Framework-free logic: FSRS, queue, scheduler, answers, stats, backup, sync, storage
  app/      Flutter UI: theme, routing, and one folder per page (review, decks, stats, settings)
test/
  core/     Unit tests, including parity tests against the TypeScript app
  app/      Widget tests that drive whole pages against the real decks
  fixtures/ Written by `pnpm dart:golden`; don't edit by hand
assets/
  decks -> ../../public/data/decks   (symlink to the built decks)
```

`lib/core/` and `lib/schema/` don't import Flutter, so they run in plain Dart tests.

## Decks

The TypeScript pipeline in `tools/` still builds every deck (`pnpm deck:build`). The app bundles `public/data/decks/` through the `assets/decks` symlink, so a fresh install works offline, and downloads newer versions from the published site.

## Parity with the web app

Scheduling, card IDs and typed-answer checks must match the web app exactly, so progress and backups move between the two. `pnpm dart:golden` runs the TypeScript code and writes its results to `test/fixtures/`; the Dart tests check against them. CI fails if the fixtures are stale. Backups use the same `recall-backup` JSON format in both apps.

## Storage

[sembast](https://pub.dev/packages/sembast) behind `lib/core/repository.dart`: IndexedDB on the web, a file in the app's support directory elsewhere, and memory in tests.

## Builds

The app ID is `dev.seafarer.cliflashcards` on every platform. CI builds a release APK, an unsigned iOS build and a macOS app on every PR, and keeps the APK and the zipped macOS app as workflow artifacts for 14 days. Signed store builds (TestFlight first) aren't set up yet.

To point a build at another deck host, pass `--dart-define=DECKS_URL=https://example.com/data/decks/`.
