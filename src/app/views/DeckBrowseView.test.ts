import { mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createRepository, type Repository } from '@/core/storage'
import {
  fakeIndexedDB,
  makeCardState,
  makeFsrsState,
  uniqueDatabaseName,
} from '@/core/storage/test-utils'

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
    expect(first.get('[data-tier]').text()).toBe('most used')
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
    expect(wrapper.text()).toContain('not downloaded yet')
    expect(wrapper.find('[data-status]').exists()).toBe(false)
  })

  it('reports unknown decks', async () => {
    const wrapper = await mountView('nope-gnu')
    expect(wrapper.get('[role="alert"]').text()).toMatch(/no deck called "nope-gnu"/)
  })

  it('lists suspended cards and unsuspends them', async () => {
    await repo.decks.install(grepDeck())
    await repo.cardStates.putMany([
      makeCardState('grep:gnu:ignore-case:flag-to-meaning', { suspended: true }),
      makeCardState('grep:gnu:invert-match:meaning-to-flag', { suspended: true }),
    ])
    const wrapper = await mountView()
    const rows = wrapper.findAll('[data-suspended]')
    expect(rows.map((r) => r.findAll('code, .hint').map((n) => n.text()))).toEqual([
      ['-i', 'Flag → meaning'],
      ['-v', 'Meaning → flag'],
    ])
    await rows[0]!.get('button').trigger('click')
    await vi.waitFor(() => expect(wrapper.findAll('[data-suspended]')).toHaveLength(1))
    expect(await repo.cardStates.get('grep:gnu:ignore-case:flag-to-meaning')).toMatchObject({
      suspended: false,
    })
    expect(wrapper.text()).not.toContain('Unsuspend all')
  })

  it('lists leeches with a link that opens the full description', async () => {
    await repo.decks.install(
      grepDeck(1, [
        [['-c', '--count'], { description: 'Print only a count of matching lines per file.' }],
      ]),
    )
    await repo.cardStates.put(
      makeCardState('grep:gnu:count:meaning-to-flag', {
        suspended: true,
        leech: true,
        fsrs: makeFsrsState({ lapses: 6 }),
      }),
    )
    const wrapper = await mountView()
    const leech = wrapper.get('[data-leech]')
    expect(leech.text()).toContain('-c')
    expect(leech.text()).toContain('forgotten 6 times')
    expect(wrapper.findAll('[data-suspended]')).toHaveLength(0)
    expect(wrapper.get('[data-option="count"] details').attributes('open')).toBeUndefined()
    await leech.get('a').trigger('click')
    expect(leech.get('a').attributes('href')).toBe('#option-count')
    expect(wrapper.get('[data-option="count"] details').attributes('open')).toBeDefined()
    expect(wrapper.get('[data-option="count"]').attributes('id')).toBe('option-count')
  })
})
