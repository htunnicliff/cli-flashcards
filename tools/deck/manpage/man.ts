/**
 * man(7) front end: finds tagged paragraphs in a classic manpage.
 *
 * Three layouts cover nearly every page in the wild:
 *
 * - `.TP` / `.IP "tag"` / `.HP` tagged paragraphs (GNU, help2man);
 * - a paragraph holding only the tag followed by an `.RS`/`.RE` indented body
 *   (asciidoc/docbook pages such as git's, and ripgrep's);
 * - `.TQ` for extra tag lines under a `.TP`.
 */
import { RoffContext, collapse, readRoff, type RoffLine } from './roff'
import { TextBuilder } from './text'
import type { RawEntry, RawPage } from './types'

type EntryKind = 'tp' | 'hp' | 'ip' | 'rs'

interface OpenEntry {
  kind: EntryKind
  section: string
  subsection?: string
  tags: string[]
  /** `.RS` depth when the entry opened. */
  depth: number
  body: TextBuilder
}

/** Font macros whose arguments alternate between two fonts with no space. */
const ALTERNATING = new Set(['BR', 'RB', 'BI', 'IB', 'IR', 'RI'])
const FONT = new Set(['B', 'I', 'SM', 'SB', 'R'])

export function parseMan(source: string): RawPage {
  const ctx = new RoffContext()
  const lines = readRoff(source, ctx)
  const page: RawPage = { format: 'man', title: '', section: undefined, entries: [] }

  let section = ''
  let subsection: string | undefined
  let rsDepth = 0
  let entry: OpenEntry | undefined
  /** Text seen since the last paragraph break while no entry is open. */
  let pending: string[] = []
  /** Next text line is a tag: for a new entry, or for a list inside a body. */
  let expectTag: 'entry' | 'extra' | 'body' | undefined
  let preformatted = false

  const close = () => {
    if (!entry) return
    const tag = collapse(entry.tags.join(', '))
    if (tag.startsWith('-')) {
      page.entries.push({
        section: entry.section,
        ...(entry.subsection ? { subsection: entry.subsection } : {}),
        tag,
        description: entry.body.toString(),
      })
    }
    entry = undefined
  }

  const open = (kind: EntryKind, tags: string[] = []) => {
    close()
    entry = { kind, section, subsection, tags, depth: rsDepth, body: new TextBuilder() }
    entry.body.setPreformatted(preformatted)
    pending = []
  }

  const text = (raw: string) => {
    const plain = ctx.unescape(raw)
    if (expectTag === 'entry' || expectTag === 'extra') {
      entry?.tags.push(plain)
      expectTag = undefined
      return
    }
    if (expectTag === 'body') {
      entry?.body.paragraph()
      entry?.body.add(plain)
      entry?.body.lineBreak()
      expectTag = undefined
      return
    }
    if (entry) entry.body.add(plain)
    else pending.push(plain)
  }

  const paragraphBreak = () => {
    if (entry) entry.body.paragraph()
    pending = []
  }

  /** True when an open tagged-paragraph entry ends at this point. */
  const endsTagged = () => entry !== undefined && entry.kind !== 'rs' && rsDepth <= entry.depth

  for (const line of lines) {
    if (line.kind === 'text') {
      text(line.text)
      continue
    }
    const { name, args } = line
    switch (name) {
      case 'TH':
        page.title = ctx.unescape(args[0] ?? '')
        page.section = args[1] ? ctx.unescape(args[1]) : undefined
        break
      case 'SH':
      case 'SS': {
        close()
        rsDepth = 0
        pending = []
        const heading = collapse(ctx.unescape(args.join(' ')))
        if (name === 'SH') {
          section = heading.toUpperCase()
          subsection = undefined
        } else {
          subsection = heading
        }
        break
      }
      case 'TP':
      case 'HP':
        if (entry && (endsTagged() || (entry.kind === 'rs' && rsDepth <= entry.depth))) close()
        if (entry) {
          expectTag = 'body'
        } else {
          open(name === 'TP' ? 'tp' : 'hp')
          expectTag = 'entry'
        }
        break
      case 'TQ':
        if (entry) expectTag = 'extra'
        break
      case 'IP': {
        const tag = args[0] ? ctx.unescape(args[0]) : ''
        if (!tag) {
          paragraphBreak()
          break
        }
        if (entry && endsTagged()) close()
        if (entry) {
          entry.body.paragraph()
          entry.body.add(tag)
          entry.body.lineBreak()
        } else {
          open('ip', [tag])
        }
        break
      }
      case 'PP':
      case 'LP':
      case 'P':
        if (endsTagged()) close()
        paragraphBreak()
        break
      case 'sp':
        paragraphBreak()
        break
      case 'br':
        entry?.body.lineBreak()
        break
      case 'RS':
        if (!entry && pending.length > 0 && collapse(pending.join(' ')).startsWith('-')) {
          const tags = [pending.join(' ')]
          open('rs', tags)
        }
        rsDepth++
        break
      case 'RE':
        rsDepth = Math.max(0, rsDepth - 1)
        if (entry?.kind === 'rs' && rsDepth <= entry.depth) close()
        break
      case 'nf':
      case 'EX':
        preformatted = true
        entry?.body.setPreformatted(true)
        break
      case 'fi':
      case 'EE':
        preformatted = false
        entry?.body.setPreformatted(false)
        break
      case 'UR':
      case 'MT':
        break
      case 'UE':
      case 'ME':
        if (args[0]) text(args[0])
        break
      default:
        if (ALTERNATING.has(name)) {
          text(args.join(''))
        } else if (FONT.has(name)) {
          text(args.join(' '))
        }
      // Other requests carry no text we need.
    }
  }
  close()
  return page
}

export type { RoffLine }
export type { RawEntry }
