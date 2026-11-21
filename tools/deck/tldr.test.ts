import fc from 'fast-check'
import { describe, expect, it } from 'vitest'
import type { OptionInput } from '../../src/schema/deck'
import { makeOption } from '../../src/schema/fixtures'
import {
  matchOptions,
  mentionedFlags,
  parseTldr,
  resolvePlaceholders,
  rewriteToPrimary,
  tldrUsage,
} from './tldr'

const options: OptionInput[] = [
  makeOption(['-l', '--files-with-matches']),
  makeOption(['-g', '--glob'], { argument: { name: 'GLOB' } }),
  makeOption(['-i', '--ignore-case']),
  makeOption(['-n', '--line-number']),
  makeOption(['--files']),
  makeOption(['-n', '--max-count'], { id: 'log.max-count', subcommand: 'log' }),
]

const page = `# rg

> Ripgrep.

- Only list matched files:

\`rg {{[-l|--files-with-matches]}} {{pattern}}\`

- Search with a glob, ignoring case and showing line numbers:

\`rg -in {{pattern}} --glob={{*.ts}}\`

- List files:

\`rg --files\`
`

describe('parseTldr', () => {
  it('reads descriptions and commands', () => {
    expect(parseTldr(page)).toEqual([
      { description: 'Only list matched files', command: 'rg -l pattern' },
      {
        description: 'Search with a glob, ignoring case and showing line numbers',
        command: 'rg -in pattern --glob=*.ts',
      },
      { description: 'List files', command: 'rg --files' },
    ])
  })

  it('resolves placeholders', () => {
    expect(resolvePlaceholders('x {{[-v|--invert]}} {{path/to/file}}')).toBe('x -v path/to/file')
  })
})

describe('matchOptions', () => {
  const ids = (command: string, subcommand?: string) =>
    matchOptions(command, options, subcommand).map((match) => match.option.id)

  it('matches both spellings and =value forms', () => {
    expect(ids('rg --files-with-matches x')).toEqual(['files-with-matches'])
    expect(ids('rg -l x --glob=*.ts')).toEqual(['files-with-matches', 'glob'])
  })

  it('splits combined short flags only when every letter is known', () => {
    expect(ids('rg -in x')).toEqual(['ignore-case', 'line-number'])
    expect(ids('rg -iz x')).toEqual([])
  })

  it('scopes matches to a subcommand', () => {
    expect(ids('git log -n 3', 'log')).toEqual(['log.max-count'])
    expect(ids('rg -n x')).toEqual(['line-number'])
  })

  it('ignores - and --', () => {
    expect(ids('rg -- -l')).toEqual(['files-with-matches'])
  })
})

describe('rewriteToPrimary', () => {
  it('rewrites long forms to the primary short flag', () => {
    expect(rewriteToPrimary('rg --files-with-matches --glob=*.ts x', options)).toBe(
      'rg -l -g *.ts x',
    )
  })

  it('keeps long-only flags and combined flags', () => {
    expect(rewriteToPrimary('rg --files -in', options)).toBe('rg --files -in')
  })

  it('honours an explicit long primary', () => {
    const long = [makeOption(['-i', '--ignore-case'], { primary: '--ignore-case' })]
    expect(rewriteToPrimary('rg -i x', long)).toBe('rg -i x')
    expect(rewriteToPrimary('rg --ignore-case x', long)).toBe('rg --ignore-case x')
  })

  it('never changes which options a command uses', () => {
    const spelling = fc.constantFrom(
      ...options.filter((o) => !o.subcommand).flatMap((o) => o.flags),
    )
    fc.assert(
      fc.property(fc.array(spelling, { maxLength: 5 }), (flags) => {
        const command = ['rg', ...flags, 'pattern'].join(' ')
        const before = matchOptions(command, options).map((m) => m.option.id)
        const after = matchOptions(rewriteToPrimary(command, options), options).map(
          (m) => m.option.id,
        )
        expect(after).toEqual(before)
      }),
    )
  })
})

describe('tldrUsage', () => {
  it('counts examples per option and attaches them simplest first', () => {
    const { counts, examples } = tldrUsage(options, [{ name: 'rg', markdown: page }])
    expect(Object.fromEntries(counts)).toEqual({
      'files-with-matches': 1,
      'ignore-case': 1,
      'line-number': 1,
      glob: 1,
      files: 1,
    })
    expect(examples.get('glob')).toEqual([
      {
        command: 'rg -in pattern -g *.ts',
        description: 'Search with a glob, ignoring case and showing line numbers',
      },
    ])
  })
})

describe('mentionedFlags', () => {
  it('finds flags in synopsis text', () => {
    expect([...mentionedFlags('rg [OPTIONS] -e PATTERN... [-v|--invert] (--files), -.')]).toEqual([
      '-e',
      '-v',
      '--invert',
      '--files',
      '-.',
    ])
  })
})
