import { readonly, ref } from 'vue'

import type { PendingDeckInstall, Repository } from '@/core/storage'
import type { DeckManifest } from '@/schema/manifest'

import { fetchDeck, fetchManifest, type FetchLike } from './catalog'

export interface PendingResult {
  installed: PendingDeckInstall[]
  /** Still queued: not in the manifest, or the download failed. */
  remaining: PendingDeckInstall[]
}

const decksChanged = ref(0)

/**
 * Bumps whenever pending decks finish installing in the background, so a view
 * that already loaded its decks (the review screen) knows to load them again.
 */
export function useDecksChanged() {
  return readonly(decksChanged)
}

const inFlight = new WeakMap<Repository, Promise<PendingResult>>()

/**
 * Installs the decks a backup import queued in `pendingDeckInstalls` (the
 * import can't fetch them itself, and may run offline). Entries that fail or
 * aren't in the manifest stay queued for the next try. Concurrent calls for
 * the same repository share one run, so the app start, an import and the
 * deck library never install the same deck twice.
 */
export function installPendingDecks(
  repository: Repository,
  options: { fetch?: FetchLike; manifest?: DeckManifest } = {},
): Promise<PendingResult> {
  const running = inFlight.get(repository)
  if (running) return running
  const run = installAll(repository, options).finally(() => inFlight.delete(repository))
  inFlight.set(repository, run)
  return run
}

async function installAll(
  repository: Repository,
  options: { fetch?: FetchLike; manifest?: DeckManifest },
): Promise<PendingResult> {
  const pending = await repository.settings.get('pendingDeckInstalls')
  if (pending.length === 0) return { installed: [], remaining: [] }
  const fetchFn: FetchLike = options.fetch ?? ((input, init) => fetch(input, init))
  const manifest = options.manifest ?? (await fetchManifest(fetchFn))
  const installedIds = new Set((await repository.decks.list()).map((d) => d.id))
  const installed: PendingDeckInstall[] = []
  const remaining: PendingDeckInstall[] = []
  for (const item of pending) {
    if (installedIds.has(item.id)) continue
    const entry = manifest.decks.find((deck) => deck.id === item.id)
    if (!entry) {
      remaining.push(item)
      continue
    }
    try {
      await repository.decks.install(await fetchDeck(entry, undefined, fetchFn))
      await repository.decks.setIncludeObscure(item.id, item.includeObscure)
      installed.push(item)
    } catch {
      remaining.push(item)
    }
  }
  await repository.settings.set('pendingDeckInstalls', remaining)
  if (installed.length > 0) decksChanged.value++
  return { installed, remaining }
}
