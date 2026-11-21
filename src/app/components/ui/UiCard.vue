<script setup lang="ts">
withDefaults(
  defineProps<{
    /** The element to render, e.g. "article" for a flashcard. */
    as?: string
  }>(),
  { as: 'div' },
)
</script>

<template>
  <component :is="as" class="card"><slot /></component>
</template>

<style scoped>
.card {
  display: flex;
  flex-direction: column;
  gap: var(--space-6);
  padding: var(--space-10);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface);
  box-shadow: var(--shadow-card);
}

@media (max-width: 600px) {
  .card {
    padding: var(--space-6);
  }
}
</style>
