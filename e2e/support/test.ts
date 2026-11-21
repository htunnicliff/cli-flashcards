import { test as base, expect, type BrowserContext, type Page } from '@playwright/test'

/** Keep in step with ONBOARDING_STORAGE_KEY in src/app/onboarding/onboarding.ts. */
const ONBOARDING_STORAGE_KEY = 'recall:onboarded'

/** Marks the welcome tour as seen before the app loads in this page or context. */
export async function skipOnboarding(target: Page | BrowserContext) {
  await target.addInitScript((key) => {
    try {
      localStorage.setItem(key, '1')
    } catch {
      // Opaque origins (about:blank) have no storage.
    }
  }, ONBOARDING_STORAGE_KEY)
}

/**
 * Shared `test` for every E2E spec. Each test gets a new browser context (so fresh
 * storage) and fails if the page logs an uncaught error.
 *
 * The welcome tour opens on a first visit, which would cover every page in a fresh
 * context, so it starts out marked as seen. Specs about the tour opt back in with
 * `test.use({ onboarding: true })`; contexts a spec opens itself call `skipOnboarding`.
 */
export const test = base.extend<{ onboarding: boolean; failOnPageError: void; skipTour: void }>({
  onboarding: [false, { option: true }],
  skipTour: [
    async ({ page, onboarding }, use) => {
      if (!onboarding) await skipOnboarding(page)
      await use()
    },
    { auto: true },
  ],
  failOnPageError: [
    async ({ page }, use) => {
      const errors: string[] = []
      page.on('pageerror', (error) => errors.push(error.message))
      await use()
      expect(errors, 'Uncaught errors in the page').toEqual([])
    },
    { auto: true },
  ],
})

export { expect }
