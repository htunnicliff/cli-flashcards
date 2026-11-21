import { expect, test } from './support/test'

test('the Reduce motion setting overrides the OS and survives a reload', async ({ page }) => {
  await page.goto('/settings')
  const group = page.getByRole('group', { name: 'Reduce motion' })
  await expect(group.getByRole('radio', { name: 'System' })).toBeChecked()

  await group.getByRole('radio', { name: 'Off' }).check()
  await expect(page.locator('html')).toHaveAttribute('data-motion', 'full')

  await page.reload()
  await expect(group.getByRole('radio', { name: 'Off' })).toBeChecked()
  await expect(page.locator('html')).toHaveAttribute('data-motion', 'full')
})
