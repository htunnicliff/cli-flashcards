/**
 * One piece of a command line, as CommandLine renders it.
 * - tool: the program and literals (`rg`, `TODO`, `src/`), plain text colour
 * - flag: an option being learned (`-l`, `--oneline`), accent colour
 * - arg: an argument placeholder (`NUM`, `PATTERN`), argument colour and Casual italic
 * - blank: the missing piece of a cloze card
 */
export type CommandPartKind = 'tool' | 'flag' | 'arg' | 'blank'

export interface CommandPart {
  kind: CommandPartKind
  text: string
}
