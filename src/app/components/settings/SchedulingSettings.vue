<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'

import {
  normalizeSchedulingSetting,
  SCHEDULING_LIMITS,
  type SchedulingSettingKey,
} from '@/core/scheduler'
import { SETTING_DEFAULTS } from '@/core/storage'

import { useRepository } from '../../repository'

const repository = useRepository()
const loaded = ref(false)

const values = reactive<Record<SchedulingSettingKey, number>>({
  desiredRetention: SETTING_DEFAULTS.desiredRetention,
  newCardsPerDay: SETTING_DEFAULTS.newCardsPerDay,
  maxReviewsPerDay: SETTING_DEFAULTS.maxReviewsPerDay,
  dayRolloverHour: SETTING_DEFAULTS.dayRolloverHour,
})

const fields: { key: SchedulingSettingKey; label: string; hint: string }[] = [
  {
    key: 'desiredRetention',
    label: 'Desired retention',
    hint: 'How likely you should be to remember a card when it comes up. Higher means more reviews.',
  },
  { key: 'newCardsPerDay', label: 'New cards per day', hint: 'Across all decks.' },
  {
    key: 'maxReviewsPerDay',
    label: 'Maximum reviews per day',
    hint: 'Reviews past this wait for tomorrow.',
  },
  {
    key: 'dayRolloverHour',
    label: 'New day starts at',
    hint: 'Hour of the day (0–23), so late-night study counts toward the day before.',
  },
]

onMounted(async () => {
  const stored = await repository.settings.getAll()
  for (const { key } of fields) values[key] = stored[key]
  loaded.value = true
})

async function save(key: SchedulingSettingKey, event: Event) {
  const input = event.target as HTMLInputElement
  const value = normalizeSchedulingSetting(key, input.valueAsNumber)
  if (value === undefined) {
    input.value = String(values[key])
    return
  }
  values[key] = value
  input.value = String(value)
  await repository.settings.set(key, value)
}
</script>

<template>
  <section class="setting" aria-labelledby="scheduling-heading" :aria-busy="!loaded">
    <h2 id="scheduling-heading">Scheduling</h2>
    <div v-for="field in fields" :key="field.key" class="field">
      <label :for="`setting-${field.key}`">{{ field.label }}</label>
      <input
        :id="`setting-${field.key}`"
        :value="values[field.key]"
        :min="SCHEDULING_LIMITS[field.key].min"
        :max="SCHEDULING_LIMITS[field.key].max"
        :step="SCHEDULING_LIMITS[field.key].step"
        :disabled="!loaded"
        :aria-describedby="`setting-${field.key}-hint`"
        type="number"
        inputmode="decimal"
        class="mono"
        @change="save(field.key, $event)"
      />
      <p :id="`setting-${field.key}-hint`" class="hint">{{ field.hint }}</p>
    </div>
  </section>
</template>

<style scoped>
.setting {
  display: flex;
  flex-direction: column;
  gap: var(--space-5);
}

h2 {
  margin: 0;
  font-size: var(--text-md);
  font-weight: 600;
}

.field {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: var(--space-1) var(--space-4);
  align-items: center;
}

label {
  font-size: var(--text-sm);
}

input {
  width: 7ch;
  min-height: 40px;
  padding: 0 var(--space-3);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-small);
  background: var(--color-surface);
  color: var(--color-text);
  font-size: var(--text-sm);
  text-align: right;
}

input:focus-visible {
  outline: var(--focus-ring-width) solid var(--color-focus);
  outline-offset: var(--focus-ring-offset);
}

.hint {
  grid-column: 1 / -1;
  margin: 0;
  max-width: 60ch;
  color: var(--color-muted);
  font-size: var(--text-xs);
}
</style>
