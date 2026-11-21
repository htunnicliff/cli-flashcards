import { mount } from '@vue/test-utils'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { exportBackup } from '@/core/backup'
import { createRepository, type Repository } from '@/core/storage'
import {
  fakeIndexedDB,
  makeCardState,
  makeLogEntry,
  uniqueDatabaseName,
} from '@/core/storage/test-utils'

import { repositoryKey } from '../../repository'
import BackupSettings from './BackupSettings.vue'

vi.mock('./backup-file', () => ({ saveBackupFile: vi.fn(async () => 'downloaded') }))
const { saveBackupFile } = await import('./backup-file')

let repo: Repository

beforeEach(() => {
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})

afterEach(async () => {
  vi.mocked(saveBackupFile).mockClear()
  await repo.destroy()
})

async function mountLoaded() {
  const wrapper = mount(BackupSettings, { global: { provide: { [repositoryKey]: repo } } })
  await vi.waitFor(() => wrapper.get('[data-test="last-backup"]'))
  return wrapper
}

async function choose(wrapper: Awaited<ReturnType<typeof mountLoaded>>, contents: string) {
  const input = wrapper.get<HTMLInputElement>('[data-test="import-file"]')
  const file = new File([contents], 'recall-backup.json', { type: 'application/json' })
  Object.defineProperty(input.element, 'files', { value: [file], configurable: true })
  await input.trigger('change')
}

describe('BackupSettings', () => {
  it('exports a backup and updates the last-backup reminder', async () => {
    await repo.reviewLog.append(makeLogEntry('grep:gnu:ignore-case:cloze'))
    const wrapper = await mountLoaded()
    expect(wrapper.get('[data-test="last-backup"]').text()).toBe('No backup yet.')

    await wrapper
      .findAll('button')
      .find((b) => b.text() === 'Export backup')!
      .trigger('click')
    await vi.waitFor(() => expect(saveBackupFile).toHaveBeenCalled())
    const [json, name] = vi.mocked(saveBackupFile).mock.calls[0]!
    expect(JSON.parse(json).reviewLog).toHaveLength(1)
    expect(name).toMatch(/^recall-backup-\d{4}-\d{2}-\d{2}\.json$/)
    await vi.waitFor(() =>
      expect(wrapper.get('[data-test="last-backup"]').text()).toBe('Last backup: today.'),
    )
  })

  it('shows days since the last backup', async () => {
    await repo.settings.set('lastBackupAt', Date.now() - 3.5 * 24 * 60 * 60 * 1000)
    const wrapper = await mountLoaded()
    expect(wrapper.get('[data-test="last-backup"]').text()).toBe('Last backup: 3 days ago.')
  })

  it('summarises a chosen backup, then merges it', async () => {
    const source = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
    const cardId = 'grep:gnu:ignore-case:cloze'
    await source.recordReview(makeCardState(cardId), makeLogEntry(cardId, { reviewedAt: 1 }))
    const json = JSON.stringify(await exportBackup(source, 2))
    await source.destroy()

    const wrapper = await mountLoaded()
    await choose(wrapper, json)
    await vi.waitFor(() => wrapper.get('[data-testid="import-summary"]'))
    expect(wrapper.get('[data-testid="import-summary"]').text()).toContain('1 card')
    expect(wrapper.get('[data-testid="import-summary"]').text()).toContain('1 review from')

    await wrapper
      .findAll('button')
      .find((b) => b.text() === 'Merge')!
      .trigger('click')
    await vi.waitFor(() => expect(wrapper.get('[role="status"]').text()).toBe('Merged 1 review.'))
    expect(await repo.cardStates.get(cardId)).toBeDefined()
    expect(wrapper.find('[data-testid="import-summary"]').exists()).toBe(false)
  })

  it('explains why a file was rejected', async () => {
    const wrapper = await mountLoaded()
    await choose(wrapper, '{"hello": "world"}')
    await vi.waitFor(() =>
      expect(wrapper.get('[role="alert"]').text()).toBe('This file isn’t a --recall backup.'),
    )
  })
})
