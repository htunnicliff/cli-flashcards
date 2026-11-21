/**
 * The colour roles from the design direction (#22), for both themes.
 *
 * `tokens.css` is what the app actually uses; this module mirrors its values so unit
 * tests can check contrast. A test fails if the two ever disagree.
 */
export const themes = ['light', 'dark'] as const
export type ThemeName = (typeof themes)[number]

export const palette = {
  light: {
    bg: '#F6F5F2',
    surface: '#FFFFFF',
    sunken: '#EFEDE8',
    border: '#DEDBD3',
    text: '#1D1C1A',
    muted: '#5F5C55',
    accent: '#2B54C9',
    arg: '#9A4A05',
    again: '#A3203A',
    'again-tint': '#FBE8EB',
    'again-border': '#F2C9D0',
    'on-primary': '#FFFFFF',
    kbd: '#EFEDE8',
  },
  dark: {
    bg: '#121315',
    surface: '#1A1B1E',
    sunken: '#232428',
    border: '#303237',
    text: '#ECEAE5',
    muted: '#A19E96',
    accent: '#94B2FF',
    arg: '#F2A65E',
    again: '#FF94A6',
    'again-tint': '#3A1C23',
    'again-border': '#55283A',
    'on-primary': '#0F1730',
    kbd: '#26272B',
  },
} as const satisfies Record<ThemeName, Record<string, string>>

export type ColorRole = keyof (typeof palette)['light']

/** Text colour → backgrounds it is drawn on. Every pair must meet WCAG AA (4.5:1). */
export const textPairs: ReadonlyArray<readonly [ColorRole, ReadonlyArray<ColorRole>]> = [
  ['text', ['bg', 'surface', 'sunken']],
  ['muted', ['bg', 'surface', 'sunken']],
  ['accent', ['bg', 'surface', 'sunken']],
  ['arg', ['bg', 'surface', 'sunken']],
  ['again', ['again-tint']],
  ['on-primary', ['accent']],
  ['text', ['kbd']],
]

/** Browser UI colour (the `theme-color` meta and manifest) for each theme. */
export const themeColor: Record<ThemeName, string> = {
  light: palette.light.bg,
  dark: palette.dark.bg,
}
