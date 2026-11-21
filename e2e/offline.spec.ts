import { readStore } from './support/storage'
import { checkForUpdate, deployNewBuild, simulateOutage, waitForServiceWorker } from './support/pwa'
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
  await expect(page.getByText('Offline')).toBeHidden()

  await context.setOffline(true)
  await expect(page.getByText('Offline')).toBeVisible()

  await context.setOffline(false)
  await expect(page.getByText('Offline')).toBeHidden()
})

test('the deck list falls back to the cache offline', async ({ page, context, baseURL }) => {
  await page.goto('/')
  await waitForServiceWorker(page)
  const online = await page.evaluate(() => fetch('data/decks/index.json').then((r) => r.json()))

  await simulateOutage(context, baseURL!)
  const offline = await page.evaluate(() => fetch('data/decks/index.json').then((r) => r.json()))
  expect(offline).toEqual(online)
})

test('a new version prompts instead of taking over, and reloads when asked', async ({
  page,
  context,
  baseURL,
}) => {
  await page.goto('/settings')
  await waitForServiceWorker(page)

  // Mark the page so we can tell whether it reloaded behind the user's back.
  await page.evaluate(() => ((window as unknown as { e2eMarker: boolean }).e2eMarker = true))

  await deployNewBuild(context, baseURL!)
  await checkForUpdate(page)

  const prompt = page.locator('.update').filter({ hasText: 'Update available' })
  await expect(prompt).toBeVisible()
  // Still the same page and the same worker: nothing was interrupted.
  expect(await page.evaluate(() => (window as unknown as { e2eMarker?: boolean }).e2eMarker)).toBe(
    true,
  )
  await expect(page.getByRole('heading', { name: 'Settings', level: 1 })).toBeVisible()

  await prompt.getByRole('button', { name: 'Reload' }).click()
  await page.waitForFunction(() => !(window as unknown as { e2eMarker?: boolean }).e2eMarker)
  await expect(page.getByRole('heading', { name: 'Settings', level: 1 })).toBeVisible()
  await expect(page.getByText('Update available')).toBeHidden()
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

test('installed decks stay available offline, and installing waits for a connection', async ({
  page,
  context,
  baseURL,
}) => {
  await page.goto('/decks')
  await waitForServiceWorker(page)
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await deck.getByRole('button', { name: 'Install' }).click()
  await expect(deck).toHaveAttribute('data-installed', 'true')

  await simulateOutage(context, baseURL!)
  await page.reload()
  await expect(deck).toHaveAttribute('data-installed', 'true')
  await page.goto('/decks/ripgrep-fixture')
  await expect(page.getByText('--ignore-case')).toBeVisible()

  await page.goto('/decks')
  await context.setOffline(true)
  await expect(page.getByText("You're offline")).toBeVisible()
  await deck.getByRole('button', { name: 'Remove' }).click()
  await page.getByRole('button', { name: 'Remove deck' }).click()
  await expect(deck).toHaveAttribute('data-installed', 'false')
  await expect(deck.getByRole('button', { name: 'Install' })).toBeDisabled()

  await context.setOffline(false)
  await expect(deck.getByRole('button', { name: 'Install' })).toBeEnabled()
})

test('a whole review session works offline after a reload', async ({ page, context, baseURL }) => {
  await page.goto('/decks')
  await waitForServiceWorker(page)
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await deck.getByRole('button', { name: 'Install' }).click()
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
