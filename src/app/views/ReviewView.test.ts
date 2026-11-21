import { flushPromises, mount, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory, createRouter } from 'vue-router'

import { createRepository, type Repository } from '@/core/storage'
import { fakeIndexedDB, uniqueDatabaseName } from '@/core/storage/test-utils'
import { DeckSchema } from '@/schema'
import { makeDeck, makeOption } from '@/schema/fixtures'

import { repositoryKey } from '../repository'
import ReviewView from './ReviewView.vue'

let repo: Repository
let wrapper: VueWrapper | undefined

const grep = () =>
  DeckSchema.parse(
    makeDeck([
      makeOption(['-i', '--ignore-case'], {
        tier: 'core',
        summary: 'Match case-insensitively',
        description: 'Ignore case distinctions in patterns and input data.',
        examples: [{ command: 'grep -i todo src/', description: 'Find TODOs in any case' }],
      }),
      makeOption(['--line-buffered'], { summary: 'Flush output on every line' }),
      makeOption(['-c', '--count'], { summary: 'Count matching lines' }),
    ]),
  )

beforeEach(() => {
  setActivePinia(createPinia())
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})
afterEach(async () => {
  wrapper?.unmount()
  wrapper = undefined
  await repo.destroy()
})

async function mountView() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/:p(.*)*', component: { template: '<div/>' } }],
  })
  wrapper = mount(ReviewView, {
    attachTo: document.body,
    global: { provide: { [repositoryKey]: repo }, plugins: [router] },
  })
  await vi.waitFor(() => expect(wrapper!.get('section').attributes('aria-busy')).toBe('false'))
  await flushPromises()
  return wrapper
}

function press(key: string) {
  window.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true }))
}

const cardId = (w: VueWrapper) => w.find('[data-card]').attributes('data-card')
const count = (w: VueWrapper, kind: string) => w.get(`[data-testid="count-${kind}"]`).text()

describe('ReviewView', () => {
  it('points to the Decks page when nothing is installed', async () => {
    const w = await mountView()
    expect(w.get('[data-testid="done"]').text()).toContain('No decks yet')
    expect(w.get('[data-testid="done"] a').attributes('href')).toBe('/decks')
  })

  it('shows the counts and the front of a card, and Space reveals the back', async () => {
    await repo.decks.install(grep())
    const w = await mountView()
    // One card per option a day: its siblings wait until tomorrow.
    expect(count(w, 'new')).toBe('3')
    expect(count(w, 'learning')).toBe('0')
    expect(w.find('[data-testid="back"]').exists()).toBe(false)
    expect(w.findAll('[data-rating]')).toHaveLength(0)

    press(' ')
    await flushPromises()
    expect(w.find('[data-testid="back"]').exists()).toBe(true)
    const buttons = w.findAll('[data-rating]')
    expect(buttons.map((b) => b.find('.grade-label').text())).toEqual([
      'Again',
      'Hard',
      'Good',
      'Easy',
    ])
    for (const button of buttons) expect(button.find('.grade-meta').text()).toMatch(/\d|<1m/)
    // Focus moves to Good so Enter grades it.
    expect(document.activeElement?.getAttribute('data-rating')).toBe('3')
  })

  it('grades with 1–4 and records the review', async () => {
    await repo.decks.install(grep())
    const w = await mountView()
    const first = cardId(w)
    press('3') // ignored: not revealed yet
    await flushPromises()
    expect(cardId(w)).toBe(first)

    press(' ')
    press('3')
    await flushPromises()
    expect(cardId(w)).not.toBe(first)
    await vi.waitFor(async () => expect(await repo.reviewLog.count()).toBe(1))
    const [entry] = await repo.reviewLog.all()
    expect(entry).toMatchObject({ cardId: first, rating: 3 })
    await vi.waitFor(() => expect(count(w, 'new')).toBe('2'))
  })

  it('applies grades pressed back to back without waiting', async () => {
    await repo.decks.install(grep())
    const w = await mountView()
    const seen = [cardId(w)]
    press(' ')
    press('4')
    await w.vm.$nextTick()
    seen.push(cardId(w))
    press(' ')
    press('4')
    await w.vm.$nextTick()
    seen.push(cardId(w))
    expect(new Set(seen).size).toBe(3)
    press(' ')
    press('4')
    await w.vm.$nextTick()
    expect(w.find('[data-testid="done"]').exists()).toBe(true)
    // The writes and refreshes that follow don't bring graded cards back.
    await vi.waitFor(async () => expect(await repo.reviewLog.count()).toBe(3))
    await flushPromises()
    expect(w.find('[data-card]').exists()).toBe(false)
    expect(w.get('[data-testid="done"]').text()).toContain('All done for today')
  })

  it('undoes the last grade with u, restoring the card and removing the log entry', async () => {
    await repo.decks.install(grep())
    const w = await mountView()
    const first = cardId(w)!
    press(' ')
    press('1')
    await vi.waitFor(async () => expect(await repo.reviewLog.count()).toBe(1))
    expect(await repo.cardStates.get(first)).toBeDefined()

    press('u')
    await vi.waitFor(async () => expect(await repo.reviewLog.count()).toBe(0))
    await flushPromises()
    expect(await repo.cardStates.get(first)).toBeUndefined()
    expect(cardId(w)).toBe(first)
    expect(w.find('[data-testid="back"]').exists()).toBe(false)
    expect(count(w, 'new')).toBe('3')
  })

  it('shows "All done for today" with the next due time', async () => {
    await repo.decks.install(
      DeckSchema.parse(makeDeck([makeOption(['--line-buffered'], { summary: 'Flush often' })])),
    )
    const w = await mountView()
    for (let i = 0; i < 2; i++) {
      press(' ')
      press('4')
      await flushPromises()
    }
    await vi.waitFor(() => expect(w.find('[data-testid="done"]').exists()).toBe(true))
    await vi.waitFor(() => expect(w.get('[data-testid="done"]').text()).toContain('next review'))
    expect(w.get('[data-testid="done"]').text()).toContain('All done for today')
  })

  it('grades Again on a swipe left and snaps back on a short one', async () => {
    await repo.decks.install(grep())
    const w = await mountView()
    const first = cardId(w)
    const stage = w.get('.card-stage')
    const swipe = async (dx: number) => {
      const init = { pointerType: 'touch', pointerId: 1, clientY: 100, bubbles: true }
      stage.element.dispatchEvent(new PointerEvent('pointerdown', { ...init, clientX: 200 }))
      stage.element.dispatchEvent(new PointerEvent('pointermove', { ...init, clientX: 200 + dx }))
      stage.element.dispatchEvent(new PointerEvent('pointerup', { ...init, clientX: 200 + dx }))
      await flushPromises()
    }
    press(' ')
    await flushPromises()
    await swipe(-40)
    expect(cardId(w)).toBe(first)
    await swipe(-150)
    expect(cardId(w)).not.toBe(first)
    await vi.waitFor(async () => expect(await repo.reviewLog.count()).toBe(1))
    expect((await repo.reviewLog.all())[0]).toMatchObject({ cardId: first, rating: 1 })
  })

  it('toggles the shortcut help with ?', async () => {
    await repo.decks.install(grep())
    const w = await mountView()
    expect(w.find('#shortcut-help').exists()).toBe(false)
    press('?')
    await flushPromises()
    expect(w.get('#shortcut-help').text()).toContain('Undo the last grade')
    press('?')
    await vi.waitFor(() => expect(w.find('#shortcut-help').exists()).toBe(false))
  })

  it('ignores shortcuts while typing in a field', async () => {
    await repo.decks.install(grep())
    const w = await mountView()
    const input = document.createElement('input')
    document.body.append(input)
    input.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true }))
    await flushPromises()
    expect(w.find('[data-testid="back"]').exists()).toBe(false)
    input.remove()
  })
})
