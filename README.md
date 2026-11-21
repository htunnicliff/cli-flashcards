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
| `pnpm schema:export` | Regenerate `schemas/deck.schema.json` from the Zod deck schema. |
| `pnpm deck:generate` | Generate a deck from a tool's manpage (see below).              |

CI runs lint, typecheck, tests with coverage and a build on every pull request and every push to `main`.

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

## Generating decks

`pnpm deck:generate <tool>` finds the tool's manpage with `man -w`, parses its options and writes `decks/<tool>/<variant>.generated.json`.

```sh
pnpm deck:generate rg
pnpm deck:generate git --pages git-log,git-commit   # options get IDs like log.oneline
pnpm deck:generate sed --variant gnu --license GPL-3.0-or-later
```

The parser in `tools/deck/` reads roff source directly, both man(7) pages (GNU, help2man, asciidoc/docbook) and mdoc(7) pages (BSD, macOS), so it needs no extra tools. It is pure (manpage text in, deck out) and covered by snapshot tests over the real pages in `tools/deck/manpage/fixtures/`. Run `pnpm test -u` to update the snapshots after a parser change and review the diff.

## Tests

Tests sit next to the code they cover as `*.test.ts`. Vitest runs two projects:

- **unit**: `src/core/`, `src/schema/` and `tools/` in a Node environment.
- **app**: `src/app/` in [happy-dom](https://github.com/capricorn86/happy-dom), with [Vue Test Utils](https://test-utils.vuejs.org/) for component tests.

[fast-check](https://fast-check.dev/) is available for property-based tests; see `src/core/clamp.test.ts` for an example.
