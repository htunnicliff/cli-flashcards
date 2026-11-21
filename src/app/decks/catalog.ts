import { DeckSchema, type Deck } from '@/schema'
import { DeckManifestSchema, type DeckManifest, type DeckManifestEntry } from '@/schema/manifest'

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>

/** Where built decks are served from, under the app's base path. */
export function decksUrl(file = ''): string {
  return `${import.meta.env.BASE_URL}decks/${file}`
}

export class CatalogError extends Error {
  override name = 'CatalogError'
}

/** Fetches and validates `decks/index.json`. Always asks the network first. */
export async function fetchManifest(fetchFn: FetchLike = fetch): Promise<DeckManifest> {
  const response = await fetchFn(decksUrl('index.json'), { cache: 'no-cache' })
  if (!response.ok) throw new CatalogError(`Couldn't load the deck list (HTTP ${response.status}).`)
  const parsed = DeckManifestSchema.safeParse(await response.json())
  if (!parsed.success)
    throw new CatalogError('The deck list is in a format this app does not understand.')
  return parsed.data
}

/**
 * Fetches one deck file and validates it against the deck schema. Reports
 * download progress (0–1) when the body can be streamed.
 */
export async function fetchDeck(
  entry: Pick<DeckManifestEntry, 'id' | 'file' | 'bytes'>,
  onProgress: (fraction: number) => void = () => {},
  fetchFn: FetchLike = fetch,
): Promise<Deck> {
  const response = await fetchFn(decksUrl(entry.file))
  if (!response.ok)
    throw new CatalogError(`Couldn't download ${entry.id} (HTTP ${response.status}).`)
  let text: string
  const reader = response.body?.getReader()
  if (reader && entry.bytes > 0) {
    const chunks: Uint8Array[] = []
    let received = 0
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      chunks.push(value)
      received += value.byteLength
      onProgress(Math.min(1, received / entry.bytes))
    }
    const all = new Uint8Array(received)
    let offset = 0
    for (const chunk of chunks) {
      all.set(chunk, offset)
      offset += chunk.byteLength
    }
    text = new TextDecoder().decode(all)
  } else {
    text = await response.text()
  }
  onProgress(1)
  let json: unknown
  try {
    json = JSON.parse(text)
  } catch {
    throw new CatalogError(`${entry.id} is not valid JSON.`)
  }
  const parsed = DeckSchema.safeParse(json)
  if (!parsed.success) {
    const first = parsed.error.issues[0]
    throw new CatalogError(
      `${entry.id} failed validation${first ? ` at ${first.path.join('.') || 'the root'}: ${first.message}` : ''}.`,
    )
  }
  if (parsed.data.id !== entry.id)
    throw new CatalogError(`${entry.file} contains deck "${parsed.data.id}", not "${entry.id}".`)
  return parsed.data
}
