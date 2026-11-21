<script setup lang="ts">
import { m } from 'motion-v'

import { presets } from '../motion/tokens'
import { useOnline } from './online'

const online = useOnline()
</script>

<template>
  <span class="offline-region" aria-live="polite">
    <AnimatePresence>
      <m.span
        v-if="!online"
        class="offline"
        title="You're offline. Reviews still work; new decks and updates download when you're back online."
        v-bind="presets.fade"
      >
        <span class="dot" aria-hidden="true"></span>Offline
      </m.span>
    </AnimatePresence>
  </span>
</template>

<style scoped>
.offline {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-1) 10px;
  border-radius: var(--radius-pill);
  background: var(--color-sunken);
  color: var(--color-text);
  font-size: var(--text-xs);
  font-weight: 600;
  white-space: nowrap;
}

.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--color-muted);
}
</style>
