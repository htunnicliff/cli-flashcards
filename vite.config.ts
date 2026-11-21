import { fileURLToPath, URL } from 'node:url'

import vue from '@vitejs/plugin-vue'
import MotionResolver from 'motion-v/resolver'
import Components from 'unplugin-vue-components/vite'
import { defineConfig } from 'vite'

export default defineConfig({
  // GitHub Pages serves the app from /cli-flashcards/; the deploy workflow sets BASE_PATH.
  base: process.env.BASE_PATH ?? '/',
  plugins: [
    vue(),
    // Auto-imports Motion components (<Motion>, <AnimatePresence>, …) in templates.
    // Our own components are imported explicitly, so local auto-import is off.
    Components({ dirs: [], resolvers: [MotionResolver()], dts: 'src/components.d.ts' }),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
})
