import { mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createRepository, type Repository } from '@/core/storage'
import { fakeIndexedDB, uniqueDatabaseName } from '@/core/storage/test-utils'

import { fakeFetch, grepDeck } from '../decks/test-fixtures'
import { repositoryKey } from '../repository'
import DeckBrowseView from './DeckBrowseView.vue'

let repo: Repository
beforeEach(() => {
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})
afterEach(async () => {
  await repo.destroy()
})

async function mountView(id = 'grep-gnu') {
  const wrapper = mount(DeckBrowseView, {
    props: { id, fetch: fakeFetch([grepDeck()]) },
    global: { provide: { [repositoryKey]: repo }, stubs: { RouterLink: true } },
  })
  await vi.waitFor(() => expect(wrapper.get('section').attributes('aria-busy')).toBe('false'))
  return wrapper
}

const optionIds = (wrapper: Awaited<ReturnType<typeof mountView>>) =>
  wrapper.findAll('[data-option]').map((li) => li.attributes('data-option'))

describe('DeckBrowseView', () => {
  it('lists every option with flags, tier and learning status', async () => {
    await repo.decks.install(grepDeck())
    await repo.cardStates.put({
      cardId: 'grep:gnu:ignore-case:flag-to-meaning',
      deckId: 'grep-gnu',
      optionId: 'ignore-case',
      suspended: false,
      fsrs: {
        phase: 'learning',
        due: 0,
        stability: 1,
        difficulty: 5,
        elapsedDays: 0,
        scheduledDays: 0,
        learningSteps: 1,
        reps: 1,
        lapses: 0,
      },
    })
    const wrapper = await mountView()
    expect(optionIds(wrapper)).toEqual(['ignore-case', 'invert-match'])
    const first = wrapper.get('[data-option="ignore-case"]')
    expect(first.get('.primary').text()).toBe('-i')
    expect(first.get('.alias').text()).toBe('--ignore-case')
    expect(first.get('[data-tier]').text()).toBe('core')
    expect(first.get('[data-status]').text()).toBe('Learning')
    expect(wrapper.get('[data-option="invert-match"] [data-status]').text()).toBe('New')
  })

  it('filters by search', async () => {
    await repo.decks.install(grepDeck())
    const wrapper = await mountView()
    await wrapper.get('input[type="search"]').setValue('--inv')
    expect(optionIds(wrapper)).toEqual(['invert-match'])
    expect(wrapper.text()).toContain('1 of 2 options')
  })

  it('browses a deck that is not installed from the network', async () => {
    const wrapper = await mountView()
    expect(optionIds(wrapper)).toEqual(['ignore-case', 'invert-match'])
    expect(wrapper.text()).toContain('not installed')
    expect(wrapper.find('[data-status]').exists()).toBe(false)
  })

  it('reports unknown decks', async () => {
    const wrapper = await mountView('nope-gnu')
    expect(wrapper.get('[role="alert"]').text()).toMatch(/no deck called "nope-gnu"/)
  })
})
