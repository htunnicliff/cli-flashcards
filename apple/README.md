# CLI Flashcards (Skip)

The native app for iPhone, iPad, Mac and Android, written in Swift and SwiftUI
with [Skip](https://skip.dev) (Skip Fuse, native mode). It replaces the Flutter
app in `../app/` and the Vue web app. The plan is in issue #70.

## Layout

```
Package.swift          The app package (Skip), app ID dev.seafarer.cliflashcards
Skip.env               Name, bundle ID and version, shared by Xcode and Gradle
Sources/CLIFlashcards/ SwiftUI app, shared by every platform
FlashcardsCore/        Plain Swift package: deck schema, cards, FSRS, typed answers
  Tests/Fixtures/      Parity fixtures written by `pnpm dart:golden`; don't edit by hand
Darwin/                Xcode project for iOS, iPadOS and macOS (native, not Catalyst)
Android/               Gradle project for Android
```

`FlashcardsCore` has no UI and no Skip dependency, so its tests run anywhere
Swift does, Linux included:

```sh
cd apple/FlashcardsCore
swift test
```

Its parity tests check scheduling, card IDs and typed answers against the
TypeScript code, so progress and backups move between the apps unchanged.

## Setup

You need a Mac with Xcode, plus Android Studio for the Android build.

```sh
brew install skiptools/skip/skip
skip checkup
open apple/Project.xcworkspace
```

Run the **CLIFlashcards App** scheme on an iPhone or iPad simulator, or on
**My Mac**. With an Android emulator running, the same build also launches the
Android app. Set `SKIP_ACTION = none` in `Darwin/CLIFlashcards.xcconfig` to
skip the Android build while you work on Apple platforms.

## Downloading a release

Each [release](https://github.com/htunnicliff/cli-flashcards/releases) has:

- **macOS:** a zipped app. It isn't notarized, so the first time, right-click
  it and choose **Open**, or allow it in **System Settings → Privacy &
  Security → Open Anyway**.
- **Android:** an APK that installs over earlier releases and keeps your
  progress.
- **iOS and iPadOS:** an unsigned archive, for anyone who re-signs it. Most
  people should build from Xcode instead, as below.

To make a release, run **Release app** from the Actions tab with a version, or
push a tag like `app-v1.2.0`.

## Installing on your own iPhone, iPad or Mac

No paid Apple Developer account is needed:

1. In Xcode, go to **Settings → Accounts** and add your Apple ID. That creates a
   free "Personal Team".
2. For an iPhone or iPad, connect it with a cable, then turn on **Settings →
   Privacy & Security → Developer Mode** on the device and restart when asked.
3. Select the **CLIFlashcards App** target, open **Signing & Capabilities**,
   and choose your Personal Team. If Xcode says the bundle ID is taken, change
   it to something unique, like `dev.seafarer.cliflashcards.yourname`.
4. Pick the device and press **Run**.

Apps signed by a free team stop opening on iPhone and iPad after 7 days. Run
again from Xcode to renew them; your progress stays. Mac builds don't expire.

## Icons

`python3 tools/skip-icons.py` (needs Pillow) draws every app icon from the
design in `public/icons/icon.svg`.
