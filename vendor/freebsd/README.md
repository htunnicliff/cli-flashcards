# Vendored FreeBSD manpages

BSD manual pages for the `bsd` deck variants, so they can be regenerated on any OS (macOS ships near-identical pages).

- Source: [freebsd/freebsd-src](https://github.com/freebsd/freebsd-src) at commit `6dc19a71f70c99b36e4384aff75b3d71033e71c5`, files `usr.bin/<tool>/<tool>.1`.
- License: BSD-3-Clause, © The Regents of the University of California and the FreeBSD contributors (see each file's header).

To refresh one:

```sh
curl -fsSL -o vendor/freebsd/sed.1 \
  https://raw.githubusercontent.com/freebsd/freebsd-src/<commit>/usr.bin/sed/sed.1
```

Then update the commit above and regenerate the deck (see `decks/README.md`).
