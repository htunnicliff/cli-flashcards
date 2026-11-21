<script setup lang="ts">
import { m } from 'motion-v'
import { computed, ref } from 'vue'

import { heatLevel, type DayCount } from '@/core/stats'

import { fade } from '../../motion/tokens'
import { useReducedMotion } from '../../motion/useReducedMotion'

const props = defineProps<{ days: DayCount[] }>()

const reduced = useReducedMotion()
const hovered = ref<DayCount>()
const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' })

const max = computed(() => Math.max(0, ...props.days.map((d) => d.count)))
const activeDays = computed(() => props.days.filter((d) => d.count > 0).length)
const total = computed(() => props.days.reduce((sum, d) => sum + d.count, 0))
/** Rows are weekdays, Sunday first, so the first column starts on the right row. */
const leading = computed(() => (props.days[0] ? new Date(props.days[0].day).getDay() : 0))

const describe = (day: DayCount) =>
  `${dateFormat.format(day.day)}: ${day.count} ${day.count === 1 ? 'review' : 'reviews'}`

const summary = computed(
  () =>
    `${total.value} ${total.value === 1 ? 'review' : 'reviews'} on ${activeDays.value} of the last ${props.days.length} days`,
)
</script>

<template>
  <figure class="heatmap">
    <p class="readout" aria-live="polite">{{ hovered ? describe(hovered) : summary }}</p>
    <div class="scroller" tabindex="0" role="region" aria-label="Review history, scrolls sideways">
      <m.div
        class="grid"
        role="img"
        :aria-label="summary"
        :initial="reduced ? false : { opacity: 0 }"
        :animate="{ opacity: 1 }"
        :transition="fade.base"
        @mouseleave="hovered = undefined"
      >
        <span v-for="n in leading" :key="`pad-${n}`" class="cell pad" />
        <span
          v-for="day in days"
          :key="day.day"
          class="cell"
          :data-level="heatLevel(day.count, max)"
          :title="describe(day)"
          @mouseenter="hovered = day"
        />
      </m.div>
    </div>
    <div class="legend" aria-hidden="true">
      <span>Less</span>
      <span v-for="level in 5" :key="level" class="cell" :data-level="level - 1" />
      <span>More</span>
    </div>
  </figure>
</template>

<style scoped>
.heatmap {
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

.scroller {
  overflow-x: auto;
  /* Newest days are on the right; start scrolled there on narrow screens. */
  direction: rtl;
}

.grid {
  direction: ltr;
  display: grid;
  grid-template-rows: repeat(7, 11px);
  grid-auto-flow: column;
  grid-auto-columns: 11px;
  gap: 2px;
  width: max-content;
}

.cell {
  display: inline-block;
  width: 11px;
  height: 11px;
  border-radius: 2px;
  background: var(--color-sunken);
}

.cell.pad {
  visibility: hidden;
}

/* One hue, light to dark: the accent mixed into the sunken surface. */
.cell[data-level='1'] {
  background: color-mix(in oklab, var(--color-accent) 30%, var(--color-sunken));
}
.cell[data-level='2'] {
  background: color-mix(in oklab, var(--color-accent) 55%, var(--color-sunken));
}
.cell[data-level='3'] {
  background: color-mix(in oklab, var(--color-accent) 78%, var(--color-sunken));
}
.cell[data-level='4'] {
  background: var(--color-accent);
}

.legend {
  display: flex;
  align-items: center;
  gap: 3px;
  align-self: flex-end;
  color: var(--color-muted);
  font-size: var(--text-xs);
}

.legend span:first-child {
  margin-right: var(--space-1);
}

.legend span:last-child {
  margin-left: var(--space-1);
}
</style>
