/**
 * PROTOTYPE: picks one of the Liquid Glass looks in glass-prototype.css.
 * Open the app with ?look=clear, ?look=aurora or ?look=frost to try one; ?look=off goes back.
 */
const KEY = 'recall:look-prototype'
const looks = ['clear', 'aurora', 'frost'] as const

export function applyLookPrototype(doc: Document = document, url = new URL(location.href)) {
  let look: string | null = null
  try {
    const asked = url.searchParams.get('look')
    if (asked === 'off') localStorage.removeItem(KEY)
    else if (asked && (looks as readonly string[]).includes(asked)) localStorage.setItem(KEY, asked)
    look = localStorage.getItem(KEY)
  } catch {
    look = url.searchParams.get('look')
  }
  if (look && (looks as readonly string[]).includes(look)) doc.documentElement.dataset.look = look
  else delete doc.documentElement.dataset.look
}
