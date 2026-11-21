/** WCAG 2.x colour contrast, for `#rrggbb` colours. */

export function parseHex(hex: string): [r: number, g: number, b: number] {
  const match = /^#([0-9a-f]{6})$/i.exec(hex.trim())
  if (!match?.[1]) throw new Error(`Expected a #rrggbb colour, got "${hex}"`)
  const n = parseInt(match[1], 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

function linear(channel: number): number {
  const c = channel / 255
  return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
}

/** Relative luminance, from 0 (black) to 1 (white). */
export function relativeLuminance(hex: string): number {
  const [r, g, b] = parseHex(hex)
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

/** Contrast ratio between two colours, from 1 to 21. Order does not matter. */
export function contrastRatio(a: string, b: string): number {
  const la = relativeLuminance(a)
  const lb = relativeLuminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}
