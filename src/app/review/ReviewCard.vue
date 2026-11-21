<script setup lang="ts">
import { m } from 'motion-v'
import { computed } from 'vue'

import { commandParts } from '@/core/review'
import type { Card, Option } from '@/schema'

import { CommandLine, type CommandPart } from '../components/ui'
import { presets } from '../motion/tokens'

const props = defineProps<{
  card: Card
  option?: Option
  /** The program name as typed, e.g. `rg` or `git`. */
  tool: string
  revealed: boolean
  /** Flag pair practice is on: the front shows one form of the flag, never both. */
  flagPairs?: boolean
}>()

/** `git log` for a subcommand option, otherwise the tool alone. */
const command = computed(() =>
  props.option?.subcommand ? `${props.tool} ${props.option.subcommand}` : props.tool,
)
const aliases = computed(() => props.card.answers.slice(1))
/** Other spellings for the front, left off while flag pair practice is on. */
const frontAliases = computed(() => (props.flagPairs ? [] : aliases.value))
const argument = computed(() => {
  const arg = props.option?.argument
  if (!arg) return undefined
  return arg.optional ? `[${arg.name}]` : arg.name
})

/** Highlights every spelling of the card's option in a command, and nothing else. */
function highlight(text: string): CommandPart[] {
  const answers = new Set(props.card.answers)
  return commandParts(text).map((part) => {
    if (part.kind === 'blank') return part
    const flag = part.text.split('=')[0]!
    if (part.kind === 'flag' && !answers.has(flag)) return { kind: 'tool', text: part.text }
    if (part.kind === 'tool' && answers.has(flag)) return { kind: 'flag', text: part.text }
    return part
  })
}

const clozeParts = computed(() => (props.card.type === 'cloze' ? highlight(props.card.cloze) : []))
const example = computed(() => {
  if (props.card.type === 'cloze') {
    return { command: props.card.command, description: props.card.exampleDescription }
  }
  return props.option?.examples[0]
})

const prompt: Record<Card['type'], string> = {
  'flag-to-meaning': 'What does this flag do?',
  'meaning-to-flag': 'Which flag does this?',
  cloze: 'Fill in the blank.',
  'short-to-long': "What's the long form?",
  'long-to-short': "What's the short form?",
}
</script>

<template>
  <article class="review-card" :data-card-type="card.type" :aria-label="prompt[card.type]">
    <p class="prompt casual">{{ prompt[card.type] }}</p>

    <!-- Front -->
    <div class="front">
      <template v-if="card.type === 'flag-to-meaning'">
        <p class="tool mono">{{ command }}</p>
        <p class="flags mono" data-testid="front-flag">
          <span class="flag-primary">{{ card.flag }}</span>
          <span v-for="alias in frontAliases" :key="alias" class="flag-alias">{{ alias }}</span>
        </p>
      </template>
      <template v-else-if="card.type === 'short-to-long' || card.type === 'long-to-short'">
        <p class="tool mono">{{ command }}</p>
        <p class="flags mono" data-testid="front-flag">
          <span class="flag-primary">{{ card.shown }}</span>
        </p>
      </template>
      <template v-else-if="card.type === 'meaning-to-flag'">
        <p class="tool mono">{{ command }}</p>
        <p class="meaning" data-testid="front-meaning">{{ card.summary }}</p>
      </template>
      <template v-else-if="card.type === 'cloze'">
        <CommandLine :parts="clozeParts" block data-testid="front-cloze" />
        <p v-if="card.exampleDescription" class="hint">{{ card.exampleDescription }}</p>
      </template>
    </div>

    <!-- Back -->
    <AnimatePresence>
      <m.div v-if="revealed" key="back" class="back" data-testid="back" v-bind="presets.slideUp">
        <hr class="divider" />
        <p class="flags mono" data-testid="back-flags">
          <span class="flag-primary">{{ card.flag }}</span>
          <span v-if="argument" class="arg mono-casual">{{ argument }}</span>
          <span v-for="alias in aliases" :key="alias" class="flag-alias">{{ alias }}</span>
        </p>
        <p class="summary">{{ card.summary }}</p>
        <div v-if="example" class="example">
          <CommandLine :parts="highlight(example.command)" block />
          <p v-if="example.description && card.type !== 'cloze'" class="hint">
            {{ example.description }}
          </p>
        </div>
        <details v-if="card.detail && card.detail !== card.summary" class="detail">
          <summary>Full description</summary>
          <p class="description">{{ card.detail }}</p>
        </details>
      </m.div>
    </AnimatePresence>
  </article>
</template>

<style scoped>
.review-card {
  display: flex;
  flex-direction: column;
  gap: var(--space-5);
  min-height: 260px;
  padding: var(--space-10);
  border: var(--border-width) solid var(--glass-rim);
  border-radius: var(--radius-card);
  background: var(--surface-glass);
  box-shadow: var(--shadow-card);
  -webkit-backdrop-filter: var(--glass-filter-card);
  backdrop-filter: var(--glass-filter-card);
}

p {
  margin: 0;
}

.prompt,
.hint {
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.front,
.back {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.tool {
  color: var(--color-muted);
  font-size: var(--text-md);
}

.flags {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: var(--space-2) var(--space-4);
}

.front .flag-primary {
  font-size: var(--text-flag);
  line-height: var(--line-height-tight);
}

.flag-primary {
  color: var(--color-accent);
  font-size: var(--text-xl);
  font-weight: 700;
}

.flag-alias {
  color: var(--color-muted);
  font-size: var(--text-lg);
}

.arg {
  color: var(--color-arg);
  font-size: var(--text-lg);
}

.meaning {
  font-size: var(--text-2xl);
  line-height: var(--line-height-tight);
}

.divider {
  width: 100%;
  margin: 0 0 var(--space-2);
  border: 0;
  border-top: var(--border-width) dashed var(--color-border);
}

.summary {
  font-size: var(--text-lg);
}

.example {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}

.detail summary {
  color: var(--color-accent);
  cursor: pointer;
  font-size: var(--text-sm);
}

.description {
  margin-top: var(--space-2);
  white-space: pre-wrap;
  color: var(--color-muted);
  font-size: var(--text-sm);
}

@media (max-width: 600px) {
  .review-card {
    padding: var(--space-6);
  }
}
</style>
