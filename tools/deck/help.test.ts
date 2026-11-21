import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { generateDeck } from './generate'
import { parseHelp, stripHelpAnnotations } from './help'

const fixture = (name: string) => readFileSync(join(__dirname, 'help-fixtures', name), 'utf8')

describe('parseHelp', () => {
  it('reads one-line entries with wrapped descriptions', () => {
    const page = parseHelp(
      [
        'Usage: tool [OPTIONS] <PATTERN>',
        '',
        'Options:',
        '  -i, --ignore-case        Search case insensitively, which is',
        '                           handy',
        '      --color <WHEN>       When to use colour',
        '  -h, --help               Print help',
        '',
        'Run `tool help` for more.',
      ].join('\n'),
    )
    expect(page.entries).toEqual([
      {
        section: 'OPTIONS',
        tag: '-i, --ignore-case',
        description: 'Search case insensitively, which is handy',
      },
      { section: 'OPTIONS', tag: '--color <WHEN>', description: 'When to use colour' },
      { section: 'OPTIONS', tag: '-h, --help', description: 'Print help' },
    ])
    expect(page.sectionText.SYNOPSIS).toBe('tool [OPTIONS] <PATTERN>\n')
  })

  it('reads long help with descriptions on the following lines', () => {
    const page = parseHelp(
      [
        'Options:',
        '      --fix',
        '          Apply fixes.',
        '',
        '          Second paragraph.',
        '',
        '  -w, --watch',
        '          Watch files',
        '      --no-cache',
        '  -o, --output <FILE>',
        '          Write here',
      ].join('\n'),
    )
    expect(page.entries.map((e) => [e.tag, e.description])).toEqual([
      ['--fix', 'Apply fixes.\n\nSecond paragraph.'],
      ['-w, --watch', 'Watch files'],
      ['--no-cache', ''],
      ['-o, --output <FILE>', 'Write here'],
    ])
  })

  it('skips positional arguments and subcommand lists', () => {
    const page = parseHelp(
      'Commands:\n  run   Run it\n\nArguments:\n  [FILES]...\n          Files\n',
    )
    expect(page.entries).toEqual([])
  })
})

describe('stripHelpAnnotations', () => {
  it('drops clap annotations', () => {
    expect(stripHelpAnnotations('Cache dir [env: UV_CACHE_DIR=] [default: ~/.cache]')).toBe(
      'Cache dir',
    )
  })
})

describe('--help fixtures', () => {
  it.each([
    { file: 'ruff-check.txt', tool: 'ruff', subcommand: 'check' },
    { file: 'uv.txt', tool: 'uv', subcommand: undefined },
  ])('generates a deck from $file', async ({ file, tool, subcommand }) => {
    const { deck, warnings } = generateDeck({
      tool,
      variant: 'default',
      toolVersion: 'fixture',
      pages: [
        {
          name: subcommand ? `${tool}-${subcommand}` : tool,
          source: fixture(file),
          format: 'help',
          ...(subcommand ? { subcommand } : {}),
        },
      ],
    })
    expect(deck.source).toBe('help')
    await expect(`${JSON.stringify({ deck, warnings }, null, 2)}\n`).toMatchFileSnapshot(
      `__snapshots__/${file}.json`,
    )
  })

  it('parses ruff check options', () => {
    const { deck } = generateDeck({
      tool: 'ruff',
      variant: 'default',
      toolVersion: '0.16.9',
      pages: [
        {
          name: 'ruff-check',
          source: fixture('ruff-check.txt'),
          format: 'help',
          subcommand: 'check',
        },
      ],
    })
    const option = (id: string) => deck.options.find((o) => o.id === id)
    expect(option('check.watch')).toMatchObject({ flags: ['-w', '--watch'], subcommand: 'check' })
    expect(option('check.output-format')).toMatchObject({
      argument: { name: 'OUTPUT_FORMAT', optional: false },
      summary: 'Output serialization format for violations.',
    })
    expect(option('check.add-noqa')?.argument).toEqual({ name: 'REASON', optional: true })
  })

  it('reads repeatable flags', () => {
    const { deck } = generateDeck({
      tool: 'uv',
      variant: 'default',
      toolVersion: '1',
      pages: [{ name: 'uv', source: fixture('uv.txt'), format: 'help' }],
    })
    expect(deck.options.find((o) => o.id === 'verbose')?.flags).toEqual(['-v', '--verbose'])
    expect(deck.options.find((o) => o.id === 'cache-dir')?.summary).toBe(
      'Path to the cache directory',
    )
  })
})
