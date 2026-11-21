import { readonly, ref } from 'vue'

const online = ref(typeof navigator === 'undefined' ? true : navigator.onLine)
let listening = false

/**
 * Whether the browser thinks it has a network connection. `navigator.onLine` can say
 * "online" on a network with no internet, so treat `true` as "worth trying", and
 * `false` as reliable: use it to disable actions that need the network.
 */
export function useOnline() {
  if (!listening && typeof window !== 'undefined') {
    listening = true
    window.addEventListener('online', () => (online.value = true))
    window.addEventListener('offline', () => (online.value = false))
  }
  return readonly(online)
}
