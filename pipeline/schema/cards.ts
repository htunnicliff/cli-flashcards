import { z } from 'zod'
import type { Deck, Option } from './deck'
import { isLongFlag, isShortFlag } from './flags'

/**
 * Cards are never stored in deck files. They are derived from options at
 * runtime, one per applicable card type, so new card types can be added
 * without regenerating decks.
 */
export const CARD_TYPES = [
  'flag-to-meaning',
  'meaning-to-flag',
  'cloze',
  'short-to-long',
  'long-to-short',
] as const
export const CardTypeSchema = z.enum(CARD_TYPES)
export type CardType = z.infer<typeof CardTypeSchema>

/** Shown in place of the flag on cloze cards. */
export const CLOZE_BLANK = '____'

interface CardBase {
  /** `{tool}:{variant}:{optionId}:{cardType}`, stable across deck regenerations. */
  id: string
  type: CardType
  deckId: string
  optionId: string
  /** The option's primary flag; what the UI leads with. */
  flag: string
  /** Every accepted spelling, primary first. */
  answers: string[]
  summary: string
  /** Full description for the "more detail" section of the card back. */
  detail: string
}

/** Front: the flag. Back: what it means. */
export interface FlagToMeaningCard extends CardBase {
  type: 'flag-to-meaning'
}

/** Front: what it means. Back: the flag. */
export interface MeaningToFlagCard extends CardBase {
  type: 'meaning-to-flag'
}

/** Front: an example command with the flag blanked. Back: the flag. */
export interface ClozeCard extends CardBase {
  type: 'cloze'
  /** The example command with the flag replaced by `CLOZE_BLANK`. */
  cloze: string
  /** The example command as written. */
  command: string
  /** The flag spelling that was blanked. */
  blanked: string
  exampleDescription?: string
}

/**
 * Flag pair cards, for learning which short flag goes with which long one.
 * Front: one form alone. Back: every spelling. Only options with both a short
 * and a long form get them, and only while flag pair practice is on.
 */
export interface FlagPairCard extends CardBase {
  type: 'short-to-long' | 'long-to-short'
  /** The one spelling the front shows. */
  shown: string
  /** The spellings of the other form that count as right, the expected one first. */
  targets: string[]
}

export type Card = FlagToMeaningCard | MeaningToFlagCard | ClozeCard | FlagPairCard

/** Card types that pair a short flag with its long form. */
export const FLAG_PAIR_TYPES = ['short-to-long', 'long-to-short'] as const

export function isFlagPairCard(card: Card): card is FlagPairCard {
  return card.type === 'short-to-long' || card.type === 'long-to-short'
}

export interface DeriveOptions {
  /** Adds short ↔ long flag pair cards. Off unless the caller passes the setting. */
  flagPairs?: boolean
}

export function cardId(
  deck: Pick<Deck, 'tool' | 'variant'>,
  optionId: string,
  type: CardType,
): string {
  return `${deck.tool}:${deck.variant}:${optionId}:${type}`
}

/**
 * The flag cards, examples and expected answers lead with: `primary` when set,
 * otherwise the first flag. Because `flags` is stored short first, that is the
 * first short flag, or the first long flag when there is none (`git log --oneline`).
 */
export function primaryFlag(option: Pick<Option, 'flags' | 'primary'>): string {
  const flag = option.primary ?? option.flags[0]
  if (flag === undefined) throw new Error('primaryFlag: an option needs at least one flag')
  return flag
}

/** All spellings with the primary flag first. */
export function answerFlags(option: Pick<Option, 'flags' | 'primary'>): string[] {
  const primary = primaryFlag(option)
  return [primary, ...option.flags.filter((flag) => flag !== primary)]
}

interface ClozeMatch {
  command: string
  cloze: string
  blanked: string
  description?: string
}

/**
 * Finds the first example that spells one of the option's flags as its own
 * token (`-i`, or `--color=always` with the value kept), preferring the primary
 * flag. Combined short flags such as `-rn` are not matched.
 */
export function findCloze(option: Option): ClozeMatch | undefined {
  for (const flag of answerFlags(option)) {
    for (const example of option.examples) {
      const tokens = example.command.split(/(\s+)/)
      const index = tokens.findIndex((token) => token === flag || token.startsWith(`${flag}=`))
      if (index === -1) continue
      const token = tokens[index]!
      tokens[index] = CLOZE_BLANK + token.slice(flag.length)
      return {
        command: example.command,
        cloze: tokens.join(''),
        blanked: flag,
        description: example.description,
      }
    }
  }
  return undefined
}

/**
 * The option's short and long spellings, each led by the primary flag when it
 * is of that form, or `undefined` when the option lacks one of the two forms.
 */
export function flagPair(
  option: Pick<Option, 'flags' | 'primary'>,
): { short: string[]; long: string[] } | undefined {
  const flags = answerFlags(option)
  const short = flags.filter(isShortFlag)
  const long = flags.filter(isLongFlag)
  return short.length && long.length ? { short, long } : undefined
}

function optionCards(deck: Deck, option: Option, derive: DeriveOptions): Card[] {
  const base = {
    deckId: deck.id,
    optionId: option.id,
    flag: primaryFlag(option),
    answers: answerFlags(option),
    summary: option.summary,
    detail: option.description,
  }
  const cards: Card[] = [
    { ...base, id: cardId(deck, option.id, 'flag-to-meaning'), type: 'flag-to-meaning' },
    { ...base, id: cardId(deck, option.id, 'meaning-to-flag'), type: 'meaning-to-flag' },
  ]
  const cloze = findCloze(option)
  if (cloze) {
    cards.push({
      ...base,
      id: cardId(deck, option.id, 'cloze'),
      type: 'cloze',
      cloze: cloze.cloze,
      command: cloze.command,
      blanked: cloze.blanked,
      ...(cloze.description === undefined ? {} : { exampleDescription: cloze.description }),
    })
  }
  const pair = derive.flagPairs ? flagPair(option) : undefined
  if (pair) {
    cards.push(
      {
        ...base,
        id: cardId(deck, option.id, 'short-to-long'),
        type: 'short-to-long',
        shown: pair.short[0]!,
        targets: pair.long,
      },
      {
        ...base,
        id: cardId(deck, option.id, 'long-to-short'),
        type: 'long-to-short',
        shown: pair.long[0]!,
        targets: pair.short,
      },
    )
  }
  return cards
}

/**
 * Derives every card for a parsed deck: each visible option × each card type
 * that applies to it. Hidden options produce no cards, `cloze` needs an
 * example that contains one of the option's flags, and the flag pair types
 * need `flagPairs` plus both a short and a long form.
 */
export function deriveCards(deck: Deck, derive: DeriveOptions = {}): Card[] {
  return deck.options
    .filter((option) => !option.hidden)
    .flatMap((option) => optionCards(deck, option, derive))
}
