<script setup lang="ts">
import { m } from 'motion-v'
import { computed, onMounted, ref, shallowRef } from 'vue'
import { RouterLink } from 'vue-router'

import { optionStatuses, searchOptions, type OptionStatus } from '@/core/library'
import type { CardState } from '@/core/storage'
import { answerFlags, type Deck } from '@/schema'

import { UiChip } from '../components/ui'
import { fetchDeck, fetchManifest, type FetchLike } from '../decks/catalog'
import { fade, spring } from '../motion/tokens'
import { useRepository } from '../repository'

const props = defineProps<{ id: string; fetch?: FetchLike }>()

const repository = useRepository()
const deck = shallowRef<Deck>()
const installed = ref(false)
const states = shallowRef<CardState[]>([])
const query = ref('')
const error = ref<string>()
const loading = ref(true)

onMounted(async () => {
  try {
    const stored = await repository.decks.get(props.id)
    if (stored) {
      deck.value = stored.deck
      installed.value = true
      states.value = await repository.cardStates.listByDeck(props.id)
    } else {
      // Not installed: browse straight from the network, as a quick reference.
      const fetchFn = props.fetch ?? ((input, init) => fetch(input, init))
      const entry = (await fetchManifest(fetchFn)).decks.find((d) => d.id === props.id)
      if (!entry) throw new Error(`There is no deck called "${props.id}".`)
      deck.value = await fetchDeck(entry, undefined, fetchFn)
    }
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    loading.value = false
  }
})

const statuses = computed(() =>
  deck.value ? optionStatuses(deck.value, states.value) : new Map<string, OptionStatus>(),
)

const visible = computed(() => (deck.value?.options ?? []).filter((option) => !option.hidden))
const results = computed(() => searchOptions(visible.value, query.value))

const statusLabel: Record<OptionStatus, string> = {
  new: 'New',
  learning: 'Learning',
  review: 'Learned',
  suspended: 'Suspended',
}
</script>

<template>
  <section class="browse" :aria-busy="loading">
    <RouterLink to="/decks" class="back">← All decks</RouterLink>
    <header v-if="deck" class="browse-header">
      <h1 class="mono">
        {{ deck.tool }} <span class="variant">{{ deck.variant }}</span>
      </h1>
      <p class="hint">
        {{ visible.length }} options · {{ deck.tool }} {{ deck.toolVersion }} · deck v{{
          deck.deckVersion
        }}<template v-if="!installed"> · not installed</template>
      </p>
    </header>
    <h1 v-else-if="!loading">Deck not found</h1>
    <p v-if="error" class="error" role="alert">{{ error }}</p>

    <template v-if="deck">
      <label class="search">
        <span class="visually-hidden">Search options</span>
        <input
          v-model="query"
          type="search"
          class="mono"
          placeholder="Search flags or descriptions…"
          autocomplete="off"
          spellcheck="false"
        />
      </label>
      <p class="hint" role="status" aria-live="polite">
        {{
          results.length === visible.length
            ? `${visible.length} options`
            : `${results.length} of ${visible.length} options`
        }}
      </p>

      <ul class="options">
        <AnimatePresence :initial="false">
          <m.li
            v-for="option in results"
            :key="option.id"
            layout="position"
            :transition="spring.snappy"
            :initial="{ opacity: 0 }"
            :animate="{ opacity: 1, transition: fade.quick }"
            :exit="{ opacity: 0, transition: fade.quick }"
            class="option"
            :data-option="option.id"
          >
            <div class="option-head">
              <code class="flags mono">
                <span class="primary">{{ answerFlags(option)[0] }}</span>
                <span v-for="flag in answerFlags(option).slice(1)" :key="flag" class="alias">{{
                  flag
                }}</span>
                <span v-if="option.argument" class="arg">{{
                  option.argument.optional ? `[${option.argument.name}]` : option.argument.name
                }}</span>
              </code>
              <span class="chips">
                <UiChip v-if="option.subcommand" mono>{{ option.subcommand }}</UiChip>
                <UiChip :data-tier="option.tier">{{ option.tier }}</UiChip>
                <UiChip v-if="installed" :data-status="statuses.get(option.id)">{{
                  statusLabel[statuses.get(option.id) ?? 'new']
                }}</UiChip>
              </span>
            </div>
            <p class="summary">{{ option.summary }}</p>
            <details v-if="option.description && option.description !== option.summary">
              <summary>Full description</summary>
              <p class="description">{{ option.description }}</p>
            </details>
          </m.li>
        </AnimatePresence>
      </ul>
    </template>
  </section>
</template>

<style scoped>
.browse {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

h1,
p {
  margin: 0;
}

.back {
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.variant {
  color: var(--color-muted);
  font-size: var(--text-lg);
  font-weight: 400;
}

.hint {
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.error {
  color: var(--color-again);
}

.search input {
  box-sizing: border-box;
  width: 100%;
  min-height: 44px;
  padding: var(--space-2) var(--space-4);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-button);
  background: var(--color-surface);
  color: var(--color-text);
  font-size: var(--text-md);
}

.options {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  margin: 0;
  padding: 0;
  list-style: none;
}

.option {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  padding: var(--space-4) var(--space-5);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-button);
  background: var(--color-surface);
}

.option-head {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  justify-content: space-between;
  gap: var(--space-2);
}

.flags {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-1) var(--space-3);
  font-size: var(--text-md);
}

.primary {
  font-weight: 700;
}

.alias {
  color: var(--color-muted);
}

.arg {
  color: var(--color-arg);
}

.chips {
  display: flex;
  gap: var(--space-1);
}

.description {
  margin-top: var(--space-2);
  white-space: pre-wrap;
  color: var(--color-muted);
  font-size: var(--text-sm);
}

details summary {
  color: var(--color-accent);
  cursor: pointer;
  font-size: var(--text-sm);
}
</style>
