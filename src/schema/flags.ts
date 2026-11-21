/**
 * Flag spelling helpers shared by the deck schema, the parser and the app.
 *
 * Vocabulary:
 * - A **short** flag is a single dash followed by exactly one character (`-i`, `-0`, `-?`).
 * - A **long** flag is anything else: double-dash (`--ignore-case`) or single-dash
 *   multi-character (`-name`, as used by `find` or `java`).
 */

/** A flag spelling: `-x`, `--long-name`, or `-name`. No whitespace, `=` or `:`. */
export const FLAG_PATTERN = /^--?[^\s=:-][^\s=:]*$/

export function isShortFlag(flag: string): boolean {
  return flag.length === 2 && flag.startsWith('-') && flag !== '--'
}

export function isLongFlag(flag: string): boolean {
  return !isShortFlag(flag)
}

/**
 * Orders flags short forms first, keeping the relative order within each group.
 * Decks must store `flags` in this order; the parser should call this before writing.
 */
export function normalizeFlags(flags: readonly string[]): string[] {
  return [...flags.filter(isShortFlag), ...flags.filter(isLongFlag)]
}

/** True when no long flag appears before a short flag. */
export function isShortFirst(flags: readonly string[]): boolean {
  let seenLong = false
  for (const flag of flags) {
    if (isShortFlag(flag)) {
      if (seenLong) return false
    } else {
      seenLong = true
    }
  }
  return true
}

/**
 * The canonical spelling used for identity: the longest flag, ties broken by
 * code-point order so the result never depends on the order flags are listed in.
 */
export function canonicalFlag(flags: readonly string[]): string {
  if (flags.length === 0) throw new Error('canonicalFlag: an option needs at least one flag')
  return flags.reduce((best, flag) => {
    if (flag.length !== best.length) return flag.length > best.length ? flag : best
    return flag < best ? flag : best
  })
}

/**
 * Derives a stable option ID from the canonical flag.
 *
 * - `--ignore-case` → `ignore-case`
 * - `-name` → `name`
 * - `-0` (short-only option) → `short-0`
 *
 * IDs are case-sensitive, because `-c` and `-C` are different options.
 */
export function deriveOptionId(flags: readonly string[]): string {
  const flag = canonicalFlag(flags)
  if (isShortFlag(flag)) return `short-${flag.slice(1)}`
  return flag.replace(/^--?/, '')
}
