import { mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { checkDecks } from './check-decks-lib'

const validDeck = {
  schemaVersion: 1,
  id: 'rg',
  tool: 'rg',
  variant: 'default',
  toolVersion: '14.1.0',
  deckVersion: 1,
  source: 'manual',
  license: 'MIT',
  attribution: 'test',
  options: [{ id: 'short-i', flags: ['-i'], summary: 'Ignore case.', tier: 'core' }],
}

describe('checkDecks', () => {
  let dir: string

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'decks-'))
  })
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true })
  })

  const write = (file: string, value: unknown) =>
    writeFile(join(dir, file), typeof value === 'string' ? value : JSON.stringify(value))

  it('passes valid decks and a consistent index', async () => {
    await write('rg.json', validDeck)
    await write('index.json', { decks: [{ id: 'rg', path: 'rg.json' }] })
    expect(await checkDecks(dir)).toEqual([])
  })

  it('passes when there are no decks yet', async () => {
    expect(await checkDecks(join(dir, 'missing'))).toEqual([])
  })

  it('reports schema problems with the file and path', async () => {
    await write('rg.json', { ...validDeck, deckVersion: 0 })
    expect(await checkDecks(dir)).toEqual([
      'rg.json: deckVersion: Too small: expected number to be >0',
    ])
  })

  it('reports invalid JSON', async () => {
    await write('rg.json', '{')
    const problems = await checkDecks(dir)
    expect(problems).toHaveLength(1)
    expect(problems[0]).toMatch(/^rg\.json: invalid JSON/)
  })

  it('reports index entries that point at missing files', async () => {
    await write('index.json', { decks: [{ id: 'rg', path: 'rg.json' }] })
    expect(await checkDecks(dir)).toEqual(['index.json: decks.0.path: rg.json does not exist'])
  })

  it('checks the E2E fixture decks', async () => {
    expect(await checkDecks(join(import.meta.dirname, '../e2e/fixtures/decks'))).toEqual([])
  })
})
