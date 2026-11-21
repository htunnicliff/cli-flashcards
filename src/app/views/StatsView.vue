<script setup lang="ts">
import { computed, onMounted, shallowRef } from 'vue'

import { computeStats, type Stats } from '@/core/stats'

import CountUp from '../components/stats/CountUp.vue'
import ForecastChart from '../components/stats/ForecastChart.vue'
import ReviewHeatmap from '../components/stats/ReviewHeatmap.vue'
import { useRepository } from '../repository'

const repository = useRepository()
const stats = shallowRef<Stats>()

onMounted(async () => {
  const [decks, log, rolloverHour] = await Promise.all([
    repository.decks.list(),
    repository.reviewLog.all(),
    repository.settings.get('dayRolloverHour'),
  ])
  const states = (
    await Promise.all(decks.map((d) => repository.cardStates.listByDeck(d.id)))
  ).flat()
  stats.value = computeStats({ decks, states, log, now: Date.now(), rolloverHour })
})

const percent = (value: number) => `${Math.round(value * 100)}%`
const retention = computed(() => stats.value?.retention)
</script>

<template>
  <section class="stats" :aria-busy="!stats">
    <h1>Stats</h1>

    <template v-if="stats">
      <div class="tiles">
        <div class="tile" data-testid="reviews-today">
          <span class="tile-value"><CountUp :value="stats.reviewsToday" /></span>
          <span class="tile-label">Reviews today</span>
        </div>
        <div class="tile" data-testid="streak">
          <span class="tile-value"><CountUp :value="stats.streak" /></span>
          <span class="tile-label">Day streak</span>
        </div>
        <div class="tile" data-testid="retention">
          <span class="tile-value">
            <CountUp
              v-if="retention?.rate !== undefined"
              :value="retention.rate"
              :format="percent"
            />
            <template v-else>–</template>
          </span>
          <span class="tile-label">
            Retention, 30 days
            <span class="tile-note">
              {{
                retention?.total
                  ? `${retention.passed} of ${retention.total} mature reviews passed`
                  : 'No mature cards reviewed yet'
              }}
            </span>
          </span>
        </div>
      </div>

      <section class="panel" aria-labelledby="forecast-heading">
        <h2 id="forecast-heading">Due forecast</h2>
        <ForecastChart :days="stats.forecast" />
      </section>

      <section class="panel" aria-labelledby="history-heading">
        <h2 id="history-heading">Past year</h2>
        <ReviewHeatmap :days="stats.history" />
      </section>

      <section class="panel" aria-labelledby="cards-heading">
        <h2 id="cards-heading">Cards</h2>
        <p v-if="stats.cards.length === 0" class="hint">Install a deck to see its cards here.</p>
        <div v-else class="table-scroll" tabindex="0" role="region" aria-labelledby="cards-heading">
          <table>
            <thead>
              <tr>
                <th scope="col">Deck</th>
                <th scope="col">New</th>
                <th scope="col">Learning</th>
                <th scope="col">Review</th>
                <th scope="col">Suspended</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="deck in stats.cards" :key="deck.deckId">
                <th scope="row" class="mono">{{ deck.deckId }}</th>
                <td>{{ deck.new }}</td>
                <td>{{ deck.learning }}</td>
                <td>{{ deck.review }}</td>
                <td>{{ deck.suspended }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
    <p v-else class="hint">Adding things up…</p>
  </section>
</template>

<style scoped>
.stats {
  display: flex;
  flex-direction: column;
  gap: var(--space-8);
}

h1 {
  margin: 0;
  font-size: var(--text-2xl);
}

h2 {
  margin: 0;
  font-size: var(--text-md);
  font-weight: 600;
}

.tiles {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: var(--space-3);
}

.tile {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  padding: var(--space-4);
  border: var(--border-width) solid var(--color-border);
  border-radius: var(--radius-button);
  background: var(--color-surface);
}

.tile-value {
  font-size: var(--text-2xl);
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  line-height: var(--line-height-tight);
}

.tile-label {
  display: flex;
  flex-direction: column;
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.tile-note {
  font-size: var(--text-xs);
}

.panel {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.hint {
  margin: 0;
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.table-scroll {
  overflow-x: auto;
}

table {
  width: 100%;
  border-collapse: collapse;
  font-size: var(--text-sm);
  font-variant-numeric: tabular-nums;
}

th,
td {
  padding: var(--space-2) var(--space-3);
  border-bottom: var(--border-width) solid var(--color-border);
  text-align: right;
}

th:first-child {
  text-align: left;
}

thead th {
  color: var(--color-muted);
  font-weight: 600;
}

@media (max-width: 600px) {
  .tiles {
    grid-template-columns: 1fr 1fr;
  }

  .tile[data-testid='retention'] {
    grid-column: 1 / -1;
  }

  th,
  td {
    padding: var(--space-2);
    font-size: var(--text-xs);
  }
}
</style>
