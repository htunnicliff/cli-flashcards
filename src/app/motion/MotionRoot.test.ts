import { flushPromises, mount } from '@vue/test-utils'
import { m } from 'motion-v'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { defineComponent, h, nextTick } from 'vue'

import { useAppearanceStore, type MotionPreference } from '../stores/appearance'
import MotionRoot from './MotionRoot.vue'

const frame = () => new Promise((resolve) => setTimeout(resolve, 20))

/** A box that slides 100px and fades in over a 300 ms tween, so a mid-point is easy to catch. */
const Box = defineComponent(
  () => () =>
    h(m.div, {
      'data-testid': 'box',
      initial: { x: 0, opacity: 0 },
      animate: { x: 100, opacity: 1 },
      transition: { duration: 0.3, ease: 'linear' },
    }),
)

async function mountWith(preference: MotionPreference) {
  useAppearanceStore().motion = preference
  const wrapper = mount(MotionRoot, { slots: { default: () => h(Box) }, attachTo: document.body })
  await flushPromises() // features chunk
  await nextTick()
  await frame()
  await frame()
  const style = wrapper.get<HTMLElement>('[data-testid="box"]').element.style
  const sample = { transform: style.transform, opacity: Number(style.opacity) }
  // Let the tween finish so unmounting doesn't cancel a running animation.
  await new Promise((resolve) => setTimeout(resolve, 400))
  wrapper.unmount()
  return sample
}

describe('MotionRoot', () => {
  beforeEach(() => {
    localStorage.clear()
    setActivePinia(createPinia())
  })

  it('animates transforms when motion is on', async () => {
    const { transform, opacity } = await mountWith('full')
    expect(transform).not.toContain('100px')
    expect(opacity).toBeLessThan(1)
  })

  it('jumps transforms to their end state but keeps fades when motion is reduced', async () => {
    const { transform, opacity } = await mountWith('reduce')
    expect(transform).toContain('100px')
    expect(opacity).toBeLessThan(1)
  })
})
