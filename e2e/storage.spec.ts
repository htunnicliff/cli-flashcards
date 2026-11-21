import { readStore, seedIndexedDB } from './support/storage'
import { expect, test } from './support/test'

test.describe.serial('fresh storage', () => {
  test('a test leaves data behind', async ({ page }) => {
    await seedIndexedDB(page, { name: 'e2e-leftover', version: 1, stores: { items: {} } })
    await page.evaluate(() => localStorage.setItem('e2e-leftover', '1'))
  })

  test('the next test does not see it', async ({ page }) => {
    await page.goto('/')
    const state = await page.evaluate(async () => ({
      databases: (await indexedDB.databases()).map((db) => db.name),
      leftover: localStorage.getItem('e2e-leftover'),
    }))
    expect(state.databases).not.toContain('e2e-leftover')
    expect(state.leftover).toBeNull()
  })
})

test('seedIndexedDB writes records the app origin can read', async ({ page }) => {
  await seedIndexedDB(page, {
    name: 'e2e-seed-check',
    version: 1,
    stores: {
      items: {
        keyPath: 'id',
        records: [
          { id: 'a', n: 1 },
          { id: 'b', n: 2 },
        ],
      },
    },
  })
  await page.goto('/')
  const items = await readStore<{ id: string; n: number }>(page, 'e2e-seed-check', 'items')
  expect(items).toEqual([
    { id: 'a', n: 1 },
    { id: 'b', n: 2 },
  ])
})
