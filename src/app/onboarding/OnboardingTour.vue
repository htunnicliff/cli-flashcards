<script setup lang="ts">
import { m } from 'motion-v'
import { storeToRefs } from 'pinia'
import { computed, nextTick, ref, watch } from 'vue'
import { useRouter } from 'vue-router'

import { UiButton, UiKbd } from '../components/ui'
import { presets } from '../motion/tokens'
import { holdUpdatesWhile } from '../pwa/update-holds'
import { useOnboardingStore } from './onboarding'

const STEPS = [
  { id: 'welcome', title: 'Welcome to --recall' },
  { id: 'review', title: 'Review your cards' },
  { id: 'offline', title: 'Works offline' },
] as const

const onboarding = useOnboardingStore()
const { open, replay } = storeToRefs(onboarding)
const router = useRouter()

// Don't reload into a new version mid-tour.
holdUpdatesWhile(open)

const dialog = ref<HTMLDialogElement>()
const heading = ref<HTMLElement>()
const index = ref(0)
const step = computed(() => STEPS[index.value]!)
const isLast = computed(() => index.value === STEPS.length - 1)

watch(
  open,
  async (isOpen) => {
    if (!isOpen) {
      if (dialog.value?.open) dialog.value.close()
      return
    }
    index.value = 0
    await nextTick()
    const el = dialog.value
    if (el && !el.open) {
      // showModal makes the rest of the page inert and traps focus in the dialog.
      if (typeof el.showModal === 'function') el.showModal()
      else el.setAttribute('open', '')
    }
    heading.value?.focus()
  },
  { immediate: true, flush: 'post' },
)

// Each step's heading takes focus as it mounts, so screen readers announce the new step.
// (Steps cross-fade, so the next heading appears only after the old one has left.)
function setHeading(el: unknown) {
  if (!(el instanceof HTMLElement)) return
  heading.value = el
  // The ref is set before motion attaches the step to the page, so wait a tick.
  void nextTick(() => {
    if (el.isConnected && dialog.value?.open) el.focus()
  })
}

function next() {
  if (!isLast.value) index.value++
  else finish(!replay.value)
}

function back() {
  if (index.value > 0) index.value--
}

function finish(toDecks = false) {
  onboarding.finish()
  if (toDecks) void router.push('/decks')
}

/** Escape closes the dialog natively; record it as skipped. */
function onCancel(event: Event) {
  event.preventDefault()
  finish()
}
</script>

<template>
  <dialog
    v-if="open"
    ref="dialog"
    class="tour"
    aria-labelledby="tour-heading"
    aria-describedby="tour-body"
    data-testid="onboarding"
    @cancel="onCancel"
  >
    <div class="tour-top">
      <p class="tour-progress hint" aria-live="polite">
        Step {{ index + 1 }} of {{ STEPS.length }}
      </p>
      <button type="button" class="tour-skip" @click="finish()">
        {{ replay ? 'Close' : 'Skip tour' }}
      </button>
    </div>

    <AnimatePresence mode="wait" :initial="false">
      <m.div :key="step.id" class="tour-step" :data-step="step.id" v-bind="presets.fade">
        <h2 id="tour-heading" :ref="setHeading" tabindex="-1" class="tour-heading">
          <template v-if="step.id === 'welcome'"
            >Welcome to
            <span class="mono"
              ><span class="dashes" aria-hidden="true">--</span>recall</span
            ></template
          >
          <template v-else>{{ step.title }}</template>
        </h2>

        <div id="tour-body" class="tour-body">
          <template v-if="step.id === 'welcome'">
            <p>
              Learn the flags of the command-line tools you use, one flashcard at a time. Each card
              comes back just before you'd forget it, so a few minutes a day is enough.
            </p>
            <p>
              Each deck covers one tool, such as <code class="mono">grep</code> or
              <code class="mono">jq</code>, and starts with its most useful flags.
            </p>
          </template>

          <template v-else-if="step.id === 'review'">
            <p>
              Each card asks about a flag. Recall the answer, then choose
              <strong>Show answer</strong> and grade yourself honestly. Your grade decides when the
              card comes back.
            </p>
            <ul class="grades" aria-label="Grades">
              <li class="grade grade--again">Again</li>
              <li class="grade">Hard</li>
              <li class="grade grade--good">Good</li>
              <li class="grade">Easy</li>
            </ul>
            <p class="on-pointer hint">
              On a keyboard, <UiKbd>Space</UiKbd> shows the answer, <UiKbd>1</UiKbd>–<UiKbd
                >4</UiKbd
              >
              grade it, and <UiKbd>?</UiKbd> lists every shortcut.
            </p>
            <p class="on-touch hint">
              Swipe a revealed card left for Again or right for Good, or tap a grade.
            </p>
          </template>

          <template v-else>
            <p>
              Once a deck is installed, everything works without a connection. Add the app to your
              home screen to open it like any other app.
            </p>
            <p>
              Your progress stays on this device, so export a backup from
              <strong>Settings</strong> now and then.
            </p>
            <p class="hint casual">
              Rather type your answers? Turn on <strong>Type answers</strong> for a deck in Decks.
            </p>
          </template>
        </div>
      </m.div>
    </AnimatePresence>

    <ol class="dots" aria-hidden="true">
      <li v-for="(s, i) in STEPS" :key="s.id" :class="{ 'dot--current': i === index }" />
    </ol>

    <div class="tour-actions">
      <UiButton v-if="index > 0" @click="back">Back</UiButton>
      <UiButton variant="primary" class="tour-next" @click="next">
        {{ !isLast ? 'Next' : replay ? 'Done' : 'Choose a deck' }}
      </UiButton>
    </div>
  </dialog>
</template>

<style scoped>
.tour {
  width: min(520px, calc(100vw - 2 * var(--space-4)));
  max-height: calc(100dvh - 2 * var(--space-4));
  padding: var(--space-6) var(--space-8) var(--space-8);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface);
  color: var(--color-text);
  box-shadow: var(--shadow-card);
  overflow-y: auto;
}

.tour::backdrop {
  background: color-mix(in srgb, var(--color-bg) 70%, transparent);
  backdrop-filter: blur(2px);
}

.tour-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-4);
  margin-bottom: var(--space-4);
}

.hint {
  margin: 0;
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.tour-skip {
  min-height: 44px;
  padding: var(--space-2) var(--space-3);
  margin-right: calc(-1 * var(--space-3));
  border: 0;
  border-radius: var(--radius-small);
  background: none;
  color: var(--color-muted);
  font-size: var(--text-sm);
  cursor: pointer;
}

.tour-skip:hover {
  color: var(--color-text);
}

.tour-step {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  min-height: 15rem;
}

.tour-heading {
  margin: 0;
  font-size: var(--text-xl);
  line-height: var(--line-height-tight);
  border-radius: var(--radius-small);
}

.tour-heading:focus {
  outline: none;
}

.dashes {
  color: var(--color-accent);
}

.tour-body {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.tour-body p {
  margin: 0;
}

.grades {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
  margin: 0;
  padding: 0;
  list-style: none;
}

.grade {
  padding: var(--space-1) var(--space-3);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-small);
  font-size: var(--text-sm);
  font-weight: 600;
}

.grade--again {
  border-color: var(--color-again-border);
  background: var(--color-again-tint);
  color: var(--color-again);
}

.grade--good {
  border-color: var(--color-accent);
  background: var(--color-accent);
  color: var(--color-on-primary);
}

.on-touch {
  display: none;
}

/* Same test the review screen uses to hide key hints on touch screens. */
@media (hover: none) and (pointer: coarse) {
  .on-touch {
    display: block;
  }

  .on-pointer {
    display: none;
  }
}

.dots {
  display: flex;
  justify-content: center;
  gap: var(--space-2);
  margin: var(--space-6) 0 var(--space-5);
  padding: 0;
  list-style: none;
}

.dots li {
  width: 6px;
  height: 6px;
  border-radius: var(--radius-pill);
  background: var(--color-border);
  transition: width var(--duration-base) var(--ease-out);
}

.dots li.dot--current {
  width: 18px;
  background: var(--color-accent);
}

.tour-actions {
  display: flex;
  justify-content: flex-end;
  gap: var(--space-2);
}

@media (max-width: 600px) {
  .tour {
    padding: var(--space-5) var(--space-5) var(--space-6);
  }

  .tour-actions > * {
    flex: 1;
  }
}
</style>
