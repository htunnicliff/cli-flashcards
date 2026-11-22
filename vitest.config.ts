import { defineConfig } from 'vitest/config'

// The deck pipeline: schema, the scheduling and answer logic the parity
// fixtures come from, and the Node build scripts.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['pipeline/**/*.test.ts', 'tools/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      include: ['pipeline/**/*.ts', 'tools/**/*.ts'],
      exclude: ['**/*.test.ts'],
      reporter: ['text', 'json-summary', 'html'],
    },
  },
})
