import { Dexie, type DexieOptions, type EntityTable } from 'dexie'

import type { CardState, ReviewLogEntry, SettingRow, StoredDeck } from './types'

export const DEFAULT_DATABASE_NAME = 'recall'

/**
 * Every version of the IndexedDB schema, oldest first. Dexie replays them in
 * order, so a browser on any older version is upgraded step by step.
 *
 * To change the schema:
 *
 * 1. Append a new entry with the next `version`. Never edit or remove an entry
 *    that has shipped: browsers in the wild are sitting on it.
 * 2. `stores` lists only the tables that change. Set a table to `null` to drop
 *    it. Only the primary key and indexed fields are declared; other fields can
 *    be added to records at any time without a new version.
 * 3. When existing records need reshaping, add an `upgrade` that rewrites them
 *    inside the upgrade transaction (`tx.table('cardStates').toCollection().modify(...)`).
 *    Upgrades must never delete review log entries.
 * 4. Add a test in `database.test.ts` that opens the previous version with
 *    `openDatabase({ version })`, writes old-shaped records, then opens the
 *    latest version and checks the records came through.
 */
export const SCHEMA_VERSIONS: readonly SchemaVersion[] = [
  {
    version: 1,
    stores: {
      decks: 'id',
      // `[deckId+optionId]` finds a removed option's states when it returns.
      cardStates: 'cardId, deckId, [deckId+optionId], fsrs.due',
      reviewLog: '++id, cardId, deckId, reviewedAt',
      settings: 'key',
    },
  },
]

export interface SchemaVersion {
  version: number
  stores: Record<string, string | null>
  upgrade?: Parameters<ReturnType<Dexie['version']>['upgrade']>[0]
}

export const LATEST_SCHEMA_VERSION = SCHEMA_VERSIONS.at(-1)!.version

export class FlashcardsDatabase extends Dexie {
  decks!: EntityTable<StoredDeck, 'id'>
  cardStates!: EntityTable<CardState, 'cardId'>
  reviewLog!: EntityTable<ReviewLogEntry, 'id'>
  settings!: EntityTable<SettingRow, 'key'>

  constructor(
    name: string,
    dependencies: DexieDependencies | undefined,
    upTo: number = LATEST_SCHEMA_VERSION,
  ) {
    super(name, dependencies)
    for (const { version, stores, upgrade } of SCHEMA_VERSIONS) {
      if (version > upTo) break
      const declared = this.version(version).stores(stores)
      if (upgrade) declared.upgrade(upgrade)
    }
  }
}

/** Lets tests and Node pass `fake-indexeddb` instead of the browser's IndexedDB. */
export type DexieDependencies = Required<Pick<DexieOptions, 'indexedDB' | 'IDBKeyRange'>>

export interface OpenDatabaseOptions {
  name?: string
  dependencies?: DexieDependencies
  /** Open an older schema version; only migration tests need this. */
  version?: number
}

export function openDatabase(options: OpenDatabaseOptions = {}): FlashcardsDatabase {
  return new FlashcardsDatabase(
    options.name ?? DEFAULT_DATABASE_NAME,
    options.dependencies,
    options.version,
  )
}
