/**
 * Static server for E2E tests: serves `dist-e2e/` like GitHub Pages would, with an SPA
 * fallback to index.html.
 *
 * To test automatic updates, a browser context can pretend a new version
 * was deployed: with the cookie `e2e-build=<n>` set, `sw.js` gets a trailing comment,
 * which makes it byte-different, so the browser installs it as an update. Cookies are
 * per context, so other tests keep seeing the original build.
 *
 * To test offline behaviour, `e2e-offline=1` makes the server drop the connection for
 * that context, like a network outage. Playwright's `context.setOffline()` isn't enough
 * on its own: in WebKit it also blocks requests the service worker would answer from
 * its cache, which a real offline device doesn't do.
 */
import { createReadStream } from 'node:fs'
import { readFile, stat } from 'node:fs/promises'
import { createServer } from 'node:http'
import { extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../dist-e2e', import.meta.url))
const port = Number(process.env.PORT ?? 4173)

const types: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
}

async function isFile(path: string) {
  return stat(path).then(
    (s) => s.isFile(),
    () => false,
  )
}

createServer(async (req, res) => {
  if (/(?:^|;\s*)e2e-offline=1/.test(req.headers.cookie ?? '')) {
    req.socket.destroy()
    return
  }
  const url = new URL(req.url ?? '/', 'http://localhost')
  let path = join(root, normalize(decodeURIComponent(url.pathname)))
  if (!path.startsWith(root)) {
    res.writeHead(403).end()
    return
  }
  if (!(await isFile(path))) {
    if (extname(url.pathname)) {
      res.writeHead(404).end('Not found')
      return
    }
    path = join(root, 'index.html')
  }

  const headers = { 'content-type': types[extname(path)] ?? 'application/octet-stream' }
  if (path === join(root, 'sw.js')) {
    const build = /(?:^|;\s*)e2e-build=(\w+)/.exec(req.headers.cookie ?? '')?.[1]
    const body = (await readFile(path, 'utf8')) + (build ? `\n// e2e build ${build}\n` : '')
    res.writeHead(200, { ...headers, 'cache-control': 'no-cache' }).end(body)
    return
  }
  res.writeHead(200, headers)
  createReadStream(path).pipe(res)
}).listen(port, () => console.log(`Serving ${root} on http://localhost:${port}`))
