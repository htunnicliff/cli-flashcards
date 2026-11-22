# CLI Flashcards

Spaced repetition flashcards for learning the flags of well-known command-line tools (git, ripgrep, sed, …).

The app is native SwiftUI for iPhone, iPad and Mac, and also runs on Android through [Skip](https://skip.dev). It lives in [`apple/`](apple/README.md), and its decks are bundled into it, so it works offline from the first launch. Downloads are on the [releases page](https://github.com/htunnicliff/cli-flashcards/releases). See the [roadmap](https://github.com/htunnicliff/cli-flashcards/issues/70) for the plan.

This top level holds the TypeScript deck pipeline. It generates the decks in `public/data/decks/` from manpages and tldr-pages, and writes the parity fixtures that the Swift tests check against.

## Prerequisites

- **Node.js 22** (22.12 or later). The exact version is pinned in [`.nvmrc`](.nvmrc), so `nvm use` or `fnm use` picks it up.
- **pnpm 10**. The version is pinned in `package.json` under `packageManager`; running `corepack enable` once makes the right version available.
- For the app: Xcode and [Skip](https://skip.dev). See [`apple/README.md`](apple/README.md).

## Install

```sh
pnpm install
```

## Scripts

| Command                | What it does                                                               |
| ---------------------- | -------------------------------------------------------------------------- |
| `pnpm typecheck`       | Type check the pipeline, tools and tests.                                  |
| `pnpm lint`            | Run ESLint and check formatting with Prettier.                             |
| `pnpm lint:fix`        | Fix what ESLint can and rewrite files with Prettier.                       |
| `pnpm format`          | Rewrite files with Prettier.                                               |
| `pnpm test`            | Run all Vitest tests once.                                                 |
| `pnpm test:watch`      | Run Vitest in watch mode.                                                  |
| `pnpm test:coverage`   | Run tests with a coverage report for `pipeline/` and `tools/`.             |
| `pnpm schema:export`   | Regenerate `schemas/deck.schema.json` from the Zod deck schema.            |
| `pnpm deck:generate`   | Generate a deck from a tool's manpage (see below).                         |
| `pnpm deck:build`      | Apply overrides and write the built decks, manifest and `ATTRIBUTIONS.md`. |
| `pnpm decks:check`     | Validate the built decks in `public/data/decks/` against the schema.       |
| `pnpm fixtures:golden` | Rewrite the parity fixtures in `apple/FlashcardsCore/Tests/Fixtures/`.     |

CI runs lint, typecheck and tests with coverage on every pull request and every push to `main`. Separate jobs check the decks and the parity fixtures, run the Swift core tests, and build the app for iOS, macOS and Android.

## Layout

```
pipeline/
  schema/   Zod schemas and types for decks, cards and flags
  core/     The scheduling (ts-fsrs) and answer-checking logic the parity fixtures come from
tools/      Node build scripts: deck generation, building, checks, fixtures
decks/      Generated and curated deck data
public/data/decks/   Built decks, bundled into the app
apple/      The Skip app and its Swift core (FlashcardsCore)
```

The Swift core in `apple/FlashcardsCore` is a port of `pipeline/`. When you change scheduling, card or answer logic here, run `pnpm fixtures:golden` and make the Swift tests pass against the new fixtures.

## Generating decks

To add a deck for a new tool, follow the step-by-step guide in [CONTRIBUTING.md](CONTRIBUTING.md#adding-a-deck). This section is a reference for the tools it uses.

`pnpm deck:generate <tool>` finds the tool's manpage with `man -w`, parses its options and writes `decks/<tool>/<variant>.generated.json`.

```sh
pnpm deck:generate rg
pnpm deck:generate git --pages git-log,git-commit   # options get IDs like log.oneline
pnpm deck:generate sed --variant gnu --license GPL-3.0-or-later
```

Decks are keyed by tool **and variant**, because flags differ between implementations (GNU `sed -i` takes an optional suffix, BSD `sed -i` requires one). The variant is always given explicitly, and `--file` builds from any manpage file, so a BSD deck can be built on Linux and vice versa. Tools with no manpage can use their `--help` output instead:

```sh
pnpm deck:generate sed --variant bsd --file vendor/freebsd/sed.1 --tool-version freebsd-14
pnpm deck:generate ruff --source help --pages check,format   # runs `ruff check --help`, …
pnpm deck:generate fd --source help --file fd-help.txt
```

The deck's `source` field records which parser produced it (`manpage` or `help`).

The parser in `tools/deck/` reads roff source directly, both man(7) pages (GNU, help2man, asciidoc/docbook) and mdoc(7) pages (BSD, macOS), so it needs no extra tools. It is pure (manpage text in, deck out) and covered by snapshot tests over the real pages in `tools/deck/manpage/fixtures/`. Run `pnpm test -u` to update the snapshots after a parser change and review the diff.

### Relevance tiers

Every option gets a `tier` so the app can introduce cards in a sensible order. `deck:generate` assigns a default:

- **core**: used in a [tldr-pages](https://github.com/tldr-pages/tldr) example for the tool. Those examples (up to three per option, long flags rewritten to the primary short flag) are attached as `examples` and feed cloze cards.
- **common**: mentioned in the manpage's SYNOPSIS or EXAMPLES.
- **obscure**: everything else.

tldr pages are vendored in `vendor/tldr/` at a pinned commit so builds are reproducible (`pnpm tldr:vendor` refreshes them). `pnpm deck:report <tool>` prints the count per tier and the most-used options; fix anything that looks wrong with `tier:` in the overrides file.

### Curating with overrides

Generated decks are never edited by hand. Fixes go in `decks/<tool>/<variant>.overrides.yaml`, which `pnpm deck:build` applies on top of the generated deck to produce `public/data/decks/<tool>-<variant>.json` (the file the app loads) and the `public/data/decks/index.json` manifest. Regenerating a deck keeps every override.

```yaml
# yaml-language-server: $schema=../../schemas/overrides.schema.json
deck:
  license: MIT OR Unlicense
options: # patches, keyed by option ID
  ignore-case:
    tier: core
    summary: Match case-insensitively
    examples: [{ command: 'rg -i todo' }] # added to the generated examples
  sort-files: { hidden: true } # stays in the deck, makes no cards
merge: # fold aliases into one option
  - { into: color, from: [colour] }
add: # options the parser missed
  - { flags: ['-0', '--null'], summary: Print NUL after file names }
```

`deckVersion` goes up by one whenever a deck's built content changes, which is how the app spots deck updates. Overrides that name an option the generated deck no longer has are reported as stale; CI runs `pnpm deck:build --check`, which fails on stale overrides, invalid or duplicate flags, and built files that are out of date.

## Tests

Tests sit next to the code they cover as `*.test.ts` and run in Node. [fast-check](https://fast-check.dev/) is available for property-based tests; see `pipeline/schema/cards.test.ts` for examples.

The app's tests are Swift: `swift test` in `apple/FlashcardsCore/`, and UI tests in Xcode. See [`apple/README.md`](apple/README.md).
