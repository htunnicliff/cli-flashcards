import { defineConfig, mergeConfig } from 'vitest/config'

import viteConfig from './vite.config.ts'

export default mergeConfig(
  viteConfig,
  defineConfig({
    test: {
      projects: [
        {
          // Framework-free code: shared schema, core logic and Node build scripts.
          extends: true,
          test: {
            name: 'unit',
            environment: 'node',
            include: [
              'src/core/**/*.test.ts',
              'src/schema/**/*.test.ts',
              'tools/**/*.test.ts',
              'e2e/fixtures/**/*.test.ts',
            ],
          },
        },
        {
          // Vue components, views and stores.
          extends: true,
          test: {
            name: 'app',
            environment: 'happy-dom',
            include: ['src/app/**/*.test.ts'],
            setupFiles: ['src/app/test-setup.ts'],
          },
        },
      ],
      coverage: {
        provider: 'v8',
        include: ['src/core/**/*.ts', 'tools/**/*.ts'],
        exclude: ['**/*.test.ts'],
        reporter: ['text', 'json-summary', 'html'],
      },
    },
  }),
)
