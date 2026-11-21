import { storeToRefs } from 'pinia'
import { computed, onScopeDispose, ref, type ComputedRef } from 'vue'

import { useAppearanceStore } from '../stores/appearance'

/**
 * Whether motion should be reduced right now: Settings > Reduce motion when it
 * is On or Off, otherwise the device's prefers-reduced-motion. For animation
 * Motion doesn't handle itself, such as counting numbers up.
 */
export function useReducedMotion(): ComputedRef<boolean> {
  const { motion } = storeToRefs(useAppearanceStore())
  const query =
    typeof matchMedia === 'undefined' ? undefined : matchMedia('(prefers-reduced-motion: reduce)')
  const system = ref(query?.matches ?? false)
  const update = (event: MediaQueryListEvent) => (system.value = event.matches)
  query?.addEventListener?.('change', update)
  onScopeDispose(() => query?.removeEventListener?.('change', update))
  return computed(() => (motion.value === 'system' ? system.value : motion.value === 'reduce'))
}
