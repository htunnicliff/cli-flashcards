import type { Transition } from 'motion-v'

/**
 * Shared motion tokens. Use these instead of inline durations or spring values, so the
 * feel of the app can be tuned in one place. Keep UI transitions under ~200 ms and
 * springs critically damped or close to it: users grind through reviews by keyboard,
 * and nothing should feel like it is waiting for an animation.
 */
export const spring = {
  /** Default for interface state changes: settles in ~150 ms with no visible overshoot. */
  snappy: { type: 'spring', stiffness: 700, damping: 50, mass: 1 },
  /** Larger elements such as a card moving away; a touch softer, still no bounce. */
  gentle: { type: 'spring', stiffness: 400, damping: 40, mass: 1 },
} as const satisfies Record<string, Transition>

export const fade = {
  quick: { duration: 0.12, ease: 'easeOut' },
  base: { duration: 0.2, ease: 'easeOut' },
} as const satisfies Record<string, Transition>

/**
 * Enter/exit presets for `AnimatePresence` children. Spread them onto a motion
 * component: `<m.div v-bind="presets.slideUp" />`.
 */
export const presets = {
  /** Fades in while rising a few pixels; leaves the same way. For toasts and banners. */
  slideUp: {
    initial: { opacity: 0, y: 8 },
    animate: { opacity: 1, y: 0, transition: spring.snappy },
    exit: { opacity: 0, y: 8, transition: fade.quick },
  },
  /** Opacity only. For content swaps where movement would distract. */
  fade: {
    initial: { opacity: 0 },
    animate: { opacity: 1, transition: fade.quick },
    exit: { opacity: 0, transition: fade.quick },
  },
} as const
