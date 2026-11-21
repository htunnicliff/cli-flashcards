/**
 * `--help` output parser, for tools that ship no manpage (many Rust and Go
 * CLIs). Handles the common layouts:
 *
 *   -x, --long-name <ARG>    Description on the same line
 *                            wrapped onto more lines
 *
 *       --long-name <ARG>
 *           Description on the following lines (clap's long help)
 *
 * Section headings are unindented lines ending in `:` ("Options:", "Cache
 * options:"). The `Usage:` lines are kept as SYNOPSIS text for tiering.
 */
import { TextBuilder } from './manpage/text'
import type { RawEntry, RawPage } from './manpage/types'

const OPTION_LINE = /^(\s+)(-\S.*?)(?:\s{2,}(\S.*))?\s*$/
const HEADING = /^(\S[^:]*):\s*(.*)$/

export function parseHelp(text: string): RawPage {
  const page: RawPage = {
    format: 'help',
    title: '',
    section: undefined,
    entries: [],
    sectionText: {},
  }
  const lines = text.replace(/\r\n?/g, '\n').replace(/\t/g, '        ').split('\n')

  let section = ''
  let entry:
    | { tag: string; indent: number; bodyIndent?: number; body: TextBuilder; section: string }
    | undefined
  let blankPending = false

  const close = () => {
    if (entry) {
      page.entries.push({
        section: entry.section,
        tag: entry.tag,
        description: entry.body.toString(),
      } satisfies RawEntry)
    }
    entry = undefined
    blankPending = false
  }

  const record = (line: string) => {
    page.sectionText[section] = `${page.sectionText[section] ?? ''}${line}\n`
  }

  for (const line of lines) {
    if (line.trim() === '') {
      if (entry) blankPending = true
      continue
    }
    const indent = line.length - line.trimStart().length

    const heading = indent === 0 ? HEADING.exec(line) : null
    if (heading) {
      close()
      const name = heading[1]!.trim().toUpperCase()
      section = name === 'USAGE' ? 'SYNOPSIS' : name
      if (heading[2]) record(heading[2])
      continue
    }
    if (indent === 0) {
      // Prose (a description line at the top, a footer): not part of an option.
      close()
      record(line)
      continue
    }

    const option = OPTION_LINE.exec(line)
    // A line continues the open entry when it is indented past the option. An
    // option line only starts a new entry when it sits left of the
    // description column (clap indents long-only options further than
    // `-x, --long` ones).
    const continues =
      entry !== undefined &&
      indent > entry.indent &&
      !(option && indent < (entry.bodyIndent ?? entry.indent + 5))
    if (option && !continues) {
      close()
      entry = {
        tag: option[2]!.trim(),
        indent: option[1]!.length,
        body: new TextBuilder(),
        section,
      }
      if (option[3]) {
        entry.body.add(option[3])
        entry.bodyIndent = line.indexOf(option[3], option[1]!.length + option[2]!.length)
      }
      continue
    }
    if (continues) {
      if (blankPending) entry!.body.paragraph()
      blankPending = false
      entry!.bodyIndent ??= indent
      entry!.body.add(line.trim())
      continue
    }
    close()
    record(line)
  }
  close()
  return page
}

/** Annotations clap and similar libraries append, which don't belong in a summary. */
export function stripHelpAnnotations(text: string): string {
  return text
    .replace(/\s*\[(?:env|default|possible values|aliases|short aliases):[^\]]*\]/g, '')
    .trim()
}
