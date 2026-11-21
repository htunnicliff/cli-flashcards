import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { defineComponent, h, nextTick } from 'vue'

import MotionRoot from '../motion/MotionRoot.vue'
import OfflineIndicator from './OfflineIndicator.vue'

function inMotionRoot(component: ReturnType<typeof defineComponent>) {
  return mount(MotionRoot, { slots: { default: () => h(component) } })
}

function setOnline(value: boolean) {
  Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => value })
  window.dispatchEvent(new Event(value ? 'online' : 'offline'))
}

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
