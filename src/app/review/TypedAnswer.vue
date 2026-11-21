<script setup lang="ts">
import { m } from 'motion-v'
import { computed, ref, watch } from 'vue'

import { diffChars, type AnswerResult } from '@/core/answers'

import { UiKbd } from '../components/ui'
import { presets } from '../motion/tokens'

const props = defineProps<{
  /** The checked answer, once submitted. */
  result?: AnswerResult & { typed: string }
  /** The tool (and subcommand) the prompt shows before the input. */
  command: string
}>()
const emit = defineEmits<{ submit: [typed: string] }>()

const text = ref('')
const input = ref<HTMLInputElement>()

// A new card clears the field.
watch(
  () => props.result,
  (result) => {
    if (!result) text.value = ''
  },
)

function submit() {
  if (!props.result) emit('submit', text.value)
}

/** Wrong answers shake (transform, so reduced motion drops it); colour carries the result too. */
const animate = computed(() => {
  if (!props.result) return { x: 0 }
  return props.result.correct
    ? { x: 0 }
    : { x: [0, -8, 8, -5, 5, 0], transition: { duration: 0.3, ease: 'easeOut' } }
})

const diff = computed(() =>
  props.result && !props.result.correct
    ? diffChars(props.result.typed.trim(), props.result.expected)
    : [],
)

defineExpose({ focus: () => input.value?.focus() })
</script>

<template>
  <form class="typed" @submit.prevent="submit">
    <m.div
      :class="['terminal', result && (result.correct ? 'terminal--correct' : 'terminal--wrong')]"
      :animate="animate"
    >
      <span class="prompt mono" aria-hidden="true">$ {{ command }}</span>
      <label class="visually-hidden" for="typed-answer">Type the flag</label>
      <input
        id="typed-answer"
        ref="input"
        v-model="text"
        class="mono"
        type="text"
        autocomplete="off"
        autocapitalize="off"
        spellcheck="false"
        enterkeyhint="done"
        :readonly="Boolean(result)"
        :aria-invalid="result ? !result.correct : undefined"
        :aria-describedby="result ? 'typed-result' : undefined"
        placeholder="type the flag"
      />
      <span v-if="!result" class="hint"><UiKbd>Enter</UiKbd></span>
    </m.div>

    <AnimatePresence>
      <m.p
        v-if="result"
        id="typed-result"
        key="result"
        class="result"
        :data-correct="result.correct"
        role="status"
        v-bind="presets.fade"
      >
        <template v-if="result.correct">
          <strong class="result-label result-label--correct">Correct</strong>
          <template v-if="result.preferred">
            · short form: <code class="mono">{{ result.preferred }}</code>
          </template>
        </template>
        <template v-else>
          <strong class="result-label result-label--wrong">Not quite</strong>
          · expected <code class="mono">{{ result.expected }}</code>
          <span v-if="result.typed.trim()" class="diff mono" aria-hidden="true"
            ><span v-for="(part, i) in diff" :key="i" :class="`diff--${part.kind}`">{{
              part.text
            }}</span></span
          >
        </template>
      </m.p>
    </AnimatePresence>
  </form>
</template>

<style scoped>
.typed {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}

.terminal {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-2) var(--space-4);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-code);
  background: var(--color-sunken);
  transition: border-color var(--duration-base) var(--ease-out);
}

.terminal:focus-within {
  border-color: var(--color-accent);
}

.terminal--correct {
  border-color: var(--color-accent);
  background: var(--color-surface);
}

.terminal--wrong {
  border-color: var(--color-again-border);
  background: var(--color-again-tint);
}

.prompt {
  flex: none;
  color: var(--color-muted);
}

input {
  flex: 1;
  min-width: 0;
  min-height: 40px;
  border: 0;
  outline: none;
  background: transparent;
  color: var(--color-text);
  font-size: var(--text-md);
}

.hint {
  color: var(--color-muted);
}

.result {
  margin: 0;
  font-size: var(--text-sm);
}

.result-label--correct {
  color: var(--color-accent);
}

.result-label--wrong {
  color: var(--color-again);
}

.diff {
  margin-left: var(--space-2);
}

.diff--removed {
  color: var(--color-again);
  text-decoration: line-through;
}

.diff--added {
  color: var(--color-accent);
  text-decoration: underline;
}
</style>
