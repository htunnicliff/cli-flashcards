<template>
  <kbd class="kbd"><slot /></kbd>
</template>

<style scoped>
.kbd {
  display: inline-block;
  padding: 1px var(--space-2);
  border-radius: var(--radius-kbd);
  background: var(--color-kbd);
  color: inherit;
  font-size: var(--text-xs);
  font-weight: 500;
  line-height: 1.5;
  white-space: nowrap;
}
</style>
