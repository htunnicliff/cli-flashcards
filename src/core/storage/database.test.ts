import { describe, expect, it } from 'vitest'

import { LATEST_SCHEMA_VERSION, openDatabase, SCHEMA_VERSIONS } from './database'
import { createRepository } from './repository'
import { fakeIndexedDB, makeCardState, makeLogEntry, uniqueDatabaseName } from './test-utils'

describe('schema versions', () => {
  it('are numbered 1, 2, 3, … in order', () => {
    expect(SCHEMA_VERSIONS.map((v) => v.version)).toEqual(
      SCHEMA_VERSIONS.map((_, index) => index + 1),
    )
    expect(LATEST_SCHEMA_VERSION).toBe(SCHEMA_VERSIONS.length)
  })

  it('opens at the latest version with every table', async () => {
    const db = openDatabase({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
    await db.open()
    expect(db.verno).toBe(LATEST_SCHEMA_VERSION)
    expect(db.tables.map((t) => t.name).sort()).toEqual([
      'cardStates',
      'decks',
      'reviewLog',
      'settings',
    ])
    await db.delete()
  })

  // Each schema change adds a case here: write records at the old version,
  // reopen at the latest and check they survived the upgrade.
  it.each(SCHEMA_VERSIONS.slice(0, -1).map((v) => v.version))(
    'upgrades from version %i without losing progress',
    async (version) => {
      const name = uniqueDatabaseName()
      const old = createRepository(openDatabase({ name, dependencies: fakeIndexedDB, version }))
      const state = makeCardState('grep:gnu:i:cloze')
      await old.recordReview(state, makeLogEntry(state.cardId))
      old.close()

      const latest = createRepository({ name, dependencies: fakeIndexedDB })
      expect(await latest.cardStates.get(state.cardId)).toBeDefined()
      expect(await latest.reviewLog.count()).toBe(1)
      await latest.destroy()
    },
  )
})
