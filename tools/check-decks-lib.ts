import { readdir, readFile, stat } from 'node:fs/promises'
import { join } from 'node:path'

import { DeckSchema } from '../src/schema/deck'

async function exists(path: string) {
  return stat(path).then(
    () => true,
    () => false,
  )
}

async function readJson(path: string): Promise<{ value?: unknown; error?: string }> {
  try {
    return { value: JSON.parse(await readFile(path, 'utf8')) }
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) }
  }
}

/**
 * Validates every deck file in `dir` against the deck schema, and checks that each
 * `path` listed in `index.json` (when there is one) points at a deck file that exists.
 * Returns one message per problem; an empty list means the decks are fine.
 */
export async function checkDecks(dir: string): Promise<string[]> {
  if (!(await exists(dir))) return []
  const problems: string[] = []
  const files = (await readdir(dir)).filter((file) => file.endsWith('.json')).sort()

  for (const file of files.filter((file) => file !== 'index.json')) {
    const { value, error } = await readJson(join(dir, file))
    if (error) {
      problems.push(`${file}: invalid JSON (${error})`)
      continue
    }
    const result = DeckSchema.safeParse(value)
    for (const issue of result.error?.issues ?? []) {
      problems.push(`${file}: ${issue.path.join('.') || '(root)'}: ${issue.message}`)
    }
  }

  if (files.includes('index.json')) {
    const { value, error } = await readJson(join(dir, 'index.json'))
    if (error) {
      problems.push(`index.json: invalid JSON (${error})`)
    } else {
      const decks = (value as { decks?: unknown }).decks
      if (!Array.isArray(decks)) {
        problems.push('index.json: expected a "decks" array')
      } else {
        for (const [i, entry] of decks.entries()) {
          const path = (entry as { path?: unknown }).path
          if (typeof path === 'string' && !(await exists(join(dir, path)))) {
            problems.push(`index.json: decks.${i}.path: ${path} does not exist`)
          }
        }
      }
    }
  }

  return problems
}
