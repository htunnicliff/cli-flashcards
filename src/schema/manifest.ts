import { z } from 'zod'
import { SourceSchema, TierSchema } from './deck'

/** Bump when the manifest format changes incompatibly. */
export const MANIFEST_VERSION = 1

/** One built deck, as listed in `public/decks/index.json`. */
export const DeckManifestEntrySchema = z.object({
  id: z.string().min(1),
  tool: z.string().min(1),
  variant: z.string().min(1),
  toolVersion: z.string().min(1),
  deckVersion: z.number().int().positive(),
  source: SourceSchema,
  license: z.string().min(1),
  /** Path of the deck file relative to the manifest, e.g. `rg-default.json`. */
  file: z.string().min(1),
  /** Size of the deck file in bytes. */
  bytes: z.number().int().nonnegative(),
  /** Options that produce cards (hidden ones are not counted). */
  optionCount: z.number().int().nonnegative(),
  tiers: z.record(TierSchema, z.number().int().nonnegative()),
})
export type DeckManifestEntry = z.infer<typeof DeckManifestEntrySchema>

export const DeckManifestSchema = z.object({
  manifestVersion: z.literal(MANIFEST_VERSION),
  decks: z.array(DeckManifestEntrySchema),
})
export type DeckManifest = z.infer<typeof DeckManifestSchema>
