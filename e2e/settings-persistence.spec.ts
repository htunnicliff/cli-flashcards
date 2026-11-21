import { readStore } from './support/storage'
import { expect, test } from './support/test'

test('scheduling settings are stored in IndexedDB and survive a reload', async ({ page }) => {
  await page.goto('/settings')
  const newCards = page.getByLabel('New cards per day')
  await expect(newCards).toBeEnabled()
  await expect(newCards).toHaveValue('20')

  await newCards.fill('7')
  await newCards.press('Tab')
  await expect
    .poll(async () => await readStore<{ key: string; value: unknown }>(page, 'recall', 'settings'))
    .toContainEqual({ key: 'newCardsPerDay', value: 7 })

  await page.reload()
  await expect(page.getByLabel('New cards per day')).toHaveValue('7')
  await expect(page.getByRole('heading', { name: 'Storage' })).toBeVisible()
})
