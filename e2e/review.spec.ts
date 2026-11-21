import { readStore } from './support/storage'
import { expect, test } from './support/test'

const DB = 'recall'

test('review cards, reload, and find progress and counts unchanged', async ({ page }) => {
  await page.goto('/decks')
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await deck.getByRole('button', { name: 'Install' }).click()
  await expect(deck).toHaveAttribute('data-installed', 'true')

  await page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Review' }).click()
  const newCount = page.getByTestId('count-new')
  // Three core and common options; the obscure one is left out by default.
  await expect(newCount).toHaveText('3')

  // Keyboard: Space reveals, 3 grades Good.
  const first = await page.locator('[data-card]').getAttribute('data-card')
  await page.keyboard.press('Space')
  await expect(page.getByTestId('back')).toBeVisible()
  await page.keyboard.press('3')
  await expect(page.locator('[data-card]')).not.toHaveAttribute('data-card', first!)
  await expect(newCount).toHaveText('2')

  // Buttons work too.
  await page.getByRole('button', { name: /Show answer/ }).click()
  await page.getByRole('button', { name: /^Easy, next in/ }).click()
  await expect(newCount).toHaveText('1')

  // Undo takes the last grade back.
  await page.keyboard.press('u')
  await expect(newCount).toHaveText('2')
  await page.keyboard.press('Space')
  await page.keyboard.press('4')
  await expect(newCount).toHaveText('1')

  await expect.poll(async () => (await readStore(page, DB, 'reviewLog')).length).toBe(2)
  await page.reload()
  await expect(newCount).toHaveText('1')
  expect(await readStore(page, DB, 'reviewLog')).toHaveLength(2)
  expect(await readStore(page, DB, 'cardStates')).toHaveLength(2)
})

test('grade the last card and see when the next review is', async ({ page }) => {
  await page.goto('/decks')
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await deck.getByRole('button', { name: 'Install' }).click()
  await expect(deck).toHaveAttribute('data-installed', 'true')
  await page.goto('/')
  await expect(page.getByTestId('count-new')).toHaveText('3')

  for (let i = 0; i < 3; i++) {
    await page.keyboard.press('Space')
    await page.keyboard.press('4')
  }
  const done = page.getByTestId('done')
  await expect(done).toContainText('All done for today')
  await expect(done).toContainText('Your next review is')
})

test('suspend a card while reviewing, then unsuspend it from the deck', async ({ page }) => {
  await page.goto('/decks')
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await deck.getByRole('button', { name: 'Install' }).click()
  await expect(deck).toHaveAttribute('data-installed', 'true')
  await page.goto('/')
  await expect(page.getByTestId('count-new')).toHaveText('3')

  const first = await page.locator('[data-card]').getAttribute('data-card')
  await page.keyboard.press('s')
  await expect(page.getByTestId('notice')).toContainText('Card suspended.')
  await expect(page.locator('[data-card]')).not.toHaveAttribute('data-card', first!)

  await page.goto('/decks/ripgrep-fixture')
  const row = page.locator('[data-suspended]')
  await expect(row).toHaveCount(1)
  await row.getByRole('button', { name: 'Unsuspend' }).click()
  await expect(row).toHaveCount(0)

  await page.goto('/')
  await expect(page.locator('[data-card]')).toHaveAttribute('data-card', first!)
})

test('keyboard hints show with a mouse and hide on a touch screen', async ({ page, isMobile }) => {
  await page.goto('/decks')
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await deck.getByRole('button', { name: 'Install' }).click()
  await expect(deck).toHaveAttribute('data-installed', 'true')
  await page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Review' }).click()

  const reveal = page.getByRole('button', { name: /Show answer/ })
  await expect(reveal).toBeVisible()
  const hints = [
    page.getByRole('button', { name: 'Keyboard shortcuts' }),
    reveal.locator('kbd'),
    page.getByRole('button', { name: /^Bury/ }).locator('kbd'),
  ]
  for (const hint of hints) {
    if (isMobile) await expect(hint).toBeHidden()
    else await expect(hint).toBeVisible()
  }
})
