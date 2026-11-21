# CLI Flashcards

A spaced repetition web app for learning the flags of well-known command-line tools (git, ripgrep, sed, …). It is a Vue 3 single-page app that will become an offline-first PWA. See the [roadmap](https://github.com/htunnicliff/cli-flashcards/issues/1) for the plan.

**Live:** <https://htunnicliff.github.io/cli-flashcards/>

## Prerequisites

- **Node.js 22** (22.12 or later). The exact version is pinned in [`.nvmrc`](.nvmrc), so `nvm use` or `fnm use` picks it up.
- **pnpm 10**. The version is pinned in `package.json` under `packageManager`; running `corepack enable` once makes the right version available.

## Install

```sh
pnpm install
```

## Scripts

| Command              | What it does                                                         |
| -------------------- | -------------------------------------------------------------------- |
| `pnpm dev`           | Start the Vite dev server with hot reload.                           |
| `pnpm build`         | Type check, then build the production bundle into `dist/`.           |
| `pnpm preview`       | Serve the built `dist/` locally.                                     |
| `pnpm typecheck`     | Run `vue-tsc` across the app, Node scripts and tests.                |
| `pnpm lint`          | Run ESLint and check formatting with Prettier.                       |
| `pnpm lint:fix`      | Fix what ESLint can and rewrite files with Prettier.                 |
| `pnpm format`        | Rewrite files with Prettier.                                         |
| `pnpm test`          | Run all Vitest tests once.                                           |
| `pnpm test:watch`    | Run Vitest in watch mode.                                            |
| `pnpm test:coverage` | Run tests with a coverage report for `src/core/` and `tools/`.       |
| `pnpm test:e2e`      | Build the app and run the Playwright E2E tests against it.           |
| `pnpm test:e2e --ui` | Open Playwright's UI mode to run and debug E2E tests.                |
| `pnpm schema:export` | Regenerate `schemas/deck.schema.json` from the Zod deck schema.      |
| `pnpm deck:generate` | Generate a deck from a tool's manpage (see below).                   |
| `pnpm decks:check`   | Validate the built decks in `public/data/decks/` against the schema. |

CI runs lint, typecheck, tests with coverage and a build on every pull request and every push to `main`. Separate jobs check the decks and run the E2E tests (uploading the Playwright report and traces when they fail).

## Offline and updates

Production builds register a service worker ([vite-plugin-pwa](https://vite-pwa-org.netlify.app/), `generateSW`). It precaches the app shell, so the app loads and reviews work with no network once it has been opened. `data/decks/index.json` is network-first with a cache fallback, and deck files are cached as they are fetched; installed decks themselves live in IndexedDB.

A new deploy never takes over mid-session: the app shows an "Update available" banner and switches only when the user picks Reload. Long-open tabs check for a new version hourly. The header shows "Offline" while the browser has no connection. The manifest is the hand-written `public/manifest.webmanifest`. There is no service worker in `pnpm dev`; use the production build (`pnpm build && pnpm preview`) or the E2E tests in `e2e/offline.spec.ts`.

## Deploy

Every push to `main` deploys to [GitHub Pages](https://htunnicliff.github.io/cli-flashcards/) from the `deploy` job in [`ci.yml`](.github/workflows/ci.yml). It runs only after the unit, deck and E2E jobs pass, builds the decks, fails if any deck is invalid, then builds the app with `BASE_PATH=/cli-flashcards/` so assets, the manifest and the service worker scope sit under the subpath. `404.html` is a copy of `index.html`, so deep links like `/cli-flashcards/decks` load the app.

To try the subpath build locally: `BASE_PATH=/cli-flashcards/ pnpm exec vite build && BASE_PATH=/cli-flashcards/ pnpm preview`, then open <http://localhost:4173/cli-flashcards/>.

## Layout

```
src/
  app/      Vue components, views, router and Pinia stores
  schema/   Shared types and Zod schemas, used by the app and by build scripts
  core/     Framework-free logic (scheduling, answer checking), tested without Vue
tools/      Node build scripts (deck generation)
decks/      Generated and curated deck data
```

`src/schema/` and `src/core/` must not import Vue or browser APIs, so the Node tools in `tools/` can import them too. The `@/` alias points at `src/`.

### Storage

All persistent state lives in IndexedDB through [Dexie](https://dexie.org/), behind the typed repository in `src/core/storage/`. The rest of the app gets it with `useRepository()` (or `getRepository()` outside components) and never touches Dexie directly. Browser globals are injected, so the repository runs in Node tests against [fake-indexeddb](https://github.com/dumbmatter/fakeIndexedDB). The review log is append-only and is only cleared by an explicit progress reset. Schema changes follow the steps documented on `SCHEMA_VERSIONS` in `src/core/storage/database.ts`.

## Generating decks

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

Tests sit next to the code they cover as `*.test.ts`. Vitest runs two projects:

- **unit**: `src/core/`, `src/schema/` and `tools/` in a Node environment.
- **app**: `src/app/` in [happy-dom](https://github.com/capricorn86/happy-dom), with [Vue Test Utils](https://test-utils.vuejs.org/) for component tests.

[fast-check](https://fast-check.dev/) is available for property-based tests; see `src/core/clamp.test.ts` for an example.

## End-to-end tests

E2E tests live in `e2e/` and use [Playwright](https://playwright.dev/). They run against the production build, because the service worker only exists there. `e2e/build.ts` builds into `dist-e2e/` and replaces the real decks with the fixture decks in `e2e/fixtures/decks/`, and `e2e/serve.ts` serves it (it can also simulate a new deploy or a network outage per browser context; see `e2e/support/pwa.ts`), so deck content changes don't break E2E tests.

```sh
pnpm exec playwright install chromium webkit   # once
pnpm test:e2e                                  # all projects
pnpm test:e2e --project=chromium               # one project
pnpm test:e2e --ui                             # UI mode
```

There are three projects: desktop Chromium, desktop WebKit (closest to iOS Safari) and a mobile viewport. Every test runs with reduced motion and in a new browser context, so storage starts empty.

Import `test` and `expect` from `e2e/support/test.ts`, which fails a test on any uncaught page error. Helpers:

- `expectNoA11yViolations(page)` in `e2e/support/a11y.ts` fails on serious or critical axe violations.
- `seedIndexedDB(page, seed)` in `e2e/support/storage.ts` creates a database with records before the app loads, for tests that need existing progress. `readStore()` reads one back.
- `fixtureDeck()` in `e2e/support/fixtures.ts` returns a fixture deck's JSON.

`page.route()` doesn't see requests the service worker answers, so a spec that stubs responses with it should add `test.use({ serviceWorkers: 'block' })`.

Keep E2E tests few and focused on flows that cross boundaries (UI, storage, service worker). Logic edge cases belong in unit tests. Avoid screenshot comparisons.
