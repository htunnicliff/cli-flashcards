import { describe, expect, it } from 'vitest'
import { RoffContext } from './roff'
import { isMdoc, parseMdoc, renderMacroLine } from './mdoc'

describe('renderMacroLine', () => {
  const ctx = { roff: new RoffContext(), name: 'grep' }
  it.each([
    ['Fl i', '-i'],
    ['Fl i , Fl Fl ignore-case', '-i, --ignore-case'],
    ['Fl A Ar num , Fl Fl after-context= Ns Ar num', '-A num, --after-context=num'],
    ['Fl Fl color= Ns Oo Ar when Oc', '--color=[when]'],
    ['Fl e Ar pattern', '-e pattern'],
    ['Fl i Op Ar extension', '-i [extension]'],
    ['Ar', 'file ...'],
    ['Nm', 'grep'],
    ['Xr re_format 7 .', 're_format(7).'],
    ['Dq Li - .', '"-".'],
    ['Ic -name Ar pattern', '-name pattern'],
    ['St -p1003.1', 'IEEE Std 1003.1 (POSIX.1)'],
    ['Pq Fl r', '(-r)'],
  ])('%s', (line, expected) => {
    expect(renderMacroLine(line, ctx)).toBe(expected)
  })
})

describe('parseMdoc', () => {
  const source = [
    '.Dd June 1, 2025',
    '.Dt SED 1',
    '.Os',
    '.Sh NAME',
    '.Nm sed',
    '.Sh DESCRIPTION',
    'The following options are available:',
    '.Bl -tag -width indent',
    '.It Fl E',
    'Use extended',
    '.Xr re_format 7',
    'syntax.',
    '.It Fl i Ar extension',
    'Edit in place.',
    '.Bl -bullet',
    '.It',
    'nested item',
    '.El',
    '.Pp',
    'Like',
    '.Nm .',
    '.El',
    '.Bl -tag',
    '.It Cm word',
    'Not an option.',
    '.El',
  ].join('\n')

  it('detects mdoc', () => {
    expect(isMdoc(source)).toBe(true)
    expect(isMdoc('.TH RG 1\n.SH NAME')).toBe(false)
  })

  it('reads option lists', () => {
    const page = parseMdoc(source)
    expect(page).toMatchObject({ format: 'mdoc', title: 'SED', section: '1' })
    expect(page.entries).toEqual([
      { section: 'DESCRIPTION', tag: '-E', description: 'Use extended re_format(7) syntax.' },
      {
        section: 'DESCRIPTION',
        tag: '-i extension',
        description: 'Edit in place.\n\n• nested item\n\nLike sed.',
      },
    ])
  })
})
