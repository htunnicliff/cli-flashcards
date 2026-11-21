import { readStore } from './support/storage'
import { expect, skipOnboarding, test } from './support/test'

const cardId = 'rg:fixture:ignore-case:flag-to-meaning'
const fsrs = {
  phase: 'review',
  due: Date.UTC(2026, 0, 10),
  stability: 4,
  difficulty: 5,
  elapsedDays: 2,
  scheduledDays: 4,
  learningSteps: 0,
  reps: 3,
  lapses: 0,
  lastReview: Date.UTC(2026, 0, 6),
}

test('a backup exported in one browser restores progress in another', async ({ browser, page }) => {
  // Seed progress straight into the app's database, as if reviews had happened.
  await page.goto('/settings')
  await expect(page.getByRole('button', { name: 'Export backup' })).toBeEnabled()
  await page.evaluate(
    ({ cardId, fsrs }) =>
      new Promise<void>((resolve, reject) => {
        const request = indexedDB.open('recall')
        request.onerror = () => reject(request.error)
        request.onsuccess = () => {
          const tx = request.result.transaction(['cardStates', 'reviewLog'], 'readwrite')
          tx.objectStore('cardStates').put({
            cardId,
            deckId: 'rg-fixture',
            optionId: 'ignore-case',
            fsrs,
            suspended: false,
          })
          tx.objectStore('reviewLog').add({
            cardId,
            deckId: 'rg-fixture',
            reviewedAt: fsrs.lastReview,
            rating: 3,
            durationMs: 3000,
            before: null,
            after: fsrs,
          })
          tx.oncomplete = () => {
            request.result.close()
            resolve()
          }
          tx.onerror = () => reject(tx.error)
        }
      }),
    { cardId, fsrs },
  )
  await page.reload()
  await expect(page.getByText('No backup yet.')).toBeVisible()

  const downloading = page.waitForEvent('download')
  await page.getByRole('button', { name: 'Export backup' }).click()
  const download = await downloading
  expect(download.suggestedFilename()).toMatch(/^recall-backup-\d{4}-\d{2}-\d{2}\.json$/)
  await expect(page.getByText('Last backup: today.')).toBeVisible()
  const file = await download.path()

  const fresh = await browser.newContext()
  await skipOnboarding(fresh)
  try {
    const other = await fresh.newPage()
    await other.goto('/settings')
    await other.getByLabel('Backup file to import').setInputFiles(file)
    const summary = other.getByTestId('import-summary')
    await expect(summary).toContainText('1 card')
    await expect(summary).toContainText('1 review from')
    await other.getByRole('button', { name: 'Merge' }).click()
    await expect(other.getByRole('status')).toContainText('Merged 1 review.')

    const states = await readStore<{ cardId: string; fsrs: unknown }>(other, 'recall', 'cardStates')
    expect(states).toEqual([expect.objectContaining({ cardId, fsrs })])
    const log = await readStore<{ cardId: string }>(other, 'recall', 'reviewLog')
    expect(log.map((e) => e.cardId)).toEqual([cardId])
  } finally {
    await fresh.close()
  }
})
