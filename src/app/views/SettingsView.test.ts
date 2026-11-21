import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { useAppearanceStore } from '../stores/appearance'
import SettingsView from './SettingsView.vue'

describe('SettingsView', () => {
  beforeEach(() => {
    localStorage.clear()
    setActivePinia(createPinia())
  })

  it('offers theme, text size and reduce motion choices', () => {
    const wrapper = mount(SettingsView)
    const labels = wrapper.findAll('label').map((l) => l.text())
    expect(labels).toEqual(['Light', 'Dark', 'System', 'S', 'M', 'L', 'System', 'On', 'Off'])
    expect(wrapper.get<HTMLInputElement>('input[value="system"]').element.checked).toBe(true)
    expect(wrapper.get<HTMLInputElement>('input[value="m"]').element.checked).toBe(true)
    expect(
      wrapper.get<HTMLInputElement>('input[name="motion"][value="system"]').element.checked,
    ).toBe(true)
  })

  it('updates the appearance settings', async () => {
    const wrapper = mount(SettingsView)
    await wrapper.get('input[value="dark"]').setValue(true)
    await wrapper.get('input[value="l"]').setValue(true)
    await wrapper.get('input[value="reduce"]').setValue(true)

    const store = useAppearanceStore()
    expect(store.theme).toBe('dark')
    expect(store.fontSize).toBe('l')
    expect(store.motion).toBe('reduce')
    expect(document.documentElement.dataset.theme).toBe('dark')
  })
})
