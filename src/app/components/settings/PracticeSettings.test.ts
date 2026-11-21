import { mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createRepository, type Repository } from '@/core/storage'
import { fakeIndexedDB, uniqueDatabaseName } from '@/core/storage/test-utils'

import { repositoryKey } from '../../repository'
import PracticeSettings from './PracticeSettings.vue'

let repo: Repository

beforeEach(() => {
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})

afterEach(async () => {
  await repo.destroy()
})

async function mountLoaded() {
  const wrapper = mount(PracticeSettings, { global: { provide: { [repositoryKey]: repo } } })
  await vi.waitFor(() => expect(wrapper.get('section').attributes('aria-busy')).toBe('false'))
  return wrapper
}

describe('PracticeSettings', () => {
  it('has flag pair practice on by default and saves turning it off', async () => {
    const wrapper = await mountLoaded()
    const box = wrapper.get<HTMLInputElement>('#setting-flagPairs')
    expect(box.element.checked).toBe(true)
    await box.setValue(false)
    await vi.waitFor(async () => expect(await repo.settings.get('flagPairs')).toBe(false))
  })

  it('shows the stored value', async () => {
    await repo.settings.set('flagPairs', false)
    const wrapper = await mountLoaded()
    expect(wrapper.get<HTMLInputElement>('#setting-flagPairs').element.checked).toBe(false)
  })
})
