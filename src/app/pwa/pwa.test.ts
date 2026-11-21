import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { defineComponent, h, nextTick, ref } from 'vue'

import MotionRoot from '../motion/MotionRoot.vue'

const needRefresh = ref(false)
const updateServiceWorker = vi.fn(async () => {})

vi.mock('./service-worker', () => ({
  useServiceWorker: () => ({ needRefresh, offlineReady: ref(false), updateServiceWorker }),
}))

const { default: UpdatePrompt } = await import('./UpdatePrompt.vue')
const { default: OfflineIndicator } = await import('./OfflineIndicator.vue')

function inMotionRoot(component: ReturnType<typeof defineComponent>) {
  return mount(MotionRoot, { slots: { default: () => h(component) } })
}

function setOnline(value: boolean) {
  Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => value })
  window.dispatchEvent(new Event(value ? 'online' : 'offline'))
}

describe('UpdatePrompt', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    needRefresh.value = false
    updateServiceWorker.mockClear()
  })

  it('stays hidden until a new version is waiting', async () => {
    const wrapper = inMotionRoot(UpdatePrompt)
    expect(wrapper.text()).toBe('')

    needRefresh.value = true
    await nextTick()
    expect(wrapper.text()).toContain('Update available')
  })

  it('reloads into the new version only when asked', async () => {
    needRefresh.value = true
    const wrapper = inMotionRoot(UpdatePrompt)
    await nextTick()
    expect(updateServiceWorker).not.toHaveBeenCalled()

    const reload = wrapper.findAll('button').find((b) => b.text() === 'Reload')!
    await reload.trigger('click')
    expect(updateServiceWorker).toHaveBeenCalledOnce()
  })

  it('can be dismissed', async () => {
    needRefresh.value = true
    const wrapper = inMotionRoot(UpdatePrompt)
    await nextTick()
    await wrapper
      .findAll('button')
      .find((b) => b.text() === 'Later')!
      .trigger('click')
    expect(needRefresh.value).toBe(false)
    expect(updateServiceWorker).not.toHaveBeenCalled()
  })
})

describe('OfflineIndicator', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('shows while the browser is offline', async () => {
    setOnline(true)
    const wrapper = inMotionRoot(OfflineIndicator)
    expect(wrapper.text()).toBe('')

    setOnline(false)
    await nextTick()
    expect(wrapper.text()).toBe('Offline')

    setOnline(true)
    await flushPromises()
    await new Promise((resolve) => setTimeout(resolve, 300)) // exit fade
    expect(wrapper.text()).toBe('')
  })
})
