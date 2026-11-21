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

export const TIERS = ['core', 'common', 'obscure'] as const
export const TierSchema = z.enum(TIERS)
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

/** Option fields without the cross-field checks, for schemas that extend it. */
export const OptionBaseSchema = z.object({
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
  /**
   * For tools with subcommands (`git log`, `git commit`), the subcommand the
   * option belongs to. Flags only need to be unique within a subcommand.
   */
  subcommand: Slug.optional(),
})

export const OptionSchema = OptionBaseSchema.superRefine((option, ctx) => {
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

export const SourcePageSchema = z.object({
  /** Manpage name, e.g. `rg` or `git-log`. */
  name: z.string().min(1),
  /** Manual section, e.g. `1`. */
  section: z.string().min(1).optional(),
  /** File the page was read from, as given to the generator. */
  path: z.string().min(1).optional(),
})
export type SourcePage = z.infer<typeof SourcePageSchema>

/**
 * How the tool reads its command line, which decides what typed answers count as
 * the same flag.
 * - `gnu` (getopt_long, the default): short flags combine (`-iw`), and a long
 *   option may be shortened to any unambiguous prefix (`--ignore` for `--ignore-case`).
 * - `posix` (getopt): short flags combine; long options must be spelled in full.
 * - `strict`: every flag is its own word, spelled in full (Go's flag package, `find`).
 */
export const PARSING_STYLES = ['gnu', 'posix', 'strict'] as const
export const ParsingStyleSchema = z.enum(PARSING_STYLES)
export type ParsingStyle = z.infer<typeof ParsingStyleSchema>

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
    /** The manpages (or `--help` output) the deck was generated from. */
    sourcePages: z.array(SourcePageSchema).optional(),
    /** Absent means `gnu`. */
    parsingStyle: ParsingStyleSchema.optional(),
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
        const key = `${option.subcommand ?? ''} ${flag}`
        const sameFlag = flags.get(key)
        if (sameFlag !== undefined && sameFlag !== index) {
          ctx.addIssue({
            code: 'custom',
            path: ['options', index, 'flags'],
            message: `Flag "${flag}" also belongs to options[${sameFlag}]`,
          })
        } else {
          flags.set(key, index)
        }
      }
    })
  })
export type Deck = z.infer<typeof DeckSchema>
export type DeckInput = z.input<typeof DeckSchema>
