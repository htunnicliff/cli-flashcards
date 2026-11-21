<script setup lang="ts">
withDefaults(
  defineProps<{
    /** primary: the one solid button on a screen (e.g. Good). again: rose tint. neutral: everything else. */
    variant?: 'primary' | 'neutral' | 'again'
    type?: 'button' | 'submit' | 'reset'
    /** Stretch to the container's width. */
    block?: boolean
  }>(),
  { variant: 'neutral', type: 'button', block: false },
)
</script>

<template>
  <button :type="type" :class="['button', `button--${variant}`, { 'button--block': block }]">
    <slot />
  </button>
</template>

<style scoped>
.button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-3);
  min-height: 44px;
  padding: var(--space-2) var(--space-5);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-button);
  background: var(--color-surface);
  color: var(--color-text);
  font-size: var(--text-md);
  font-weight: 600;
  line-height: 1.2;
  cursor: pointer;
  transition:
    transform var(--duration-fast) var(--ease-out),
    opacity var(--duration-fast) var(--ease-out);
}

.button:active {
  transform: scale(0.98);
}

.button:disabled {
  cursor: not-allowed;
  opacity: 0.55;
}

.button--primary {
  border-color: var(--color-accent);
  background: var(--color-accent);
  color: var(--color-on-primary);
}

/* The ring sits outside the solid fill, so it is offset a little further. */
.button--primary:focus-visible {
  outline-offset: calc(var(--focus-ring-offset) + 1px);
}

.button--primary :deep(.kbd) {
  background: var(--color-kbd-on-primary);
  color: inherit;
}

.button--again {
  border-color: var(--color-again-border);
  background: var(--color-again-tint);
  color: var(--color-again);
}

.button--block {
  display: flex;
  width: 100%;
}
</style>
