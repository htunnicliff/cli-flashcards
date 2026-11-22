import { enableAutoUnmount, flushPromises, mount, type VueWrapper } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory, createRouter } from 'vue-router'

import { createRepository, type Repository } from '@/core/storage'
import { fakeIndexedDB, uniqueDatabaseName } from '@/core/storage/test-utils'
import type { Deck } from '@/schema'

import { fakeFetch, grepDeck, sedDeck } from '../decks/test-fixtures'
import { repositoryKey } from '../repository'
import DecksView from './DecksView.vue'

let repo: Repository

enableAutoUnmount(afterEach)

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
  // Then the background download that the page starts.
  await vi.waitFor(() => expect(wrapper.find('[data-testid="deck-sync"]').exists()).toBe(false))
  await flushPromises()
  return wrapper
}

const card = (wrapper: VueWrapper, tool: string) => wrapper.get(`[data-deck^="${tool}-"]`)
const button = (wrapper: VueWrapper, tool: string, text: string) =>
  card(wrapper, tool)
    .findAll('button')
    .find((b) => b.text().startsWith(text))

describe('DecksView', () => {
  it('downloads every deck on its own and lists how many options each starts with', async () => {
    const wrapper = await mountView([grepDeck()])
    // On a slow runner the background download may not have started when
    // mountView stops waiting, so wait for it to land.
    await vi.waitFor(() => expect(card(wrapper, 'grep').attributes('data-installed')).toBe('true'))
    const grep = card(wrapper, 'grep')
    expect(grep.text()).toContain('2 options, starting with the 1 most used')
    expect(grep.attributes('data-studying')).toBe('true')
    expect(grep.find('button').exists() && grep.text()).not.toContain('Install')
    expect(await repo.decks.get('grep-gnu')).toBeDefined()
    expect(wrapper.get('[role="status"]').text()).toBe('Downloaded grep.')
  })

  it('downloads the BSD flavor on macOS and GNU elsewhere', async () => {
    const mac = await mountView([sedDeck('gnu'), sedDeck('bsd')], MAC)
    expect(card(mac, 'sed').attributes('data-deck')).toBe('sed-bsd')
    expect(await repo.decks.get('sed-bsd')).toBeDefined()
    expect(await repo.decks.get('sed-gnu')).toBeUndefined()
  })

  it('switches every tool to the flavor picked, keeping its settings', async () => {
    const wrapper = await mountView([sedDeck('gnu'), sedDeck('bsd')], LINUX)
    expect(card(wrapper, 'sed').attributes('data-deck')).toBe('sed-gnu')
    await repo.decks.setTypeAnswers('sed-gnu', true)
    await wrapper.get('input[value="bsd"]').setValue(true)
    await vi.waitFor(async () => expect(await repo.decks.get('sed-gnu')).toBeUndefined())
    await flushPromises()
    expect(await repo.decks.get('sed-bsd')).toMatchObject({ typeAnswers: true })
    expect(await repo.settings.get('deckFlavor')).toBe('bsd')
    expect(card(wrapper, 'sed').attributes('data-deck')).toBe('sed-bsd')
    expect(wrapper.get('[role="status"]').text()).toBe('Switched sed to BSD / macOS.')
  })

  it('updates decks on its own and reports added and removed options, keeping progress', async () => {
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
    expect((await repo.decks.get('grep-gnu'))?.deckVersion).toBe(2)
    expect(wrapper.get('[role="status"]').text()).toBe(
      'Updated grep to version 2: 1 option added, 1 removed.',
    )
    expect(await repo.cardStates.get(state.cardId)).toEqual(state)
  })

  it('pauses a deck and offers a review when one is turned back on', async () => {
    const wrapper = await mountView([grepDeck()])
    const study = () => card(wrapper, 'grep').get('.deck-settings input')
    await study().setValue(false)
    await vi.waitFor(async () =>
      expect(await repo.decks.get('grep-gnu')).toMatchObject({ paused: true }),
    )
    await flushPromises()
    expect(card(wrapper, 'grep').text()).toContain('Paused')
    expect(wrapper.find('[data-testid="start-reviewing"]').exists()).toBe(false)

    await study().setValue(true)
    await vi.waitFor(async () =>
      expect(await repo.decks.get('grep-gnu')).toMatchObject({ paused: false }),
    )
    await flushPromises()
    expect(wrapper.get('[role="status"]').text()).toBe('Studying grep.')
    expect(wrapper.get('[data-testid="start-reviewing"]').attributes('href')).toBe('/')
  })

  it("resets a deck's progress after asking", async () => {
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
    await button(wrapper, 'grep', 'Reset progress')!.trigger('click')
    await button(wrapper, 'grep', 'Cancel')!.trigger('click')
    expect(await repo.reviewLog.count()).toBe(1)
    await button(wrapper, 'grep', 'Reset progress')!.trigger('click')
    await card(wrapper, 'grep').get('.confirm button').trigger('click')
    await vi.waitFor(async () => expect(await repo.reviewLog.count()).toBe(0))
    expect(await repo.decks.get('grep-gnu')).toBeDefined()
  })

  it('saves per-deck settings', async () => {
    await repo.decks.install(grepDeck())
    const wrapper = await mountView([grepDeck()])
    const [, obscure, typed] = card(wrapper, 'grep').findAll('.deck-settings input')
    await obscure!.setValue(true)
    await typed!.setValue(true)
    await vi.waitFor(async () =>
      expect(await repo.decks.get('grep-gnu')).toMatchObject({
        includeObscure: true,
        typeAnswers: true,
      }),
    )
  })

  it('downloads decks queued by a backup import, keeping unknown ones queued', async () => {
    await repo.settings.set('pendingDeckInstalls', [
      { id: 'grep-gnu', deckVersion: 1, includeObscure: true },
      { id: 'gone-gnu', deckVersion: 1, includeObscure: false },
    ])
    await mountView([grepDeck()])
    expect(await repo.decks.get('grep-gnu')).toMatchObject({ includeObscure: true })
    expect(await repo.settings.get('pendingDeckInstalls')).toEqual([
      { id: 'gone-gnu', deckVersion: 1, includeObscure: false },
    ])
  })

  it('shows an error when the deck list cannot load', async () => {
    const wrapper = mount(DecksView, {
      props: { libraryOptions: { fetch: async () => new Response('', { status: 500 }) } },
      global: { provide: { [repositoryKey]: repo }, stubs: { RouterLink: true } },
    })
    await vi.waitFor(() => expect(wrapper.find('[role="alert"]').exists()).toBe(true))
    expect(wrapper.get('[role="alert"]').text()).toMatch(/HTTP 500/)
  })

  it('explains that downloads wait while offline', async () => {
    const setOnline = (value: boolean) => {
      Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => value })
      window.dispatchEvent(new Event(value ? 'online' : 'offline'))
    }
    const wrapper = await mountView([sedDeck('gnu'), sedDeck('bsd')])
    try {
      setOnline(false)
      await flushPromises()
      expect(wrapper.text()).toContain("You're offline")
      expect(wrapper.get('input[value="bsd"]').attributes('disabled')).toBeDefined()

      setOnline(true)
      await flushPromises()
      expect(wrapper.get('input[value="bsd"]').attributes('disabled')).toBeUndefined()
      expect(wrapper.text()).not.toContain("You're offline")
    } finally {
      setOnline(true)
    }
  })
})
