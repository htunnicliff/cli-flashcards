import { expectNoA11yViolations } from './support/a11y'
import { expect, test } from './support/test'

test.use({ onboarding: true })

test('a first visit walks through the tour and lands on Decks', async ({ page }) => {
  await page.goto('/')
  const tour = page.getByRole('dialog', { name: /Welcome to/ })
  await expect(tour).toBeVisible()
  await expect(tour.getByText('Step 1 of 5')).toBeVisible()
  await expectNoA11yViolations(page)

  const headings = ['Install a deck', 'Review your cards', 'Practice your way', 'Works offline']
  for (const heading of headings) {
    await page.getByRole('button', { name: 'Next' }).click()
    await expect(page.getByRole('dialog', { name: heading })).toBeVisible()
    // The new step's heading takes focus so it is announced.
    await expect(page.getByRole('heading', { name: heading })).toBeFocused()
  }
  await expectNoA11yViolations(page)

  await page.getByRole('button', { name: 'Back' }).click()
  await expect(page.getByRole('dialog', { name: 'Practice your way' })).toBeVisible()
  await page.getByRole('button', { name: 'Next' }).click()

  await page.getByRole('button', { name: 'Choose a deck' }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page).toHaveURL(/\/decks$/)
  await expect(page.getByRole('heading', { level: 1, name: 'Decks' })).toBeVisible()

  // Seen once, never again on its own.
  await page.reload()
  await expect(page.getByRole('heading', { level: 1, name: 'Decks' })).toBeVisible()
  await expect(page.getByRole('dialog')).toHaveCount(0)
})

test('the tour can be skipped with the button or Escape', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: 'Skip tour' }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page.getByRole('heading', { level: 1, name: 'Review' })).toBeVisible()

  await page.evaluate(() => localStorage.clear())
  await page.reload()
  await expect(page.getByRole('dialog')).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await page.reload()
  await expect(page.getByRole('heading', { level: 1, name: 'Review' })).toBeVisible()
  await expect(page.getByRole('dialog')).toHaveCount(0)
})

test('Settings replays the tour', async ({ page }) => {
  await page.goto('/settings')
  await page.getByRole('button', { name: 'Skip tour' }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)

  await page.getByRole('button', { name: 'Replay the welcome tour' }).click()
  await expect(page.getByRole('dialog', { name: /Welcome to/ })).toBeVisible()
  for (let i = 0; i < 4; i++) await page.getByRole('button', { name: 'Next' }).click()
  await page.getByRole('button', { name: 'Done' }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  // A replay ends where it started.
  await expect(page).toHaveURL(/\/settings$/)
})

test('shows keyboard shortcuts on desktop and swipes on touch screens', async ({
  page,
  isMobile,
}) => {
  await page.goto('/')
  await page.getByRole('button', { name: 'Next' }).click()
  await page.getByRole('button', { name: 'Next' }).click()
  const tour = page.getByRole('dialog', { name: 'Review your cards' })
  await expect(tour.getByText(/shows the answer/)).toBeVisible({ visible: !isMobile })
  await expect(tour.getByText(/Swipe a revealed card/)).toBeVisible({ visible: isMobile })
})

test('someone who already has decks is not shown the tour', async ({ page }) => {
  // Like a learner from before the tour existed: decks installed, no tour record.
  await page.goto('/decks')
  await page.getByRole('button', { name: 'Skip tour' }).click()
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await deck.getByRole('button', { name: 'Install' }).click()
  await expect(deck).toHaveAttribute('data-installed', 'true')
  await page.evaluate(() => localStorage.removeItem('recall:onboarded'))

  await page.goto('/')
  await expect(page.getByTestId('count-new')).toHaveText('3')
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect.poll(() => page.evaluate(() => localStorage.getItem('recall:onboarded'))).toBe('1')
})
