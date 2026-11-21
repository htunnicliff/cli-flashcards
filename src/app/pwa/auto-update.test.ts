import { flushPromises } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { defineComponent, effectScope, nextTick, ref } from 'vue'
import { createMemoryHistory, createRouter, type Router } from 'vue-router'

import { startAutoUpdates } from './auto-update'
import { holdUpdatesDuring, holdUpdatesWhile, updatesHeld } from './update-holds'

const Page = defineComponent({ render: () => null })

function setHidden(hidden: boolean) {
  Object.defineProperty(document, 'visibilityState', {
    configurable: true,
    get: () => (hidden ? 'hidden' : 'visible'),
  })
  document.dispatchEvent(new Event('visibilitychange'))
}

describe('startAutoUpdates', () => {
  let router: Router
  const needRefresh = ref(false)
  const held = ref(false)
  const activate = vi.fn()
  const load = vi.fn()
  let updates: ReturnType<typeof startAutoUpdates>

  beforeEach(async () => {
    router = createRouter({
      history: createMemoryHistory(),
      routes: ['/', '/decks', '/stats'].map((path) => ({ path, component: Page })),
    })
    await router.push('/')
    needRefresh.value = false
    held.value = false
    activate.mockClear()
    load.mockClear()
    setHidden(false)
    updates = startAutoUpdates({ needRefresh, held, activate, router, load })
  })
  afterEach(() => updates.stop())

  const interact = () => document.dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }))
  async function waitingVersion() {
    needRefresh.value = true
    await nextTick()
  }

  it('updates right away if the page has not been touched yet', async () => {
    await waitingVersion()
    expect(activate).toHaveBeenCalledOnce()
    updates.reloadNeeded()
    expect(load).toHaveBeenCalledWith()
  })

  it('waits while the user is on a screen, and updates on the next one', async () => {
    interact()
    await waitingVersion()
    expect(activate).not.toHaveBeenCalled()

    await router.push('/decks')
    await nextTick()
    expect(activate).toHaveBeenCalledOnce()
  })

  it('updates while the app is in the background', async () => {
    interact()
    await waitingVersion()
    setHidden(true)
    expect(activate).toHaveBeenCalledOnce()
  })

  it('never updates while something holds updates', async () => {
    held.value = true
    await waitingVersion()
    await router.push('/decks')
    await nextTick()
    setHidden(true)
    expect(activate).not.toHaveBeenCalled()

    // Once the hold ends, the background tab updates.
    held.value = false
    await nextTick()
    expect(activate).toHaveBeenCalledOnce()
  })

  it('only activates once', async () => {
    await waitingVersion()
    await router.push('/decks')
    await nextTick()
    setHidden(true)
    expect(activate).toHaveBeenCalledOnce()
  })

  it('loads the next screen fresh when another tab moved to the new version', async () => {
    interact()
    updates.reloadNeeded()
    expect(load).not.toHaveBeenCalled()

    await router.push('/stats').catch(() => {})
    expect(load).toHaveBeenCalledWith('/stats')
    expect(router.currentRoute.value.path).toBe('/')
  })
})

describe('update holds', () => {
  it('holds while a source is true, and releases with its scope', async () => {
    const busy = ref(true)
    const scope = effectScope()
    scope.run(() => holdUpdatesWhile(() => busy.value))
    expect(updatesHeld.value).toBe(true)

    busy.value = false
    await nextTick()
    expect(updatesHeld.value).toBe(false)

    busy.value = true
    await nextTick()
    expect(updatesHeld.value).toBe(true)
    scope.stop()
    expect(updatesHeld.value).toBe(false)
  })

  it('holds until work settles, even if it fails', async () => {
    let finish!: () => void
    const work = holdUpdatesDuring(() => new Promise<void>((r) => (finish = r)))
    expect(updatesHeld.value).toBe(true)
    finish()
    await work
    expect(updatesHeld.value).toBe(false)

    await holdUpdatesDuring(async () => {
      throw new Error('nope')
    }).catch(() => {})
    await flushPromises()
    expect(updatesHeld.value).toBe(false)
  })
})
