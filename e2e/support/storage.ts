import type { Page } from '@playwright/test'

/** A blank same-origin page, so storage can be seeded before the app first opens it. */
const BLANK_PATH = '/__e2e_blank__'

export interface ObjectStoreSeed {
  keyPath?: string | string[]
  autoIncrement?: boolean
  indexes?: { name: string; keyPath: string | string[]; unique?: boolean; multiEntry?: boolean }[]
  records?: unknown[]
}

export interface DatabaseSeed {
  name: string
  version: number
  stores: Record<string, ObjectStoreSeed>
}

/**
 * Seeds IndexedDB before the app loads: opens a blank page on the app's origin, creates
 * the database with the given stores and records, and leaves the page there. Navigate to
 * the app afterwards. Every test already starts from a fresh browser context, so storage
 * is empty unless a test seeds it.
 *
 * Keep the store layout in step with the app's Dexie schema (#8). Dexie opens an existing
 * database at version `n` as IndexedDB version `n * 10`, so pass that number here.
 */
export async function seedIndexedDB(page: Page, seed: DatabaseSeed) {
  await page.route(BLANK_PATH, (route) =>
    route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>seed</title>' }),
  )
  await page.goto(BLANK_PATH)
  await page.evaluate(
    (db) =>
      new Promise<void>((resolve, reject) => {
        const request = indexedDB.open(db.name, db.version)
        request.onupgradeneeded = () => {
          for (const [name, store] of Object.entries(db.stores)) {
            const objectStore = request.result.createObjectStore(name, {
              keyPath: store.keyPath,
              autoIncrement: store.autoIncrement,
            })
            for (const index of store.indexes ?? []) {
              objectStore.createIndex(index.name, index.keyPath, {
                unique: index.unique,
                multiEntry: index.multiEntry,
              })
            }
          }
        }
        request.onerror = () => reject(request.error)
        request.onsuccess = () => {
          const connection = request.result
          const names = Object.keys(db.stores)
          if (names.length === 0) {
            connection.close()
            resolve()
            return
          }
          const tx = connection.transaction(names, 'readwrite')
          for (const [name, store] of Object.entries(db.stores)) {
            for (const record of store.records ?? []) tx.objectStore(name).put(record)
          }
          tx.oncomplete = () => {
            connection.close()
            resolve()
          }
          tx.onerror = () => reject(tx.error)
        }
      }),
    seed,
  )
  await page.unroute(BLANK_PATH)
}

/** Reads every record of one object store, for asserting what the app persisted. */
export async function readStore<T = unknown>(page: Page, dbName: string, storeName: string) {
  return page.evaluate(
    ([name, store]) =>
      new Promise<T[]>((resolve, reject) => {
        const request = indexedDB.open(name)
        request.onerror = () => reject(request.error)
        request.onsuccess = () => {
          const connection = request.result
          const all = connection.transaction(store, 'readonly').objectStore(store).getAll()
          all.onsuccess = () => {
            connection.close()
            resolve(all.result as T[])
          }
          all.onerror = () => reject(all.error)
        }
      }),
    [dbName, storeName] as const,
  )
}
