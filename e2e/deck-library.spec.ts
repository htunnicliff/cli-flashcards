import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { DeckSchema } from '../src/schema/deck'
import { manifestEntry } from '../src/schema/manifest'
import { readStore } from './support/storage'
import { expect, test } from './support/test'

const v2Text = readFileSync(
  fileURLToPath(new URL('./fixtures/updates/ripgrep-fixture.v2.json', import.meta.url)),
  'utf8',
)
const v2 = DeckSchema.parse(JSON.parse(v2Text))

const DB = 'recall'

// These tests swap deck files with page.route(), which doesn't see requests the service
// worker answers. Once the worker controls the page (after the reload below), the route
// would race the worker, so keep it out of the way here; e2e/offline.spec.ts covers it.
test.use({ serviceWorkers: 'block' })

interface StoredCardState {
  cardId: string
  fsrs: { phase: string; reps: number }
}

test('decks download and update on their own without losing progress', async ({ page }) => {
  await page.goto('/decks')
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await expect(deck).toContainText('4 options')
  await expect(deck).toHaveAttribute('data-installed', 'true')
  await expect(deck).toHaveAttribute('data-studying', 'true')
  await expect(page.getByRole('status').first()).toHaveText('Downloaded rg.')

  // Progress on one unchanged card, as a review would leave it.
  await page.evaluate((name) => {
    return new Promise<void>((resolve, reject) => {
      const request = indexedDB.open(name)
      request.onerror = () => reject(request.error)
      request.onsuccess = () => {
        const db = request.result
        const tx = db.transaction('cardStates', 'readwrite')
        tx.objectStore('cardStates').put({
          cardId: 'rg:fixture:short-i:flag-to-meaning',
          deckId: 'ripgrep-fixture',
          optionId: 'short-i',
          suspended: false,
          fsrs: {
            phase: 'review',
            due: Date.now() + 86_400_000,
            stability: 4,
            difficulty: 5,
            elapsedDays: 1,
            scheduledDays: 4,
            learningSteps: 0,
            reps: 3,
            lapses: 0,
          },
        })
        tx.oncomplete = () => {
          db.close()
          resolve()
        }
        tx.onerror = () => reject(tx.error)
      }
    })
  }, DB)

  // Publish version 2: adds -v, removes --color.
  await page.route('**/decks/index.json', (route) =>
    route.fulfill({
      json: {
        manifestVersion: 1,
        decks: [manifestEntry(v2, 'ripgrep-fixture.json', v2Text.length)],
      },
    }),
  )
  await page.route('**/decks/ripgrep-fixture.json', (route) =>
    route.fulfill({ body: v2Text, contentType: 'application/json' }),
  )
  await page.reload()

  await expect(page.getByRole('status').first()).toHaveText(
    'Updated rg to version 2: 1 option added, 1 removed.',
  )

  const states = await readStore<StoredCardState>(page, DB, 'cardStates')
  expect(states).toEqual([
    expect.objectContaining({
      cardId: 'rg:fixture:short-i:flag-to-meaning',
      fsrs: expect.objectContaining({ reps: 3 }),
    }),
  ])

  // The browse view reflects the new version and the kept progress.
  await deck.getByRole('link', { name: 'Browse options' }).click()
  await expect(page.locator('[data-option]')).toHaveCount(4)
  await expect(page.locator('[data-option="short-v"]')).toBeVisible()
  await expect(page.locator('[data-option="long-color"]')).toHaveCount(0)
  await expect(page.locator('[data-option="short-i"] [data-status]')).toHaveText('Learned')

  await page.getByRole('searchbox', { name: 'Search options' }).fill('--inv')
  await expect(page.locator('[data-option]')).toHaveCount(1)
})

test('a paused deck shows no cards until it is turned back on', async ({ page }) => {
  await page.goto('/decks')
  const deck = page.locator('[data-deck="ripgrep-fixture"]')
  await expect(deck).toHaveAttribute('data-installed', 'true')
  await deck.getByRole('checkbox', { name: 'Study this deck' }).uncheck()
  await expect(deck).toHaveAttribute('data-studying', 'false')
  await expect(deck).toContainText('Paused')

  await page.goto('/')
  await expect(page.getByTestId('done')).toBeVisible()
  await expect(page.locator('[data-card]')).toHaveCount(0)

  await page.goto('/decks')
  await deck.getByRole('checkbox', { name: 'Study this deck' }).check()
  await page.getByTestId('start-reviewing').click()
  await expect(page.getByTestId('count-new')).toHaveText('3')
})
