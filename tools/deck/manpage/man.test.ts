import { describe, expect, it } from 'vitest'
import { parseMan } from './man'

const page = (body: string) => `.TH TOOL 1\n.SH NAME\ntool \\- does things\n.SH OPTIONS\n${body}`

describe('parseMan', () => {
  it('reads .TP tagged paragraphs', () => {
    const { entries, title, section } = parseMan(
      page('.TP\n\\fB\\-a\\fR, \\fB\\-\\-all\\fR\nShow all.\n.TP\n.B \\-b\nBe brief.\n'),
    )
    expect(title).toBe('TOOL')
    expect(section).toBe('1')
    expect(entries).toEqual([
      { section: 'OPTIONS', tag: '-a, --all', description: 'Show all.' },
      { section: 'OPTIONS', tag: '-b', description: 'Be brief.' },
    ])
  })

  it('adds .TQ lines to the tag', () => {
    const { entries } = parseMan(page('.TP\n\\-a\n.TQ\n\\-\\-all\nShow all.\n'))
    expect(entries[0]?.tag).toBe('-a, --all')
  })

  it('reads .IP "tag" and help2man .HP layouts', () => {
    const { entries } = parseMan(
      page('.IP "\\-a" 4\nShow all.\n.HP\n\\fB\\-b\\fR, \\fB\\-\\-brief\\fR\n.IP\nBe brief.\n'),
    )
    expect(entries.map((e) => [e.tag, e.description])).toEqual([
      ['-a', 'Show all.'],
      ['-b, --brief', 'Be brief.'],
    ])
  })

  it('reads tag paragraphs followed by an .RS body', () => {
    const { entries } = parseMan(
      page(
        [
          '.PP',
          '\\-\\-follow',
          '.RS 4',
          'Follow renames.',
          '.sp',
          'Second paragraph.',
          '.RS 4',
          '.nf',
          'git log \\-\\-follow',
          '.fi',
          '.RE',
          '.RE',
          '.PP',
          'Not an option.',
          '.RS 4',
          'Indented prose.',
          '.RE',
        ].join('\n'),
      ),
    )
    expect(entries).toEqual([
      {
        section: 'OPTIONS',
        tag: '--follow',
        description: 'Follow renames.\n\nSecond paragraph.\n\ngit log --follow',
      },
    ])
  })

  it('keeps nested lists inside a description', () => {
    const { entries } = parseMan(
      page(
        '.TP\n\\-c WHEN\nColour:\n.RS\n.TP\nalways\nAlways.\n.TP\nnever\nNever.\n.RE\n.TP\n\\-d\nD.\n',
      ),
    )
    expect(entries.map((e) => e.tag)).toEqual(['-c WHEN', '-d'])
    expect(entries[0]?.description).toBe('Colour:\n\nalways\nAlways.\n\nnever\nNever.')
  })

  it('records subsections and ignores tags that are not flags', () => {
    const { entries } = parseMan(page('.SS "Output options"\n.TP\nWORD\nNope.\n.TP\n\\-o\nOut.\n'))
    expect(entries).toEqual([
      { section: 'OPTIONS', subsection: 'Output options', tag: '-o', description: 'Out.' },
    ])
  })

  it('ends an entry at .PP and joins font macros', () => {
    const { entries } = parseMan(
      page('.TP\n\\-x\nUses\n.BR foo (1)\nhere.\n.PP\nTrailing prose.\n'),
    )
    expect(entries).toEqual([{ section: 'OPTIONS', tag: '-x', description: 'Uses foo(1) here.' }])
  })
})
