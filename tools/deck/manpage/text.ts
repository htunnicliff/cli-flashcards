/**
 * Collects description text as paragraphs while a front end walks a page.
 * Ordinary text is filled (whitespace collapsed); preformatted text keeps its
 * line breaks.
 */
export class TextBuilder {
  private paragraphs: string[] = []
  private current: string[] = []
  private preformatted = false

  get isPreformatted(): boolean {
    return this.preformatted
  }

  add(text: string): void {
    if (this.preformatted) {
      this.current.push(text.replace(/\s+$/, ''))
      return
    }
    const clean = text.replace(/\s+/g, ' ').trim()
    if (clean) this.current.push(clean)
  }

  /** Appends to the previous word with no space (mdoc `Ns`, roff `\c`). */
  addJoined(text: string): void {
    if (this.current.length === 0) return this.add(text)
    this.current[this.current.length - 1] += text.trim()
  }

  lineBreak(): void {
    if (this.preformatted) return
    if (this.current.length > 0) this.current.push('\n')
  }

  paragraph(): void {
    if (this.current.length === 0) return
    const text = this.preformatted
      ? this.current.join('\n').replace(/^\n+|\s+$/g, '')
      : this.current
          .join(' ')
          .replace(/ ?\n ?/g, '\n')
          .trim()
    if (text) this.paragraphs.push(text)
    this.current = []
  }

  setPreformatted(on: boolean): void {
    if (on === this.preformatted) return
    this.paragraph()
    this.preformatted = on
  }

  isEmpty(): boolean {
    return this.paragraphs.length === 0 && this.current.length === 0
  }

  toString(): string {
    this.paragraph()
    return this.paragraphs.join('\n\n')
  }
}

/** Abbreviations that end with a dot but do not end a sentence. */
const ABBREVIATIONS = /(?:^|\s)(?:e\.g|i\.e|etc|vs|cf|approx|incl|resp|viz|al|Ex|ex|No|no)\.$/

/**
 * The first sentence of a description, used as the card summary. Falls back
 * to the first line, then to the first 200 characters.
 */
export function firstSentence(description: string): string {
  const paragraph = (description.split(/\n\n/)[0] ?? '').replace(/\s+/g, ' ').trim()
  if (!paragraph) return ''
  const re = /[.!?](?=\s+[A-Z0-9"'(`[]|\s*$)/g
  let match: RegExpExecArray | null
  while ((match = re.exec(paragraph))) {
    const candidate = paragraph.slice(0, match.index + 1)
    if (ABBREVIATIONS.test(candidate)) continue
    // Do not stop on a dot inside a flag or filename, like `.gitignore` or `1.5`.
    if (match[0] === '.' && /\S\.$/.test(candidate) && /^\S/.test(paragraph.slice(match.index + 1)))
      continue
    return capitalize(trimLength(candidate))
  }
  return capitalize(trimLength(paragraph))
}

function capitalize(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1)
}

function trimLength(text: string, max = 300): string {
  if (text.length <= max) return text
  const cut = text.slice(0, max)
  return `${cut.slice(0, cut.lastIndexOf(' '))}…`
}
