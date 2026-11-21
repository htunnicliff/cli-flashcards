<script setup lang="ts">
import { m } from 'motion-v'
import { computed, ref } from 'vue'

import type { DayCount } from '@/core/stats'

import { spring } from '../../motion/tokens'
import { useReducedMotion } from '../../motion/useReducedMotion'

const props = defineProps<{ days: DayCount[] }>()

const reduced = useReducedMotion()
const hovered = ref<number>()
const dateFormat = new Intl.DateTimeFormat(undefined, {
  weekday: 'short',
  month: 'short',
  day: 'numeric',
})

const max = computed(() => Math.max(1, ...props.days.map((d) => d.count)))
const total = computed(() => props.days.reduce((sum, d) => sum + d.count, 0))

function label(index: number): string {
  const day = props.days[index]!
  const when = index === 0 ? 'Today' : index === 1 ? 'Tomorrow' : dateFormat.format(day.day)
  return `${when}: ${day.count} ${day.count === 1 ? 'card' : 'cards'} due`
}

const readout = computed(() =>
  hovered.value === undefined
    ? `${total.value} ${total.value === 1 ? 'card' : 'cards'} due in the next ${props.days.length} days`
    : label(hovered.value),
)
</script>

<template>
  <figure class="chart">
    <p class="readout" aria-live="polite">{{ readout }}</p>
    <div
      class="plot"
      role="list"
      :aria-label="`Cards due per day, next ${days.length} days`"
      @mouseleave="hovered = undefined"
    >
      <div
        v-for="(day, index) in days"
        :key="day.day"
        class="slot"
        role="listitem"
        :aria-label="label(index)"
        @mouseenter="hovered = index"
      >
        <m.div
          v-if="day.count > 0"
          class="bar"
          :class="{ active: hovered === index }"
          :style="{ height: `${(day.count / max) * 100}%` }"
          :initial="reduced ? false : { scaleY: 0 }"
          :animate="{ scaleY: 1 }"
          :transition="{ ...spring.gentle, delay: reduced ? 0 : index * 0.012 }"
        />
      </div>
    </div>
    <div class="axis" aria-hidden="true">
      <span>Today</span>
      <span>+{{ Math.floor(days.length / 2) }} days</span>
      <span>+{{ days.length - 1 }} days</span>
    </div>
    <figcaption class="visually-hidden">Peak: {{ max }} cards in one day.</figcaption>
  </figure>
</template>

<style scoped>
.chart {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  margin: 0;
}

.readout {
  margin: 0;
  min-height: 1.5em;
  color: var(--color-muted);
  font-size: var(--text-sm);
  font-variant-numeric: tabular-nums;
}

.plot {
  display: grid;
  grid-auto-flow: column;
  grid-auto-columns: 1fr;
  gap: 2px;
  height: 140px;
  border-bottom: var(--border-width) solid var(--color-border);
}

.slot {
  display: flex;
  align-items: flex-end;
  min-width: 0;
}

.bar {
  width: 100%;
  min-height: 3px;
  border-radius: 4px 4px 0 0;
  background: var(--color-accent);
  transform-origin: bottom;
  opacity: 0.85;
}

.bar.active {
  opacity: 1;
}

.axis {
  display: flex;
  justify-content: space-between;
  color: var(--color-muted);
  font-size: var(--text-xs);
}
</style>
