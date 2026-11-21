import { z } from 'zod'
import type { Deck, Option } from './deck'

/**
 * Cards are never stored in deck files. They are derived from options at
 * runtime, one per applicable card type, so new card types can be added
 * without regenerating decks.
 */
export const CARD_TYPES = ['flag-to-meaning', 'meaning-to-flag', 'cloze'] as const
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

export type Card = FlagToMeaningCard | MeaningToFlagCard | ClozeCard

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

function optionCards(deck: Deck, option: Option): Card[] {
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
  return cards
}

/**
 * Derives every card for a parsed deck: each visible option × each card type
 * that applies to it. Hidden options produce no cards, and `cloze` needs an
 * example that contains one of the option's flags.
 */
export function deriveCards(deck: Deck): Card[] {
  return deck.options
    .filter((option) => !option.hidden)
    .flatMap((option) => optionCards(deck, option))
}
