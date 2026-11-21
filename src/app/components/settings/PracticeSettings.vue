<script setup lang="ts">
import { onMounted, ref } from 'vue'

import { SETTING_DEFAULTS } from '@/core/storage'

import { useRepository } from '../../repository'

const repository = useRepository()
const loaded = ref(false)
const flagPairs = ref(SETTING_DEFAULTS.flagPairs)

onMounted(async () => {
  flagPairs.value = await repository.settings.get('flagPairs')
  loaded.value = true
})

async function save(event: Event) {
  flagPairs.value = (event.target as HTMLInputElement).checked
  await repository.settings.set('flagPairs', flagPairs.value)
}
</script>

<template>
  <section class="setting" aria-labelledby="practice-heading" :aria-busy="!loaded">
    <h2 id="practice-heading">Practice</h2>
    <label class="check">
      <input
        id="setting-flagPairs"
        type="checkbox"
        :checked="flagPairs"
        :disabled="!loaded"
        aria-describedby="setting-flagPairs-hint"
        @change="save"
      />
      Flag pair practice
    </label>
    <p id="setting-flagPairs-hint" class="hint">
      Adds cards that show a short flag and ask for its long form, and the other way round. Card
      fronts show one form only, so <code class="mono">-r</code> never appears next to
      <code class="mono">--recursive</code> until you reveal the answer. Turning it off pauses those
      cards and keeps their progress.
    </p>
  </section>
</template>

<style scoped>
.setting {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}

h2 {
  margin: 0 0 var(--space-1);
  font-size: var(--text-md);
  font-weight: 600;
}

.check {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  min-height: 44px;
  font-size: var(--text-sm);
}

.hint {
  margin: 0;
  max-width: 60ch;
  color: var(--color-muted);
  font-size: var(--text-xs);
}
</style>
