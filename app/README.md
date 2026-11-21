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
  core/     Framework-free logic: FSRS, queue, scheduler, answers, stats, backup, storage
test/
  core/     Unit tests, including parity tests against the TypeScript app
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
