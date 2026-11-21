import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'

import { CommandLine, UiButton, UiCard, UiChip, UiKbd, type CommandPart } from '.'

describe('UiButton', () => {
  it('is a neutral type="button" by default', () => {
    const wrapper = mount(UiButton, { slots: { default: 'Hard' } })
    expect(wrapper.element.tagName).toBe('BUTTON')
    expect(wrapper.attributes('type')).toBe('button')
    expect(wrapper.classes()).toContain('button--neutral')
    expect(wrapper.text()).toBe('Hard')
  })

  it.each(['primary', 'again'] as const)('renders the %s variant', (variant) => {
    const wrapper = mount(UiButton, { props: { variant } })
    expect(wrapper.classes()).toContain(`button--${variant}`)
  })

  it('emits clicks', async () => {
    const wrapper = mount(UiButton)
    await wrapper.trigger('click')
    expect(wrapper.emitted('click')).toHaveLength(1)
  })
})

describe('UiKbd, UiChip, UiCard', () => {
  it('renders a <kbd>', () => {
    const wrapper = mount(UiKbd, { slots: { default: 'Space' } })
    expect(wrapper.element.tagName).toBe('KBD')
    expect(wrapper.text()).toBe('Space')
  })

  it('renders a chip, optionally in mono', () => {
    const wrapper = mount(UiChip, { props: { mono: true }, slots: { default: 'rg' } })
    expect(wrapper.classes()).toEqual(['chip', 'mono'])
  })

  it('renders a card as the requested element', () => {
    const wrapper = mount(UiCard, { props: { as: 'article' }, slots: { default: 'front' } })
    expect(wrapper.element.tagName).toBe('ARTICLE')
    expect(wrapper.classes()).toContain('card')
  })
})

describe('CommandLine', () => {
  const parts: CommandPart[] = [
    { kind: 'tool', text: 'rg' },
    { kind: 'flag', text: '-m' },
    { kind: 'arg', text: 'NUM' },
    { kind: 'flag', text: '-i' },
    { kind: 'arg', text: 'PATTERN' },
  ]

  it('reads as the plain command, so copying it works', () => {
    expect(mount(CommandLine, { props: { parts } }).text()).toBe('rg -m NUM -i PATTERN')
  })

  it('styles flags and arguments, with arguments also in Casual italic', () => {
    const wrapper = mount(CommandLine, { props: { parts } })
    expect(wrapper.findAll('.part--flag').map((s) => s.text())).toEqual(['-m', '-i'])
    const args = wrapper.findAll('.part--arg')
    expect(args.map((s) => s.text())).toEqual(['NUM', 'PATTERN'])
    for (const arg of args) expect(arg.classes()).toContain('mono-casual')
  })

  it('renders a cloze blank', () => {
    const wrapper = mount(CommandLine, {
      props: {
        parts: [
          { kind: 'tool', text: 'sed' },
          { kind: 'blank', text: '-E' },
          { kind: 'tool', text: "'s/(foo|bar)+/x/'" },
        ],
      },
    })
    const blank = wrapper.get('.part--blank')
    expect(blank.attributes('aria-label')).toBe('blank')
    expect(blank.text()).toBe('')
    expect(wrapper.text()).not.toContain('-E')
  })

  it('renders as a sunken block for examples', () => {
    const wrapper = mount(CommandLine, { props: { parts, block: true } })
    expect(wrapper.classes()).toContain('command-line--block')
  })
})
