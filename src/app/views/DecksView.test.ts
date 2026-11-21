import { flushPromises, mount, type VueWrapper } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory, createRouter } from 'vue-router'

import { createRepository, type Repository } from '@/core/storage'
import { fakeIndexedDB, uniqueDatabaseName } from '@/core/storage/test-utils'
import type { Deck } from '@/schema'

import { fakeFetch, grepDeck, sedDeck } from '../decks/test-fixtures'
import { repositoryKey } from '../repository'
import DecksView from './DecksView.vue'

let repo: Repository

beforeEach(() => {
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})
afterEach(async () => {
  await repo.destroy()
})

const LINUX = 'Mozilla/5.0 (X11; Linux x86_64)'
const MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5)'

async function mountView(decks: Deck[], userAgent = LINUX) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/:p(.*)*', component: { template: '<div/>' } }],
  })
  const wrapper = mount(DecksView, {
    props: { libraryOptions: { fetch: fakeFetch(decks), userAgent } },
    global: { provide: { [repositoryKey]: repo }, plugins: [router] },
  })
  await vi.waitFor(() => expect(wrapper.get('section').attributes('aria-busy')).toBe('false'))
  return wrapper
}

const card = (wrapper: VueWrapper, tool: string) => wrapper.get(`[data-deck^="${tool}-"]`)
const button = (wrapper: VueWrapper, tool: string, text: string) =>
  card(wrapper, tool)
    .findAll('button')
    .find((b) => b.text().startsWith(text))

describe('DecksView', () => {
  it('lists available decks with option counts per tier', async () => {
    const wrapper = await mountView([grepDeck()])
    const grep = card(wrapper, 'grep')
    expect(grep.text()).toContain('2 options')
    expect(grep.text()).toContain('1 core · 1 common · 0 obscure')
    expect(grep.attributes('data-installed')).toBe('false')
  })

  it('installs a deck into IndexedDB', async () => {
    const wrapper = await mountView([grepDeck()])
    await button(wrapper, 'grep', 'Install')!.trigger('click')
    await vi.waitFor(async () => expect(await repo.decks.get('grep-gnu')).toBeDefined())
    await flushPromises()
    expect(card(wrapper, 'grep').attributes('data-installed')).toBe('true')
    expect(wrapper.get('[role="status"]').text()).toBe('Installed grep (gnu).')
  })

  it('preselects the BSD variant on macOS and GNU elsewhere', async () => {
    const mac = await mountView([sedDeck('gnu'), sedDeck('bsd')], MAC)
    expect(card(mac, 'sed').attributes('data-deck')).toBe('sed-bsd')
    const linux = await mountView([sedDeck('gnu'), sedDeck('bsd')], LINUX)
    expect(card(linux, 'sed').attributes('data-deck')).toBe('sed-gnu')
    await linux.get('input[value="bsd"]').setValue(true)
    expect(card(linux, 'sed').attributes('data-deck')).toBe('sed-bsd')
  })

  it('offers updates and reports added and removed options, keeping progress', async () => {
    await repo.decks.install(grepDeck(1))
    const state = {
      cardId: 'grep:gnu:ignore-case:flag-to-meaning',
      deckId: 'grep-gnu',
      optionId: 'ignore-case',
      suspended: false,
      fsrs: {
        phase: 'review' as const,
        due: 0,
        stability: 3,
        difficulty: 5,
        elapsedDays: 0,
        scheduledDays: 3,
        learningSteps: 0,
        reps: 2,
        lapses: 0,
      },
    }
    await repo.cardStates.put(state)
    const v2 = grepDeck(2, [[['-c', '--count'], { tier: 'core' }]])
    v2.options = v2.options.filter((o) => o.id !== 'invert-match')

    const wrapper = await mountView([v2])
    expect(card(wrapper, 'grep').text()).toContain('Update available')
    await button(wrapper, 'grep', 'Update to v2')!.trigger('click')
    await vi.waitFor(async () => expect((await repo.decks.get('grep-gnu'))?.deckVersion).toBe(2))
    await flushPromises()
    expect(wrapper.get('[role="status"]').text()).toBe(
      'Updated grep to version 2: 1 option added, 1 removed.',
    )
    expect(await repo.cardStates.get(state.cardId)).toEqual(state)
  })

  it('removes a deck but keeps its history unless asked to reset', async () => {
    await repo.decks.install(grepDeck())
    await repo.reviewLog.append({
      cardId: 'grep:gnu:ignore-case:flag-to-meaning',
      deckId: 'grep-gnu',
      reviewedAt: 1,
      rating: 3,
      durationMs: 1,
      before: null,
      after: {
        phase: 'learning',
        due: 2,
        stability: 1,
        difficulty: 5,
        elapsedDays: 0,
        scheduledDays: 0,
        learningSteps: 1,
        reps: 1,
        lapses: 0,
      },
    })
    const wrapper = await mountView([grepDeck()])
    await button(wrapper, 'grep', 'Remove')!.trigger('click')
    await button(wrapper, 'grep', 'Remove deck')!.trigger('click')
    await vi.waitFor(async () => expect(await repo.decks.get('grep-gnu')).toBeUndefined())
    expect(await repo.reviewLog.count()).toBe(1)

    await repo.decks.install(grepDeck())
    const again = await mountView([grepDeck()])
    await button(again, 'grep', 'Remove')!.trigger('click')
    await card(again, 'grep').get('.confirm input[type="checkbox"]').setValue(true)
    await button(again, 'grep', 'Remove deck')!.trigger('click')
    await vi.waitFor(async () => expect(await repo.reviewLog.count()).toBe(0))
  })

  it('saves per-deck settings', async () => {
    await repo.decks.install(grepDeck())
    const wrapper = await mountView([grepDeck()])
    const [obscure, pause] = card(wrapper, 'grep').findAll('.deck-settings input')
    await obscure!.setValue(true)
    await pause!.setValue(true)
    await vi.waitFor(async () =>
      expect(await repo.decks.get('grep-gnu')).toMatchObject({
        includeObscure: true,
        paused: true,
      }),
    )
  })

  it('installs decks queued by a backup import, keeping unknown ones queued', async () => {
    await repo.settings.set('pendingDeckInstalls', [
      { id: 'grep-gnu', deckVersion: 1, includeObscure: true },
      { id: 'gone-gnu', deckVersion: 1, includeObscure: false },
    ])
    const wrapper = await mountView([grepDeck()])
    expect(await repo.decks.get('grep-gnu')).toMatchObject({ includeObscure: true })
    expect(await repo.settings.get('pendingDeckInstalls')).toEqual([
      { id: 'gone-gnu', deckVersion: 1, includeObscure: false },
    ])
    expect(wrapper.get('[role="status"]').text()).toBe('Installed 1 deck from your backup.')
  })

  it('shows an error when the deck list cannot load', async () => {
    const wrapper = mount(DecksView, {
      props: { libraryOptions: { fetch: async () => new Response('', { status: 500 }) } },
      global: { provide: { [repositoryKey]: repo }, stubs: { RouterLink: true } },
    })
    await vi.waitFor(() => expect(wrapper.find('[role="alert"]').exists()).toBe(true))
    expect(wrapper.get('[role="alert"]').text()).toMatch(/HTTP 500/)
  })

  it('disables install and explains why while offline', async () => {
    const setOnline = (value: boolean) => {
      Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => value })
      window.dispatchEvent(new Event(value ? 'online' : 'offline'))
    }
    const wrapper = await mountView([grepDeck()])
    try {
      setOnline(false)
      await flushPromises()
      expect(button(wrapper, 'grep', 'Install')!.attributes('disabled')).toBeDefined()
      expect(wrapper.text()).toContain("You're offline")

      setOnline(true)
      await flushPromises()
      expect(button(wrapper, 'grep', 'Install')!.attributes('disabled')).toBeUndefined()
      expect(wrapper.text()).not.toContain("You're offline")
    } finally {
      setOnline(true)
    }
  })
})
