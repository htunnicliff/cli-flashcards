import { test as base, expect } from '@playwright/test'

/**
 * Shared `test` for every E2E spec. Each test gets a new browser context (so fresh
 * storage) and fails if the page logs an uncaught error.
 */
export const test = base.extend<{ failOnPageError: void }>({
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
