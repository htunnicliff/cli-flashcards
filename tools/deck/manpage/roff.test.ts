import { describe, expect, it } from 'vitest'
import { RoffContext, readRoff, splitArgs } from './roff'

describe('RoffContext.unescape', () => {
  const ctx = new RoffContext()
  it.each([
    ['\\fB\\-i\\fP, \\fB\\-\\-ignore\\-case\\fR', '-i, --ignore-case'],
    ['\\f(CWcode\\fP and \\f[B]bold\\f[]', 'code and bold'],
    ['doesn\\(cqt \\(lqquote\\(rq \\(em dash', 'doesn\'t "quote" — dash'],
    ['\\[u00E9]t\\[aq]', "ét'"],
    ['a\\&.b \\e c\\\\d', 'a.b \\ c\\d'],
    ["x\\h'-0.04i'y\\s-1z\\s0", 'xyz'],
    ['text \\" a comment', 'text'],
    ['\\*(Aq', "'"],
    ['\\,italic\\/', 'italic'],
  ])('%j', (input, expected) => {
    expect(ctx.unescape(input)).toBe(expected)
  })

  it('expands strings defined with .ds', () => {
    const local = new RoffContext()
    readRoff('.ds sd \\fIsed\\fP\n', local)
    expect(local.unescape('\\*(sd is')).toBe('sed is')
  })
})

describe('splitArgs', () => {
  it('groups quoted words', () => {
    expect(splitArgs('"two words" one "say ""hi"""')).toEqual(['two words', 'one', 'say "hi"'])
  })
})

describe('readRoff', () => {
  const lines = (source: string) => readRoff(source, new RoffContext())

  it('drops comments, macro definitions and layout requests', () => {
    expect(lines('.\\" comment\n.de XX\n.ft B\n..\n.ad l\ntext\n')).toEqual([
      { kind: 'text', text: 'text' },
    ])
  })

  it('keeps the nroff branch of conditionals', () => {
    const source = [
      '.ie n \\{\\',
      'terminal',
      '.\\}',
      '.el \\{\\',
      'typeset',
      '.\\}',
      '.if t skipped',
      '.if n kept',
    ].join('\n')
    expect(lines(source).map((line) => (line.kind === 'text' ? line.text : line.name))).toEqual([
      'terminal',
      'kept',
    ])
  })

  it('joins continuation lines and parses requests', () => {
    expect(lines('.TP 8\nfoo\\\nbar\n')).toEqual([
      { kind: 'request', name: 'TP', args: ['8'], rest: '8' },
      { kind: 'text', text: 'foobar' },
    ])
  })
})
