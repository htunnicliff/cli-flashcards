<script setup lang="ts">
import { computed, onMounted, ref, shallowRef } from 'vue'

import {
  backupFileName,
  BackupError,
  daysSinceBackup,
  exportBackup,
  importBackup,
  parseBackup,
  summarizeBackup,
  type Backup,
  type ImportMode,
} from '@/core/backup'

import type { FetchLike } from '../../decks/catalog'
import { installPendingDecks } from '../../decks/pending'
import { holdUpdatesWhile } from '../../pwa/update-holds'
import { useRepository } from '../../repository'
import { UiButton } from '../ui'
import { saveBackupFile } from './backup-file'

const props = defineProps<{ deckFetch?: FetchLike }>()

const repository = useRepository()
const lastBackupAt = ref<number | null>()
const exportMessage = ref('')
// Shallow: IndexedDB can't store Vue's reactive proxies, so the backup stays a plain object.
const pending = shallowRef<{ backup: Backup; fileName: string }>()
const importError = ref('')
const importMessage = ref('')
const busy = ref(false)
const fileInput = ref<HTMLInputElement>()

onMounted(async () => {
  lastBackupAt.value = await repository.settings.get('lastBackupAt')
})

const lastBackupText = computed(() => {
  if (lastBackupAt.value === undefined) return ''
  const days = daysSinceBackup(lastBackupAt.value, Date.now())
  if (days === undefined) return 'No backup yet.'
  if (days === 0) return 'Last backup: today.'
  return `Last backup: ${days} ${days === 1 ? 'day' : 'days'} ago.`
})

const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' })

const summary = computed(() => {
  if (!pending.value) return undefined
  const s = summarizeBackup(pending.value.backup)
  const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
  const range =
    s.firstReview === undefined
      ? 'no reviews'
      : `${plural(s.reviews, 'review')} from ${dateFormat.format(s.firstReview)} to ${dateFormat.format(s.lastReview!)}`
  return {
    decks: s.decks.length ? s.decks.join(', ') : 'none',
    reviews: range,
    cards: plural(s.cards, 'card'),
    exportedAt: dateFormat.format(s.exportedAt),
  }
})

// Don't reload into a new version mid-export, mid-import, or with a backup chosen to import.
holdUpdatesWhile(() => busy.value || pending.value !== undefined)

async function onExport() {
  busy.value = true
  exportMessage.value = ''
  try {
    const now = Date.now()
    const backup = await exportBackup(repository, now)
    const outcome = await saveBackupFile(JSON.stringify(backup, null, 2), backupFileName(now))
    lastBackupAt.value = now
    exportMessage.value = outcome === 'cancelled' ? 'Export cancelled.' : 'Backup saved.'
  } finally {
    busy.value = false
  }
}

async function onFileChosen(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  importError.value = ''
  importMessage.value = ''
  pending.value = undefined
  if (!file) return
  try {
    pending.value = { backup: parseBackup(await file.text()), fileName: file.name }
  } catch (error) {
    importError.value = error instanceof BackupError ? error.message : 'This file couldn’t be read.'
  }
}

/** Installs the decks the backup used right away, so Review has them without a trip to Decks. */
async function installBackupDecks(): Promise<string> {
  let installed: string[] = []
  let remaining = (await repository.settings.get('pendingDeckInstalls')).map((d) => d.id)
  try {
    const result = await installPendingDecks(repository, { fetch: props.deckFetch })
    installed = result.installed.map((d) => d.id)
    remaining = result.remaining.map((d) => d.id)
  } catch {
    // Offline or the deck list failed to load: everything stays queued.
  }
  return [
    installed.length ? `Installed ${installed.join(', ')}.` : '',
    remaining.length
      ? `${remaining.join(', ')} will be installed when the deck library can reach ${remaining.length === 1 ? 'it' : 'them'}.`
      : '',
  ]
    .filter(Boolean)
    .join(' ')
}

async function onImport(mode: ImportMode) {
  if (!pending.value) return
  busy.value = true
  try {
    const result = await importBackup(repository, pending.value.backup, mode)
    const reviews = `${result.addedReviews} ${result.addedReviews === 1 ? 'review' : 'reviews'}`
    pending.value = undefined
    importMessage.value =
      mode === 'replace' ? `Progress replaced with ${reviews}.` : `Merged ${reviews}.`
    if (result.pendingDecks.length > 0) {
      importMessage.value += ' ' + (await installBackupDecks())
    }
  } catch {
    importError.value = 'Import failed, so nothing was changed.'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <section class="setting" aria-labelledby="backup-heading">
    <h2 id="backup-heading">Backup</h2>
    <p class="hint">
      Your progress lives only in this browser. Export a backup to keep it safe or move it to
      another device.
    </p>
    <p v-if="lastBackupText" data-test="last-backup" class="hint">{{ lastBackupText }}</p>

    <div class="actions">
      <UiButton :disabled="busy" @click="onExport">Export backup</UiButton>
      <UiButton :disabled="busy" @click="fileInput?.click()">Import backup…</UiButton>
      <input
        ref="fileInput"
        type="file"
        accept="application/json,.json"
        class="visually-hidden"
        tabindex="-1"
        aria-label="Backup file to import"
        data-test="import-file"
        @change="onFileChosen"
      />
    </div>
    <p v-if="exportMessage" role="status" class="hint">{{ exportMessage }}</p>

    <div v-if="pending && summary" class="summary" data-testid="import-summary">
      <p>
        <strong>{{ pending.fileName }}</strong>, exported {{ summary.exportedAt }}
      </p>
      <dl>
        <dt>Decks</dt>
        <dd>{{ summary.decks }}</dd>
        <dt>Cards</dt>
        <dd>{{ summary.cards }}</dd>
        <dt>History</dt>
        <dd>{{ summary.reviews }}</dd>
      </dl>
      <p class="hint">
        <strong>Merge</strong> adds reviews this browser doesn’t have and keeps the newer progress
        for each card. <strong>Replace</strong> discards this browser’s progress first.
      </p>
      <div class="actions">
        <UiButton variant="primary" :disabled="busy" @click="onImport('merge')">Merge</UiButton>
        <UiButton variant="again" :disabled="busy" @click="onImport('replace')">Replace</UiButton>
        <UiButton :disabled="busy" @click="pending = undefined">Cancel</UiButton>
      </div>
    </div>
    <p v-if="importError" role="alert" class="error">{{ importError }}</p>
    <p v-if="importMessage" role="status">{{ importMessage }}</p>
  </section>
</template>

<style scoped>
.setting {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

h2 {
  margin: 0;
  font-size: var(--text-md);
  font-weight: 600;
}

p {
  margin: 0;
  max-width: 60ch;
}

.hint {
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.actions {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
}

.summary {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding: var(--space-4);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface);
}

dl {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: var(--space-1) var(--space-4);
  margin: 0;
  font-size: var(--text-sm);
}

dt {
  color: var(--color-muted);
}

dd {
  margin: 0;
  overflow-wrap: anywhere;
}

.error {
  color: var(--color-again);
}
</style>
