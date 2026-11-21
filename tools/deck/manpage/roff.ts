/**
 * A small roff reader shared by the man(7) and mdoc(7) front ends.
 *
 * It does not try to typeset anything. It splits a page into requests
 * (`.TP`, `.It Fl i`) and text lines, joins continuation lines, drops comments
 * and conditionals, and turns inline escapes into plain text. That is enough
 * to pull options and their descriptions out of real-world manpages.
 */

export interface RequestLine {
  kind: 'request'
  name: string
  args: string[]
  /** Everything after the request name, unsplit (escapes still in place). */
  rest: string
}

export interface TextLine {
  kind: 'text'
  /** Raw text; run it through `unescape` to get plain text. */
  text: string
}

export type RoffLine = RequestLine | TextLine

/** Named glyphs (`\(xx`, `\[xx]`) that show up in manpages. */
const GLYPHS: Record<string, string> = {
  aq: "'",
  cq: "'",
  oq: "'",
  dq: '"',
  lq: '"',
  rq: '"',
  Lq: '"',
  Rq: '"',
  em: '—',
  en: '–',
  hy: '-',
  mi: '-',
  bu: '•',
  ba: '|',
  bv: '|',
  co: '©',
  rg: '®',
  tm: '™',
  de: '°',
  ga: '`',
  ha: '^',
  ti: '~',
  ti_: '~',
  tf: '∴',
  rs: '\\',
  sl: '/',
  lh: '☜',
  rh: '☞',
  '<=': '≤',
  '>=': '≥',
  '!=': '≠',
  '->': '→',
  '<-': '←',
  pl: '+',
  eq: '=',
  mu: '×',
  di: '÷',
  '+-': '±',
  sq: '□',
  ul: '_',
  ru: '_',
  at: '@',
  sh: '#',
  Do: '$',
  fm: "'",
  sd: '"',
  '12': '½',
  '14': '¼',
  '34': '¾',
}

/** Predefined strings (`\*(xx`) used by man and mdoc pages. */
const DEFAULT_STRINGS: Record<string, string> = {
  lq: '"',
  rq: '"',
  Aq: "'",
  R: '®',
  Tm: '™',
  q: '"',
}

export class RoffContext {
  readonly strings = new Map<string, string>(Object.entries(DEFAULT_STRINGS))

  /**
   * Turns roff escapes into plain text. Font changes, motions and size changes
   * are dropped; glyphs and strings are expanded.
   */
  unescape(input: string): string {
    let out = ''
    let i = 0
    while (i < input.length) {
      const ch = input[i]!
      if (ch !== '\\') {
        out += ch
        i++
        continue
      }
      const next = input[i + 1]
      i += 2
      switch (next) {
        case undefined:
          break
        case '"':
          // Comment to end of line.
          return out.replace(/\s+$/, '')
        case '-':
        case '.':
        case "'":
        case '`':
          out += next === '-' ? '-' : next
          break
        case '\\':
        case 'e':
        case 'E':
          out += '\\'
          break
        case ' ':
        case '~':
        case '0':
        case '_':
          out += ' '
          break
        case 't':
          out += '\t'
          break
        case '&':
        case '|':
        case '^':
        case ',':
        case '/':
        case '%':
        case 'c':
        case ':':
        case '{':
        case '}':
        case 'a':
        case 'd':
        case 'u':
        case 'r':
        case 'p':
          break
        case 'f':
        case 'F': {
          // \fB, \f(CW, \f[CB]
          i = skipName(input, i)
          break
        }
        case '(': {
          const name = input.slice(i, i + 2)
          i += 2
          out += GLYPHS[name] ?? ''
          break
        }
        case '[': {
          const end = input.indexOf(']', i)
          const name = end === -1 ? input.slice(i) : input.slice(i, end)
          i = end === -1 ? input.length : end + 1
          out += glyphByLongName(name)
          break
        }
        case '*': {
          const start = i
          i = skipName(input, i)
          out += this.strings.get(nameFrom(input.slice(start, i))) ?? ''
          break
        }
        case 'n':
        case 'g':
        case 'k':
        case 'm':
        case 'M':
        case 'V':
        case 'Y':
          // Registers, colours, marks: take a name, print nothing.
          if (input[i] === '+' || input[i] === '-') i++
          i = skipName(input, i)
          break
        case 'h':
        case 'v':
        case 'w':
        case 'l':
        case 'L':
        case 'o':
        case 'b':
        case 'x':
        case 'D':
        case 'X':
        case 'Z':
        case 'S':
        case 'H':
        case 'R':
        case 'A':
        case 'B':
        case 'C':
        case 'N':
        case 'O': {
          // Escapes with a delimited argument: \h'-0.04i', \w'text'.
          const delimiter = input[i]
          if (delimiter === undefined) break
          if (delimiter === '[' || delimiter === '(') {
            i = skipName(input, i)
            break
          }
          const end = input.indexOf(delimiter, i + 1)
          if (next === 'C' && end !== -1) out += glyphByLongName(input.slice(i + 1, end))
          if (next === 'N' && end !== -1) {
            const code = Number(input.slice(i + 1, end))
            if (Number.isFinite(code)) out += String.fromCodePoint(code)
          }
          i = end === -1 ? input.length : end + 1
          break
        }
        case 's': {
          // \s+2, \s-1, \s0, \s'+2', \s(12, \s[12]
          if (input[i] === '+' || input[i] === '-') i++
          const c = input[i]
          if (c === "'" || c === '[' || c === '(') {
            i = c === "'" ? input.indexOf("'", i + 1) + 1 || input.length : skipName(input, i)
          } else {
            while (i < input.length && /\d/.test(input[i]!)) i++
          }
          break
        }
        default:
          // Unknown escapes print the character itself (`\x` -> `x`).
          out += next
      }
    }
    return out
  }
}

/** Skips a one-character, `(xx` or `[name]` escape name starting at `i`. */
function skipName(input: string, i: number): number {
  const c = input[i]
  if (c === '(') return i + 3
  if (c === '[') {
    const end = input.indexOf(']', i)
    return end === -1 ? input.length : end + 1
  }
  return i + 1
}

function nameFrom(token: string): string {
  if (token.startsWith('(')) return token.slice(1, 3)
  if (token.startsWith('[')) return token.slice(1, -1)
  return token
}

function glyphByLongName(name: string): string {
  if (name in GLYPHS) return GLYPHS[name]!
  const unicode = /^u([0-9A-Fa-f]{4,6})$/.exec(name)
  if (unicode) return String.fromCodePoint(parseInt(unicode[1]!, 16))
  return ''
}

/**
 * Splits request arguments the way roff does: on spaces, with double quotes
 * grouping words (`""` inside quotes is a literal quote).
 */
export function splitArgs(rest: string): string[] {
  const args: string[] = []
  let i = 0
  while (i < rest.length) {
    while (rest[i] === ' ' || rest[i] === '\t') i++
    if (i >= rest.length) break
    let arg = ''
    if (rest[i] === '"') {
      i++
      while (i < rest.length) {
        if (rest[i] === '"') {
          if (rest[i + 1] === '"') {
            arg += '"'
            i += 2
            continue
          }
          i++
          break
        }
        if (rest[i] === '\\' && i + 1 < rest.length) {
          arg += rest.slice(i, i + 2)
          i += 2
          continue
        }
        arg += rest[i]
        i++
      }
    } else {
      while (i < rest.length && rest[i] !== ' ' && rest[i] !== '\t') {
        if (rest[i] === '\\' && i + 1 < rest.length) {
          arg += rest.slice(i, i + 2)
          i += 2
          continue
        }
        arg += rest[i]
        i++
      }
    }
    args.push(arg)
  }
  return args
}

/** Removes a trailing `\"` comment that is not itself escaped. */
function stripComment(line: string): string {
  for (let i = 0; i < line.length; i++) {
    if (line[i] === '\\') {
      if (line[i + 1] === '"') return line.slice(0, i).replace(/\s+$/, '')
      i++
    }
  }
  return line
}

/** Requests that only affect layout and never carry text worth keeping. */
const IGNORED_REQUESTS = new Set([
  'ad',
  'na',
  'nh',
  'hy',
  'ft',
  'ps',
  'vs',
  'in',
  'ti',
  'ta',
  'll',
  'ne',
  'nr',
  'rr',
  'it',
  'so',
  'mso',
  'pc',
  'lf',
  'cp',
  'ss',
  'cs',
  'ev',
  'tr',
  'hw',
  'ns',
  'rs',
  'bp',
  'pl',
  'po',
  'ch',
  'wh',
  'ig',
  'em',
  'tm',
  'warn',
  'do',
  'als',
  'rm',
  'rn',
  'am',
  'char',
  'fchar',
  'ec',
  'eo',
  'cc',
  'c2',
  'lg',
  'kern',
  'fam',
  'fp',
  'ul',
  'cu',
  'uf',
  'mk',
  'rt',
  'sv',
  'os',
  'nm',
  'nn',
  'mc',
  'tl',
  'lt',
  'ab',
  'ex',
  'pm',
  'fl',
  'hc',
  'hla',
  'hlm',
  'hpf',
  'hym',
  'hys',
  'pso',
  'sy',
  'UC',
  'PD',
  'DT',
  'AT',
])

/**
 * Reads a roff source into lines. Comments, macro definitions and
 * conditionals are removed. For `.if`/`.ie`/`.el`, the nroff (terminal) branch
 * is kept: `.if n` and `.ie n` bodies are read, `.if t` bodies and the `.el`
 * that follows `.ie n` are skipped. Other conditions are kept, which is the
 * right call for the `\n(.g` (groff) checks that pages make most often.
 */
export function readRoff(source: string, ctx: RoffContext): RoffLine[] {
  const physical = source.replace(/\r\n?/g, '\n').replace(/\n$/, '').split('\n')
  // Join lines ending in an unescaped backslash.
  const lines: string[] = []
  let pending = ''
  for (const line of physical) {
    if (/(^|[^\\])(\\\\)*\\$/.test(line)) {
      pending += line.slice(0, -1)
      continue
    }
    lines.push(pending + line)
    pending = ''
  }
  if (pending) lines.push(pending)

  const out: RoffLine[] = []
  /** Brace depth of a conditional block being skipped (0 = not skipping). */
  let skipDepth = 0
  let lastIeTaken = true
  let inMacroDefinition = false

  const handle = (raw: string): void => {
    if (inMacroDefinition) {
      if (/^\.\.\s*$/.test(raw)) inMacroDefinition = false
      return
    }
    if (skipDepth > 0) {
      skipDepth += countBraces(raw)
      if (skipDepth < 0) skipDepth = 0
      return
    }
    let line = raw
    // `.\}` closes a block we are inside; drop the brace and keep the rest.
    line = line.replace(/\\\}/g, '')
    if (/^[.'][ \t]*$/.test(line)) return
    // A blank line is a paragraph break, like `.sp`.
    if (/^\s*$/.test(line)) {
      out.push({ kind: 'request', name: 'sp', args: [], rest: '' })
      return
    }
    if (/^[.']\s*\\"/.test(line) || /^\\"/.test(line)) return
    const request = /^[.']\s*(\S+)\s*(.*)$/.exec(line)
    if (!request) {
      const text = stripComment(line)
      out.push({ kind: 'text', text })
      return
    }
    const name = request[1]!
    let rest = stripComment(request[2] ?? '')

    if (name === 'de' || name === 'de1' || name === 'am' || name === 'ig') {
      inMacroDefinition = true
      return
    }
    if (name === 'if' || name === 'ie' || name === 'el') {
      let taken = true
      if (name === 'el') {
        taken = !lastIeTaken
      } else {
        const cond = /^(!?)(\S+)\s*(.*)$/.exec(rest)
        if (!cond) return
        const [, not, test, body] = cond
        taken = evaluateCondition(test!)
        if (not) taken = !taken
        rest = body ?? ''
        if (name === 'ie') lastIeTaken = taken
      }
      if (name === 'el') rest = rest.trim()
      const opensBlock = rest.startsWith('\\{')
      if (!taken) {
        if (opensBlock) skipDepth = Math.max(1, countBraces(rest))
        return
      }
      rest = rest.replace(/^\\\{\\?/, '').trim()
      if (rest) handle(rest)
      return
    }
    if (name === 'ds' || name === 'ds1') {
      const ds = /^(\S+)\s?"?(.*)$/.exec(rest)
      if (ds) ctx.strings.set(ds[1]!, ctx.unescape(ds[2]!))
      return
    }
    if (IGNORED_REQUESTS.has(name)) return
    out.push({ kind: 'request', name, args: splitArgs(rest), rest })
  }

  for (const line of lines) handle(line)
  return out
}

function countBraces(line: string): number {
  return (line.match(/\\\{/g)?.length ?? 0) - (line.match(/\\\}/g)?.length ?? 0)
}

function evaluateCondition(test: string): boolean {
  if (test === 'n') return true
  if (test === 't') return false
  if (test === 'v' || test === 'o' || test === 'e') return test === 'o'
  // Register comparisons and string tests: assume groff-ish defaults.
  if (/^\\n\(\.g$/.test(test) || /^\\n\[\.g\]$/.test(test)) return true
  if (/^\\n\(\.H/.test(test)) return true
  return true
}

/** Collapses runs of whitespace and trims. */
export function collapse(text: string): string {
  return text.replace(/\s+/g, ' ').trim()
}
