## What and why

<!-- What this changes, and the issue it closes (Closes #123). -->

## Checklist

- [ ] `pnpm lint`, `pnpm typecheck` and `pnpm test` pass
- [ ] New logic has unit tests in the cheapest layer that catches it ([Testing](../CONTRIBUTING.md#testing))

### For deck changes

- [ ] The generate command is listed in `decks/README.md`
- [ ] `license` and `attribution` match the source text's copyright notice
- [ ] Core options are the flags people use first; every core summary is in my own words
- [ ] Every core option has an example that spells its flag on its own, using the short flag where there is one
- [ ] No existing option ID was renamed (that resets learners' progress)
- [ ] `pnpm deck:build --check` passes, and `public/decks/` and `ATTRIBUTIONS.md` are committed
- [ ] Parser fixes come with a fixture, a focused test and reviewed snapshot changes
