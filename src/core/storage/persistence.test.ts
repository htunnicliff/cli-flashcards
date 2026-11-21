import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import {
  formatBytes,
  getStorageReport,
  requestPersistenceOnce,
  type StorageManagerLike,
} from './persistence'
import { createRepository, type Repository } from './repository'
import { fakeIndexedDB, uniqueDatabaseName } from './test-utils'

let repo: Repository

beforeEach(() => {
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})

afterEach(async () => {
  await repo.destroy()
})

function fakeStorage(granted: boolean): StorageManagerLike & { persisted: () => Promise<boolean> } {
  let persisted = false
  return {
    persist: vi.fn(async () => {
      persisted = granted
      return granted
    }),
    persisted: vi.fn(async () => persisted),
    estimate: vi.fn(async () => ({ usage: 2048, quota: 1024 ** 3 })),
  }
}

describe('requestPersistenceOnce', () => {
  it('asks once and remembers the answer', async () => {
    const storage = fakeStorage(true)
    expect(await requestPersistenceOnce(repo, storage, 10)).toEqual({
      requestedAt: 10,
      granted: true,
    })
    expect(await requestPersistenceOnce(repo, storage, 20)).toEqual({
      requestedAt: 10,
      granted: true,
    })
    expect(storage.persist).toHaveBeenCalledTimes(1)
  })

  it('records a refusal, including one that throws', async () => {
    const storage: StorageManagerLike = { persist: () => Promise.reject(new Error('nope')) }
    expect(await requestPersistenceOnce(repo, storage, 10)).toEqual({
      requestedAt: 10,
      granted: false,
    })
  })

  it('does nothing without a Storage API', async () => {
    expect(await requestPersistenceOnce(repo, undefined)).toBeNull()
    expect(await repo.settings.get('persistence')).toBeNull()
  })
})

describe('getStorageReport', () => {
  it('reports not-requested, then persistent once granted', async () => {
    const storage = fakeStorage(true)
    expect(await getStorageReport(repo, storage)).toEqual({
      persistence: 'not-requested',
      usage: 2048,
      quota: 1024 ** 3,
    })
    await requestPersistenceOnce(repo, storage)
    expect((await getStorageReport(repo, storage)).persistence).toBe('persistent')
  })

  it('reports denied after a refusal', async () => {
    const storage = fakeStorage(false)
    await requestPersistenceOnce(repo, storage)
    expect((await getStorageReport(repo, storage)).persistence).toBe('denied')
  })

  it('reports unsupported without a Storage API, and survives a failing estimate', async () => {
    expect(await getStorageReport(repo, undefined)).toEqual({ persistence: 'unsupported' })
    expect(
      await getStorageReport(repo, { estimate: () => Promise.reject(new Error('x')) }),
    ).toEqual({ persistence: 'unsupported' })
  })
})

describe('formatBytes', () => {
  it.each([
    [0, '0 bytes'],
    [1, '1 byte'],
    [1023, '1023 bytes'],
    [1536, '1.5 KB'],
    [20 * 1024 ** 2, '20 MB'],
    [3.25 * 1024 ** 3, '3.3 GB'],
  ])('%i → %s', (bytes, text) => {
    expect(formatBytes(bytes)).toBe(text)
  })
})
