import type { Repository } from './repository'
import type { PersistenceRecord } from './types'

/**
 * The parts of `navigator.storage` we use, injected so this module stays
 * framework-free and testable. Any may be missing in older browsers.
 */
export interface StorageManagerLike {
  persist?(): Promise<boolean>
  persisted?(): Promise<boolean>
  estimate?(): Promise<{ usage?: number; quota?: number }>
}

/**
 * Asks the browser not to evict our data (mobile Safari otherwise may). Call it
 * when the user finishes a review session: browsers are likelier to grant it
 * after real engagement. Only the first call asks; later calls return the
 * stored result.
 */
export async function requestPersistenceOnce(
  repository: Pick<Repository, 'settings'>,
  storage: StorageManagerLike | undefined,
  now: number = Date.now(),
): Promise<PersistenceRecord | null> {
  const previous = await repository.settings.get('persistence')
  if (previous) return previous
  if (!storage?.persist) return null
  let granted = false
  try {
    granted = await storage.persist()
  } catch {
    granted = false
  }
  const record = { requestedAt: now, granted }
  await repository.settings.set('persistence', record)
  return record
}

export type PersistenceStatus =
  /** The browser won't evict our data. */
  | 'persistent'
  /** We asked and the browser said no (it may still grant it later on its own). */
  | 'denied'
  /** We haven't asked yet; that happens after the first review session. */
  | 'not-requested'
  /** This browser has no Storage API. */
  | 'unsupported'

export interface StorageReport {
  persistence: PersistenceStatus
  /** Bytes used and available to this site, when the browser says. */
  usage?: number
  quota?: number
}

export async function getStorageReport(
  repository: Pick<Repository, 'settings'>,
  storage: StorageManagerLike | undefined,
): Promise<StorageReport> {
  const report: StorageReport = { persistence: 'unsupported' }
  if (storage?.estimate) {
    try {
      const { usage, quota } = await storage.estimate()
      if (usage !== undefined) report.usage = usage
      if (quota !== undefined) report.quota = quota
    } catch {
      // Leave the estimate out.
    }
  }
  if (!storage?.persisted) return report
  let persisted = false
  try {
    persisted = await storage.persisted()
  } catch {
    persisted = false
  }
  if (persisted) report.persistence = 'persistent'
  else {
    const record = await repository.settings.get('persistence')
    report.persistence = record ? 'denied' : 'not-requested'
  }
  return report
}

/** `1536` → `"1.5 KB"`. Uses 1024-based units, as browsers report quota. */
export function formatBytes(bytes: number): string {
  const units = ['bytes', 'KB', 'MB', 'GB', 'TB']
  let value = bytes
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit++
  }
  if (unit === 0) return `${Math.round(value)} ${value === 1 ? 'byte' : 'bytes'}`
  return `${value < 10 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`
}
