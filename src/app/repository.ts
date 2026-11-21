import { createRepository, type Repository } from '@/core/storage'
import type { InjectionKey } from 'vue'
import { inject } from 'vue'

let shared: Repository | undefined

/** The app's one IndexedDB connection, opened on first use. */
export function getRepository(): Repository {
  shared ??= createRepository()
  return shared
}

/** Tests `provide` a repository backed by fake-indexeddb under this key. */
export const repositoryKey: InjectionKey<Repository> = Symbol('repository')

/** The provided repository in a component, falling back to the shared one. */
export function useRepository(): Repository {
  return inject(repositoryKey, getRepository, true)
}
