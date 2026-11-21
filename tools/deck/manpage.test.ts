import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { generateDeck } from './generate'

const fixture = (name: string) => readFileSync(join(__dirname, 'manpage/fixtures', name), 'utf8')

/**
 * Snapshot tests over real manpages. When the parser changes, the JSON
 * snapshots under __snapshots__/ change too, so the effect shows up in review.
 * Update them with `pnpm test -u`.
 */
describe('generateDeck snapshots', () => {
  const cases = [
    { file: 'rg.1', tool: 'rg', variant: 'default', name: 'rg' },
    { file: 'git-log.1', tool: 'git', variant: 'default', name: 'git-log', subcommand: 'log' },
    { file: 'sed.gnu.1', tool: 'sed', variant: 'gnu', name: 'sed' },
    { file: 'sed.bsd.1', tool: 'sed', variant: 'bsd', name: 'sed' },
  ]
  for (const { file, tool, variant, name, subcommand } of cases) {
    it(`parses ${file}`, async () => {
      const { deck, warnings } = generateDeck({
        tool,
        variant,
        toolVersion: 'fixture',
        pages: [{ name, source: fixture(file), path: file, ...(subcommand ? { subcommand } : {}) }],
      })
      const snapshot = { deck, warnings }
      await expect(`${JSON.stringify(snapshot, null, 2)}\n`).toMatchFileSnapshot(
        `__snapshots__/${file}.json`,
      )
    })
  }
})

describe('parsed fixtures', () => {
  const rg = generateDeck({
    tool: 'rg',
    variant: 'default',
    toolVersion: '14.1.0',
    pages: [{ name: 'rg', source: fixture('rg.1') }],
  }).deck
  const option = (id: string) => rg.options.find((o) => o.id === id)

  it('finds every ripgrep option', () => {
    expect(rg.options.length).toBeGreaterThan(100)
    expect(option('ignore-case')).toMatchObject({
      flags: ['-i', '--ignore-case'],
      summary: 'When this flag is provided, all patterns will be searched case insensitively.',
    })
  })

  it('records arguments', () => {
    expect(option('color')?.argument).toEqual({ name: 'WHEN', optional: false })
    expect(option('glob')).toMatchObject({ flags: ['-g', '--glob'], argument: { name: 'GLOB' } })
  })

  it('keeps preformatted examples in descriptions', () => {
    expect(option('regexp')?.description).toContain('\n\n    rg -e -foo\n\n')
  })

  it('tags git options with their subcommand', () => {
    const git = generateDeck({
      tool: 'git',
      variant: 'default',
      toolVersion: '2.43.0',
      pages: [{ name: 'git-log', source: fixture('git-log.1'), subcommand: 'log' }],
    }).deck
    const oneline = git.options.find((o) => o.id === 'log.oneline')
    expect(oneline).toMatchObject({ flags: ['--oneline'], subcommand: 'log', tags: ['log'] })
    const maxCount = git.options.find((o) => o.id === 'log.max-count')
    expect(maxCount).toMatchObject({
      flags: ['-n', '--max-count'],
      argument: { name: 'number', optional: false },
    })
    expect(git.options.find((o) => o.id === 'log.no-decorate')?.flags).toEqual([
      '--decorate',
      '--no-decorate',
    ])
  })

  it('reads BSD mdoc pages', () => {
    const sed = generateDeck({
      tool: 'sed',
      variant: 'bsd',
      toolVersion: '1',
      pages: [{ name: 'sed', source: fixture('sed.bsd.1') }],
    }).deck
    expect(sed.options.map((o) => o.flags[0])).toEqual(
      expect.arrayContaining(['-E', '-a', '-e', '-f', '-I', '-i', '-n', '-r']),
    )
    expect(sed.options.find((o) => o.id === 'short-i')).toMatchObject({
      argument: { name: 'extension', optional: false },
      summary:
        'Edit files in-place similarly to -I, but treat each file independently from other files.',
    })
  })

  it('reads help2man pages', () => {
    const sed = generateDeck({
      tool: 'sed',
      variant: 'gnu',
      toolVersion: '4.9',
      pages: [{ name: 'sed', source: fixture('sed.gnu.1') }],
    }).deck
    expect(sed.options.find((o) => o.id === 'in-place')).toMatchObject({
      flags: ['-i', '--in-place'],
      argument: { name: 'SUFFIX', optional: true },
      summary: 'Edit files in place (makes backup if SUFFIX supplied)',
    })
    expect(sed.options.find((o) => o.id === 'regexp-extended')?.flags).toEqual([
      '-E',
      '-r',
      '--regexp-extended',
    ])
  })
})
