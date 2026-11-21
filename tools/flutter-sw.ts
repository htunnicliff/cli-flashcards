/**
 * Writes the Flutter web app's service worker, so it works offline like the
 * Vue app. Flutter's own service worker is deprecated (it only unregisters
 * itself), so this uses Workbox, configured to match vite.config.ts.
 *
 * Run after `flutter build web --no-web-resources-cdn` (the flag keeps
 * CanvasKit on our own origin so it can be cached):
 *
 *   pnpm flutter:sw [app/build/web]
 */
import { generateSW } from 'workbox-build'

const dir = process.argv[2] ?? 'app/build/web'

const { count, size, warnings } = await generateSW({
  globDirectory: dir,
  swDest: `${dir}/sw.js`,
  globPatterns: [
    '*.{js,html,json,png,svg}',
    'icons/**',
    'assets/**',
    // The default CanvasKit build and the Chromium one; the other renderers
    // (skwasm, wimp) are only used when asked for.
    'canvaskit/canvaskit.{js,wasm}',
    'canvaskit/chromium/*.{js,wasm}',
  ],
  // classic/ is the old Vue app, which has its own service worker.
  globIgnores: ['sw.js', 'flutter_service_worker.js', 'data/**', 'classic/**', '**/*.symbols'],
  // main.dart.js and canvaskit.wasm are several megabytes each.
  maximumFileSizeToCacheInBytes: 16 * 1024 * 1024,
  // Flutter fingerprints neither main.dart.js nor its assets, so Workbox's
  // revision hashes decide what changed.
  navigateFallback: 'index.html',
  navigateFallbackDenylist: [/\/data\//, /\/classic(\/|$)/],
  cleanupOutdatedCaches: true,
  // Wait for the page to hand over (see web/flutter_bootstrap.js).
  skipWaiting: false,
  clientsClaim: false,
  runtimeCaching: [
    {
      urlPattern: ({ url, sameOrigin }) =>
        sameOrigin && url.pathname.endsWith('/data/decks/index.json'),
      handler: 'NetworkFirst',
      options: { cacheName: 'deck-index', networkTimeoutSeconds: 4 },
    },
    {
      urlPattern: ({ url, sameOrigin }) =>
        sameOrigin &&
        /\/data\/decks\/.+\.json$/.test(url.pathname) &&
        !url.pathname.endsWith('/index.json'),
      handler: 'NetworkFirst',
      options: { cacheName: 'decks', networkTimeoutSeconds: 8, expiration: { maxEntries: 40 } },
    },
  ],
})

for (const w of warnings) console.warn(w)
console.log(`sw.js precaches ${count} files, ${(size / 1024 / 1024).toFixed(1)} MB`)
