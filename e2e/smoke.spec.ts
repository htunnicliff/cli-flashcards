import { expectNoA11yViolations } from './support/a11y'
import { expect, test } from './support/test'

test('every route in the main navigation loads without accessibility violations', async ({
  page,
}) => {
  await page.goto('/')
  const nav = page.getByRole('navigation', { name: 'Main' })
  const hrefs = await nav
    .getByRole('link')
    .evaluateAll((links) => links.map((link) => new URL((link as HTMLAnchorElement).href).pathname))
  expect(hrefs.length).toBeGreaterThan(0)

  for (const href of hrefs) {
    await test.step(href, async () => {
      await page.goto(href)
      await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
      await expectNoA11yViolations(page)
    })
  }
})

test('client-side navigation reaches every route', async ({ page }) => {
  await page.goto('/')
  const nav = page.getByRole('navigation', { name: 'Main' })
  const names = await nav.getByRole('link').allTextContents()

  for (const name of names) {
    await nav.getByRole('link', { name }).click()
    await expect(nav.getByRole('link', { name })).toHaveAttribute('aria-current', 'page')
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
  }
})

test('fixture decks are served instead of the real ones', async ({ page }) => {
  const response = await page.request.get('/data/decks/index.json')
  expect(response.ok()).toBe(true)
  const index = (await response.json()) as { decks: { id: string }[] }
  expect(index.decks.map((deck) => deck.id)).toEqual(['ripgrep-fixture'])
})

test('tests run with reduced motion', async ({ page }) => {
  await page.goto('/')
  expect(await page.evaluate(() => matchMedia('(prefers-reduced-motion: reduce)').matches)).toBe(
    true,
  )
})
