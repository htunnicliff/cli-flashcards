/**
 * Parses an option tag as manpages and `--help` output spell it:
 *
 *   -i, --ignore-case
 *   -e PATTERN, --regexp=PATTERN
 *   --color[=WHEN]          -i[SUFFIX]          -C[<n>]
 *   --colour=[when]         -n <number>         --[no-]verify
 */
import { FLAG_PATTERN, isShortFlag, normalizeFlags } from '../../src/schema/flags'
import type { Argument } from '../../src/schema/deck'

export interface ParsedTag {
  /** Short first, de-duplicated. */
  flags: string[]
  argument?: Argument
}

/** Splits on `, ` (or `,` before a dash) outside brackets. */
export function splitTag(tag: string): string[] {
  const parts: string[] = []
  let depth = 0
  let current = ''
  for (let i = 0; i < tag.length; i++) {
    const ch = tag[i]!
    if (ch === '[' || ch === '<' || ch === '{' || ch === '(') depth++
    if (ch === ']' || ch === '>' || ch === '}' || ch === ')') depth = Math.max(0, depth - 1)
    if (ch === ',' && depth === 0 && /^\s|^-/.test(tag.slice(i + 1))) {
      parts.push(current.trim())
      current = ''
      continue
    }
    current += ch
  }
  if (current.trim()) parts.push(current.trim())
  return parts
}

const FLAG_START = /^(--?)(\[no-?\])?([A-Za-z0-9?@#][\w.?#@+-]*)/

interface Part {
  flags: string[]
  argument?: Argument
}

function cleanArgName(raw: string): string {
  return raw
    .trim()
    .replace(/^=/, '')
    .replace(/^<([^<>]*)>$/, '$1')
    .trim()
}

/** Parses the text after a flag name into an argument, or `null` if it is not one. */
function parseArgument(rest: string): Argument | undefined | null {
  if (rest === '') return undefined
  let match: RegExpExecArray | null
  // [=X], =[X], [X]: optional value (`--color[=WHEN]`, `-i[SUFFIX]`, `--stat[=<w>[,<n>]]`).
  if (/^=?\[/.test(rest) && rest.endsWith(']')) {
    return { name: cleanArgName(rest.replace(/[[\]]/g, '')), optional: true }
  }
  // =X or <X> attached.
  if ((match = /^=(\S.*)$/.exec(rest)) || (match = /^(<.+)$/.exec(rest))) {
    return { name: cleanArgName(match[1]!), optional: false }
  }
  // Space-separated: `-e PATTERN`, `-n <number>`, `-amin [-|+]n`, `-exec utility [argument ...] ;`
  if ((match = /^\s+(\S.*)$/.exec(rest))) {
    const value = match[1]!.trim()
    if (value.startsWith('-')) return null
    const words = value.split(/\s+/)
    // Prose after a flag ("--full-history without parent rewriting") is not an argument.
    const looksLikeProse = words.length > 2 && words.every((word) => /^[a-z]+$/.test(word))
    if (looksLikeProse || value.length > 40) return null
    const optional = /^\[[^\]]*\]$/.test(value)
    return { name: cleanArgName(optional ? value.slice(1, -1) : value), optional }
  }
  return null
}

function parsePart(part: string): Part | null {
  const match = FLAG_START.exec(part)
  if (!match) return null
  const [whole, dashes, negation, name] = match
  // `-NUM`, `-WIDTH`: placeholders for numeric options, not real flags.
  if (dashes === '-' && name!.length > 1 && /^[A-Z_]+$/.test(name!)) return null
  const argument = parseArgument(part.slice(whole!.length))
  if (argument === null) return null
  const base = `${dashes}${name}`
  const flags = negation
    ? [base, `${dashes}${negation.slice(1, -1).replace(/-?$/, '-')}${name}`]
    : [base]
  if (!flags.every((flag) => FLAG_PATTERN.test(flag))) return null
  return { flags, ...(argument ? { argument } : {}) }
}

/**
 * Returns the flags and argument a tag describes, or `null` when the tag does
 * not name any flag (prose that happens to start with a dash, `-<number>`).
 */
export function parseTag(tag: string): ParsedTag | null {
  const parts = splitTag(tag.replace(/\s+/g, ' ').trim())
  const flags: string[] = []
  let shortArgument: Argument | undefined
  let longArgument: Argument | undefined
  for (const text of parts) {
    const part = parsePart(text)
    if (!part) continue
    for (const flag of part.flags) if (!flags.includes(flag)) flags.push(flag)
    if (!part.argument) continue
    if (isShortFlag(part.flags[0]!)) shortArgument ??= part.argument
    else longArgument ??= part.argument
  }
  // Prefer the argument as the long form spells it; it is usually the clearer name.
  const argument = longArgument ?? shortArgument
  if (flags.length === 0) return null
  return { flags: positiveFirst(normalizeFlags(flags)), ...(argument ? { argument } : {}) }
}

/**
 * Moves `--no-x` after `--x` when a tag lists both, so the positive form
 * leads (`--no-decorate, --decorate` → `--decorate, --no-decorate`).
 */
function positiveFirst(flags: string[]): string[] {
  const negated = (flag: string) => {
    const match = /^(--?)no-(.+)$/.exec(flag)
    return match !== null && flags.includes(`${match[1]}${match[2]}`)
  }
  return [...flags.filter((flag) => !negated(flag)), ...flags.filter(negated)]
}
