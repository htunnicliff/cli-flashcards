import { reactive, readonly, ref, shallowRef } from 'vue'

import {
  describeChanges,
  diffDecks,
  groupByTool,
  isUpdateAvailable,
  resolveFlavor,
  variantForFlavor,
  type DeckChanges,
} from '@/core/library'
import type {
  DeckFlavor,
  DeckPreferences,
  PendingDeckInstall,
  Repository,
  StoredDeck,
} from '@/core/storage'
import type { DeckManifest, DeckManifestEntry } from '@/schema/manifest'

import { holdUpdatesDuring } from '../pwa/update-holds'
import { fetchDeck, fetchManifest, type FetchLike } from './catalog'

export interface SyncOptions {
  fetch?: FetchLike
  /** A manifest the caller already fetched, to save a request. */
  manifest?: DeckManifest
  userAgent?: string
}

export interface DeckUpdate {
  entry: DeckManifestEntry
  changes: DeckChanges
}

export interface SyncResult {
  /** Decks downloaded for the first time on this device. */
  downloaded: DeckManifestEntry[]
  /** Of those, the ones a backup import asked for. */
  restored: PendingDeckInstall[]
  updated: DeckUpdate[]
  /** Decks swapped for another flavor of the same tool: `from` is removed. */
  switched: { from: string; to: DeckManifestEntry }[]
  /** Deck IDs whose download failed; the next sync tries again. */
  failed: string[]
}

/** Progress of the sync in flight, for the Decks page and the review screen. */
const state = reactive({ running: false, done: 0, total: 0 })
const decksChanged = ref(0)
const lastResult = shallowRef<SyncResult>()

export function useDeckSync() {
  return {
    state: readonly(state),
    /** Bumps whenever a sync changes the stored decks, so views reload them. */
    changed: readonly(decksChanged),
    /** The most recent finished sync. */
    lastResult: lastResult as Readonly<typeof lastResult>,
  }
}

/** Bumps whenever decks finish downloading, so a view that loaded them reloads. */
export function useDecksChanged() {
  return readonly(decksChanged)
}

const inFlight = new WeakMap<Repository, Promise<SyncResult>>()

/**
 * Brings the device's decks in line with the deck list: downloads every tool
 * that has no deck here yet (in the user's flavor), updates decks that have a
 * newer version, installs decks a backup import queued, and, once the user has
 * picked a flavor, swaps decks of the other flavor for it. Updates keep all
 * progress, because card IDs don't change between versions.
 *
 * A deck that downloads on its own starts paused when the user already studies
 * other decks, so a new tool never floods their reviews. On a new device every
 * deck starts on.
 *
 * Failed downloads are left for the next sync. Concurrent calls for the same
 * repository share one run.
 */
export function syncDecks(repository: Repository, options: SyncOptions = {}): Promise<SyncResult> {
  const running = inFlight.get(repository)
  if (running) return running
  state.running = true
  state.done = 0
  state.total = 0
  // A reload into a new version would cut the downloads short.
  const run = holdUpdatesDuring(() => sync(repository, options))
    .then((result) => {
      lastResult.value = result
      return result
    })
    .finally(() => {
      inFlight.delete(repository)
      state.running = false
    })
  inFlight.set(repository, run)
  return run
}

/**
 * Like `syncDecks`, but never joins a run that started before the caller's
 * change (a backup import, a new flavor): waits for it, then syncs again.
 */
export async function syncDecksAfterChange(
  repository: Repository,
  options: SyncOptions = {},
): Promise<SyncResult> {
  await inFlight.get(repository)?.catch(() => {})
  return syncDecks(repository, options)
}

/** Saves the flavor the user picked, then syncs so every tool follows it. */
export async function setDeckFlavor(
  repository: Repository,
  flavor: DeckFlavor,
  options: Omit<SyncOptions, 'manifest'> = {},
): Promise<SyncResult> {
  await repository.settings.set('deckFlavor', flavor)
  return syncDecksAfterChange(repository, options)
}

interface Step {
  entry: DeckManifestEntry
  initial?: DeckPreferences
  pending?: PendingDeckInstall
  previous?: StoredDeck
  replaces?: StoredDeck
}

async function sync(repository: Repository, options: SyncOptions): Promise<SyncResult> {
  const fetchFn: FetchLike = options.fetch ?? ((input, init) => fetch(input, init))
  const userAgent =
    options.userAgent ?? (typeof navigator === 'undefined' ? '' : navigator.userAgent)
  const manifest = options.manifest ?? (await fetchManifest(fetchFn))
  const [installed, pending, chosen] = await Promise.all([
    repository.decks.list(),
    repository.settings.get('pendingDeckInstalls'),
    repository.settings.get('deckFlavor'),
  ])
  const byId = new Map(installed.map((d) => [d.id, d]))
  const entries = new Map(manifest.decks.map((entry) => [entry.id, entry]))
  const flavor = resolveFlavor(
    chosen,
    installed.map((d) => d.deck.variant),
    userAgent,
  )
  const startPaused = installed.some((d) => !d.paused)

  const steps: Step[] = []
  const planned = new Set<string>()
  const plan = (step: Step) => {
    steps.push(step)
    planned.add(step.entry.id)
  }

  // Decks a backup used come first, with the settings they had there.
  const queued: PendingDeckInstall[] = []
  for (const item of pending) {
    if (byId.has(item.id)) continue
    const entry = entries.get(item.id)
    queued.push(item)
    if (entry)
      plan({
        entry,
        pending: item,
        initial: { includeObscure: item.includeObscure, paused: false },
      })
  }

  for (const group of groupByTool(manifest.decks)) {
    const here = group.variants.filter((v) => byId.has(v.id) || planned.has(v.id))
    for (const entry of here) {
      const stored = byId.get(entry.id)
      if (stored && isUpdateAvailable(stored, entry)) plan({ entry, previous: stored })
    }
    const wantedName = variantForFlavor(
      group.variants.map((v) => v.variant),
      flavor,
    )
    const wanted = group.variants.find((v) => v.variant === wantedName)!
    if (here.length === 0) {
      plan({ entry: wanted, initial: { paused: startPaused } })
    } else if (chosen && !here.includes(wanted)) {
      // The user picked a flavor: swap the other one for it, keeping its settings.
      const old = here.map((v) => byId.get(v.id)).find((d) => d !== undefined)
      if (old) {
        const { includeObscure, paused, typeAnswers } = old
        plan({ entry: wanted, initial: { includeObscure, paused, typeAnswers }, replaces: old })
      }
    }
  }

  const result: SyncResult = { downloaded: [], restored: [], updated: [], switched: [], failed: [] }
  state.total = steps.length
  const restoredIds = new Set<string>()
  for (const step of steps) {
    try {
      const deck = await fetchDeck(step.entry, undefined, fetchFn)
      await repository.decks.install(deck, undefined, step.initial)
      if (step.previous) {
        result.updated.push({ entry: step.entry, changes: diffDecks(step.previous.deck, deck) })
      } else {
        result.downloaded.push(step.entry)
      }
      if (step.pending) {
        result.restored.push(step.pending)
        restoredIds.add(step.pending.id)
      }
      if (step.replaces) {
        // Progress on the old flavor stays, should the user switch back.
        await repository.decks.remove(step.replaces.id)
        result.switched.push({ from: step.replaces.id, to: step.entry })
      }
    } catch {
      result.failed.push(step.entry.id)
    } finally {
      state.done++
    }
  }

  const remaining = queued.filter((item) => !restoredIds.has(item.id))
  if (remaining.length !== pending.length)
    await repository.settings.set('pendingDeckInstalls', remaining)
  if (result.downloaded.length + result.updated.length + result.switched.length > 0)
    decksChanged.value++
  return result
}

/** One line for the Decks page's status region, or `undefined` when nothing changed. */
export function describeSync(result: SyncResult): string | undefined {
  const parts: string[] = []
  const fresh = result.downloaded.filter((d) => !result.switched.some((s) => s.to.id === d.id))
  if (fresh.length === 1) parts.push(`Downloaded ${fresh[0]!.tool}.`)
  else if (fresh.length > 1) parts.push(`Downloaded ${fresh.length} decks.`)
  if (result.switched.length > 0) {
    const tools = result.switched.map((s) => s.to.tool)
    const list =
      tools.length > 1 ? `${tools.slice(0, -1).join(', ')} and ${tools.at(-1)}` : tools[0]
    parts.push(`Switched ${list} to ${flavorLabel(result.switched[0]!.to.variant)}.`)
  }
  for (const { entry, changes } of result.updated)
    parts.push(
      `Updated ${entry.tool} to version ${entry.deckVersion}: ${describeChanges(changes)}.`,
    )
  return parts.length ? parts.join(' ') : undefined
}

/** Variant names are implementation families; say where people meet them. */
const FLAVOR_LABELS: Record<string, string> = { gnu: 'GNU / Linux', bsd: 'BSD / macOS' }
export function flavorLabel(variant: string): string {
  return FLAVOR_LABELS[variant] ?? variant
}
