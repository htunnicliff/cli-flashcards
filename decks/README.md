# Decks

Each tool has a folder with one pair of files per variant:

- `<variant>.generated.json`: written by `pnpm deck:generate`. Never edit it by hand.
- `<variant>.overrides.yaml`: hand-written curation, applied by `pnpm deck:build`.

The commands below regenerate every shipped deck. GNU pages come from the Ubuntu 24.04 packages of each tool (`git-man` for git); BSD pages are vendored in `vendor/freebsd/`.

```sh

pnpm deck:generate git --pages git-log,git-commit,git-rebase,git-reset,git-diff,git-stash,git-checkout,git-switch,git-branch,git-push \
  --license GPL-2.0-only --attribution "Git manual pages by the Git project contributors (https://git-scm.com/docs)."

pnpm deck:generate rg --license 'MIT OR Unlicense' \
  --attribution 'ripgrep manual page by Andrew Gallant and contributors (https://github.com/BurntSushi/ripgrep).'

for t in sed grep find; do
  pkg=$t; [ $t = find ] && pkg=findutils
  pnpm deck:generate $t --variant gnu --license GPL-3.0-or-later \
    --attribution "GNU $t manual page © Free Software Foundation, Inc. (https://www.gnu.org/software/$pkg/)."
  pnpm deck:generate $t --variant bsd --file vendor/freebsd/$t.1 --tool-version freebsd-15 --license BSD-3-Clause \
    --attribution "FreeBSD $t(1) manual page © The Regents of the University of California and FreeBSD contributors (https://github.com/freebsd/freebsd-src)."
done

pnpm deck:generate tar --variant gnu --license GPL-3.0-or-later \
  --attribution "GNU tar manual page © Free Software Foundation, Inc. (https://www.gnu.org/software/tar/)."

pnpm deck:generate curl --license curl \
  --attribution "curl manual page © Daniel Stenberg and contributors (https://curl.se/docs/manpage.html)."

pnpm deck:build
```

| Deck           | Source                 | License          |
| -------------- | ---------------------- | ---------------- |
| `git-default`  | git 2.43.0 manpages    | GPL-2.0-only     |
| `rg-default`   | ripgrep 14.1.0 manpage | MIT OR Unlicense |
| `sed-gnu`      | GNU sed 4.9            | GPL-3.0-or-later |
| `sed-bsd`      | FreeBSD sed(1)         | BSD-3-Clause     |
| `grep-gnu`     | GNU grep 3.11          | GPL-3.0-or-later |
| `grep-bsd`     | FreeBSD grep(1)        | BSD-3-Clause     |
| `find-gnu`     | GNU findutils 4.9.0    | GPL-3.0-or-later |
| `find-bsd`     | FreeBSD find(1)        | BSD-3-Clause     |
| `tar-gnu`      | GNU tar 1.35           | GPL-3.0-or-later |
| `curl-default` | curl 8.5.0             | curl             |

tldr-pages examples (CC BY 4.0) are attached to every deck. `ATTRIBUTIONS.md` at the repo root is generated from deck metadata by `pnpm deck:build`.
