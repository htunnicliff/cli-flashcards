import AxeBuilder from '@axe-core/playwright'
import { expect, type Page } from '@playwright/test'

const BLOCKING_IMPACTS = new Set(['serious', 'critical'])

/** Fails the test on any serious or critical WCAG 2.1 A/AA violation on the current page. */
export async function expectNoA11yViolations(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze()

  const blocking = results.violations
    .filter((violation) => BLOCKING_IMPACTS.has(violation.impact ?? ''))
    .map((violation) => ({
      rule: violation.id,
      impact: violation.impact,
      help: violation.help,
      targets: violation.nodes.map((node) => node.target.join(' ')),
    }))

  expect(blocking, `Accessibility violations on ${page.url()}`).toEqual([])
}
