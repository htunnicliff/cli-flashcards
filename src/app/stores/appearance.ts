import { defineStore } from 'pinia'
import { ref, watch } from 'vue'

import { themeColor, type ThemeName } from '../styles/palette'

export const themePreferences = ['system', 'light', 'dark'] as const
export type ThemePreference = (typeof themePreferences)[number]

export const fontSizes = ['s', 'm', 'l'] as const
export type FontSize = (typeof fontSizes)[number]

export interface Appearance {
  theme: ThemePreference
  fontSize: FontSize
}

/**
 * Appearance settings live in localStorage, not IndexedDB (#8), because the inline
 * script in index.html has to read them synchronously before first paint so the page
 * never flashes the wrong theme or size. Keep this key and shape in step with that script.
 */
export const APPEARANCE_STORAGE_KEY = 'recall:appearance'

const defaults: Appearance = { theme: 'system', fontSize: 'm' }

export function loadAppearance(storage: Pick<Storage, 'getItem'> | undefined): Appearance {
  try {
    const raw = storage?.getItem(APPEARANCE_STORAGE_KEY)
    if (!raw) return { ...defaults }
    const parsed: unknown = JSON.parse(raw)
    if (typeof parsed !== 'object' || parsed === null) return { ...defaults }
    const { theme, fontSize } = parsed as Record<string, unknown>
    return {
      theme: themePreferences.includes(theme as ThemePreference)
        ? (theme as ThemePreference)
        : defaults.theme,
      fontSize: fontSizes.includes(fontSize as FontSize)
        ? (fontSize as FontSize)
        : defaults.fontSize,
    }
  } catch {
    return { ...defaults }
  }
}

function saveAppearance(value: Appearance) {
  try {
    localStorage.setItem(APPEARANCE_STORAGE_KEY, JSON.stringify(value))
  } catch {
    // Private mode or storage disabled: the setting still applies for this visit.
  }
}

/** Puts the settings on <html> and points the browser's theme-color at the right theme. */
export function applyAppearance(value: Appearance, doc: Document = document) {
  const root = doc.documentElement
  if (value.theme === 'system') delete root.dataset.theme
  else root.dataset.theme = value.theme
  root.dataset.fontSize = value.fontSize

  // Two metas with media queries cover "system"; an override pins both to one colour.
  for (const meta of doc.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]')) {
    const scheme: ThemeName = meta.getAttribute('media')?.includes('dark') ? 'dark' : 'light'
    meta.content = themeColor[value.theme === 'system' ? scheme : value.theme]
  }
}

export const useAppearanceStore = defineStore('appearance', () => {
  const initial = loadAppearance(typeof localStorage === 'undefined' ? undefined : localStorage)
  const theme = ref<ThemePreference>(initial.theme)
  const fontSize = ref<FontSize>(initial.fontSize)

  watch(
    [theme, fontSize],
    () => {
      const value = { theme: theme.value, fontSize: fontSize.value }
      applyAppearance(value)
      saveAppearance(value)
    },
    { immediate: true },
  )

  return { theme, fontSize }
})
