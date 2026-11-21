<script setup lang="ts">
import { LazyMotion, MotionConfig } from 'motion-v'
import { storeToRefs } from 'pinia'

import { useAppearanceStore, type MotionPreference } from '../stores/appearance'
import { spring } from './tokens'

const { motion } = storeToRefs(useAppearanceStore())

// LazyMotion with `m.*` components keeps Motion's animation features out of the
// initial bundle: they load as a separate chunk right after first paint. Use `m.div`
// (not `Motion`) inside the app so this stays true.
const loadFeatures = () => import('./features').then((module) => module.default)

/**
 * Motion's own reduced-motion mode turns transform and layout animations off and keeps
 * opacity fades, which is what we want. "system" follows prefers-reduced-motion.
 */
const reducedMotion = {
  system: 'user',
  reduce: 'always',
  full: 'never',
} as const satisfies Record<MotionPreference, 'user' | 'always' | 'never'>
</script>

<template>
  <LazyMotion :features="loadFeatures">
    <MotionConfig :reduced-motion="reducedMotion[motion]" :transition="spring.snappy">
      <slot />
    </MotionConfig>
  </LazyMotion>
</template>
