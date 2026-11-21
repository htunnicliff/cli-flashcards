<script setup lang="ts">
import { m } from 'motion-v'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'

import { formatNextDue } from '@/core/review'
import type { Rating } from '@/core/storage'

import { UiButton, UiKbd } from '../components/ui'
import { useDecksChanged } from '../decks/pending'
import { fade, presets, spring } from '../motion/tokens'
import ReviewCard from '../review/ReviewCard.vue'
import TypedAnswer from '../review/TypedAnswer.vue'
import {
  RATINGS,
  useReviewSession,
  type LeaveHint,
  frontFlag,
  type ReviewSessionOptions,
} from '../review/useReviewSession'

const props = defineProps<{ sessionOptions?: ReviewSessionOptions }>()

const session = useReviewSession(props.sessionOptions)
const {
  current,
  deck,
  option,
  counts,
  done,
  loading,
  revealed,
  intervals,
  nextDue,
  nextLearningDue,
  leaveHint,
  notice,
  error,
  canUndo,
  hasDecks,
  typing,
  answer,
  suggestedRating,
  flagPairs,
} = session

// Decks restored from a backup can finish installing while this screen is open.
watch(useDecksChanged(), () => session.refresh())

const helpOpen = ref(false)
const revealButton = ref<{ $el: HTMLElement }>()
const typedAnswer = ref<InstanceType<typeof TypedAnswer>>()
const gradeButtons = ref<{ $el: HTMLElement }[]>([])
const now = props.sessionOptions?.now ?? (() => Date.now())

const COUNT_LABELS = [
  { kind: 'new', label: 'New' },
  { kind: 'learning', label: 'Learning' },
  { kind: 'review', label: 'Review' },
] as const

/**
 * Where a card goes as it leaves. Graded cards drift by grade: Again left, Hard
 * down, Good right, Easy up. A suspended or buried card drops and shrinks instead,
 * so it reads as set aside rather than graded.
 */
const cardVariants = {
  initial: { opacity: 0, y: 8, scale: 1 },
  enter: { opacity: 1, x: 0, y: 0, scale: 1, transition: spring.gentle },
  exit: (hint: LeaveHint) => {
    if (hint?.kind === 'aside') {
      return { opacity: 0, y: 56, scale: 0.94, transition: fade.base }
    }
    const rating = hint?.rating
    return {
      opacity: 0,
      x: rating === 1 ? -48 : rating === 3 ? 48 : 0,
      y: rating === 2 ? 24 : rating === 4 ? -24 : 0,
      transition: fade.base,
    }
  },
}

// The snackbar leaves on its own after a while; a new notice restarts the clock.
const NOTICE_MS = 8000
let noticeTimer: ReturnType<typeof setTimeout> | undefined
watch(notice, (next) => {
  if (noticeTimer) clearTimeout(noticeTimer)
  if (next) noticeTimer = setTimeout(() => session.dismissNotice(), NOTICE_MS)
})
onBeforeUnmount(() => noticeTimer && clearTimeout(noticeTimer))

const nextDueText = computed(() => {
  const due = nextLearningDue.value ?? nextDue.value
  return due === undefined ? undefined : formatNextDue(due, now())
})

function reveal() {
  if (!current.value || revealed.value) return
  session.reveal()
}

function grade(rating: Rating) {
  if (!current.value || !revealed.value) return
  swipeX.value = 0
  session.grade(rating)
}

const command = computed(() => {
  const tool = deck.value?.tool ?? ''
  return option.value?.subcommand ? `${tool} ${option.value.subcommand}` : tool
})

// Focus follows the flow, so keyboard and screen reader users stay on the controls:
// the suggested (or Good) grade once revealed, otherwise the answer field or Show answer.
watch(
  [revealed, () => current.value?.card.id],
  async ([isRevealed]) => {
    await nextTick()
    if (isRevealed) gradeButtons.value[(suggestedRating.value ?? 3) - 1]?.$el.focus()
    else if (typing.value) typedAnswer.value?.focus()
    else revealButton.value?.$el.focus()
  },
  { flush: 'post' },
)

function isTyping(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false
  return target.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)
}

function onKeydown(event: KeyboardEvent) {
  if (event.ctrlKey || event.metaKey || event.altKey || isTyping(event.target)) return
  if (event.key === '?') {
    helpOpen.value = !helpOpen.value
    event.preventDefault()
    return
  }
  if (event.key === 'Escape' && helpOpen.value) {
    helpOpen.value = false
    return
  }
  if (event.key === ' ' || event.key === 'Spacebar') {
    // Space also clicks a focused button; handle it here once instead.
    event.preventDefault()
    reveal()
    return
  }
  if (event.key === 'u' || event.key === 'U') {
    if (canUndo.value) void session.undo()
    return
  }
  if (event.key === 's' || event.key === 'S') {
    session.setAside('suspend', event.shiftKey || event.key === 'S' ? 'option' : 'card')
    return
  }
  if (event.key === 'b') {
    session.setAside('bury')
    return
  }
  const rating = RATINGS.find((r) => r.key === event.key)
  if (rating) grade(rating.rating)
}

onMounted(() => window.addEventListener('keydown', onKeydown))
onBeforeUnmount(() => window.removeEventListener('keydown', onKeydown))

// Swipe to grade on touch screens: left is Again, right is Good. Below the
// threshold the card snaps back. The buttons remain the main control.
const SWIPE_THRESHOLD = 96
const swipeX = ref(0)
let swipeStart: { x: number; y: number; id: number } | undefined

function onPointerDown(event: PointerEvent) {
  if (!revealed.value || event.pointerType === 'mouse') return
  swipeStart = { x: event.clientX, y: event.clientY, id: event.pointerId }
}

function onPointerMove(event: PointerEvent) {
  if (!swipeStart || event.pointerId !== swipeStart.id) return
  const dx = event.clientX - swipeStart.x
  if (Math.abs(dx) < Math.abs(event.clientY - swipeStart.y)) return
  swipeX.value = dx
}

function onPointerUp() {
  if (!swipeStart) return
  swipeStart = undefined
  const dx = swipeX.value
  swipeX.value = 0
  if (dx <= -SWIPE_THRESHOLD) grade(1)
  else if (dx >= SWIPE_THRESHOLD) grade(3)
}

const swipeHint = computed(() => {
  if (swipeX.value <= -SWIPE_THRESHOLD) return 'Again'
  if (swipeX.value >= SWIPE_THRESHOLD) return 'Good'
  return undefined
})
</script>

<template>
  <section class="review" :aria-busy="loading">
    <header class="session-header">
      <h1 class="title">Review</h1>
      <ul class="counts" aria-label="Cards left">
        <li
          v-for="{ kind, label } in COUNT_LABELS"
          :key="kind"
          :class="['count', `count--${kind}`]"
        >
          <span class="count-label">{{ label }}</span>
          <span class="count-value mono" :data-testid="`count-${kind}`">
            <AnimatePresence mode="popLayout" :initial="false">
              <m.span
                :key="counts[kind]"
                class="count-number"
                :initial="{ opacity: 0, y: -6 }"
                :animate="{ opacity: 1, y: 0, transition: spring.snappy }"
                :exit="{ opacity: 0, y: 6, transition: fade.quick }"
                >{{ counts[kind] }}</m.span
              >
            </AnimatePresence>
          </span>
        </li>
      </ul>
      <div class="header-actions">
        <UiButton v-if="canUndo" class="undo" aria-keyshortcuts="u" @click="session.undo()">
          Undo <UiKbd>u</UiKbd>
        </UiButton>
        <UiButton
          class="help-toggle"
          :aria-expanded="helpOpen"
          aria-controls="shortcut-help"
          aria-keyshortcuts="?"
          aria-label="Keyboard shortcuts"
          @click="helpOpen = !helpOpen"
          ><UiKbd>?</UiKbd></UiButton
        >
      </div>
    </header>

    <AnimatePresence>
      <m.aside
        v-if="helpOpen"
        id="shortcut-help"
        key="help"
        class="help"
        role="region"
        aria-label="Keyboard shortcuts"
        v-bind="{
          initial: { opacity: 0, y: -4 },
          animate: { opacity: 1, y: 0, transition: spring.snappy },
          exit: { opacity: 0, transition: fade.quick },
        }"
      >
        <dl>
          <div>
            <dt><UiKbd>Space</UiKbd></dt>
            <dd>Show the answer</dd>
          </div>
          <div>
            <dt><UiKbd>1</UiKbd>–<UiKbd>4</UiKbd></dt>
            <dd>Again, Hard, Good, Easy</dd>
          </div>
          <div>
            <dt><UiKbd>u</UiKbd></dt>
            <dd>Undo the last grade, suspend or bury</dd>
          </div>
          <div>
            <dt><UiKbd>s</UiKbd></dt>
            <dd>Suspend this card</dd>
          </div>
          <div>
            <dt><UiKbd>S</UiKbd></dt>
            <dd>Suspend every card for this flag</dd>
          </div>
          <div>
            <dt><UiKbd>b</UiKbd></dt>
            <dd>Bury this card until tomorrow</dd>
          </div>
          <div>
            <dt><UiKbd>?</UiKbd></dt>
            <dd>Show or hide this list</dd>
          </div>
        </dl>
        <p class="hint">On a phone, swipe a revealed card left for Again or right for Good.</p>
      </m.aside>
    </AnimatePresence>

    <p v-if="error" class="error" role="alert">{{ error }}</p>
    <p v-if="loading" class="hint">Loading your cards…</p>

    <div v-else-if="done" class="done" data-testid="done" role="status">
      <template v-if="hasDecks">
        <h2>All done for today</h2>
        <p v-if="nextLearningDue !== undefined" class="hint">
          A card you're learning comes back {{ nextDueText }}. It will show up here on its own.
        </p>
        <p v-else-if="nextDueText" class="hint">Your next review is {{ nextDueText }}.</p>
        <p v-else class="hint">Nothing else is scheduled. Add a deck for more to learn.</p>
      </template>
      <template v-else>
        <h2>No decks yet</h2>
        <p class="hint">Pick a tool you use, and its most useful flags become your first cards.</p>
        <RouterLink to="/decks" class="choose-deck">Choose a deck</RouterLink>
      </template>
    </div>

    <template v-else-if="current">
      <div
        class="card-stage"
        @pointerdown="onPointerDown"
        @pointermove="onPointerMove"
        @pointerup="onPointerUp"
        @pointercancel="onPointerUp"
      >
        <AnimatePresence mode="wait" :custom="leaveHint">
          <m.div
            :key="current.card.id"
            class="card-motion"
            :variants="cardVariants"
            :custom="leaveHint"
            initial="initial"
            animate="enter"
            exit="exit"
          >
            <div
              class="card-swipe"
              :class="{ 'card-swipe--dragging': swipeX !== 0 }"
              :style="
                swipeX
                  ? { transform: `translate3d(${swipeX}px, 0, 0) rotate(${swipeX / 40}deg)` }
                  : undefined
              "
              :data-card="current.card.id"
              @click="reveal"
            >
              <ReviewCard
                :card="current.card"
                :option="option"
                :tool="deck?.tool ?? ''"
                :revealed="revealed"
                :flag-pairs="flagPairs"
              />
            </div>
          </m.div>
        </AnimatePresence>
        <p v-if="swipeHint" class="swipe-hint" aria-hidden="true">{{ swipeHint }}</p>
      </div>

      <div class="controls">
        <TypedAnswer
          v-if="typing"
          ref="typedAnswer"
          :result="answer"
          :command="command"
          @submit="session.submitAnswer"
        />
        <UiButton
          v-if="!revealed && !typing"
          ref="revealButton"
          variant="primary"
          block
          class="reveal"
          aria-keyshortcuts="Space"
          @click="reveal"
          >Show answer <UiKbd>Space</UiKbd></UiButton
        >
        <div v-if="revealed" class="grades" role="group" aria-label="Grade this card">
          <UiButton
            v-for="{ rating, label, key } in RATINGS"
            :key="rating"
            ref="gradeButtons"
            :variant="rating === 1 ? 'again' : rating === 3 ? 'primary' : 'neutral'"
            class="grade"
            :data-rating="rating"
            :data-suggested="suggestedRating === rating ? 'true' : undefined"
            :aria-keyshortcuts="key"
            :aria-label="`${label}, next in ${intervals[rating]}`"
            @click="grade(rating)"
          >
            <span class="grade-label">{{ label }}</span>
            <span class="grade-meta"
              ><span class="mono">{{ intervals[rating] }}</span> <UiKbd>{{ key }}</UiKbd></span
            >
          </UiButton>
        </div>
        <div class="set-aside" role="group" aria-label="Set this card aside">
          <button type="button" aria-keyshortcuts="b" @click="session.setAside('bury')">
            Bury <UiKbd>b</UiKbd>
          </button>
          <button type="button" aria-keyshortcuts="s" @click="session.setAside('suspend')">
            Suspend <UiKbd>s</UiKbd>
          </button>
          <button
            type="button"
            aria-keyshortcuts="Shift+S"
            @click="session.setAside('suspend', 'option')"
          >
            Suspend all {{ frontFlag(current.card) }} cards <UiKbd>S</UiKbd>
          </button>
        </div>
      </div>
    </template>

    <AnimatePresence>
      <m.div
        v-if="notice"
        :key="notice.id"
        class="snackbar"
        role="status"
        data-testid="notice"
        v-bind="presets.slideUp"
      >
        <p>{{ notice.message }}</p>
        <RouterLink v-if="notice.link" :to="notice.link.to" class="snackbar-link">{{
          notice.link.label
        }}</RouterLink>
        <button
          v-if="notice.undoable && canUndo"
          type="button"
          class="snackbar-undo"
          @click="session.undo()"
        >
          Undo
        </button>
        <button type="button" aria-label="Dismiss" @click="session.dismissNotice()">×</button>
      </m.div>
    </AnimatePresence>
  </section>
</template>

<style scoped>
.review {
  display: flex;
  flex-direction: column;
  gap: var(--space-5);
}

h2,
p {
  margin: 0;
}

.hint {
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.error {
  color: var(--color-again);
}

.session-header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
}

.title {
  margin: 0;
  font-size: var(--text-xl);
}

.counts {
  display: flex;
  flex: 1;
  gap: var(--space-5);
  margin: 0;
  padding: 0;
  list-style: none;
}

.count {
  display: flex;
  align-items: baseline;
  gap: var(--space-2);
  font-size: var(--text-sm);
}

.count-label {
  color: var(--color-muted);
}

.count-value {
  display: inline-flex;
  min-width: 2ch;
  font-weight: 700;
}

.count-number {
  display: inline-block;
}

.count--new .count-value {
  color: var(--color-accent);
}

.count--learning .count-value {
  color: var(--color-again);
}

.count--review .count-value {
  color: var(--color-arg);
}

.header-actions {
  display: flex;
  gap: var(--space-2);
}

.help {
  padding: var(--space-4) var(--space-5);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-button);
  background: var(--color-surface);
}

.help dl {
  display: grid;
  gap: var(--space-2);
  margin: 0 0 var(--space-3);
}

.help dl > div {
  display: flex;
  gap: var(--space-3);
}

.help dt {
  min-width: 7ch;
}

.help dd {
  margin: 0;
}

.done {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: var(--space-2);
  padding: var(--space-10);
  border: var(--border-width) dashed var(--color-border);
  border-radius: var(--radius-card);
}

.done a {
  color: var(--color-accent);
  font-weight: 600;
}

.done .choose-deck {
  display: inline-flex;
  align-items: center;
  min-height: 44px;
  margin-top: var(--space-2);
  padding: var(--space-2) var(--space-5);
  border-radius: var(--radius-button);
  background: var(--color-accent);
  color: var(--color-on-primary);
  text-decoration: none;
}

.card-stage {
  position: relative;
  touch-action: pan-y;
}

.card-swipe {
  transition: transform var(--duration-base) var(--ease-out);
  /* Keep the card on its own compositing layer so a drag only moves it. Without
     this, iOS WebKit repaints the rotated card tile by tile on every pointer move,
     and half-updated tiles show the card torn in two (seen in Orion and Safari). */
  will-change: transform;
}

.card-swipe--dragging {
  transition: none;
}

.swipe-hint {
  position: absolute;
  z-index: 1;
  top: var(--space-4);
  right: var(--space-4);
  margin: 0;
  padding: var(--space-1) var(--space-3);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-pill);
  background: var(--color-surface);
  color: var(--color-muted);
  font-weight: 700;
  pointer-events: none;
}

.controls {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.grade[data-suggested] {
  box-shadow: 0 0 0 2px var(--color-accent);
}

.set-aside {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: var(--space-1) var(--space-4);
}

.set-aside button,
.snackbar button {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  min-height: 44px;
  padding: var(--space-1) var(--space-2);
  border: 0;
  border-radius: var(--radius-small);
  background: transparent;
  color: var(--color-muted);
  font: inherit;
  font-size: var(--text-sm);
  cursor: pointer;
}

.snackbar {
  position: fixed;
  z-index: 10;
  right: var(--space-4);
  bottom: var(--space-4);
  left: var(--space-4);
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2) var(--space-4);
  max-width: var(--content-width);
  margin: 0 auto;
  padding: var(--space-3) var(--space-4);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-button);
  background: var(--color-surface);
  box-shadow: var(--shadow-card);
}

.snackbar p {
  flex: 1;
  font-size: var(--text-sm);
}

.snackbar .snackbar-undo {
  color: var(--color-accent);
  font-weight: 600;
}

.snackbar-link {
  color: var(--color-accent);
  font-size: var(--text-sm);
  font-weight: 600;
}

.grades {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: var(--space-3);
}

.grade {
  flex-direction: column;
  gap: var(--space-1);
  min-height: 64px;
  padding: var(--space-2);
}

.grade-meta {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  font-size: var(--text-xs);
  font-weight: 500;
  opacity: 0.85;
}

@media (max-width: 600px) {
  .grades {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .done {
    padding: var(--space-6);
  }
}

/*
 * Touch screens (phones, most tablets) usually have no keyboard: hide the
 * shortcut badges and the shortcut list toggle. The list itself keeps its
 * badges, since only a keyboard can open it there.
 */
@media (hover: none) and (pointer: coarse) {
  .help-toggle,
  .header-actions :deep(.kbd),
  .controls :deep(.kbd) {
    display: none;
  }
}
</style>
