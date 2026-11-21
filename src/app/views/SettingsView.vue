<script setup lang="ts">
import { storeToRefs } from 'pinia'

import BackupSettings from '../components/settings/BackupSettings.vue'
import PracticeSettings from '../components/settings/PracticeSettings.vue'
import SchedulingSettings from '../components/settings/SchedulingSettings.vue'
import StorageSettings from '../components/settings/StorageSettings.vue'
import { UiButton } from '../components/ui'
import { useOnboardingStore } from '../onboarding/onboarding'
import {
  useAppearanceStore,
  type FontSize,
  type MotionPreference,
  type ThemePreference,
} from '../stores/appearance'

const { theme, fontSize, motion } = storeToRefs(useAppearanceStore())
const onboarding = useOnboardingStore()

const themeOptions: { value: ThemePreference; label: string }[] = [
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
  { value: 'system', label: 'System' },
]

const fontSizeOptions: { value: FontSize; label: string }[] = [
  { value: 's', label: 'S' },
  { value: 'm', label: 'M' },
  { value: 'l', label: 'L' },
]

const motionOptions: { value: MotionPreference; label: string }[] = [
  { value: 'system', label: 'System' },
  { value: 'reduce', label: 'On' },
  { value: 'full', label: 'Off' },
]
</script>

<template>
  <section class="settings">
    <h1>Settings</h1>

    <fieldset class="setting">
      <legend>Theme</legend>
      <div class="segmented">
        <label v-for="option in themeOptions" :key="option.value" class="segment">
          <input v-model="theme" type="radio" name="theme" :value="option.value" />
          <span>{{ option.label }}</span>
        </label>
      </div>
      <p class="hint casual">System follows your device's light or dark setting.</p>
    </fieldset>

    <fieldset class="setting">
      <legend>Text size</legend>
      <div class="segmented">
        <label v-for="option in fontSizeOptions" :key="option.value" class="segment">
          <input v-model="fontSize" type="radio" name="font-size" :value="option.value" />
          <span>{{ option.label }}</span>
        </label>
      </div>
    </fieldset>

    <fieldset class="setting">
      <legend>Reduce motion</legend>
      <div class="segmented">
        <label v-for="option in motionOptions" :key="option.value" class="segment">
          <input v-model="motion" type="radio" name="motion" :value="option.value" />
          <span>{{ option.label }}</span>
        </label>
      </div>
      <p class="hint casual">
        On keeps fades but drops movement. System follows your device's reduced motion setting.
      </p>
    </fieldset>

    <PracticeSettings />

    <SchedulingSettings />

    <BackupSettings />

    <StorageSettings />

    <section class="setting" aria-labelledby="help-heading">
      <h2 id="help-heading" class="section-heading">Help</h2>
      <UiButton class="replay-tour" @click="onboarding.start()">Replay the welcome tour</UiButton>
      <p class="hint casual">A quick walk through decks, grading and offline use.</p>
    </section>
  </section>
</template>

<style scoped>
.settings {
  display: flex;
  flex-direction: column;
  gap: var(--space-8);
}

h1 {
  margin: 0;
  font-size: var(--text-2xl);
}

.setting {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  margin: 0;
  padding: 0;
  border: 0;
}

.section-heading {
  margin: 0 0 var(--space-1);
  font-size: var(--text-md);
  font-weight: 600;
}

.setting > .replay-tour {
  align-self: flex-start;
}

legend {
  margin-bottom: var(--space-3);
  padding: 0;
  font-size: var(--text-md);
  font-weight: 600;
}

.segmented {
  display: inline-flex;
  align-self: flex-start;
  gap: var(--space-1);
  padding: var(--space-1);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-button);
  background: var(--color-surface);
}

.segment {
  position: relative;
}

.segment input {
  position: absolute;
  inset: 0;
  margin: 0;
  opacity: 0;
  cursor: pointer;
}

.segment span {
  display: flex;
  align-items: center;
  justify-content: center;
  min-width: 64px;
  min-height: 40px;
  padding: 0 var(--space-4);
  border-radius: 10px;
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.segment input:checked + span {
  background: var(--color-sunken);
  color: var(--color-text);
  font-weight: 600;
}

.segment input:focus-visible + span {
  outline: var(--focus-ring-width) solid var(--color-focus);
  outline-offset: var(--focus-ring-offset);
}

.hint {
  margin: 0;
  color: var(--color-muted);
  font-size: var(--text-sm);
}
</style>
