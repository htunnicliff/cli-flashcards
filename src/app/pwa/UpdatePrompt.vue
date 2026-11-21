<script setup lang="ts">
import { m } from 'motion-v'
import { ref } from 'vue'

import UiButton from '../components/ui/UiButton.vue'
import { presets } from '../motion/tokens'
import { useServiceWorker } from './service-worker'

const { needRefresh, updateServiceWorker } = useServiceWorker()
const reloading = ref(false)

function reload() {
  reloading.value = true
  void updateServiceWorker()
}
</script>

<template>
  <!-- A banner, never a modal: it must not interrupt a review in progress. -->
  <div class="update-region" role="status" aria-live="polite">
    <AnimatePresence>
      <m.div v-if="needRefresh" class="update" v-bind="presets.slideUp">
        <p class="update-text">Update available.</p>
        <div class="update-actions">
          <UiButton :disabled="reloading" @click="needRefresh = false">Later</UiButton>
          <UiButton variant="primary" :disabled="reloading" @click="reload">Reload</UiButton>
        </div>
      </m.div>
    </AnimatePresence>
  </div>
</template>

<style scoped>
.update-region {
  position: fixed;
  inset: auto var(--space-4) var(--space-4);
  z-index: 20;
  display: flex;
  justify-content: center;
  pointer-events: none;
}

.update {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3) var(--space-6);
  width: 100%;
  max-width: 480px;
  padding: var(--space-3) var(--space-3) var(--space-3) var(--space-5);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface);
  box-shadow: var(--shadow-card);
  pointer-events: auto;
}

.update-text {
  margin: 0;
  font-weight: 600;
}

.update-actions {
  display: flex;
  gap: var(--space-2);
}

/* Sit above the bottom tab bar on phones. */
@media (max-width: 600px) {
  .update-region {
    bottom: calc(72px + env(safe-area-inset-bottom));
  }
}
</style>
