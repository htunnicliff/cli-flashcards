/**
 * Checks a typed flag against the option a card asks for. It accepts every way the
 * tool itself would read the same option, so a correct answer is never marked wrong:
 * short or long form, `--opt=value` or `--opt value`, short flags combined (`-iw`
 * contains `-i`), and unambiguous long-option prefixes for getopt_long tools.
 */
import { isShortFlag, primaryFlag, type Option, type ParsingStyle } from '../../schema'

export interface AnswerContext {
  /** The option the card asks for. */
  option: Option
  /** Every option in the deck, so prefixes and combined flags resolve as the tool would. */
  options: readonly Option[]
  /** How the tool reads its command line. Defaults to `gnu`. */
  style?: ParsingStyle
  /**
   * Accept only these exact spellings, the expected one first, with no prefixes
   * or combined short flags. Flag pair cards use it: the point is to recall the
   * other form, so typing the flag the card shows, or `--rec`, is not enough.
   */
  only?: readonly string[]
}

export interface AnswerResult {
  correct: boolean
  /** The flag the card expects: the option's primary (normally short) flag. */
  expected: string
  /** The target's full spelling the answer was read as, e.g. `--ignore-case` for `--ign`. */
  matched?: string
  /**
   * Set when the answer was right but not spelled as the primary flag, so the
   * result can say "Correct · short form: `-l`".
   */
  preferred?: string
}

/**
 * The options a single command-line word names, in the order the tool reads them.
 * Empty when the word is not a flag or names nothing in the deck.
 */
export function optionsNamedBy(
  word: string,
  options: readonly Option[],
  style: ParsingStyle = 'gnu',
): { option: Option; flag: string }[] {
  if (!word.startsWith('-') || word === '-' || word === '--') return []
  const name = word.split('=')[0]!
  const exact = options.find((option) => option.flags.includes(name))
  if (exact) return [{ option: exact, flag: name }]

  if (word.startsWith('--')) {
    if (style !== 'gnu' || name.length < 3) return []
    const matches = new Map<Option, string>()
    for (const option of options) {
      const flag = option.flags.find((f) => f.startsWith('--') && f.startsWith(name))
      if (flag) matches.set(option, flag)
    }
    if (matches.size !== 1) return []
    const [option, flag] = [...matches][0]!
    return [{ option, flag }]
  }

  // `-iw`: each letter a short flag, until one that takes an argument swallows the rest.
  if (style === 'strict') return []
  const named: { option: Option; flag: string }[] = []
  for (const char of word.slice(1)) {
    const flag = `-${char}`
    const option = options.find((o) => o.flags.includes(flag))
    if (!option) return []
    named.push({ option, flag })
    if (option.argument) break
  }
  return named
}

/**
 * Whether `input` names `context.option`. The answer must hold exactly one flag
 * word (combined short flags count as one); other words are taken as values or
 * the tool's name, so `rg -i`, `--max-count 5` and `--color=always` are all fine.
 */
export function checkAnswer(input: string, context: AnswerContext): AnswerResult {
  const { option, only } = context
  const expected = only?.[0] ?? primaryFlag(option)
  const scope = context.options.filter((o) => o.subcommand === option.subcommand)
  const flagWords = input
    .trim()
    .split(/\s+/)
    .filter((word) => word.startsWith('-'))
  if (flagWords.length !== 1) return { correct: false, expected }

  if (only) {
    const name = flagWords[0]!.split('=')[0]!
    if (!only.includes(name)) return { correct: false, expected }
    return { correct: true, expected, matched: name }
  }

  const named = optionsNamedBy(flagWords[0]!, scope, context.style)
  const hit = named.find((n) => n.option.id === option.id)
  if (!hit) return { correct: false, expected }
  const typedAsPrimary = named.length === 1 && flagWords[0]!.split('=')[0] === expected
  return {
    correct: true,
    expected,
    matched: hit.flag,
    ...(typedAsPrimary ? {} : { preferred: expected }),
  }
}

/** Whether a short form exists, so the result line can call the primary "short form". */
export function hasShortForm(option: Option): boolean {
  return option.flags.some(isShortFlag)
}

export type DiffPart = { kind: 'same' | 'added' | 'removed'; text: string }

/**
 * A character diff from `from` to `to` (longest common subsequence), with runs of
 * the same kind merged: what was typed against what was expected.
 */
export function diffChars(from: string, to: string): DiffPart[] {
  const a = [...from]
  const b = [...to]
  // lengths[i][j]: LCS length of a[i..] and b[j..]
  const lengths = Array.from({ length: a.length + 1 }, () =>
    new Array<number>(b.length + 1).fill(0),
  )
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      lengths[i]![j] =
        a[i] === b[j]
          ? lengths[i + 1]![j + 1]! + 1
          : Math.max(lengths[i + 1]![j]!, lengths[i]![j + 1]!)
    }
  }
  const parts: DiffPart[] = []
  const push = (kind: DiffPart['kind'], text: string) => {
    const last = parts.at(-1)
    if (last?.kind === kind) last.text += text
    else parts.push({ kind, text })
  }
  let i = 0
  let j = 0
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] === b[j]) {
      push('same', a[i]!)
      i++
      j++
    } else if (j < b.length && (i === a.length || lengths[i]![j + 1]! >= lengths[i + 1]![j]!)) {
      push('added', b[j]!)
      j++
    } else {
      push('removed', a[i]!)
      i++
    }
  }
  return parts
}
