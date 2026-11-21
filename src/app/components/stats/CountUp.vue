<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from 'vue'

import { useReducedMotion } from '../../motion/useReducedMotion'

const props = withDefaults(
  defineProps<{
    value: number
    /** Formats the in-between and final number, e.g. as a percentage. */
    format?: (value: number) => string
  }>(),
  { format: (value: number) => String(Math.round(value)) },
)

/** Long enough to read as counting, short enough not to hold anyone up. */
const DURATION_MS = 500

const reduced = useReducedMotion()
const shown = ref(reduced.value ? props.value : 0)
let frame: number | undefined

watch(
  () => props.value,
  (target) => {
    if (frame !== undefined) cancelAnimationFrame(frame)
    if (reduced.value || typeof requestAnimationFrame === 'undefined') {
      shown.value = target
      return
    }
    const from = shown.value
    const start = performance.now()
    const tick = (time: number) => {
      const t = Math.min(1, (time - start) / DURATION_MS)
      const eased = 1 - (1 - t) ** 3
      shown.value = from + (target - from) * eased
      frame = t < 1 ? requestAnimationFrame(tick) : undefined
    }
    frame = requestAnimationFrame(tick)
  },
  { immediate: true },
)

onBeforeUnmount(() => {
  if (frame !== undefined) cancelAnimationFrame(frame)
})
</script>

<template>
  <!-- Screen readers get the final value straight away, not every step. -->
  <span aria-hidden="true">{{ format(shown) }}</span>
  <span class="visually-hidden">{{ format(value) }}</span>
</template>
