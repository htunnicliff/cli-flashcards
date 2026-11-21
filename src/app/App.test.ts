import { mount } from '@vue/test-utils'
import { createPinia } from 'pinia'
import { describe, expect, it } from 'vitest'
import { createMemoryHistory, createRouter } from 'vue-router'

import App from './App.vue'
import { routes } from './router'

async function mountAt(path: string) {
  const router = createRouter({ history: createMemoryHistory(), routes })
  await router.push(path)
  await router.isReady()
  return mount(App, { global: { plugins: [createPinia(), router] } })
}

describe('App', () => {
  it('links to every top-level page', async () => {
    const wrapper = await mountAt('/')
    const hrefs = wrapper.findAll('nav a').map((a) => a.attributes('href'))
    expect(hrefs).toEqual(['/', '/decks', '/stats', '/settings'])
  })

  it.each([
    ['/', "Today's review"],
    ['/decks', 'Decks'],
    ['/stats', 'Stats'],
    ['/settings', 'Settings'],
  ])('renders the %s route', async (path, heading) => {
    const wrapper = await mountAt(path)
    expect(wrapper.find('h1').text()).toBe(heading)
  })
})
