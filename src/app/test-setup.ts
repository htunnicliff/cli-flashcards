// happy-dom has no IndexedDB. Components that fall back to the shared
// repository get an in-memory one instead of failing.
import 'fake-indexeddb/auto'

// Component tests run with prefers-reduced-motion: reduce, like the E2E tests, so
// animations can't make results timing-dependent. Tests that check motion itself
// override this through the appearance store's `motion` setting.
const realMatchMedia = window.matchMedia.bind(window)

window.matchMedia = (query: string) => {
  const result = realMatchMedia(query)
  if (!query.includes('prefers-reduced-motion')) return result
  const matches = /prefers-reduced-motion:\s*reduce\b/.test(query)
  return new Proxy(result, {
    get: (target, key) => {
      if (key === 'matches') return matches
      const value = Reflect.get(target, key, target)
      return typeof value === 'function' ? value.bind(target) : value
    },
  })
}
