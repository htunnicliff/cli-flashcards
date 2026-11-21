/**
 * Fails if any built deck is invalid, so a broken deck never deploys.
 *
 *   pnpm decks:check            check public/decks/
 *   pnpm decks:check some/dir   check another directory
 */
import { resolve } from 'node:path'

import { checkDecks } from './check-decks-lib'

const dir = resolve(process.cwd(), process.argv[2] ?? 'public/decks')
const problems = await checkDecks(dir)

if (problems.length > 0) {
  console.error(`Deck validation failed (${problems.length} problems in ${dir}):`)
  for (const problem of problems) console.error(`  ${problem}`)
  process.exit(1)
}
console.log(`Decks in ${dir} are valid.`)
