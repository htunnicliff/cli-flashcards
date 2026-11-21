<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'

import { formatBytes, getStorageReport, type StorageReport } from '@/core/storage'

import { useRepository } from '../../repository'

const repository = useRepository()
const report = ref<StorageReport>()

onMounted(async () => {
  const storage = typeof navigator === 'undefined' ? undefined : navigator.storage
  report.value = await getStorageReport(repository, storage)
})

const usageText = computed(() => {
  const usage = report.value?.usage
  if (usage === undefined) return undefined
  const quota = report.value?.quota
  return quota === undefined
    ? `Using about ${formatBytes(usage)}.`
    : `Using about ${formatBytes(usage)} of ${formatBytes(quota)} available.`
})

const persistenceText: Record<StorageReport['persistence'], string> = {
  persistent: 'Your progress is stored persistently, so the browser won’t clear it to save space.',
  denied:
    'The browser didn’t agree to keep your data persistently, so it may clear it if space runs low. Export a backup now and then.',
  'not-requested':
    'After your first review session, we’ll ask the browser to keep your progress persistently.',
  unsupported:
    'This browser can’t keep data persistently, so it may clear it if space runs low. Export a backup now and then.',
}
</script>

<template>
  <section class="setting" aria-labelledby="storage-heading">
    <h2 id="storage-heading">Storage</h2>
    <template v-if="report">
      <p data-test="persistence" :data-status="report.persistence">
        {{ persistenceText[report.persistence] }}
      </p>
      <p v-if="usageText" data-test="usage" class="hint">{{ usageText }}</p>
    </template>
    <p v-else class="hint">Checking storage…</p>
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
</style>
