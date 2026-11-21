import { readStore } from './support/storage'
import {
  checkForUpdate,
  deployNewBuild,
  markPage,
  setHidden,
  simulateOutage,
  waitForServiceWorker,
  waitForWaitingVersion,
  type Marked,
} from './support/pwa'
import { expect, test } from './support/test'

test('the app loads and navigates offline once it has been visited', async ({
  page,
  context,
  baseURL,
}) => {
  await page.goto('/')
  await waitForServiceWorker(page)

  await simulateOutage(context, baseURL!)
  await page.reload()
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible()

  // Deep links fall back to the cached app shell.
  await page.goto('/settings')
  await expect(page.getByRole('heading', { name: 'Settings', level: 1 })).toBeVisible()
})

test('the header says when the browser is offline', async ({ page, context }) => {
  await page.goto('/')
  await expect(page.getByText('Offline', { exact: true })).toBeHidden()

  await context.setOffline(true)
  await expect(page.getByText('Offline', { exact: true })).toBeVisible()

  await context.setOffline(false)
  await expect(page.getByText('Offline', { exact: true })).toBeHidden()
})

test('the deck list falls back to the cache offline', async ({ page, context, baseURL }) => {
  await page.goto('/')
  await waitForServiceWorker(page)
  const online = await page.evaluate(() => fetch('data/decks/index.json').then((r) => r.json()))

  await simulateOutage(context, baseURL!)
  const offline = await page.evaluate(() => fetch('data/decks/index.json').then((r) => r.json()))
  expect(offline).toEqual(online)
})

test('a new version takes over by itself before the page is touched', async ({
  page,
  context,
  baseURL,
}) => {
  await page.goto('/settings')
  await waitForServiceWorker(page)
  await markPage(page)

  await deployNewBuild(context, baseURL!)
  await checkForUpdate(page)

  await page.waitForFunction(() => !(window as Marked).e2eMarker)
  await expect(page.getByRole('heading', { name: 'Settings', level: 1 })).toBeVisible()
  await expect(page.getByText('Update available')).toHaveCount(0)
})

test('a new version waits while the user is on a screen, then takes over on the next', async ({
  page,
  context,
  baseURL,
}) => {
  await page.goto('/settings')
  await waitForServiceWorker(page)
  await page.keyboard.press('Shift') // The user is using the page now.
  await markPage(page)

  await deployNewBuild(context, baseURL!)
  await checkForUpdate(page)
  await waitForWaitingVersion(page)

  // Still the same page: nothing was interrupted, and nothing asks the user anything.
  expect(await page.evaluate(() => (window as Marked).e2eMarker)).toBe(true)
  await expect(page.getByText('Update available')).toHaveCount(0)

  await page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Stats' }).click()
  await page.waitForFunction(() => !(window as Marked).e2eMarker)
  await expect(page.getByRole('heading', { name: 'Stats', level: 1 })).toBeVisible()
  await expect(page).toHaveURL(/\/stats$/)
  await expect(page.locator('html')).not.toHaveAttribute('data-update', 'waiting')
})

test('a new version never interrupts a review, even in the background', async ({
  page,
  context,
  baseURL,
}) => {
  await page.goto('/decks')
  await waitForServiceWorker(page)
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await expect(deck).toHaveAttribute('data-installed', 'true')

  await page.goto('/')
  await expect(page.getByTestId('count-new')).toHaveText('3')
  await page.keyboard.press('Space')
  await expect(page.getByTestId('back')).toBeVisible()
  await markPage(page)

  await deployNewBuild(context, baseURL!)
  await checkForUpdate(page)
  await waitForWaitingVersion(page)
  await setHidden(page, true)
  await setHidden(page, false)

  // A beat for a reload that must not happen.
  await page.waitForTimeout(500)
  expect(await page.evaluate(() => (window as Marked).e2eMarker)).toBe(true)
  await expect(page.getByTestId('back')).toBeVisible()
})

test('Chromium considers the app installable', async ({ page, browserName }) => {
  test.skip(
    browserName !== 'chromium',
    'Installability errors come from the Chrome DevTools Protocol',
  )
  await page.goto('/')
  await waitForServiceWorker(page)
  const cdp = await page.context().newCDPSession(page)
  const { installabilityErrors } = await cdp.send('Page.getInstallabilityErrors')
  expect(installabilityErrors).toEqual([])
})

test('downloaded decks stay available offline, and their settings still work', async ({
  page,
  context,
  baseURL,
}) => {
  await page.goto('/decks')
  await waitForServiceWorker(page)
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await expect(deck).toHaveAttribute('data-installed', 'true')

  await simulateOutage(context, baseURL!)
  await page.reload()
  await expect(deck).toHaveAttribute('data-installed', 'true')
  await page.goto('/decks/ripgrep-fixture')
  await expect(page.getByText('--ignore-case')).toBeVisible()

  await page.goto('/decks')
  // Let the deck list finish loading first: WebKit's setOffline() also fails requests
  // still in flight to the service worker, which would leave the list empty.
  await expect(deck).toHaveAttribute('data-installed', 'true')
  await context.setOffline(true)
  await expect(page.getByText("You're offline")).toBeVisible()
  await deck.getByRole('checkbox', { name: 'Study this deck' }).uncheck()
  await expect(deck).toHaveAttribute('data-studying', 'false')

  await context.setOffline(false)
  await expect(page.getByText("You're offline")).toHaveCount(0)
})

test('a whole review session works offline after a reload', async ({ page, context, baseURL }) => {
  await page.goto('/decks')
  await waitForServiceWorker(page)
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await expect(deck).toHaveAttribute('data-installed', 'true')

  await simulateOutage(context, baseURL!)
  await page.goto('/')
  const newCount = page.getByTestId('count-new')
  await expect(newCount).toHaveText('3')
  for (const left of ['2', '1', '0']) {
    await page.keyboard.press('Space')
    await expect(page.getByTestId('back')).toBeVisible()
    await page.keyboard.press('4')
    if (left !== '0') await expect(newCount).toHaveText(left)
  }
  await expect(page.getByTestId('done')).toContainText('All done for today')

  // Progress made offline is still there after another offline reload.
  await expect.poll(async () => (await readStore(page, 'recall', 'reviewLog')).length).toBe(3)
  await page.reload()
  await expect(page.getByTestId('done')).toContainText('All done for today')
})
