<script setup lang="ts">
import { onMounted, watch } from 'vue'
import { RouterLink, RouterView } from 'vue-router'

import { installPendingDecks } from './decks/pending'
import MotionRoot from './motion/MotionRoot.vue'
import { useOnboardingStore } from './onboarding/onboarding'
import OnboardingTour from './onboarding/OnboardingTour.vue'
import OfflineIndicator from './pwa/OfflineIndicator.vue'
import { useOnline } from './pwa/online'
import { useServiceWorker } from './pwa/service-worker'
import { useRepository } from './repository'
import { useAppearanceStore } from './stores/appearance'

// Instantiated here so the saved theme and text size stay applied on every page.
useAppearanceStore()

// New versions install in the background and take over at a quiet moment.
useServiceWorker()

// Decks a backup import couldn't fetch (it was offline) install on the next
// start or when the connection comes back, without a visit to Decks.
const repository = useRepository()
const online = useOnline()
function retryPendingDecks() {
  if (online.value) installPendingDecks(repository).catch(() => {})
}
onMounted(retryPendingDecks)

// First visit: a short tour of decks, reviewing and offline use (replayable from Settings).
const onboarding = useOnboardingStore()
onMounted(() => onboarding.startIfNew(repository))
watch(online, retryPendingDecks)

const links = [
  { to: '/', label: 'Review' },
  { to: '/decks', label: 'Decks' },
  { to: '/stats', label: 'Stats' },
  { to: '/settings', label: 'Settings' },
]
</script>

<template>
  <MotionRoot>
    <header class="app-header">
      <div class="app-brand">
        <RouterLink to="/" class="wordmark mono" aria-label="--recall, home"
          ><span class="wordmark-dashes" aria-hidden="true">--</span>recall</RouterLink
        >
        <OfflineIndicator />
      </div>
      <nav aria-label="Main" class="app-nav">
        <RouterLink v-for="link in links" :key="link.to" :to="link.to" class="nav-link">{{
          link.label
        }}</RouterLink>
      </nav>
    </header>
    <main class="app-main">
      <RouterView />
    </main>
    <OnboardingTour />
  </MotionRoot>
</template>

<style scoped>
/* A frosted bar that content scrolls under. */
.app-header {
  position: sticky;
  top: 0;
  z-index: 20;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3) var(--space-6);
  padding: 14px var(--space-8);
  border-bottom: var(--border-width) solid var(--glass-edge);
  background: var(--glass-chrome);
  -webkit-backdrop-filter: var(--glass-filter);
  backdrop-filter: var(--glass-filter);
}

.app-brand {
  display: flex;
  align-items: center;
  gap: var(--space-3);
}

.wordmark {
  color: var(--color-text);
  font-size: var(--text-lg);
  font-weight: 700;
  text-decoration: none;
  border-radius: var(--radius-small);
}

.wordmark-dashes {
  color: var(--color-accent);
}

/* A capsule of tabs; the current one is a raised pane. */
.app-nav {
  display: flex;
  gap: var(--space-1);
  padding: var(--space-1);
  border-radius: var(--radius-pill);
  background: var(--color-sunken);
}

.nav-link {
  padding: var(--space-2) var(--space-4);
  border-radius: var(--radius-pill);
  color: var(--color-muted);
  font-size: var(--text-sm);
  text-decoration: none;
}

.nav-link:hover {
  color: var(--color-text);
}

.nav-link.router-link-exact-active {
  background: var(--color-surface);
  box-shadow: var(--shadow-control);
  color: var(--color-text);
  font-weight: 600;
}

.app-main {
  width: 100%;
  max-width: calc(var(--content-width) + 2 * var(--space-6));
  margin: 0 auto;
  padding: var(--space-10) var(--space-6) var(--space-12);
}

/* Phone: the same four destinations as a floating glass tab bar, in the thumb zone. */
@media (max-width: 600px) {
  .app-header {
    position: static;
    padding: var(--space-3) var(--space-4);
    border-bottom: 0;
    background: none;
    -webkit-backdrop-filter: none;
    backdrop-filter: none;
  }

  .app-nav {
    position: fixed;
    inset: auto var(--space-4) calc(var(--space-3) + env(safe-area-inset-bottom));
    z-index: 10;
    justify-content: space-around;
    padding: 5px;
    border: var(--border-width) solid var(--glass-rim);
    background: var(--glass-sheen), var(--glass-chrome);
    box-shadow: var(--shadow-card);
    -webkit-backdrop-filter: var(--glass-filter);
    backdrop-filter: var(--glass-filter);
  }

  .nav-link {
    flex: 1;
    min-height: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-2);
    font-size: var(--text-xs);
  }

  .app-main {
    padding: var(--space-6) var(--space-4) calc(96px + env(safe-area-inset-bottom));
  }
}
</style>
