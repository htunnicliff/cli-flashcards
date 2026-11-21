import { defineConfig, devices } from '@playwright/test'

const PORT = 4173
const isCI = !!process.env.CI

/**
 * E2E tests run against the production build (`vite build`, served by `e2e/serve.ts`), because
 * the service worker only exists there. `e2e/build.ts` builds into `dist-e2e/` and swaps
 * the real decks for the fixture decks in `e2e/fixtures/decks/`.
 */
export default defineConfig({
  testDir: './e2e',
  testMatch: '**/*.spec.ts',
  fullyParallel: true,
  forbidOnly: isCI,
  retries: isCI ? 1 : 0,
  workers: isCI ? 2 : undefined,
  reporter: isCI
    ? [['github'], ['html', { open: 'never' }]]
    : [['list'], ['html', { open: 'never' }]],

  use: {
    baseURL: `http://localhost:${PORT}`,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    // Animations must never make a result timing-dependent.
    contextOptions: { reducedMotion: 'reduce' },
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    // Closest to iOS Safari, where storage eviction and PWA quirks live.
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
    { name: 'mobile', use: { ...devices['Pixel 7'] } },
  ],

  webServer: {
    command: `pnpm exec jiti e2e/build.ts && pnpm exec jiti e2e/serve.ts`,
    env: { PORT: String(PORT) },
    url: `http://localhost:${PORT}`,
    reuseExistingServer: !isCI,
    timeout: 120_000,
  },
})
