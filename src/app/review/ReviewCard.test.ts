import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'

import { DeckSchema, deriveCards, type Card } from '@/schema'
import { makeDeck, makeOption } from '@/schema/fixtures'

import ReviewCard from './ReviewCard.vue'

const deck = DeckSchema.parse(
  makeDeck([
    makeOption(['-i', '--ignore-case'], {
      summary: 'Match case-insensitively',
      description: 'Ignore case distinctions in patterns and input data.',
      examples: [{ command: 'grep -i todo src/', description: 'Find TODOs in any case' }],
    }),
    makeOption(['-m', '--max-count'], {
      summary: 'Stop after NUM matches',
      argument: { name: 'NUM', optional: false },
    }),
    makeOption(['--line-buffered'], { summary: 'Flush output on every line' }),
  ]),
)
const cards = deriveCards(deck)
const find = (id: string) => cards.find((card) => card.id === `grep:gnu:${id}`)!
const optionOf = (card: Card) => deck.options.find((o) => o.id === card.optionId)

function render(id: string, revealed = false) {
  const card = find(id)
  return mount(ReviewCard, { props: { card, option: optionOf(card), tool: 'grep', revealed } })
}

const texts = (node: { findAll(selector: string): { text(): string }[] }, selector: string) =>
  node.findAll(selector).map((found) => found.text())

describe('ReviewCard', () => {
  it('shows a flag → meaning front with the short flag large and the long form beside it', () => {
    const wrapper = render('ignore-case:flag-to-meaning')
    expect(texts(wrapper, '.front .flag-primary')).toEqual(['-i'])
    expect(texts(wrapper, '.front .flag-alias')).toEqual(['--ignore-case'])
    expect(wrapper.text()).not.toContain('Match case-insensitively')
    expect(wrapper.find('[data-testid="back"]').exists()).toBe(false)
  })

  it('shows a meaning → flag front with the summary only', () => {
    const wrapper = render('ignore-case:meaning-to-flag')
    expect(wrapper.get('[data-testid="front-meaning"]').text()).toBe('Match case-insensitively')
    expect(wrapper.findAll('.flag-primary')).toHaveLength(0)
  })

  it('shows a cloze front with the flag blanked', () => {
    const wrapper = render('ignore-case:cloze')
    const cloze = wrapper.get('[data-testid="front-cloze"]')
    expect(cloze.find('[aria-label="blank"]').exists()).toBe(true)
    expect(cloze.text()).toContain('todo')
    expect(cloze.text()).not.toContain('-i')
    expect(wrapper.text()).toContain('Find TODOs in any case')
  })

  it('puts a long-only flag in the primary position with nothing beside it', () => {
    const wrapper = render('line-buffered:flag-to-meaning')
    expect(texts(wrapper, '.front .flag-primary')).toEqual(['--line-buffered'])
    expect(wrapper.findAll('.front .flag-alias')).toHaveLength(0)
  })

  it('shows every spelling, the summary, an example and the full description on the back', () => {
    const wrapper = render('ignore-case:meaning-to-flag', true)
    const back = wrapper.get('[data-testid="back"]')
    expect(texts(back, '.flag-primary')).toEqual(['-i'])
    expect(texts(back, '.flag-alias')).toEqual(['--ignore-case'])
    expect(back.text()).toContain('Match case-insensitively')
    expect(back.text()).toContain('grep -i todo src/')
    expect(back.get('details').text()).toContain('Ignore case distinctions')
  })

  it('shows the argument after the primary flag', () => {
    const wrapper = render('max-count:flag-to-meaning', true)
    expect(texts(wrapper, '[data-testid="back"] .arg')).toEqual(['NUM'])
  })

  it('shows a subcommand with the tool', () => {
    const card = find('ignore-case:flag-to-meaning')
    const wrapper = mount(ReviewCard, {
      props: {
        card,
        option: { ...optionOf(card)!, subcommand: 'log' },
        tool: 'git',
        revealed: false,
      },
    })
    expect(wrapper.get('.tool').text()).toBe('git log')
  })
})
