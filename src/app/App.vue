<script setup lang="ts">
import { RouterLink, RouterView } from 'vue-router'

import MotionRoot from './motion/MotionRoot.vue'
import OfflineIndicator from './pwa/OfflineIndicator.vue'
import UpdatePrompt from './pwa/UpdatePrompt.vue'
import { useAppearanceStore } from './stores/appearance'

// Instantiated here so the saved theme and text size stay applied on every page.
useAppearanceStore()

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
    <UpdatePrompt />
  </MotionRoot>
</template>

<style scoped>
.app-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3) var(--space-6);
  padding: 14px var(--space-8);
  border-bottom: var(--border-width) solid var(--color-border);
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

.app-nav {
  display: flex;
  gap: var(--space-1);
}

.nav-link {
  padding: var(--space-2) var(--space-3);
  border-radius: var(--radius-small);
  color: var(--color-muted);
  font-size: var(--text-sm);
  text-decoration: none;
}

.nav-link:hover {
  color: var(--color-text);
}

.nav-link.router-link-exact-active {
  background: var(--color-sunken);
  color: var(--color-text);
  font-weight: 600;
}

.app-main {
  width: 100%;
  max-width: calc(var(--content-width) + 2 * var(--space-6));
  margin: 0 auto;
  padding: var(--space-10) var(--space-6) var(--space-12);
}

/* Phone: the same four destinations as a bottom tab bar, in the thumb zone. */
@media (max-width: 600px) {
  .app-header {
    padding: var(--space-3) var(--space-4);
  }

  .app-nav {
    position: fixed;
    inset: auto 0 0;
    z-index: 10;
    justify-content: space-around;
    padding: var(--space-1) var(--space-2) calc(var(--space-1) + env(safe-area-inset-bottom));
    border-top: var(--border-width) solid var(--color-border);
    background: var(--color-surface);
  }

  .nav-link {
    flex: 1;
    min-height: 48px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: var(--text-xs);
  }

  .app-main {
    padding: var(--space-6) var(--space-4) calc(72px + env(safe-area-inset-bottom));
  }
}
</style>
