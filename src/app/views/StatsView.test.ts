import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { DeckSchema } from '@/schema'
import { makeDeck, makeOption } from '@/schema/fixtures'
import { createRepository, type Repository } from '@/core/storage'
import {
  fakeIndexedDB,
  makeCardState,
  makeFsrsState,
  makeLogEntry,
  uniqueDatabaseName,
} from '@/core/storage/test-utils'

import { repositoryKey } from '../repository'
import StatsView from './StatsView.vue'

const DAY = 24 * 60 * 60 * 1000
let repo: Repository

beforeEach(() => {
  localStorage.clear()
  setActivePinia(createPinia())
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})

afterEach(async () => {
  await repo.destroy()
})

async function mountLoaded() {
  const wrapper = mount(StatsView, { global: { provide: { [repositoryKey]: repo } } })
  await vi.waitFor(() => expect(wrapper.get('section').attributes('aria-busy')).toBe('false'))
  return wrapper
}

describe('StatsView', () => {
  it('shows an empty state with no data', async () => {
    const wrapper = await mountLoaded()
    expect(wrapper.get('[data-testid="reviews-today"]').text()).toContain('0')
    expect(wrapper.get('[data-testid="retention"]').text()).toContain(
      'No mature cards reviewed yet',
    )
    expect(wrapper.text()).toContain('Install a deck to see its cards here.')
  })

  it('shows today’s reviews, streak, retention, forecast and card counts', async () => {
    await repo.decks.install(DeckSchema.parse(makeDeck([makeOption(['-i', '--ignore-case'])])))
    const cardId = 'grep:gnu:ignore-case:flag-to-meaning'
    const now = Date.now()
    const mature = makeFsrsState({ phase: 'review', scheduledDays: 30 })
    await repo.cardStates.put(
      makeCardState(cardId, { fsrs: makeFsrsState({ phase: 'review', due: now + 2 * DAY }) }),
    )
    for (const [ago, rating] of [
      [2, 3],
      [1, 3],
      [0, 1],
      [0, 3],
    ] as const) {
      await repo.reviewLog.append(
        makeLogEntry(cardId, { reviewedAt: now - ago * DAY, rating, before: mature }),
      )
    }

    const wrapper = await mountLoaded()
    // Reduced motion is forced in component tests, so numbers show their final value.
    expect(wrapper.get('[data-testid="reviews-today"] .tile-value').text()).toContain('2')
    expect(wrapper.get('[data-testid="streak"] .tile-value').text()).toContain('3')
    expect(wrapper.get('[data-testid="retention"]').text()).toContain('75%')
    expect(wrapper.get('[data-testid="retention"]').text()).toContain(
      '3 of 4 mature reviews passed',
    )
    expect(wrapper.findAll('.plot [role="listitem"]')).toHaveLength(30)
    expect(wrapper.text()).toContain('1 card due in the next 30 days')
    expect(
      wrapper.findAll('tbody tr').map((r) => r.findAll('th, td').map((c) => c.text())),
      // The two flag pair cards count as new while flag pair practice is on (the default).
    ).toEqual([['grep (gnu)', '3', '0', '1', '0']])
  })
})
