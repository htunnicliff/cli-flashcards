import { z } from 'zod'
import { FLAG_PATTERN, isShortFirst } from './flags'

/** Bump when the deck file format changes in a way that needs a migration. */
export const SCHEMA_VERSION = 1

/** Lowercase slug, used for `tool`, `variant` and deck `id`. */
const Slug = z
  .string()
  .regex(/^[a-z0-9][a-z0-9._-]*$/, 'Use lowercase letters, digits, ".", "_" or "-"')

/**
 * Option IDs are part of card IDs (`tool:variant:optionId:cardType`), so they
 * may not contain `:` or whitespace. Case is significant (`short-c` ≠ `short-C`).
 */
export const OptionIdSchema = z
  .string()
  .regex(/^[^\s:]+$/, 'Option IDs may not contain whitespace or ":"')

export const FlagSchema = z
  .string()
  .regex(FLAG_PATTERN, 'A flag looks like "-x", "--long-name" or "-name"')

export const TierSchema = z.enum(['core', 'common', 'obscure'])
export type Tier = z.infer<typeof TierSchema>

export const SourceSchema = z.enum(['manpage', 'help', 'manual'])
export type Source = z.infer<typeof SourceSchema>

export const ArgumentSchema = z.object({
  /** Placeholder name as the docs spell it, e.g. `WHEN` or `PATTERN`. */
  name: z.string().min(1),
  /** `--color[=WHEN]` takes an optional argument; `-e PATTERN` a required one. */
  optional: z.boolean().default(false),
})
export type Argument = z.infer<typeof ArgumentSchema>

export const ExampleSchema = z.object({
  /** A full command line. It should spell the option with its primary flag. */
  command: z.string().min(1),
  /** What the command does; shown as context on cloze cards. */
  description: z.string().optional(),
})
export type Example = z.infer<typeof ExampleSchema>

export const OptionSchema = z
  .object({
    /** Stable identity, normally `deriveOptionId(flags)`. */
    id: OptionIdSchema,
    /** Every spelling of the option, short forms first. */
    flags: z.array(FlagSchema).min(1),
    /** Overrides the default primary flag; must be one of `flags`. */
    primary: FlagSchema.optional(),
    argument: ArgumentSchema.optional(),
    /** One line; the front or back of a card. */
    summary: z.string().min(1),
    /** Full text; shown on the card back as "more detail". */
    description: z.string().default(''),
    tier: TierSchema,
    examples: z.array(ExampleSchema).default([]),
    tags: z.array(z.string().min(1)).default([]),
    /** Hidden options stay in the deck but produce no cards. */
    hidden: z.boolean().default(false),
  })
  .superRefine((option, ctx) => {
    if (!isShortFirst(option.flags)) {
      ctx.addIssue({
        code: 'custom',
        path: ['flags'],
        message: 'List short flags before long flags',
      })
    }
    if (new Set(option.flags).size !== option.flags.length) {
      ctx.addIssue({ code: 'custom', path: ['flags'], message: 'Flags must be unique' })
    }
    if (option.primary !== undefined && !option.flags.includes(option.primary)) {
      ctx.addIssue({
        code: 'custom',
        path: ['primary'],
        message: '`primary` must be one of `flags`',
      })
    }
  })
export type Option = z.infer<typeof OptionSchema>
export type OptionInput = z.input<typeof OptionSchema>

export const DeckSchema = z
  .object({
    /** Lets deck files point at `schemas/deck.schema.json` for editor support. */
    $schema: z.string().optional(),
    schemaVersion: z.literal(SCHEMA_VERSION),
    id: Slug,
    tool: Slug,
    /** e.g. `gnu`, `bsd`. */
    variant: Slug,
    /** Version of the tool the deck was generated from, as the tool reports it. */
    toolVersion: z.string().min(1),
    /** Increments whenever the deck's content changes. */
    deckVersion: z.number().int().positive(),
    source: SourceSchema,
    /** License of the source text, ideally an SPDX identifier. */
    license: z.string().min(1),
    attribution: z.string().min(1),
    options: z.array(OptionSchema),
  })
  .superRefine((deck, ctx) => {
    const ids = new Map<string, number>()
    const flags = new Map<string, number>()
    deck.options.forEach((option, index) => {
      const sameId = ids.get(option.id)
      if (sameId !== undefined) {
        ctx.addIssue({
          code: 'custom',
          path: ['options', index, 'id'],
          message: `Duplicate option ID "${option.id}" (also options[${sameId}])`,
        })
      } else {
        ids.set(option.id, index)
      }
      for (const flag of option.flags) {
        const sameFlag = flags.get(flag)
        if (sameFlag !== undefined && sameFlag !== index) {
          ctx.addIssue({
            code: 'custom',
            path: ['options', index, 'flags'],
            message: `Flag "${flag}" also belongs to options[${sameFlag}]`,
          })
        } else {
          flags.set(flag, index)
        }
      }
    })
  })
export type Deck = z.infer<typeof DeckSchema>
export type DeckInput = z.input<typeof DeckSchema>
