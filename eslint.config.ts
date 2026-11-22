import prettier from 'eslint-config-prettier'
import { globalIgnores } from 'eslint/config'
import globals from 'globals'
import tseslint from 'typescript-eslint'

export default tseslint.config(
  globalIgnores(['**/coverage/**', 'apple/**', 'vendor/**']),

  tseslint.configs.recommended,

  {
    name: 'pipeline/node',
    files: ['**/*.ts'],
    languageOptions: { globals: globals.node },
  },

  prettier,
)
