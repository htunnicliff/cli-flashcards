# CLI Flashcards

A spaced repetition web app for learning the flags of well-known command-line tools (git, ripgrep, sed, …). It is a Vue 3 single-page app that will become an offline-first PWA. See the [roadmap](https://github.com/htunnicliff/cli-flashcards/issues/1) for the plan.

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

CI runs lint, typecheck, tests with coverage and a build on every pull request and every push to `main`. A separate job runs the E2E tests and uploads the Playwright report and traces when they fail.

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
