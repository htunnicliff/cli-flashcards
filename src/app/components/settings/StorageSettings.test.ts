import { mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createRepository, type Repository } from '@/core/storage'
import { fakeIndexedDB, uniqueDatabaseName } from '@/core/storage/test-utils'

import { repositoryKey } from '../../repository'
import StorageSettings from './StorageSettings.vue'

let repo: Repository

beforeEach(() => {
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})

afterEach(async () => {
  vi.unstubAllGlobals()
  await repo.destroy()
})

function mountWith(storage: Partial<StorageManager> | undefined) {
  vi.stubGlobal('navigator', { ...navigator, storage })
  return mount(StorageSettings, { global: { provide: { [repositoryKey]: repo } } })
}

/** IndexedDB answers on a later task, so wait for the report to render. */
async function loaded(wrapper: ReturnType<typeof mountWith>) {
  await vi.waitFor(() => wrapper.get('[data-test="persistence"]'))
}

describe('StorageSettings', () => {
  it('shows usage and that persistence will be requested later', async () => {
    const wrapper = mountWith({
      persisted: async () => false,
      estimate: async () => ({ usage: 1536, quota: 2 * 1024 ** 3 }),
    })
    await loaded(wrapper)
    expect(wrapper.get('[data-test="persistence"]').attributes('data-status')).toBe('not-requested')
    expect(wrapper.get('[data-test="usage"]').text()).toBe(
      'Using about 1.5 KB of 2.0 GB available.',
    )
  })

  it('shows when storage is persistent', async () => {
    await repo.settings.set('persistence', { requestedAt: 1, granted: true })
    const wrapper = mountWith({ persisted: async () => true })
    await loaded(wrapper)
    expect(wrapper.get('[data-test="persistence"]').attributes('data-status')).toBe('persistent')
    expect(wrapper.find('[data-test="usage"]').exists()).toBe(false)
  })

  it('copes with a browser without the Storage API', async () => {
    const wrapper = mountWith(undefined)
    await loaded(wrapper)
    expect(wrapper.get('[data-test="persistence"]').attributes('data-status')).toBe('unsupported')
  })
})
