import { parseMan } from './man'
import { isMdoc, parseMdoc } from './mdoc'
import type { RawPage } from './types'

export type { RawEntry, RawPage } from './types'

/** Parses man(7) or mdoc(7) source into tagged option entries. */
export function parseManpage(source: string): RawPage {
  return isMdoc(source) ? parseMdoc(source) : parseMan(source)
}
