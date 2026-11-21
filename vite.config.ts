import { fileURLToPath, URL } from 'node:url'

import vue from '@vitejs/plugin-vue'
import MotionResolver from 'motion-v/resolver'
import Components from 'unplugin-vue-components/vite'
import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  // GitHub Pages serves the app from /cli-flashcards/; the deploy workflow sets BASE_PATH.
  base: process.env.BASE_PATH ?? '/',
  plugins: [
    vue(),
    // Auto-imports Motion components (<Motion>, <AnimatePresence>, …) in templates.
    // Our own components are imported explicitly, so local auto-import is off.
    Components({ dirs: [], resolvers: [MotionResolver()], dts: 'src/components.d.ts' }),
    VitePWA({
      // Never swap versions mid-session: a new build waits until the user chooses to reload.
      registerType: 'prompt',
      injectRegister: false,
      // The hand-written public/manifest.webmanifest (linked from index.html) is the manifest.
      manifest: false,
      workbox: {
        // App shell. Decks are fetched on demand and cached at runtime instead.
        globPatterns: ['**/*.{js,css,html,svg,png,woff2,webmanifest}'],
        globIgnores: ['data/**'],
        navigateFallback: 'index.html',
        // Deck data lives under data/ so it never collides with the /decks routes.
        navigateFallbackDenylist: [/\/data\//],
        runtimeCaching: [
          {
            // The deck list should be fresh when online, and still work offline.
            urlPattern: ({ url, sameOrigin }) =>
              sameOrigin && url.pathname.endsWith('/data/decks/index.json'),
            handler: 'NetworkFirst',
            options: { cacheName: 'deck-index', networkTimeoutSeconds: 4 },
          },
          {
            // Deck files are cached as they are installed. Installed decks live in
            // IndexedDB, so this is only a fallback for reinstalling while offline.
            urlPattern: ({ url, sameOrigin }) =>
              sameOrigin &&
              /\/data\/decks\/.+\.json$/.test(url.pathname) &&
              !url.pathname.endsWith('/index.json'),
            handler: 'NetworkFirst',
            options: {
              cacheName: 'decks',
              networkTimeoutSeconds: 8,
              expiration: { maxEntries: 40 },
            },
          },
        ],
      },
    }),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
})
