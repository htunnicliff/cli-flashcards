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

/**
 * Cuts this context off from the server (see e2e/serve.ts), so anything that still
 * loads must come from the service worker. Works the same in every browser, unlike
 * `context.setOffline()`, which WebKit also applies to service-worker cache hits.
 */
export async function simulateOutage(context: BrowserContext, baseURL: string, down = true) {
  if (down) await context.addCookies([{ name: 'e2e-offline', value: '1', url: baseURL }])
  else await context.clearCookies({ name: 'e2e-offline' })
}

/** Marks the page, so a test can tell whether it reloaded. */
export type Marked = Window & { e2eMarker?: boolean }
export async function markPage(page: Page) {
  await page.evaluate(() => ((window as Marked).e2eMarker = true))
}

/** Waits until the app knows a new version is installed and waiting to take over. */
export async function waitForWaitingVersion(page: Page) {
  await page.locator('html[data-update="waiting"]').waitFor({ state: 'attached' })
}

/** Pretends the app went to the background (or came back), as when switching apps. */
export async function setHidden(page: Page, hidden: boolean) {
  await page.evaluate((hidden) => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => (hidden ? 'hidden' : 'visible'),
    })
    document.dispatchEvent(new Event('visibilitychange'))
  }, hidden)
}
