# Contributing

Setup, scripts and the project layout are in the [README](README.md). This guide covers the two things contributors do most: adding a deck for a new command-line tool, and changing code without breaking the tests. The last section covers how animation is used in the app.

## Adding a deck

A deck is the set of options for one tool, such as `jq` or `grep`. The app turns each option into flashcards: one asks what a flag does, one asks for the flag that does something, and a cloze card blanks the flag out of an example command. With flag pair practice on (Settings › Practice), an option that has both a short and a long form also gets two cards that show one form and ask for the other. So a good deck needs three things from you: the right options marked as worth learning first, a short summary for each, and an example that uses each flag.

Most of that is generated. `pnpm deck:generate` reads the tool's manpage or `--help` output, and you correct the result in a small YAML file of overrides. You never edit generated JSON by hand, so the deck can be regenerated for a new tool version without losing your work.

Before starting, open a [new deck issue](https://github.com/htunnicliff/cli-flashcards/issues/new?template=new-deck.yml) so nobody else picks the same tool.

### 1. Generate the deck

Most tools have a manpage, and `deck:generate` finds it with `man -w`:

```sh
pnpm deck:generate grep --variant gnu --license GPL-3.0-or-later \
  --attribution "GNU grep manual page © Free Software Foundation, Inc. (https://www.gnu.org/software/grep/)."
```

This writes `decks/grep/gnu.generated.json`. Warnings name entries the parser skipped; read them, because a skipped option won't be in the deck (see [When the parser gets it wrong](#when-the-parser-gets-it-wrong)).

A few choices shape the command:

- **Source.** Use the manpage when there is one: it usually has fuller descriptions. Tools that ship only `--help` (many Rust and Go CLIs) use `--source help`, which runs `<tool> --help`, or `--source help --file saved-help.txt` to read saved output. The deck's `source` field records which was used.
- **Variant.** If the tool has implementations whose flags differ, give each its own deck with `--variant`, such as `gnu` and `bsd` for `sed`, `grep` and `find`. GNU `sed -i` takes an optional backup suffix, while BSD `sed -i` requires one, so one deck can't be right for both. Tools with a single implementation use the default variant, `default`. The variant is never detected automatically. To build a variant your machine doesn't have, pass its manpage with `--file`. FreeBSD pages are vendored in `vendor/freebsd/` for this.
- **Subcommands.** For tools like git, list the pages with `--pages git-log,git-commit`. Options from `git-log` get IDs like `log.oneline`.
- **License and attribution.** Record the source text's license as an SPDX identifier, plus a line crediting its authors. See [Licensing](#licensing).

Add the exact command to the list in [`decks/README.md`](decks/README.md), so anyone can regenerate the deck later.

### 2. Review the report

```sh
pnpm deck:report grep --variant gnu
```

The report counts options per tier, lists the options used most in [tldr-pages](https://github.com/tldr-pages/tldr) examples, and names any `core` option that still needs curating (see the checks in step 4).

Each option gets a **tier**, which sets the order the app introduces cards in:

- **core**: the flags most people use. The generator marks an option core when a tldr-pages example uses it, and attaches up to three of those examples.
- **common**: mentioned in the manpage's SYNOPSIS or EXAMPLES section.
- **obscure**: everything else.

That guess is a starting point. Aim for roughly 5 to 20 core options for a small tool. Promote the flags you would teach a colleague in their first week, and demote the ones that only made it in through an odd tldr example. tldr pages are vendored in `vendor/tldr/` at a pinned commit. If the tool has no page there yet, add its name to `vendor/tldr/pin.json` and run `pnpm tldr:vendor` before generating.

### 3. Write the overrides

Create `decks/<tool>/<variant>.overrides.yaml` next to the generated file. Here is part of the jq deck's overrides file, which shows the common edits:

```yaml
# yaml-language-server: $schema=../../schemas/overrides.schema.json
options: # changes to generated options, keyed by option ID
  raw-output:
    tier: core
    summary: Print strings without JSON quotes, e.g. for use in shell scripts
    examples:
      - command: jq -r '.name' package.json
  arg: # already core; the summary is rewritten and an example added
    summary: Bind a shell string to $name inside the filter
    examples:
      - command: jq --arg user "$USER" '.owner = $user' path/to/file.json
  slurpfile:
    tier: common
```

Option IDs come from the generated JSON: `deriveOptionId` builds them from the flags, so `-r, --raw-output` becomes `raw-output`. They are part of every card's ID (`jq:default:raw-output:cloze`), which is how the app keeps a learner's progress. Don't change an existing option's ID, or everyone loses their progress on its cards.

Everything an overrides file can do:

| Key                              | What it does                                                                                                                                               |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `options.<id>.summary`           | Replaces the one-line summary shown on cards.                                                                                                              |
| `options.<id>.tier`              | Sets `core`, `common` or `obscure`.                                                                                                                        |
| `options.<id>.examples`          | Adds examples after the generated ones. With `replaceExamples: true`, replaces them instead, for a shared tldr example that doesn't work for this variant. |
| `options.<id>.primary`           | Chooses which spelling leads on cards, e.g. `--color` over `--colour`.                                                                                     |
| `options.<id>.hidden`            | Keeps the option in the deck but makes no cards, e.g. for deprecated flags.                                                                                |
| `options.<id>.description`       | Replaces the long description on the back of the card.                                                                                                     |
| `options.<id>.argument`, `.tags` | Fix the argument placeholder (`null` removes it), add tags.                                                                                                |
| `merge`                          | Folds aliases into one option: `- { into: color, from: [colour] }`.                                                                                        |
| `add`                            | Adds an option the parser missed. Give `flags`, `summary` and `examples`; `tier` defaults to `common`, and `subcommand` places it in a git-style deck.     |
| `deck`                           | Overrides deck-level `license`, `attribution` or `toolVersion`.                                                                                            |

The full formats are JSON Schemas generated from the Zod schemas in `pipeline/schema/`: [`schemas/deck.schema.json`](schemas/deck.schema.json) for decks and [`schemas/overrides.schema.json`](schemas/overrides.schema.json) for overrides. The `yaml-language-server` comment on the first line gives you completion and validation in editors that support it. Run `pnpm schema:export` after changing a Zod schema.

Write every **core summary in your own words**. Aim for a short line that answers "what does this flag do for me?", such as "Print strings without JSON quotes". The generated summary is the manpage's first sentence, which is often too long for a card and, for GNU tools, GPL or GFDL text.

Give every **core option an example that spells the flag on its own**. Cloze cards blank out a flag that appears as its own word in the command, so `tar -czf` can't make a card for `-z`, but `tar -x -z -f archive.tar.gz` can. Use the short flag when one exists, and add a `description` when the command's purpose isn't obvious.

YAML treats `: ` as the start of a key, so quote any value that contains one: `summary: "Add a header, e.g. 'Accept: text/html'"`.

### 4. Build and validate

```sh
pnpm deck:build           # writes public/data/decks/ and ATTRIBUTIONS.md
pnpm deck:build --check   # what CI runs
pnpm decks:check
```

`deck:build` applies your overrides, validates the result, and writes `public/data/decks/<tool>-<variant>.json`, the manifest `public/data/decks/index.json`, and `ATTRIBUTIONS.md`. It raises a deck's `deckVersion` whenever its content changes, which is how the app notices updates. The app bundles everything in `public/data/decks/`, so run it from Xcode to try the deck (see [`apple/README.md`](apple/README.md)).

With `--check`, or whenever `CI` is set, these are errors:

- an override names an option ID the generated deck doesn't have (a **stale override**, usually after regenerating for a new tool version)
- a core summary is a close copy of the manpage text
- a core option has no example that can make a cloze card
- a built file or `ATTRIBUTIONS.md` is out of date
- the deck is invalid, for example two options share a flag

Locally they are warnings, so you can build while you work.

### 5. Open a pull request

Commit the generated JSON, the overrides file, the built files in `public/data/decks/`, `ATTRIBUTIONS.md` and your line in `decks/README.md`, then open a pull request. The [pull request template](.github/pull_request_template.md) has a checklist for deck changes.

## Licensing

Deck text comes from other people's documentation, so every deck records where it came from:

- `license` is the license of the source text, as an SPDX identifier where one exists. GNU manpages are usually `GPL-3.0-or-later` (git's are `GPL-2.0-only`); some GNU manuals are GFDL. BSD pages are `BSD-3-Clause`. Check the copyright notice in the page itself, often in a `COPYRIGHT` section or the roff comments at the top.
- `attribution` credits the authors and links the source. The generator appends a credit for tldr-pages examples, which are [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Option descriptions quote the manpage and keep its license, which is why attribution matters. Summaries for core options are the text learners see on every card, so they are written for this project. The copy check flags a core summary that is the description's opening words, or that shares 80% of its words with the description's first sentence. `ATTRIBUTIONS.md` is generated from deck metadata; don't edit it by hand.

## When the parser gets it wrong

Sometimes the parser misses an option, joins two together or garbles a summary. You can work around any of these in the overrides file, but if the cause is a pattern other tools will hit too, fix the parser so every deck benefits.

The parsers live in `tools/deck/`: `manpage/` reads roff (man(7) and mdoc(7) pages) and `help.ts` reads `--help` output. Both are pure functions, text in and deck out, and are covered by snapshot tests over real pages. To fix a bug:

1. Save the input as a fixture: a manpage in `tools/deck/manpage/fixtures/`, or `--help` output in `tools/deck/help-fixtures/` (for example `jq --help > tools/deck/help-fixtures/jq.txt`). Add a row to that folder's `README.md` with the source, version and license.
2. Add the fixture to the snapshot cases in `tools/deck/manpage.test.ts` or `tools/deck/help.test.ts`, and add a small focused test that reproduces the bug, with just the lines that trigger it. Check that it fails.
3. Fix the parser until the focused test passes.
4. Run `pnpm test -u` to update the snapshots under `tools/deck/__snapshots__/`, and read their diff. Every change in another fixture's snapshot is a change to a shipped deck, so make sure each one is an improvement.
5. Regenerate the affected decks and rebuild.

For example, `jq --help` aligns descriptions in a column but lets one long option run up to it with a single space (`--slurpfile name file set $name to …`). The parser expected two spaces, so it skipped the option. The fix splits such lines at the description column the other options use; it is covered by a focused test in `help.test.ts` and the `jq.txt` snapshot.

## Testing

Every pull request runs lint, typecheck, unit tests, the deck checks, the Swift core tests and the app builds in CI. Run the fast ones before pushing:

```sh
pnpm lint && pnpm typecheck && pnpm test
```

Each layer has a job, and a test belongs in the cheapest layer that can catch the bug:

| Layer       | Where                                                         | What belongs there                                                                                                             | Run                                           |
| ----------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------- |
| Unit        | `*.test.ts` next to the code in `pipeline/` and `tools/`      | Plain TypeScript logic: scheduling, card building, flag handling, parsers. Most tests live here.                               | `pnpm test`                                   |
| Property    | the same files, using [fast-check](https://fast-check.dev/)   | Invariants over many generated inputs, such as "shuffling options never changes a card ID" (`pipeline/schema/cards.test.ts`).  | `pnpm test`                                   |
| Snapshot    | `tools/deck/*.test.ts`, `tools/deck/__snapshots__/`           | Parser output over real manpages and `--help` fixtures, so parser changes show up in review.                                   | `pnpm test` (`pnpm test -u` to update)        |
| Deck checks | `tools/deck-build.ts`, `tools/check-decks.ts`                 | The shipped decks: schema validation, stale overrides, duplicate flags, copied summaries, missing examples, out-of-date files. | `pnpm deck:build --check`, `pnpm decks:check` |
| Parity      | `apple/FlashcardsCore/Tests/`, against `pnpm fixtures:golden` | The Swift port of scheduling, cards and answers gives the same results as `pipeline/`.                                         | `swift test` in `apple/FlashcardsCore/`       |
| App         | the app in `apple/`                                           | Screens and flows: review, decks, stats, settings, backup.                                                                     | Xcode                                         |

A bug in a function needs a unit test, even if you found it in the app.

## Motion

Animation in the app explains state changes, such as a card revealing its answer or a graded card leaving. It isn't decoration. Keep it short, never block input, and follow the Motion setting: `apple/Sources/CLIFlashcards/Theme/Motion.swift` resolves it against the system's Reduce Motion, and views read `\.reducedMotion` to swap movement for a fade.
