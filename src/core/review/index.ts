/** Review-screen helpers that don't need Vue. */
import { CLOZE_BLANK } from '../../schema'

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

/** Short interval label for a grade button: "<1m", "10m", "3h", "4d", "2.5mo", "1.2y". */
export function formatInterval(ms: number): string {
  if (ms < MINUTE) return '<1m'
  if (ms < HOUR) return `${Math.round(ms / MINUTE)}m`
  if (ms < DAY) return `${Math.round(ms / HOUR)}h`
  const days = ms / DAY
  if (days < 30) return `${Math.round(days)}d`
  if (days < 365) return `${trim(days / 30)}mo`
  return `${trim(days / 365)}y`
}

function trim(value: number): string {
  return value >= 10 ? String(Math.round(value)) : value.toFixed(1).replace(/\.0$/, '')
}

/** When a later card is due, in words: "in 12 minutes", "tomorrow at 9:00 AM", … */
export function formatNextDue(due: number, now: number, locale?: string): string {
  const diff = due - now
  if (diff < HOUR) {
    const minutes = Math.max(1, Math.round(diff / MINUTE))
    return `in ${minutes} minute${minutes === 1 ? '' : 's'}`
  }
  const time = new Date(due).toLocaleTimeString(locale, { hour: 'numeric', minute: '2-digit' })
  const startOfDay = (t: number) => new Date(new Date(t).toDateString()).getTime()
  const days = Math.round((startOfDay(due) - startOfDay(now)) / DAY)
  if (days === 0) return `today at ${time}`
  if (days === 1) return `tomorrow at ${time}`
  if (days < 7) return `${new Date(due).toLocaleDateString(locale, { weekday: 'long' })} at ${time}`
  return `on ${new Date(due).toLocaleDateString(locale, { month: 'long', day: 'numeric' })}`
}

export type PartKind = 'tool' | 'flag' | 'arg' | 'blank'
export interface Part {
  kind: PartKind
  text: string
}

/**
 * Splits a command into parts for display: the first word (and a git-style
 * subcommand) as the tool, flag tokens as flags, the blank of a cloze card as
 * a blank, and `<placeholder>` words as arguments.
 */
export function commandParts(command: string): Part[] {
  const words = command.trim().split(/\s+/).filter(Boolean)
  return words.map((word, index): Part => {
    if (word.includes(CLOZE_BLANK)) {
      const rest = word.replace(CLOZE_BLANK, '')
      return rest ? { kind: 'blank', text: rest } : { kind: 'blank', text: '' }
    }
    if (index === 0) return { kind: 'tool', text: word }
    if (/^--?[^\s-]/.test(word)) return { kind: 'flag', text: word }
    if (/^<.+>$/.test(word)) return { kind: 'arg', text: word }
    return { kind: 'tool', text: word }
  })
}
