import { mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createRepository, type Repository } from '@/core/storage'
import { fakeIndexedDB, uniqueDatabaseName } from '@/core/storage/test-utils'

import { repositoryKey } from '../../repository'
import SchedulingSettings from './SchedulingSettings.vue'

let repo: Repository

beforeEach(() => {
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})

afterEach(async () => {
  await repo.destroy()
})

async function mountLoaded() {
  const wrapper = mount(SchedulingSettings, { global: { provide: { [repositoryKey]: repo } } })
  await vi.waitFor(() => expect(wrapper.get('section').attributes('aria-busy')).toBe('false'))
  return wrapper
}

const input = (wrapper: Awaited<ReturnType<typeof mountLoaded>>, key: string) =>
  wrapper.get<HTMLInputElement>(`#setting-${key}`)

describe('SchedulingSettings', () => {
  it('shows the stored values', async () => {
    await repo.settings.set('newCardsPerDay', 7)
    const wrapper = await mountLoaded()
    expect(input(wrapper, 'desiredRetention').element.value).toBe('0.9')
    expect(input(wrapper, 'newCardsPerDay').element.value).toBe('7')
    expect(wrapper.findAll('label').map((l) => l.text())).toEqual([
      'New cards per day',
      'Desired retention',
      'Maximum reviews per day',
      'New day starts at',
      'Suspend hard cards after',
    ])
  })

  it('saves a change, brought into range', async () => {
    const wrapper = await mountLoaded()
    await input(wrapper, 'desiredRetention').setValue('0.5')
    await vi.waitFor(async () => expect(await repo.settings.get('desiredRetention')).toBe(0.7))
    expect(input(wrapper, 'desiredRetention').element.value).toBe('0.7')

    await input(wrapper, 'dayRolloverHour').setValue('2')
    await vi.waitFor(async () => expect(await repo.settings.get('dayRolloverHour')).toBe(2))
  })

  it('puts back the old value when the input is not a number', async () => {
    const wrapper = await mountLoaded()
    await input(wrapper, 'maxReviewsPerDay').setValue('')
    expect(input(wrapper, 'maxReviewsPerDay').element.value).toBe('200')
    expect(await repo.settings.get('maxReviewsPerDay')).toBe(200)
  })
})
