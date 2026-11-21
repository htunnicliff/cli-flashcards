import { computed, reactive, ref, shallowRef } from 'vue'

import {
  defaultVariant,
  describeChanges,
  diffDecks,
  groupByTool,
  isUpdateAvailable,
  type DeckChanges,
} from '@/core/library'
import type { StoredDeck } from '@/core/storage'
import type { DeckManifest, DeckManifestEntry } from '@/schema/manifest'

import { useRepository } from '../repository'
import { fetchDeck, fetchManifest, type FetchLike } from './catalog'
import { installPendingDecks } from './pending'

export type DeckTask = { kind: 'install' | 'update' | 'remove'; progress: number }

export interface LibraryOptions {
  fetch?: FetchLike
  userAgent?: string
}

/**
 * State and actions for the deck library. Every view that needs it calls this;
 * the data lives in IndexedDB and the manifest, so there is nothing to share.
 */
export function useLibrary(options: LibraryOptions = {}) {
  const repository = useRepository()
  const fetchFn = options.fetch ?? ((input, init) => fetch(input, init))
  const userAgent =
    options.userAgent ?? (typeof navigator === 'undefined' ? '' : navigator.userAgent)

  const manifest = shallowRef<DeckManifest>()
  const installed = ref<StoredDeck[]>([])
  const loading = ref(true)
  const error = ref<string>()
  const tasks = reactive<Record<string, DeckTask>>({})
  /** Last completed action, for the live status region. */
  const status = ref<string>()
  /** Variant picked per tool, when a tool has more than one. */
  const chosen = reactive<Record<string, string>>({})

  const installedById = computed(() => new Map(installed.value.map((d) => [d.id, d])))

  async function reloadInstalled() {
    installed.value = await repository.decks.list()
  }

  async function refresh() {
    loading.value = true
    error.value = undefined
    try {
      await reloadInstalled()
      manifest.value = await fetchManifest(fetchFn)
      await installPending(manifest.value)
    } catch (cause) {
      error.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
      loading.value = false
    }
  }

  /** Installs decks a backup import queued, if the import couldn't reach them. */
  async function installPending(current: DeckManifest) {
    const { installed: done } = await installPendingDecks(repository, {
      fetch: fetchFn,
      manifest: current,
    })
    if (done.length === 0) return
    await reloadInstalled()
    status.value = `Installed ${done.length} deck${done.length === 1 ? '' : 's'} from your backup.`
  }

  /** Tools in the manifest, installed ones first, with the variant to show for each. */
  const tools = computed(() => {
    const groups = groupByTool(manifest.value?.decks ?? [])
    const byId = installedById.value
    return groups
      .map((group) => {
        const installedVariant = group.variants.find((v) => byId.has(v.id))
        const variant =
          group.variants.find((v) => v.variant === chosen[group.tool]) ??
          installedVariant ??
          group.variants.find(
            (v) =>
              v.variant ===
              defaultVariant(
                group.variants.map((x) => x.variant),
                userAgent,
              ),
          )!
        const stored = byId.get(variant.id)
        return {
          ...group,
          entry: variant,
          stored,
          updateAvailable: stored ? isUpdateAvailable(stored, variant) : false,
          /** Another variant of this tool is installed instead of the one shown. */
          otherInstalled:
            installedVariant && installedVariant.id !== variant.id ? installedVariant : undefined,
        }
      })
      .sort(
        (a, b) =>
          Number(Boolean(b.stored)) - Number(Boolean(a.stored)) || a.tool.localeCompare(b.tool),
      )
  })

  async function run<T>(
    id: string,
    kind: DeckTask['kind'],
    action: (task: DeckTask) => Promise<T>,
  ) {
    tasks[id] = { kind, progress: 0 }
    error.value = undefined
    try {
      return await action(tasks[id]!)
    } catch (cause) {
      error.value = cause instanceof Error ? cause.message : String(cause)
      return undefined
    } finally {
      delete tasks[id]
    }
  }

  async function install(entry: DeckManifestEntry) {
    await run(entry.id, 'install', async (task) => {
      const deck = await fetchDeck(entry, (p) => (task.progress = p), fetchFn)
      await repository.decks.install(deck)
      await reloadInstalled()
      status.value = `Installed ${entry.tool} (${entry.variant}).`
    })
  }

  /** Installs the newer version; progress for unchanged card IDs is untouched. */
  async function update(entry: DeckManifestEntry): Promise<DeckChanges | undefined> {
    return run(entry.id, 'update', async (task) => {
      const previous = installedById.value.get(entry.id)
      const deck = await fetchDeck(entry, (p) => (task.progress = p), fetchFn)
      await repository.decks.install(deck)
      await reloadInstalled()
      const changes = previous
        ? diffDecks(previous.deck, deck)
        : { added: deck.options, removed: [] }
      status.value = `Updated ${entry.tool} to version ${deck.deckVersion}: ${describeChanges(changes)}.`
      return changes
    })
  }

  /** Removes a deck. Review history stays unless `resetProgress` is set. */
  async function remove(id: string, { resetProgress = false } = {}) {
    await run(id, 'remove', async () => {
      await repository.decks.remove(id)
      if (resetProgress) await repository.resetProgress(id)
      await reloadInstalled()
      status.value = resetProgress
        ? `Removed ${id} and reset its progress.`
        : `Removed ${id}. Your progress is kept if you install it again.`
    })
  }

  async function setIncludeObscure(id: string, include: boolean) {
    await repository.decks.setIncludeObscure(id, include)
    await reloadInstalled()
  }

  async function setPaused(id: string, paused: boolean) {
    await repository.decks.setPaused(id, paused)
    await reloadInstalled()
  }

  async function setTypeAnswers(id: string, typeAnswers: boolean) {
    await repository.decks.setTypeAnswers(id, typeAnswers)
    await reloadInstalled()
  }

  return {
    manifest,
    installed,
    installedById,
    tools,
    loading,
    error,
    tasks,
    status,
    chosen,
    refresh,
    install,
    update,
    remove,
    setIncludeObscure,
    setPaused,
    setTypeAnswers,
  }
}

export type Library = ReturnType<typeof useLibrary>
