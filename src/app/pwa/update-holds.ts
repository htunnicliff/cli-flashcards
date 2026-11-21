import { computed, getCurrentScope, onScopeDispose, ref, watch, type WatchSource } from 'vue'

/**
 * Work that a reload into a new version would cut short, such as a review in
 * progress or a deck install. While anything holds updates, a waiting version
 * keeps waiting.
 */
const holds = ref(0)

export const updatesHeld = computed(() => holds.value > 0)

/** Holds updates whenever `busy` is true, until the calling component or scope goes away. */
export function holdUpdatesWhile(busy: WatchSource<boolean>) {
  let holding = false
  const set = (value: boolean) => {
    if (value === holding) return
    holding = value
    holds.value += value ? 1 : -1
  }
  const stop = watch(busy, set, { immediate: true })
  const release = () => {
    stop()
    set(false)
  }
  if (getCurrentScope()) onScopeDispose(release)
  return release
}

/** Holds updates until `work` settles. */
export async function holdUpdatesDuring<T>(work: () => Promise<T>): Promise<T> {
  holds.value++
  try {
    return await work()
  } finally {
    holds.value--
  }
}
