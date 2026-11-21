/**
 * Vendors tldr-pages examples used to rank options, pinned to one commit so
 * deck builds are reproducible.
 *
 *   pnpm tldr:vendor                     refresh the pinned pages
 *   pnpm tldr:vendor --commit <sha>      move the pin to another commit
 *
 * Pages land in vendor/tldr/pages/<platform>/<page>.md. tldr-pages is
 * CC BY 4.0; see vendor/tldr/README.md.
 */
import { existsSync, readFileSync } from 'node:fs'
import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { parseArgs } from 'node:util'

const { values } = parseArgs({ options: { commit: { type: 'string' } } })

const root = resolve(process.cwd(), 'vendor', 'tldr')
const pinFile = join(root, 'pin.json')
const pin = JSON.parse(readFileSync(pinFile, 'utf8')) as { commit: string; pages: string[] }
if (values.commit) pin.commit = values.commit

const PLATFORMS = ['common', 'linux', 'osx']

let fetched = 0
for (const page of pin.pages) {
  for (const platform of PLATFORMS) {
    const url = `https://raw.githubusercontent.com/tldr-pages/tldr/${pin.commit}/pages/${platform}/${page}.md`
    const response = await fetch(url)
    if (response.status === 404) continue
    if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`)
    const target = join(root, 'pages', platform, `${page}.md`)
    await mkdir(dirname(target), { recursive: true })
    await writeFile(target, await response.text())
    fetched++
  }
  if (!PLATFORMS.some((platform) => existsSync(join(root, 'pages', platform, `${page}.md`)))) {
    console.warn(`warning: tldr has no page for "${page}"`)
  }
}
await writeFile(pinFile, `${JSON.stringify(pin, null, 2)}\n`)
console.log(`Fetched ${fetched} pages at tldr-pages/tldr@${pin.commit.slice(0, 7)}`)
