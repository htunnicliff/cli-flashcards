import { z } from 'zod'
import {
  ArgumentSchema,
  ExampleSchema,
  FlagSchema,
  OptionIdSchema,
  OptionBaseSchema,
  TierSchema,
} from './deck'

/**
 * Hand-written curation applied on top of a generated deck. Lives next to it
 * as `decks/<tool>/<variant>.overrides.yaml`, so regenerating the deck never
 * erases a curator's work.
 */

/** Changes to one generated option, keyed by option ID. */
export const OptionPatchSchema = z
  .object({
    summary: z.string().min(1).optional(),
    description: z.string().optional(),
    tier: TierSchema.optional(),
    /** Which spelling leads on cards and in examples. */
    primary: FlagSchema.optional(),
    argument: ArgumentSchema.nullable().optional(),
    /** Appended to the generated examples. */
    examples: z.array(ExampleSchema).optional(),
    /** Added to the generated tags. */
    tags: z.array(z.string().min(1)).optional(),
    hidden: z.boolean().optional(),
  })
  .strict()
export type OptionPatch = z.infer<typeof OptionPatchSchema>

/** Folds `from` options into `into`: their flags, examples and tags move over. */
export const MergeSchema = z
  .object({
    into: OptionIdSchema,
    from: z.array(OptionIdSchema).min(1),
  })
  .strict()
export type Merge = z.infer<typeof MergeSchema>

/** An option the parser missed. `id` defaults to the derived ID, `tier` to `common`. */
export const AddedOptionSchema = OptionBaseSchema.extend({
  id: OptionIdSchema.optional(),
  tier: TierSchema.default('common'),
}).strict()
export type AddedOption = z.input<typeof AddedOptionSchema>

export const DeckPatchSchema = z
  .object({
    license: z.string().min(1).optional(),
    attribution: z.string().min(1).optional(),
    toolVersion: z.string().min(1).optional(),
  })
  .strict()

export const OverridesSchema = z
  .object({
    $schema: z.string().optional(),
    deck: DeckPatchSchema.optional(),
    /** Applied after merges, so a patch can refer to the merged option. */
    options: z.record(OptionIdSchema, OptionPatchSchema).default({}),
    merge: z.array(MergeSchema).default([]),
    add: z.array(AddedOptionSchema).default([]),
  })
  .strict()
export type Overrides = z.infer<typeof OverridesSchema>
export type OverridesInput = z.input<typeof OverridesSchema>
