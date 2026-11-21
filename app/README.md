# CLI Flashcards (Flutter)

The cross-platform app: web, iOS, iPadOS, Android and macOS from one Dart codebase. It is the live site at <https://htunnicliff.github.io/cli-flashcards/>. The previous Vue app stays at `/classic/` so its saved progress can be exported as a backup and imported here.

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

The app ID is `dev.seafarer.cliflashcards` on every platform. The icons are drawn from `public/icons/icon.svg` by `tools/flutter-icons.py`. Android uses an adaptive icon defined in XML. CI builds a release APK, an unsigned iOS build and a macOS app on every PR, and keeps the APK and the zipped macOS app as workflow artifacts for 14 days.

To publish a release, run **Release app** from the Actions tab with a version like `0.2.0`, or push a tag like `app-v0.2.0`. It attaches the APK and the zipped macOS app to a GitHub release.

For the web, build with `flutter build web --no-web-resources-cdn` and then run `pnpm flutter:sw` from the repo root. The flag serves CanvasKit from our own origin instead of Google's CDN, so the service worker can cache it. The service worker precaches the app (about 18 MB) so it works offline and can be added to a phone's home screen. A new version installs in the background and takes over the next time the page is hidden.

To point a build at another deck host, pass `--dart-define=DECKS_URL=https://example.com/data/decks/`.

### Android signing (optional)

Without a signing key, each release APK is signed with a throwaway debug key. Android then refuses to install a new release over an old one, and you'd have to uninstall first, which deletes your progress unless you export a backup. To sign every release with the same key, make one once:

```sh
keytool -genkeypair -v -keystore release.jks -alias release \
  -keyalg RSA -keysize 4096 -validity 10000
base64 -i release.jks | pbcopy   # macOS; on Linux: base64 -w0 release.jks
```

Then add two repository secrets: `ANDROID_KEYSTORE_BASE64` (the copied text) and `ANDROID_KEYSTORE_PASSWORD`. Keep `release.jks` and its password somewhere safe. Losing them means the next release won't install over the old one.

## Install

There's no App Store or Play Store listing. Every platform below is free.

### iPhone and iPad

**Web app (simplest).** Open the site in Safari, tap **Share**, then **Add to Home Screen**. It opens full screen, works offline, and doesn't expire.

**Native app from Xcode.** This needs a Mac with Xcode, but no paid developer account:

1. In Xcode, go to **Settings → Accounts** and add your Apple ID. That creates a free "Personal Team".
2. Connect the iPhone or iPad with a cable. On the device, turn on **Settings → Privacy & Security → Developer Mode** and restart when asked.
3. Open `app/ios/Runner.xcworkspace`. Select the **Runner** target, then **Signing & Capabilities**. Tick **Automatically manage signing** and choose your Personal Team. If Xcode says the bundle ID is taken, change it to something unique, like `dev.seafarer.cliflashcards.yourname`.
4. From `app/`, run `flutter run --release` and pick the device.
5. On the device, go to **Settings → General → VPN & Device Management** and trust your developer certificate.

Free builds expire after 7 days. Run step 4 again to renew; progress is kept as long as you don't delete the app. Apple allows up to 3 apps this way per device.

### Android

Download the `.apk` from the latest [release](https://github.com/htunnicliff/cli-flashcards/releases) on the phone and open it. Allow your browser to install unknown apps when Android asks.

### macOS

Download the `-macos.zip` from the latest [release](https://github.com/htunnicliff/cli-flashcards/releases), unzip it, and move the app to Applications. It isn't notarized (that needs a paid account), so macOS blocks the first launch. To allow it, either:

- Open it once, then go to **System Settings → Privacy & Security** and choose **Open Anyway**, or
- Run `xattr -dr com.apple.quarantine /Applications/cliflashcards.app`.
