<script setup lang="ts">
withDefaults(
  defineProps<{
    /** Set in Recursive Mono, for tool names and flags. */
    mono?: boolean
  }>(),
  { mono: false },
)
</script>

<template>
  <span :class="['chip', { mono }]"><slot /></span>
</template>

<style scoped>
.chip {
  display: inline-flex;
  align-items: center;
  gap: var(--space-1);
  padding: var(--space-1) 10px;
  border-radius: var(--radius-pill);
  background: var(--color-sunken);
  color: var(--color-text);
  font-size: var(--text-xs);
  font-weight: 600;
  line-height: 1.4;
  white-space: nowrap;
}
</style>
