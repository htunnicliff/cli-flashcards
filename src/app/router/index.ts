import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'

export const routes: RouteRecordRaw[] = [
  {
    path: '/',
    name: 'review',
    component: () => import('../views/ReviewView.vue'),
  },
  {
    path: '/decks',
    name: 'decks',
    component: () => import('../views/DecksView.vue'),
  },
  {
    path: '/stats',
    name: 'stats',
    component: () => import('../views/StatsView.vue'),
  },
  {
    path: '/settings',
    name: 'settings',
    component: () => import('../views/SettingsView.vue'),
  },
]

export const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
})
