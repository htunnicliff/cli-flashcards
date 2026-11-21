import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { nextTick } from 'vue'

import { APPEARANCE_STORAGE_KEY, loadAppearance, useAppearanceStore } from './appearance'

function themeColors() {
  return [...document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]')].map(
    (meta) => meta.content,
  )
}

describe('appearance', () => {
  beforeEach(() => {
    localStorage.clear()
    delete document.documentElement.dataset.theme
    delete document.documentElement.dataset.fontSize
    document.head.innerHTML = `
      <meta name="theme-color" media="(prefers-color-scheme: light)" content="#F6F5F2">
      <meta name="theme-color" media="(prefers-color-scheme: dark)" content="#121315">`
    setActivePinia(createPinia())
  })

  it('defaults to following the system at medium size', () => {
    const store = useAppearanceStore()
    expect(store.theme).toBe('system')
    expect(store.fontSize).toBe('m')
    expect(document.documentElement.dataset.theme).toBeUndefined()
    expect(document.documentElement.dataset.fontSize).toBe('m')
    expect(themeColors()).toEqual(['#F6F5F2', '#121315'])
  })

  it('applies and persists an override', async () => {
    const store = useAppearanceStore()
    store.theme = 'dark'
    store.fontSize = 'l'
    await nextTick()

    expect(document.documentElement.dataset.theme).toBe('dark')
    expect(document.documentElement.dataset.fontSize).toBe('l')
    expect(themeColors()).toEqual(['#121315', '#121315'])
    expect(JSON.parse(localStorage.getItem(APPEARANCE_STORAGE_KEY)!)).toEqual({
      theme: 'dark',
      fontSize: 'l',
    })

    store.theme = 'system'
    await nextTick()
    expect(document.documentElement.dataset.theme).toBeUndefined()
    expect(themeColors()).toEqual(['#F6F5F2', '#121315'])
  })

  it('restores saved settings', () => {
    localStorage.setItem(APPEARANCE_STORAGE_KEY, JSON.stringify({ theme: 'light', fontSize: 's' }))
    const store = useAppearanceStore()
    expect(store.theme).toBe('light')
    expect(store.fontSize).toBe('s')
  })

  it.each([
    ['garbage', 'not json'],
    ['wrong values', JSON.stringify({ theme: 'sepia', fontSize: 'xl' })],
    ['null', 'null'],
  ])('falls back to defaults for %s', (_, raw) => {
    expect(loadAppearance({ getItem: () => raw })).toEqual({ theme: 'system', fontSize: 'm' })
  })

  describe('pre-paint script in index.html', () => {
    const html = readFileSync(resolve(import.meta.dirname, '../../../index.html'), 'utf8')
    const script = /<script>([\s\S]*?)<\/script>/.exec(html)![1]!

    it('applies a saved override before the app loads', () => {
      localStorage.setItem(APPEARANCE_STORAGE_KEY, JSON.stringify({ theme: 'dark', fontSize: 's' }))
      new Function(script)()
      expect(document.documentElement.dataset.theme).toBe('dark')
      expect(document.documentElement.dataset.fontSize).toBe('s')
      expect(themeColors()).toEqual(['#121315', '#121315'])
    })

    it('leaves the system theme alone', () => {
      new Function(script)()
      expect(document.documentElement.dataset.theme).toBeUndefined()
      expect(themeColors()).toEqual(['#F6F5F2', '#121315'])
    })

    it('ignores broken storage', () => {
      localStorage.setItem(APPEARANCE_STORAGE_KEY, '{')
      expect(() => new Function(script)()).not.toThrow()
    })
  })
})
