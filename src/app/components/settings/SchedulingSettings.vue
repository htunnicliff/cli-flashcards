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
  leechThreshold: SETTING_DEFAULTS.leechThreshold,
})

type Field = { key: SchedulingSettingKey; label: string; hint: string }

/** The one setting most people change: how fast new flags arrive. */
const mainField: Field = {
  key: 'newCardsPerDay',
  label: 'New cards per day',
  hint: 'Across all decks. Lower it for shorter daily sessions.',
}

/** Tuning for people who know spaced repetition; the defaults suit everyone else. */
const advancedFields: Field[] = [
  {
    key: 'desiredRetention',
    label: 'Desired retention',
    hint: 'How likely you should be to remember a card when it comes up. Higher means more reviews.',
  },
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
  {
    key: 'leechThreshold',
    label: 'Suspend hard cards after',
    hint: "Times you can forget a card before it's suspended so it stops slowing you down. Find these cards in the deck's options.",
  },
]

const fields = [mainField, ...advancedFields]

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
    <div v-for="field in [mainField]" :key="field.key" class="field">
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
    <details class="advanced">
      <summary>Advanced</summary>
      <div class="advanced-fields">
        <div v-for="field in advancedFields" :key="field.key" class="field">
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
      </div>
    </details>
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
  /* Room for "0.95" or "9999" plus the browser's spin buttons. */
  width: 11ch;
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

.advanced summary {
  min-height: 44px;
  display: flex;
  align-items: center;
  font-size: var(--text-sm);
  font-weight: 600;
  cursor: pointer;
}

.advanced summary::before {
  content: '▸';
  margin-right: var(--space-2);
  color: var(--color-muted);
  font-size: var(--text-xs);
}

.advanced[open] summary::before {
  content: '▾';
}

.advanced summary::-webkit-details-marker {
  display: none;
}

.advanced-fields {
  display: flex;
  flex-direction: column;
  gap: var(--space-5);
  padding-top: var(--space-2);
}

.hint {
  grid-column: 1 / -1;
  margin: 0;
  max-width: 60ch;
  color: var(--color-muted);
  font-size: var(--text-xs);
}
</style>
