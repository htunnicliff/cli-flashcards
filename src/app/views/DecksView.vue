<script setup lang="ts">
import { m } from 'motion-v'
import { onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'

import type { DeckFlavor } from '@/core/storage'
import type { DeckManifestEntry } from '@/schema/manifest'

import { UiButton, UiChip } from '../components/ui'
import { flavorLabel } from '../decks/sync'
import { useLibrary, type LibraryOptions } from '../decks/useLibrary'
import { fade, spring } from '../motion/tokens'
import { useOnline } from '../pwa/online'

const props = defineProps<{ libraryOptions?: LibraryOptions }>()

const library = useLibrary(props.libraryOptions)
const { tools, flavor, flavoredTools, loading, error, status, syncState } = library
const online = useOnline()

const FLAVORS: DeckFlavor[] = ['gnu', 'bsd']

/** Deck ID whose reset confirmation is open. */
const confirmingReset = ref<string>()

onMounted(() => library.refresh())

/** How much there is to learn, in plain words: the deck opens with its core flags. */
function sizeSummary(entry: DeckManifestEntry): string {
  const { core } = entry.tiers
  if (core === 0 || core >= entry.optionCount) return `${entry.optionCount} options`
  return `${entry.optionCount} options, starting with the ${core} most used`
}

function listOf(names: readonly string[]): string {
  return names.length > 1 ? `${names.slice(0, -1).join(', ')} and ${names.at(-1)}` : names[0]!
}

/** The deck just turned on, so the next step (a review) is one tap away. */
const justStarted = ref<string>()

async function onToggle(
  id: string,
  tool: string,
  kind: 'obscure' | 'study' | 'typed',
  event: Event,
) {
  const checked = (event.target as HTMLInputElement).checked
  if (kind === 'obscure') return library.setIncludeObscure(id, checked)
  if (kind === 'typed') return library.setTypeAnswers(id, checked)
  await library.setStudying(id, checked)
  justStarted.value = checked ? tool : undefined
  status.value = checked ? `Studying ${tool}.` : `Paused ${tool}. Its progress is kept.`
}

async function confirmReset(id: string, tool: string) {
  confirmingReset.value = undefined
  await library.resetProgress(id, tool)
}
</script>

<template>
  <section class="decks" :aria-busy="loading">
    <header class="decks-header">
      <h1>Decks</h1>
      <p class="hint casual">
        Every deck downloads on its own and works offline. Turn on the ones you want to study.
      </p>
    </header>

    <fieldset v-if="flavoredTools.length > 0" class="variants flavor">
      <legend class="hint">Flavor</legend>
      <div class="segmented">
        <label v-for="option in FLAVORS" :key="option" class="segment">
          <input
            type="radio"
            name="deck-flavor"
            :value="option"
            :checked="flavor === option"
            :disabled="!online || syncState.running"
            @change="library.setFlavor(option)"
          />
          <span>{{ flavorLabel(option) }}</span>
        </label>
      </div>
      <p class="hint flavor-hint">For {{ listOf(flavoredTools) }}, whose flags differ.</p>
    </fieldset>

    <div v-if="syncState.running && syncState.total > 0" class="sync" data-testid="deck-sync">
      <p class="hint">Downloading decks… {{ syncState.done }} of {{ syncState.total }}</p>
      <div
        class="progress"
        role="progressbar"
        aria-label="Downloading decks"
        aria-valuemin="0"
        :aria-valuemax="syncState.total"
        :aria-valuenow="syncState.done"
      >
        <m.div
          class="progress-bar"
          :initial="{ scaleX: 0 }"
          :animate="{ scaleX: syncState.done / syncState.total }"
          :transition="spring.snappy"
        />
      </div>
    </div>

    <div class="status-row">
      <p class="status" role="status" aria-live="polite">{{ status }}</p>
      <RouterLink v-if="justStarted" to="/" class="start-link" data-testid="start-reviewing"
        >Start reviewing</RouterLink
      >
    </div>
    <p v-if="!online" class="offline-note">
      You're offline. Downloaded decks still work; new decks and updates download when you're back
      online.
    </p>
    <p v-if="error" class="error" role="alert">{{ error }}</p>

    <p v-if="loading && tools.length === 0" class="hint">Loading decks…</p>
    <p v-else-if="!loading && tools.length === 0 && !error" class="hint">
      No decks are available yet.
    </p>

    <ul class="deck-list">
      <AnimatePresence :initial="false">
        <m.li
          v-for="tool in tools"
          :key="tool.tool"
          layout
          :transition="spring.snappy"
          :exit="{ opacity: 0, transition: fade.quick }"
          class="deck"
          :data-deck="tool.entry.id"
          :data-installed="tool.stored ? 'true' : 'false'"
          :data-studying="tool.studying ? 'true' : 'false'"
        >
          <div class="deck-head">
            <h2 class="deck-title mono">{{ tool.tool }}</h2>
            <UiChip v-if="tool.stored?.paused">Paused</UiChip>
            <UiChip v-if="!tool.stored">{{
              online ? 'Downloading soon' : 'Downloads when online'
            }}</UiChip>
          </div>

          <p class="meta hint">
            <template v-if="tool.variants.length > 1"
              >{{ flavorLabel(tool.entry.variant) }} ·
            </template>
            {{ sizeSummary(tool.entry) }}
          </p>

          <div v-if="tool.stored" class="deck-settings">
            <label class="check check--primary">
              <input
                type="checkbox"
                :checked="!tool.stored.paused"
                @change="onToggle(tool.entry.id, tool.tool, 'study', $event)"
              />
              Study this deck
            </label>
            <label class="check">
              <input
                type="checkbox"
                :checked="tool.stored.includeObscure"
                @change="onToggle(tool.entry.id, tool.tool, 'obscure', $event)"
              />
              Include rarely used flags
            </label>
            <label class="check">
              <input
                type="checkbox"
                :checked="tool.stored.typeAnswers ?? false"
                @change="onToggle(tool.entry.id, tool.tool, 'typed', $event)"
              />
              Type answers
            </label>
          </div>

          <div class="actions">
            <RouterLink class="browse-link" :to="`/decks/${tool.entry.id}`"
              >Browse options</RouterLink
            >
            <UiButton
              v-if="tool.stored && confirmingReset !== tool.entry.id"
              @click="confirmingReset = tool.entry.id"
              >Reset progress</UiButton
            >
          </div>

          <AnimatePresence>
            <m.div
              v-if="confirmingReset === tool.entry.id"
              key="confirm"
              class="confirm"
              role="group"
              :aria-label="`Reset progress on ${tool.tool}`"
              :initial="{ opacity: 0 }"
              :animate="{ opacity: 1, transition: fade.quick }"
              :exit="{ opacity: 0, transition: fade.quick }"
            >
              <p>Reset your progress on {{ tool.tool }}? Its cards start over as new.</p>
              <div class="actions">
                <UiButton variant="again" @click="confirmReset(tool.entry.id, tool.tool)"
                  >Reset progress</UiButton
                >
                <UiButton @click="confirmingReset = undefined">Cancel</UiButton>
              </div>
            </m.div>
          </AnimatePresence>
        </m.li>
      </AnimatePresence>
    </ul>
  </section>
</template>

<style scoped>
.decks {
  display: flex;
  flex-direction: column;
  gap: var(--space-6);
}

.decks-header {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}

h1,
h2,
p {
  margin: 0;
}

.hint {
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.status-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2) var(--space-4);
}

.status-row:has(.status:empty):not(:has(.start-link)) {
  display: none;
}

.start-link {
  display: inline-flex;
  align-items: center;
  min-height: 44px;
  padding: var(--space-2) var(--space-5);
  border-radius: var(--radius-button);
  background: var(--color-accent);
  color: var(--color-on-primary);
  font-weight: 600;
  text-decoration: none;
}

.start-link::after {
  content: ' →';
  white-space: pre;
}

.error {
  color: var(--color-again);
}

.offline-note {
  margin: 0;
  padding: var(--space-3) var(--space-4);
  border-radius: var(--radius-small);
  background: var(--color-sunken);
  font-size: var(--text-sm);
}

.deck-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  margin: 0;
  padding: 0;
  list-style: none;
}

.deck {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding: var(--space-6);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface);
  box-shadow: var(--shadow-card);
}

.deck-head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2);
}

.deck-title {
  margin-right: var(--space-2);
  font-size: var(--text-xl);
}

.variants {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  margin: 0;
  padding: 0;
  border: 0;
}

.flavor {
  flex-wrap: wrap;
}

.flavor-hint {
  flex-basis: 100%;
}

.sync {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}

.variants legend {
  float: left;
  margin-right: var(--space-3);
}

.segmented {
  display: inline-flex;
  padding: 2px;
  border-radius: var(--radius-small);
  background: var(--color-sunken);
}

.segment {
  position: relative;
}

.segment input {
  position: absolute;
  opacity: 0;
}

.segment span {
  display: block;
  padding: var(--space-1) var(--space-3);
  border-radius: calc(var(--radius-small) - 2px);
  cursor: pointer;
  font-size: var(--text-sm);
}

.segment input:checked + span {
  background: var(--color-surface);
  font-weight: 600;
}

.segment input:focus-visible + span {
  outline: var(--focus-ring-width) solid var(--color-accent);
  outline-offset: var(--focus-ring-offset);
}

.progress {
  overflow: hidden;
  height: 6px;
  border-radius: var(--radius-pill);
  background: var(--color-sunken);
}

.progress-bar {
  height: 100%;
  transform-origin: left center;
  background: var(--color-accent);
}

.deck-settings {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2) var(--space-6);
}

.check {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  min-height: 44px;
  font-size: var(--text-sm);
}

.check--primary {
  font-weight: 600;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-3);
}

.browse-link {
  padding: var(--space-2);
  color: var(--color-accent);
  font-size: var(--text-sm);
  font-weight: 600;
}

.confirm {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  padding: var(--space-4);
  border: var(--border-width) solid var(--color-again-border);
  border-radius: var(--radius-button);
  background: var(--color-again-tint);
}
</style>
