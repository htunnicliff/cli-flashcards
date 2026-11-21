import { existsSync, readFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import type { TldrPage } from './tldr'

export const TLDR_DIR = resolve(import.meta.dirname, '../../vendor/tldr/pages')

/** tldr platforms to read for a deck variant, most specific first. */
export function tldrPlatforms(variant: string): string[] {
  return /^(bsd|macos|osx|darwin)$/.test(variant) ? ['osx', 'common'] : ['linux', 'common']
}

/** Loads the vendored tldr pages for the given manpages, if there are any. */
export function loadTldrPages(
  pages: readonly { name: string; subcommand?: string }[],
  variant: string,
  dir = TLDR_DIR,
): TldrPage[] {
  return pages.flatMap((page) =>
    tldrPlatforms(variant)
      .map((platform) => join(dir, platform, `${page.name}.md`))
      .filter((path) => existsSync(path))
      .map((path) => ({
        name: page.name,
        markdown: readFileSync(path, 'utf8'),
        ...(page.subcommand ? { subcommand: page.subcommand } : {}),
      })),
  )
}
