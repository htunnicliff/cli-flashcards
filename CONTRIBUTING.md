# Contributing

Setup, scripts and the project layout are in the [README](README.md).

## Motion

Animation in this app explains state changes: a card revealing its answer, a graded card leaving, a list re-ordering. It isn't decoration.

### Motion or CSS?

Use [Motion for Vue](https://motion.dev/docs/vue) (`motion-v`) when it adds something CSS can't do well:

- springs and gestures (drag, swipe)
- layout and shared-element animation (`layout`, `layoutId`)
- exit animations and coordinated enter/exit (`AnimatePresence`)

Use plain CSS or Vue's `<Transition>` for hover and focus colours and simple fades. CSS transitions use the `--duration-*` and `--ease-*` tokens in `src/app/styles/tokens.css`.

### How to use it

- Take durations and springs from `src/app/motion/tokens.ts` (`spring.snappy`, `spring.gentle`, `fade.quick`, `presets.slideUp`, …). Don't write inline values; add a token if none fits.
- Use `m.div` (import `m` from `motion-v`), not `<Motion>`. The app is wrapped in `LazyMotion`, which loads Motion's animation features as a separate chunk after first paint; `<Motion>` pulls them back into the initial bundle (about 16 kB gzipped).
- `<AnimatePresence>` and the other Motion components are auto-imported in templates.
- With `AnimatePresence`, put the conditional (`v-if`, `v-show` or a changing `key`) on its **direct child**, never on `AnimatePresence` itself.
- Animate `transform` and `opacity` only, so mid-range phones stay smooth.
- Keep UI transitions under about 200 ms. Springs should settle quickly: high stiffness, enough damping that they don't bounce.

### Never block input

People review by keyboard, fast. Animations must be interruptible: a keypress during an exit animation applies immediately, and the next card appears without waiting for the old one to finish leaving. Never `await` an animation before updating state, and never disable controls while something animates.

### Reduced motion

`MotionRoot` (`src/app/motion/MotionRoot.vue`) sets Motion's `reducedMotion` from Settings > Reduce motion: **System** follows `prefers-reduced-motion`, **On** and **Off** override it. With reduced motion, Motion skips transform and layout animations and keeps opacity fades. Plain CSS transitions follow the same setting through `data-motion` on `<html>` (see `src/app/styles/base.css`).

Component tests and E2E tests run with reduced motion forced, so animations can't make results timing-dependent.
