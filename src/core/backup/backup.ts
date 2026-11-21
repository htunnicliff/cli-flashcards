import { z } from 'zod'

import {
  CARD_PHASES,
  SETTING_DEFAULTS,
  type CardState,
  type PendingDeckInstall,
  type Repository,
  type ReviewLogEntry,
  type Settings,
} from '../storage'

/** Bump when the backup format changes; `parseBackup` must keep reading older versions. */
export const BACKUP_VERSION = 1
export const BACKUP_FORMAT = 'recall-backup'

const FsrsStateSchema = z.object({
  phase: z.enum(CARD_PHASES),
  due: z.number(),
  stability: z.number(),
  difficulty: z.number(),
  elapsedDays: z.number(),
  scheduledDays: z.number(),
  learningSteps: z.number(),
  reps: z.number().int().nonnegative(),
  lapses: z.number().int().nonnegative(),
  lastReview: z.number().optional(),
})

const CardStateSchema = z.object({
  cardId: z.string().min(1),
  deckId: z.string().min(1),
  optionId: z.string().min(1),
  fsrs: FsrsStateSchema,
  suspended: z.boolean(),
  buriedUntil: z.number().optional(),
})

const ReviewLogEntrySchema = z.object({
  cardId: z.string().min(1),
  deckId: z.string().min(1),
  reviewedAt: z.number(),
  rating: z.union([z.literal(1), z.literal(2), z.literal(3), z.literal(4)]),
  durationMs: z.number().nonnegative(),
  before: FsrsStateSchema.nullable(),
  after: FsrsStateSchema,
})

const BackupDeckSchema = z.object({
  id: z.string().min(1),
  deckVersion: z.number().int().positive(),
  includeObscure: z.boolean(),
})

/**
 * Settings that travel with a backup. Device-specific ones (storage
 * persistence, last backup time, pending installs) stay behind.
 */
const BackupSettingsSchema = z
  .object({
    desiredRetention: z.number(),
    newCardsPerDay: z.number(),
    maxReviewsPerDay: z.number(),
    dayRolloverHour: z.number(),
  })
  .partial()
export type BackupSettings = z.infer<typeof BackupSettingsSchema>
const BACKUP_SETTING_KEYS = Object.keys(BackupSettingsSchema.shape) as (keyof BackupSettings)[]

export const BackupSchema = z.object({
  format: z.literal(BACKUP_FORMAT),
  backupVersion: z.literal(BACKUP_VERSION),
  exportedAt: z.number(),
  decks: z.array(BackupDeckSchema),
  cardStates: z.array(CardStateSchema),
  /** Oldest first. */
  reviewLog: z.array(ReviewLogEntrySchema),
  settings: BackupSettingsSchema,
})
export type Backup = z.infer<typeof BackupSchema>

export class BackupError extends Error {
  override name = 'BackupError'
}

/** Snapshot of everything worth keeping. Also records `lastBackupAt`. */
export async function exportBackup(
  repository: Repository,
  now: number = Date.now(),
): Promise<Backup> {
  const backup = await repository.atomically(async () => {
    const [decks, cardStates, reviewLog, settings] = await Promise.all([
      repository.decks.list(),
      repository.cardStates.dueBy(Infinity),
      repository.reviewLog.all(),
      repository.settings.getAll(),
    ])
    return {
      format: BACKUP_FORMAT,
      backupVersion: BACKUP_VERSION,
      exportedAt: now,
      decks: decks
        .map((d) => ({ id: d.id, deckVersion: d.deckVersion, includeObscure: d.includeObscure }))
        .sort((a, b) => a.id.localeCompare(b.id)),
      cardStates: cardStates.sort((a, b) => a.cardId.localeCompare(b.cardId)),
      reviewLog: reviewLog.map(withoutId),
      settings: pickBackupSettings(settings),
    } satisfies Backup
  })
  await repository.settings.set('lastBackupAt', now)
  return backup
}

/** Validates parsed JSON (or a JSON string) as a backup, with a readable error. */
export function parseBackup(input: unknown): Backup {
  let data = input
  if (typeof input === 'string') {
    try {
      data = JSON.parse(input)
    } catch {
      throw new BackupError('This file isn’t valid JSON.')
    }
  }
  if (
    typeof data !== 'object' ||
    data === null ||
    (data as { format?: unknown }).format !== BACKUP_FORMAT
  ) {
    throw new BackupError('This file isn’t a --recall backup.')
  }
  const version = (data as { backupVersion?: unknown }).backupVersion
  if (typeof version === 'number' && version > BACKUP_VERSION) {
    throw new BackupError(
      'This backup was made by a newer version of the app. Update and try again.',
    )
  }
  const result = BackupSchema.safeParse(data)
  if (!result.success) {
    const issue = result.error.issues[0]!
    const path = issue.path.join('.')
    throw new BackupError(`This backup is damaged (${path || 'file'}: ${issue.message}).`)
  }
  return result.data
}

export interface BackupSummary {
  decks: string[]
  cards: number
  reviews: number
  firstReview?: number
  lastReview?: number
  exportedAt: number
}

export function summarizeBackup(backup: Backup): BackupSummary {
  const times = backup.reviewLog.map((e) => e.reviewedAt)
  return {
    decks: backup.decks.map((d) => d.id),
    cards: backup.cardStates.length,
    reviews: backup.reviewLog.length,
    ...(times.length ? { firstReview: Math.min(...times), lastReview: Math.max(...times) } : {}),
    exportedAt: backup.exportedAt,
  }
}

export type ImportMode = 'replace' | 'merge'

export interface ImportResult {
  /** Decks the backup used that aren't installed here; queued in `pendingDeckInstalls`. */
  pendingDecks: PendingDeckInstall[]
  addedReviews: number
}

/**
 * Loads a backup.
 *
 * - **replace** wipes card states and the review log, then writes the backup's,
 *   and takes its scheduling settings.
 * - **merge** adds review log entries this device doesn't have (an entry is
 *   the same if its card, time and rating match), keeps whichever card state
 *   was reviewed more recently, and keeps this device's settings.
 *
 * Either way, per-deck preferences are applied to installed decks, and decks
 * that aren't installed are queued for the deck library to install.
 */
export async function importBackup(
  repository: Repository,
  backup: Backup,
  mode: ImportMode,
): Promise<ImportResult> {
  return repository.atomically(async () => {
    let addedReviews = 0
    if (mode === 'replace') {
      await repository.resetProgress()
      await repository.cardStates.putMany(backup.cardStates)
      for (const entry of backup.reviewLog) await repository.reviewLog.append(entry)
      addedReviews = backup.reviewLog.length
      for (const key of BACKUP_SETTING_KEYS) {
        const value = backup.settings[key]
        await repository.settings.set(key, value ?? SETTING_DEFAULTS[key])
      }
    } else {
      const existing = new Set((await repository.reviewLog.all()).map(logKey))
      for (const entry of backup.reviewLog) {
        const key = logKey(entry)
        if (existing.has(key)) continue
        existing.add(key)
        await repository.reviewLog.append(entry)
        addedReviews++
      }
      const local = await repository.cardStates.getMany(backup.cardStates.map((s) => s.cardId))
      const newer = backup.cardStates.filter((incoming, i) => isNewer(incoming, local[i]))
      await repository.cardStates.putMany(newer)
    }

    const pending = new Map(
      (await repository.settings.get('pendingDeckInstalls')).map((p) => [p.id, p]),
    )
    for (const deck of backup.decks) {
      const installed = await repository.decks.get(deck.id)
      if (installed) {
        if (mode === 'replace' || deck.includeObscure) {
          await repository.decks.setIncludeObscure(deck.id, deck.includeObscure)
        }
      } else {
        pending.set(deck.id, deck)
      }
    }
    const pendingDecks = [...pending.values()]
    await repository.settings.set('pendingDeckInstalls', pendingDecks)
    return {
      pendingDecks: pendingDecks.filter((p) => backup.decks.some((d) => d.id === p.id)),
      addedReviews,
    }
  })
}

function logKey(entry: Pick<ReviewLogEntry, 'cardId' | 'reviewedAt' | 'rating'>): string {
  return `${entry.cardId}\u0000${entry.reviewedAt}\u0000${entry.rating}`
}

/** The incoming state wins when it was reviewed later, or there is no local one. */
function isNewer(incoming: CardState, local: CardState | undefined): boolean {
  if (!local) return true
  const a = incoming.fsrs.lastReview ?? -Infinity
  const b = local.fsrs.lastReview ?? -Infinity
  return a > b
}

function withoutId(entry: ReviewLogEntry): ReviewLogEntry {
  const copy = { ...entry }
  delete copy.id
  return copy
}

function pickBackupSettings(settings: Settings): BackupSettings {
  const picked: BackupSettings = {}
  for (const key of BACKUP_SETTING_KEYS) picked[key] = settings[key]
  return picked
}

/** `recall-backup-2026-01-31.json`, by local date. */
export function backupFileName(now: number): string {
  const date = new Date(now)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `recall-backup-${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}.json`
}

/** Whole days since the last backup, or `undefined` if there has never been one. */
export function daysSinceBackup(lastBackupAt: number | null, now: number): number | undefined {
  if (lastBackupAt === null) return undefined
  return Math.max(0, Math.floor((now - lastBackupAt) / (24 * 60 * 60 * 1000)))
}
