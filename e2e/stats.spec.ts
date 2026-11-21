import { DeckSchema } from '../src/schema/deck'
import { expectNoA11yViolations } from './support/a11y'
import { fixtureDeck } from './support/fixtures'
import { expect, test } from './support/test'

const DAY = 24 * 60 * 60 * 1000

test('stats are computed from the stored review log', async ({ page }) => {
  // Open the app once so it creates its database, then add history to it.
  await page.goto('/settings')
  await expect(page.getByRole('button', { name: 'Export backup' })).toBeEnabled()
  const deck = DeckSchema.parse(fixtureDeck())
  const option = deck.options[0]!
  const cardId = `${deck.tool}:${deck.variant}:${option.id}:flag-to-meaning`
  await page.evaluate(
    ({ deck, option, cardId, DAY }) =>
      new Promise<void>((resolve, reject) => {
        const request = indexedDB.open('recall')
        request.onerror = () => reject(request.error)
        request.onsuccess = () => {
          const now = Date.now()
          const fsrs = (scheduledDays: number, due: number) => ({
            phase: 'review',
            due,
            stability: 30,
            difficulty: 5,
            elapsedDays: scheduledDays,
            scheduledDays,
            learningSteps: 0,
            reps: 4,
            lapses: 0,
            lastReview: now,
          })
          const tx = request.result.transaction(['decks', 'cardStates', 'reviewLog'], 'readwrite')
          tx.objectStore('decks').put({
            id: deck.id,
            deckVersion: deck.deckVersion,
            installedAt: now,
            updatedAt: now,
            includeObscure: false,
            deck,
          })
          tx.objectStore('cardStates').put({
            cardId,
            deckId: deck.id,
            optionId: option.id,
            suspended: false,
            fsrs: fsrs(30, now + 3 * DAY),
          })
          // One mature review a day for three days, the last one failed.
          for (const [ago, rating] of [
            [2, 3],
            [1, 3],
            [0, 1],
          ]) {
            tx.objectStore('reviewLog').add({
              cardId,
              deckId: deck.id,
              reviewedAt: now - ago! * DAY,
              rating,
              durationMs: 2000,
              before: fsrs(30, now),
              after: fsrs(30, now + DAY),
            })
          }
          tx.oncomplete = () => {
            request.result.close()
            resolve()
          }
          tx.onerror = () => reject(tx.error)
        }
      }),
    { deck, option, cardId, DAY },
  )

  await page.goto('/stats')
  await expect(page.getByTestId('streak')).toContainText('3')
  await expect(page.getByTestId('retention')).toContainText('67%')
  await expect(page.getByTestId('retention')).toContainText('2 of 3 mature reviews passed')
  await expect(page.getByText('1 card due in the next 30 days')).toBeVisible()
  await expect(page.getByText('3 reviews on 3 of the last 365 days')).toBeVisible()
  await expect(page.getByRole('row', { name: `${deck.tool} (${deck.variant})` })).toBeVisible()
  await expectNoA11yViolations(page)
})
