/** One tagged paragraph from a manpage whose tag starts with a flag. */
export interface RawEntry {
  /** Upper-cased `.SH`/`.Sh` heading the entry appeared under. */
  section: string
  subsection?: string
  /** The tag as plain text, e.g. `-i, --ignore-case` or `--color=WHEN`. */
  tag: string
  /** Plain-text description; paragraphs separated by a blank line. */
  description: string
}

export interface RawPage {
  format: 'man' | 'mdoc'
  /** Page name from `.TH` / `.Dt`, e.g. `RG` or `SED`. */
  title: string
  section: string | undefined
  entries: RawEntry[]
  /** Plain text of each section, keyed by upper-cased heading (for SYNOPSIS/EXAMPLES mentions). */
  sectionText: Record<string, string>
}
