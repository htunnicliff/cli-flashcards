import { describe, expect, it } from 'vitest'
import { TextBuilder, firstSentence } from './text'

describe('firstSentence', () => {
  it.each([
    ['Print matches. Then more.', 'Print matches.'],
    ['suppress automatic printing', 'Suppress automatic printing'],
    ['Search files, e.g. logs. More.', 'Search files, e.g. logs.'],
    ['Respect .gitignore files. More.', 'Respect .gitignore files.'],
    ['Version 1.5 is required. More.', 'Version 1.5 is required.'],
    ['First paragraph\n\nSecond.', 'First paragraph'],
    ['', ''],
  ])('%j', (input, expected) => {
    expect(firstSentence(input)).toBe(expected)
  })

  it('shortens very long sentences on a word boundary', () => {
    const summary = firstSentence(`${'word '.repeat(100)}end.`)
    expect(summary.length).toBeLessThanOrEqual(301)
    expect(summary.endsWith('…')).toBe(true)
  })
})

describe('TextBuilder', () => {
  it('fills text and keeps preformatted blocks', () => {
    const text = new TextBuilder()
    text.add('Some   text')
    text.add('continues.')
    text.setPreformatted(true)
    text.add('    rg foo')
    text.add('    rg bar')
    text.setPreformatted(false)
    text.add('After.')
    text.lineBreak()
    text.add('Next line.')
    expect(text.toString()).toBe(
      'Some text continues.\n\n    rg foo\n    rg bar\n\nAfter.\nNext line.',
    )
  })

  it('joins words for no-space macros', () => {
    const text = new TextBuilder()
    text.addJoined('start')
    text.add('--color')
    text.addJoined('=always')
    expect(text.toString()).toBe('start --color=always')
  })
})
