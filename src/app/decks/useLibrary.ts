import { computed, ref, shallowRef, watch } from 'vue'

import { groupByTool, resolveFlavor, variantForFlavor } from '@/core/library'
import type { DeckFlavor, StoredDeck } from '@/core/storage'
import { manifestEntry, type DeckManifest } from '@/schema/manifest'

import { useOnline } from '../pwa/online'
import { useRepository } from '../repository'
import { fetchManifest, type FetchLike } from './catalog'
import {
  describeSync,
  setDeckFlavor,
  syncDecks,
  useDeckSync,
  type SyncOptions,
  type SyncResult,
} from './sync'

export interface LibraryOptions {
  fetch?: FetchLike
  userAgent?: string
}

/**
 * State and actions for the Decks page. Decks download and update on their
 * own (see `syncDecks`); this lists them and keeps each deck's settings.
 */
export function useLibrary(options: LibraryOptions = {}) {
  const repository = useRepository()
  const online = useOnline()
  const sync = useDeckSync()
  const fetchFn = options.fetch ?? ((input, init) => fetch(input, init))
  const userAgent =
    options.userAgent ?? (typeof navigator === 'undefined' ? '' : navigator.userAgent)
  const syncOptions: SyncOptions = { fetch: fetchFn, userAgent }

  const manifest = shallowRef<DeckManifest>()
  const installed = ref<StoredDeck[]>([])
  const chosenFlavor = ref<DeckFlavor | null>(null)
  const loading = ref(true)
  const error = ref<string>()
  /** Last completed action, for the live status region. */
  const status = ref<string>()

  const installedById = computed(() => new Map(installed.value.map((d) => [d.id, d])))

  /** The flavor new tools download in, and the one the picker shows. */
  const flavor = computed(() =>
    resolveFlavor(
      chosenFlavor.value,
      installed.value.map((d) => d.deck.variant),
      userAgent,
    ),
  )

  async function reloadInstalled() {
    const [decks, chosen] = await Promise.all([
      repository.decks.list(),
      repository.settings.get('deckFlavor'),
    ])
    installed.value = decks
    chosenFlavor.value = chosen
  }

  function report(result: SyncResult) {
    status.value = describeSync(result) ?? status.value
    if (result.failed.length > 0 && online.value) {
      error.value = `Couldn't download ${result.failed.join(', ')}. The app will try again later.`
    }
  }

  // Background syncs (at start, after a backup import) land here too.
  watch(sync.lastResult, async (result) => {
    if (result) report(result)
    await reloadInstalled().catch(() => {})
  })

  async function runSync(run: () => Promise<SyncResult>) {
    error.value = undefined
    try {
      await run()
    } catch (cause) {
      if (online.value) error.value = cause instanceof Error ? cause.message : String(cause)
    }
  }

  /** Loads the decks here and the deck list, then downloads anything missing or outdated. */
  async function refresh() {
    loading.value = true
    error.value = undefined
    try {
      await reloadInstalled()
      manifest.value = await fetchManifest(fetchFn)
    } catch (cause) {
      // Offline, the decks already here are still listed below.
      if (online.value || installed.value.length === 0)
        error.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
      loading.value = false
    }
    if (manifest.value && online.value) {
      const current = manifest.value
      await runSync(() => syncDecks(repository, { ...syncOptions, manifest: current }))
    }
  }

  /** Tools to show: studied ones first, each with the deck in use or the one that will download. */
  const tools = computed(() => {
    const byId = installedById.value
    const entries =
      manifest.value?.decks ??
      installed.value.map((stored) => manifestEntry(stored.deck, `${stored.id}.json`, 0))
    return groupByTool(entries)
      .map((group) => {
        const wanted = variantForFlavor(
          group.variants.map((v) => v.variant),
          flavor.value,
        )
        const here = group.variants.filter((v) => byId.has(v.id))
        const entry =
          here.find((v) => v.variant === wanted) ??
          here[0] ??
          group.variants.find((v) => v.variant === wanted)!
        const stored = byId.get(entry.id)
        return { ...group, entry, stored, studying: Boolean(stored && !stored.paused) }
      })
      .sort(
        (a, b) =>
          Number(b.studying) - Number(a.studying) ||
          Number(Boolean(b.stored)) - Number(Boolean(a.stored)) ||
          a.tool.localeCompare(b.tool),
      )
  })

  /** Tools that come in more than one flavor, which the flavor picker applies to. */
  const flavoredTools = computed(() =>
    tools.value.filter((tool) => tool.variants.length > 1).map((tool) => tool.tool),
  )

  async function setFlavor(next: DeckFlavor) {
    chosenFlavor.value = next
    await runSync(() => setDeckFlavor(repository, next, syncOptions))
  }

  async function setStudying(id: string, studying: boolean) {
    await repository.decks.setPaused(id, !studying)
    await reloadInstalled()
  }

  async function setIncludeObscure(id: string, include: boolean) {
    await repository.decks.setIncludeObscure(id, include)
    await reloadInstalled()
  }

  async function setTypeAnswers(id: string, typeAnswers: boolean) {
    await repository.decks.setTypeAnswers(id, typeAnswers)
    await reloadInstalled()
  }

  /** Clears a deck's review history; its cards start over as new. */
  async function resetProgress(id: string, tool: string) {
    await repository.resetProgress(id)
    status.value = `Reset your progress on ${tool}.`
  }

  return {
    manifest,
    installed,
    installedById,
    tools,
    flavor,
    flavoredTools,
    loading,
    error,
    status,
    syncState: sync.state,
    refresh,
    setFlavor,
    setStudying,
    setIncludeObscure,
    setTypeAnswers,
    resetProgress,
  }
}

export type Library = ReturnType<typeof useLibrary>
