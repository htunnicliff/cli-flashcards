/**
 * Builds the app for E2E tests into `dist-e2e/`, then replaces the real decks with
 * the fixture decks, so deck content changes never break E2E tests.
 */
import { cp, rm } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

import { build } from 'vite'

const root = fileURLToPath(new URL('..', import.meta.url))
const outDir = fileURLToPath(new URL('../dist-e2e', import.meta.url))
const fixtures = fileURLToPath(new URL('./fixtures/decks', import.meta.url))

await build({ root, logLevel: 'warn', build: { outDir, emptyOutDir: true } })
await rm(`${outDir}/decks`, { recursive: true, force: true })
await cp(fixtures, `${outDir}/decks`, { recursive: true })
