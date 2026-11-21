import skipFormatting from '@vue/eslint-config-prettier/skip-formatting'
import { defineConfigWithVueTs, vueTsConfigs } from '@vue/eslint-config-typescript'
import { globalIgnores } from 'eslint/config'
import pluginVue from 'eslint-plugin-vue'
import globals from 'globals'

export default defineConfigWithVueTs(
  {
    name: 'app/files-to-lint',
    files: ['**/*.{ts,mts,tsx,vue}'],
  },

  globalIgnores([
    '**/dist/**',
    '**/dist-e2e/**',
    '**/coverage/**',
    'app/**',
    'playwright-report/**',
    'test-results/**',
  ]),

  pluginVue.configs['flat/essential'],
  vueTsConfigs.recommended,

  {
    name: 'app/node-scripts',
    files: ['tools/**/*.ts', 'e2e/**/*.ts', '*.config.ts'],
    languageOptions: { globals: globals.node },
  },

  skipFormatting,
)
