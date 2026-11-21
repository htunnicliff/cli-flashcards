<script setup lang="ts">
import { m } from 'motion-v'
import { onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'

import type { DeckManifestEntry } from '@/schema/manifest'

import { UiButton, UiChip } from '../components/ui'
import { useLibrary, type LibraryOptions } from '../decks/useLibrary'
import { fade, spring } from '../motion/tokens'

const props = defineProps<{ libraryOptions?: LibraryOptions }>()

const library = useLibrary(props.libraryOptions)
const { tools, loading, error, tasks, status, chosen } = library

/** Deck ID whose remove confirmation is open. */
const confirmingRemove = ref<string>()
const resetProgress = ref(false)

onMounted(() => library.refresh())

function tierSummary(entry: DeckManifestEntry): string {
  const { core, common, obscure } = entry.tiers
  return `${core} core · ${common} common · ${obscure} obscure`
}

function askRemove(id: string) {
  confirmingRemove.value = id
  resetProgress.value = false
}

async function confirmRemove(id: string) {
  const reset = resetProgress.value
  confirmingRemove.value = undefined
  await library.remove(id, { resetProgress: reset })
}

function onToggle(id: string, kind: 'obscure' | 'paused' | 'typed', event: Event) {
  const checked = (event.target as HTMLInputElement).checked
  if (kind === 'obscure') return library.setIncludeObscure(id, checked)
  if (kind === 'typed') return library.setTypeAnswers(id, checked)
  return library.setPaused(id, checked)
}
</script>

<template>
  <section class="decks" :aria-busy="loading">
    <header class="decks-header">
      <h1>Decks</h1>
      <p class="hint casual">Pick the tools you want to learn. Installed decks work offline.</p>
    </header>

    <p class="status" role="status" aria-live="polite">{{ status }}</p>
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
        >
          <div class="deck-head">
            <h2 class="deck-title mono">{{ tool.tool }}</h2>
            <UiChip v-if="tool.stored">Installed</UiChip>
            <UiChip v-if="tool.stored?.paused">Paused</UiChip>
            <UiChip v-if="tool.updateAvailable" class="update-chip">Update available</UiChip>
          </div>

          <fieldset v-if="tool.variants.length > 1" class="variants">
            <legend class="hint">Variant</legend>
            <div class="segmented">
              <label v-for="variant in tool.variants" :key="variant.id" class="segment">
                <input
                  type="radio"
                  :name="`variant-${tool.tool}`"
                  :value="variant.variant"
                  :checked="variant.id === tool.entry.id"
                  @change="chosen[tool.tool] = variant.variant"
                />
                <span class="mono">{{ variant.variant }}</span>
              </label>
            </div>
          </fieldset>
          <p v-if="tool.otherInstalled" class="hint">
            You have the {{ tool.otherInstalled.variant }} variant installed.
          </p>

          <p class="meta">
            <span>{{ tool.entry.optionCount }} options</span>
            <span class="hint">{{ tierSummary(tool.entry) }}</span>
            <span class="hint mono"
              >v{{ tool.entry.deckVersion }} · {{ tool.entry.toolVersion }}</span
            >
          </p>

          <div
            v-if="tasks[tool.entry.id] && tasks[tool.entry.id]!.kind !== 'remove'"
            class="progress"
            role="progressbar"
            :aria-label="`${tasks[tool.entry.id]!.kind === 'install' ? 'Installing' : 'Updating'} ${tool.tool}`"
            aria-valuemin="0"
            aria-valuemax="100"
            :aria-valuenow="Math.round(tasks[tool.entry.id]!.progress * 100)"
          >
            <m.div
              class="progress-bar"
              :initial="{ scaleX: 0 }"
              :animate="{ scaleX: tasks[tool.entry.id]!.progress }"
              :transition="spring.snappy"
            />
          </div>

          <div v-if="tool.stored" class="deck-settings">
            <label class="check">
              <input
                type="checkbox"
                :checked="tool.stored.includeObscure"
                @change="onToggle(tool.entry.id, 'obscure', $event)"
              />
              Include obscure options
            </label>
            <label class="check">
              <input
                type="checkbox"
                :checked="tool.stored.typeAnswers ?? false"
                @change="onToggle(tool.entry.id, 'typed', $event)"
              />
              Type answers
            </label>
            <label class="check">
              <input
                type="checkbox"
                :checked="tool.stored.paused ?? false"
                @change="onToggle(tool.entry.id, 'paused', $event)"
              />
              Pause deck
            </label>
          </div>

          <div class="actions">
            <template v-if="!tool.stored">
              <UiButton
                variant="primary"
                :disabled="Boolean(tasks[tool.entry.id])"
                @click="library.install(tool.entry)"
                >Install</UiButton
              >
            </template>
            <template v-else>
              <UiButton
                v-if="tool.updateAvailable"
                variant="primary"
                :disabled="Boolean(tasks[tool.entry.id])"
                @click="library.update(tool.entry)"
                >Update to v{{ tool.entry.deckVersion }}</UiButton
              >
              <UiButton
                v-if="confirmingRemove !== tool.entry.id"
                :disabled="Boolean(tasks[tool.entry.id])"
                @click="askRemove(tool.entry.id)"
                >Remove</UiButton
              >
            </template>
            <RouterLink class="browse-link" :to="`/decks/${tool.entry.id}`"
              >Browse options</RouterLink
            >
          </div>

          <AnimatePresence>
            <m.div
              v-if="confirmingRemove === tool.entry.id"
              key="confirm"
              class="confirm"
              role="group"
              :aria-label="`Remove ${tool.tool}`"
              :initial="{ opacity: 0 }"
              :animate="{ opacity: 1, transition: fade.quick }"
              :exit="{ opacity: 0, transition: fade.quick }"
            >
              <p>Remove {{ tool.tool }}? Your review history is kept unless you reset it.</p>
              <label class="check">
                <input v-model="resetProgress" type="checkbox" />
                Also reset progress for this deck
              </label>
              <div class="actions">
                <UiButton variant="again" @click="confirmRemove(tool.entry.id)"
                  >Remove deck</UiButton
                >
                <UiButton @click="confirmingRemove = undefined">Cancel</UiButton>
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

.status:empty {
  display: none;
}

.error {
  color: var(--color-again);
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

.meta {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-1) var(--space-4);
}

.variants {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  margin: 0;
  padding: 0;
  border: 0;
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
