import type { BrowserContext, Page } from '@playwright/test'

/** Waits until a service worker is active and controls the page, so reloads go through it. */
export async function waitForServiceWorker(page: Page) {
  await page.evaluate(() => navigator.serviceWorker.ready)
  // The visit that installed the worker isn't controlled by it (no clientsClaim); a reload is.
  await page.reload()
  await page.waitForFunction(() => navigator.serviceWorker.controller !== null)
}

/** Makes the E2E server hand this context a byte-different sw.js, like a new deploy. */
export async function deployNewBuild(context: BrowserContext, baseURL: string, build = '2') {
  await context.addCookies([{ name: 'e2e-build', value: build, url: baseURL }])
}

/** Asks the browser to check for a new service worker now, instead of waiting for its timer. */
export async function checkForUpdate(page: Page) {
  await page.evaluate(async () => {
    const registration = await navigator.serviceWorker.getRegistration()
    await registration?.update()
  })
}
