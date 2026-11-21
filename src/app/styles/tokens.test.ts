import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

import { describe, expect, it } from 'vitest'

import { contrastRatio } from '@/core/contrast'

import { palette, textPairs, themes } from './palette'

// Read from disk: Vitest doesn't load CSS contents, even with ?raw.
const css = readFileSync(resolve(import.meta.dirname, 'tokens.css'), 'utf8')

/** The --color-* declarations directly inside the first block that opens after `opener`. */
function colorTokens(opener: string): Record<string, string> {
  const start = css.indexOf(opener)
  if (start === -1) throw new Error(`tokens.css has no block for ${opener}`)
  const open = css.indexOf('{', start + opener.length - 1)
  const body = css.slice(open + 1, css.indexOf('}', open))
  return Object.fromEntries(
    [...body.matchAll(/--color-([a-z-]+):\s*(#[0-9a-f]{6})\s*;/gi)].map(([, name, value]) => [
      name,
      value!.toUpperCase(),
    ]),
  )
}

const cssThemes = {
  light: [colorTokens(":root[data-theme='light'] {")],
  dark: [
    colorTokens(":root[data-theme='dark'] {"),
    colorTokens(":root:not([data-theme='light']) {"),
  ],
}

describe('design tokens', () => {
  describe.each(themes)('%s theme', (theme) => {
    it('matches palette.ts in every tokens.css block', () => {
      for (const block of cssThemes[theme]) expect(block).toEqual(palette[theme])
    })

    const pairs = textPairs.flatMap(([fg, bgs]) => bgs.map((bg) => [fg, bg] as const))

    // The design commits to ≥ 5.3:1; WCAG AA is 4.5:1. Fail on either slipping.
    it.each(pairs)('%s on %s meets AA (≥ 5.3:1)', (fg, bg) => {
      const ratio = contrastRatio(palette[theme][fg], palette[theme][bg])
      expect(ratio, `${fg} on ${bg} is ${ratio.toFixed(2)}:1`).toBeGreaterThanOrEqual(5.3)
    })

    it('keeps the focus ring visible (≥ 3:1) against every surface', () => {
      for (const bg of ['bg', 'surface', 'sunken'] as const) {
        expect(contrastRatio(palette[theme].accent, palette[theme][bg])).toBeGreaterThanOrEqual(3)
      }
    })
  })

  it('keeps raw hex colours out of component styles', () => {
    const files = import.meta.glob('../**/*.vue', { query: '?raw', import: 'default', eager: true })
    const offenders = Object.entries(files)
      .filter(([, source]) =>
        [...(source as string).matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].some(([, style]) =>
          /#[0-9a-f]{3,8}\b/i.test(style!),
        ),
      )
      .map(([path]) => path)
    expect(Object.keys(files).length).toBeGreaterThan(5)
    expect(offenders).toEqual([])
  })
})
