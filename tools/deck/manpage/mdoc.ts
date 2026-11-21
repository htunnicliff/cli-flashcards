/**
 * mdoc(7) front end, for BSD and macOS pages. Options live in `.Bl -tag`
 * lists whose items start with `Fl` (`.It Fl i Ar extension`) or, for `find`
 * primaries, `Ic`/`Cm`.
 */
import { RoffContext, collapse, readRoff, splitArgs } from './roff'
import { TextBuilder } from './text'
import type { RawPage } from './types'

/** Punctuation that attaches to the word before it. */
const CLOSING = /^[.,;:?!)\]]+$/
/** Punctuation that attaches to the word after it. */
const OPENING = /^[([]+$/

/** Macros whose arguments print as they are. */
const LITERAL = new Set([
  'Ad',
  'An',
  'Cd',
  'Cm',
  'Dv',
  'Em',
  'Er',
  'Ev',
  'Fa',
  'Fn',
  'Fr',
  'Ft',
  'Ic',
  'Li',
  'Lk',
  'Ms',
  'Mt',
  'No',
  'Pa',
  'Sx',
  'Sy',
  'Tn',
  'Va',
  'Vt',
  'Xc',
  'Xo',
  'Ql',
  'Ot',
  'Ex',
  'Rv',
])

/** Macros that wrap the rest of the line. */
const ENCLOSE: Record<string, [string, string]> = {
  Dq: ['"', '"'],
  Qq: ['"', '"'],
  Sq: ["'", "'"],
  Pq: ['(', ')'],
  Bq: ['[', ']'],
  Brq: ['{', '}'],
  Aq: ['<', '>'],
  Op: ['[', ']'],
  Ql: ["'", "'"],
  Eo: ['', ''],
}

const OPEN: Record<string, string> = {
  Oo: '[',
  Do: '"',
  Qo: '"',
  So: "'",
  Po: '(',
  Bo: '[',
  Bro: '{',
  Ao: '<',
}
const CLOSE: Record<string, string> = {
  Oc: ']',
  Dc: '"',
  Qc: '"',
  Sc: "'",
  Pc: ')',
  Bc: ']',
  Brc: '}',
  Ac: '>',
  Ec: '',
}

const NAMES: Record<string, string> = {
  Ux: 'UNIX',
  Bx: 'BSD',
  Fx: 'FreeBSD',
  Nx: 'NetBSD',
  Ox: 'OpenBSD',
  Dx: 'DragonFly',
  Bsx: 'BSD/OS',
  At: 'AT&T UNIX',
}

const STANDARDS: Record<string, string> = {
  '-p1003.1': 'IEEE Std 1003.1 (POSIX.1)',
  '-p1003.1-2001': 'IEEE Std 1003.1-2001 (POSIX.1)',
  '-p1003.1-2004': 'IEEE Std 1003.1-2004 (POSIX.1)',
  '-p1003.1-2008': 'IEEE Std 1003.1-2008 (POSIX.1)',
  '-p1003.2': 'IEEE Std 1003.2 (POSIX.2)',
  '-p1003.2-92': 'IEEE Std 1003.2-1992 (POSIX.2)',
  '-susv2': 'Version 2 of the Single UNIX Specification (SUSv2)',
  '-susv3': 'Version 3 of the Single UNIX Specification (SUSv3)',
  '-susv4': 'Version 4 of the Single UNIX Specification (SUSv4)',
  '-xpg4': 'X/Open Portability Guide Issue 4 (XPG4)',
  '-xpg4.2': 'X/Open Portability Guide Issue 4, Version 2 (XPG4.2)',
  '-isoC': 'ISO/IEC 9899:1990 (ISO C90)',
  '-isoC-99': 'ISO/IEC 9899:1999 (ISO C99)',
}

const MACRO = /^[A-Z][a-z]{1,2}$|^[A-Z][a-z]?[a-z]?$/

export interface MdocRenderContext {
  roff: RoffContext
  /** The page's `.Nm`, printed by later bare `.Nm` calls. */
  name: string
}

/** Renders one mdoc macro line (without the leading dot) to plain text. */
export function renderMacroLine(rest: string, ctx: MdocRenderContext): string {
  const words = splitArgs(rest).map((arg) => ({ raw: arg, text: ctx.roff.unescape(arg) }))
  const pieces: string[] = []
  let noSpace = false
  const push = (text: string) => {
    if (text === '') return
    if (pieces.length === 0 || noSpace || CLOSING.test(text)) {
      if (pieces.length === 0) pieces.push(text)
      else pieces[pieces.length - 1] += text
    } else if (OPENING.test(pieces[pieces.length - 1]!)) {
      pieces[pieces.length - 1] += text
    } else {
      pieces.push(text)
    }
    noSpace = false
  }

  /** Renders words[i..] until the end of line; returns rendered text. */
  const renderFrom = (start: number, stopAtClose = false): [string, number] => {
    const saved = pieces.splice(0)
    const savedNoSpace = noSpace
    noSpace = false
    let i = start
    let macro: string | undefined
    while (i < words.length) {
      const word = words[i]!
      if (MACRO.test(word.raw) && isMacro(word.raw)) {
        if (stopAtClose && word.raw in CLOSE) break
        macro = word.raw
        i++
        i = applyMacro(macro, i)
        continue
      }
      // Plain arguments keep the formatting of the macro before them; for
      // our purposes that means Fl keeps adding dashes.
      if (macro === 'Fl' && !CLOSING.test(word.text) && !OPENING.test(word.text)) {
        push(`-${word.text}`)
      } else {
        push(word.text)
      }
      i++
    }
    const text = pieces.join(' ')
    pieces.splice(0, pieces.length, ...saved)
    noSpace = savedNoSpace
    return [text, i]
  }

  /** Applies a macro whose name was at i-1; returns the next index. */
  const applyMacro = (macro: string, i: number): number => {
    if (macro === 'Ns') {
      noSpace = true
      return i
    }
    if (macro === 'Ap') {
      noSpace = true
      push("'")
      noSpace = true
      return i
    }
    if (macro === 'Pf') {
      const word = words[i]
      if (word) push(word.text)
      noSpace = true
      return i + 1
    }
    if (macro === 'Fl') {
      const word = words[i]
      if (!word || isMacro(word.raw) || CLOSING.test(word.text)) {
        push('-')
        if (word && isMacro(word.raw)) noSpace = true
        return i
      }
      return i
    }
    if (macro === 'Ar') {
      const word = words[i]
      if (!word || isMacro(word.raw) || CLOSING.test(word.text)) push('file ...')
      return i
    }
    if (macro === 'Nm') {
      const word = words[i]
      if (!word || isMacro(word.raw) || CLOSING.test(word.text)) push(ctx.name)
      return i
    }
    if (macro === 'Xr') {
      const name = words[i]?.text ?? ''
      const section = words[i + 1]?.text
      push(section && /^\w+$/.test(section) ? `${name}(${section})` : name)
      return section && /^\w+$/.test(section) ? i + 2 : i + 1
    }
    if (macro === 'St') {
      const flag = words[i]?.text ?? ''
      push(STANDARDS[flag] ?? 'the relevant standard')
      return i + 1
    }
    if (macro in NAMES) {
      push(NAMES[macro]!)
      return i
    }
    if (macro in ENCLOSE) {
      const [left, right] = ENCLOSE[macro]!
      // Trailing punctuation stays outside the enclosure.
      let end = words.length
      while (end > i && CLOSING.test(words[end - 1]!.text)) end--
      const [inner] = renderSlice(i, end)
      push(`${left}${inner}${right}`)
      for (let j = end; j < words.length; j++) push(words[j]!.text)
      return words.length
    }
    if (macro in OPEN) {
      const [inner, next] = renderFrom(i, true)
      const closer = words[next]
      push(`${OPEN[macro]}${inner}${closer ? (CLOSE[closer.raw] ?? '') : ''}`)
      return closer ? next + 1 : next
    }
    if (macro in CLOSE) return i
    // Literal macros and anything unknown: just let the arguments print.
    return i
  }

  const renderSlice = (start: number, end: number): [string, number] => {
    const tail = words.splice(end)
    const result = renderFrom(start)
    words.push(...tail)
    return result
  }

  const [text] = renderFrom(0)
  return text
}

function isMacro(word: string): boolean {
  return (
    word === 'Fl' ||
    word === 'Ar' ||
    word === 'Ns' ||
    word === 'Nm' ||
    word === 'Xr' ||
    word === 'St' ||
    word === 'Ap' ||
    word === 'Pf' ||
    LITERAL.has(word) ||
    word in ENCLOSE ||
    word in OPEN ||
    word in CLOSE ||
    word in NAMES
  )
}

interface ListState {
  tagged: boolean
  /** Item being collected for this list, if it is an option list. */
  item?: { tag: string; body: TextBuilder; section: string; subsection?: string }
}

export function parseMdoc(source: string): RawPage {
  const roff = new RoffContext()
  const lines = readRoff(source, roff)
  const ctx: MdocRenderContext = { roff, name: '' }
  const page: RawPage = {
    format: 'mdoc',
    title: '',
    section: undefined,
    entries: [],
    sectionText: {},
  }

  let section = ''
  let subsection: string | undefined
  const lists: ListState[] = []

  /** Innermost list item currently collecting a body, if any. */
  const currentBody = (): TextBuilder | undefined => {
    for (let i = lists.length - 1; i >= 0; i--) {
      const item = lists[i]!.item
      if (item) return item.body
    }
    return undefined
  }

  const closeItem = (list: ListState) => {
    const item = list.item
    if (!item) return
    list.item = undefined
    const tag = collapse(item.tag)
    if (tag.startsWith('-')) {
      page.entries.push({
        section: item.section,
        ...(item.subsection ? { subsection: item.subsection } : {}),
        tag,
        description: item.body.toString(),
      })
    }
  }

  const record = (text: string) => {
    page.sectionText[section] = `${page.sectionText[section] ?? ''}${text}\n`
  }

  for (const line of lines) {
    if (line.kind === 'text') {
      const text = roff.unescape(line.text)
      record(text)
      currentBody()?.add(text)
      continue
    }
    const { name, rest, args } = line
    if (MACRO.test(name) && name !== 'Sh' && name !== 'Ss')
      record(renderMacroLine(`${name} ${rest}`, ctx))
    switch (name) {
      case 'Dt':
        page.title = roff.unescape(args[0] ?? '')
        page.section = args[1] ? roff.unescape(args[1]) : undefined
        break
      case 'Nm':
        if (!ctx.name && args[0]) ctx.name = roff.unescape(args[0])
        currentBody()?.add(renderMacroLine(`Nm ${rest}`, ctx))
        break
      case 'Sh':
      case 'Ss': {
        while (lists.length) closeItem(lists.pop()!)
        const heading = collapse(renderMacroLine(rest, ctx))
        if (name === 'Sh') {
          section = heading.toUpperCase()
          subsection = undefined
        } else {
          subsection = heading
        }
        break
      }
      case 'Bl': {
        lists.push({ tagged: /-(tag|hang|ohang|inset|diag)\b/.test(rest) })
        currentBody()?.paragraph()
        break
      }
      case 'El': {
        const list = lists.pop()
        if (list) closeItem(list)
        currentBody()?.paragraph()
        break
      }
      case 'It': {
        const list = lists[lists.length - 1]
        if (!list) break
        closeItem(list)
        const tag = renderMacroLine(rest, ctx)
        const outer = currentBody()
        if (outer) {
          // A list inside an option's description: keep it as text.
          outer.paragraph()
          if (list.tagged) {
            outer.add(tag)
            outer.lineBreak()
          } else {
            outer.add(tag ? `• ${tag}` : '•')
          }
          break
        }
        if (list.tagged) {
          list.item = { tag, body: new TextBuilder(), section, subsection }
        }
        break
      }
      case 'Pp':
      case 'Lp':
        currentBody()?.paragraph()
        break
      case 'br':
        currentBody()?.lineBreak()
        break
      case 'Bd':
        currentBody()?.setPreformatted(/-(literal|unfilled)\b/.test(rest))
        break
      case 'Ed':
        currentBody()?.setPreformatted(false)
        break
      case 'D1':
      case 'Dl': {
        const body = currentBody()
        if (body) {
          body.paragraph()
          body.add(renderMacroLine(rest, ctx))
          body.paragraph()
        }
        break
      }
      case 'Dd':
      case 'Os':
      case 'Nd':
      case 'Rs':
      case 'Re':
      case 'In':
      case 'Fd':
      case 'sp':
        break
      default:
        if (MACRO.test(name)) currentBody()?.add(renderMacroLine(`${name} ${rest}`, ctx))
    }
  }
  while (lists.length) closeItem(lists.pop()!)
  return page
}

/** True when the source uses mdoc macros rather than man(7). */
export function isMdoc(source: string): boolean {
  return /^\.Dd\b/m.test(source) || /^\.Sh\s/m.test(source)
}
