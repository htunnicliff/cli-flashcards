<script setup lang="ts">
import { RouterLink, RouterView } from 'vue-router'

const links = [
  { to: '/', label: 'today' },
  { to: '/decks', label: 'decks' },
  { to: '/stats', label: 'stats' },
  { to: '/settings', label: 'settings' },
]
</script>

<template>
  <header class="app-header">
    <span class="app-title">$ flashcards</span>
    <nav aria-label="Main">
      <RouterLink v-for="link in links" :key="link.to" :to="link.to">{{ link.label }}</RouterLink>
    </nav>
  </header>
  <main class="app-main">
    <RouterView />
  </main>
</template>

<style scoped>
.app-header {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space);
  align-items: baseline;
  padding: var(--space);
  border-bottom: 1px solid var(--color-muted);
}

.app-title {
  font-weight: 700;
}

nav {
  display: flex;
  gap: var(--space);
}

nav a.router-link-exact-active {
  font-weight: 700;
  text-decoration: none;
}

.app-main {
  padding: var(--space);
}
</style>
