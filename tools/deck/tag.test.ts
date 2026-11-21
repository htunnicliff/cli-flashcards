import { describe, expect, it } from 'vitest'
import { parseTag, splitTag } from './tag'

describe('splitTag', () => {
  it('splits on commas outside brackets', () => {
    expect(splitTag('-i, --ignore-case')).toEqual(['-i', '--ignore-case'])
    expect(splitTag('-L<start>,<end>:<file>, -L:<f>:<file>')).toEqual([
      '-L<start>,<end>:<file>',
      '-L:<f>:<file>',
    ])
    expect(splitTag('--stat[=<w>[,<n>]]')).toEqual(['--stat[=<w>[,<n>]]'])
  })
})

describe('parseTag', () => {
  it.each([
    ['-i, --ignore-case', { flags: ['-i', '--ignore-case'] }],
    ['--ignore-case, -i', { flags: ['-i', '--ignore-case'] }],
    [
      '-e PATTERN, --regexp=PATTERN',
      { flags: ['-e', '--regexp'], argument: { name: 'PATTERN', optional: false } },
    ],
    ['--color=WHEN', { flags: ['--color'], argument: { name: 'WHEN', optional: false } }],
    ['--color[=WHEN]', { flags: ['--color'], argument: { name: 'WHEN', optional: true } }],
    ['--colour=[when]', { flags: ['--colour'], argument: { name: 'when', optional: true } }],
    [
      '-i[SUFFIX], --in-place[=SUFFIX]',
      { flags: ['-i', '--in-place'], argument: { name: 'SUFFIX', optional: true } },
    ],
    ['-C[<n>]', { flags: ['-C'], argument: { name: 'n', optional: true } }],
    ['-S<string>', { flags: ['-S'], argument: { name: 'string', optional: false } }],
    [
      '-n <number>, --max-count=<number>',
      { flags: ['-n', '--max-count'], argument: { name: 'number', optional: false } },
    ],
    ['--[no-]verify', { flags: ['--verify', '--no-verify'] }],
    ['--no-decorate, --decorate', { flags: ['--decorate', '--no-decorate'] }],
    ['-E, -r, --regexp-extended', { flags: ['-E', '-r', '--regexp-extended'] }],
    ['-name pattern', { flags: ['-name'], argument: { name: 'pattern', optional: false } }],
    ['-amin [-|+]n', { flags: ['-amin'], argument: { name: '[-|+]n', optional: false } }],
    ['-?', { flags: ['-?'] }],
    // Short-form argument names are used when the long form has none.
    [
      '-A num, --after-context',
      { flags: ['-A', '--after-context'], argument: { name: 'num', optional: false } },
    ],
    // The long form's argument name wins.
    [
      '-f FILE, --file=PATTERNFILE',
      { flags: ['-f', '--file'], argument: { name: 'PATTERNFILE', optional: false } },
    ],
  ])('%s', (tag, expected) => {
    expect(parseTag(tag)).toEqual(expected)
  })

  it.each(['-<number>', '-NUM', '--', '--full-history without parent rewriting', 'prose'])(
    'rejects %s',
    (tag) => {
      expect(parseTag(tag)).toBeNull()
    },
  )

  it('keeps the flags it can read when one part is not a flag', () => {
    expect(parseTag('-<number>, -n <number>')).toEqual({
      flags: ['-n'],
      argument: { name: 'number', optional: false },
    })
  })
})
