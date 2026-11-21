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

| Command              | What it does                                                    |
| -------------------- | --------------------------------------------------------------- |
| `pnpm dev`           | Start the Vite dev server with hot reload.                      |
| `pnpm build`         | Type check, then build the production bundle into `dist/`.      |
| `pnpm preview`       | Serve the built `dist/` locally.                                |
| `pnpm typecheck`     | Run `vue-tsc` across the app, Node scripts and tests.           |
| `pnpm lint`          | Run ESLint and check formatting with Prettier.                  |
| `pnpm lint:fix`      | Fix what ESLint can and rewrite files with Prettier.            |
| `pnpm format`        | Rewrite files with Prettier.                                    |
| `pnpm test`          | Run all Vitest tests once.                                      |
| `pnpm test:watch`    | Run Vitest in watch mode.                                       |
| `pnpm test:coverage` | Run tests with a coverage report for `src/core/` and `tools/`.  |
| `pnpm test:e2e`      | Build the app and run the Playwright E2E tests against it.      |
| `pnpm test:e2e --ui` | Open Playwright's UI mode to run and debug E2E tests.           |
| `pnpm schema:export` | Regenerate `schemas/deck.schema.json` from the Zod deck schema. |
| `pnpm deck:generate` | Generate a deck from a tool's manpage (see below).              |
| `pnpm decks:check`   | Validate the built decks in `public/decks/` against the schema. |

CI runs lint, typecheck, tests with coverage and a build on every pull request and every push to `main`. Separate jobs check the decks and run the E2E tests (uploading the Playwright report and traces when they fail).

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

The parser in `tools/deck/` reads roff source directly, both man(7) pages (GNU, help2man, asciidoc/docbook) and mdoc(7) pages (BSD, macOS), so it needs no extra tools. It is pure (manpage text in, deck out) and covered by snapshot tests over the real pages in `tools/deck/manpage/fixtures/`. Run `pnpm test -u` to update the snapshots after a parser change and review the diff.

### Curating with overrides

Generated decks are never edited by hand. Fixes go in `decks/<tool>/<variant>.overrides.yaml`, which `pnpm deck:build` applies on top of the generated deck to produce `public/decks/<tool>-<variant>.json` (the file the app loads) and the `public/decks/index.json` manifest. Regenerating a deck keeps every override.

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

E2E tests live in `e2e/` and use [Playwright](https://playwright.dev/). They run against the production build (`vite build` + `vite preview`), because the service worker only exists there. `e2e/build.ts` builds into `dist-e2e/` and replaces the real decks with the fixture decks in `e2e/fixtures/decks/`, so deck content changes don't break E2E tests.

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

Keep E2E tests few and focused on flows that cross boundaries (UI, storage, service worker). Logic edge cases belong in unit tests. Avoid screenshot comparisons.
