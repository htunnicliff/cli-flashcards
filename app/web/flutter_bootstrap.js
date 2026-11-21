{{flutter_js}}
{{flutter_build_config}}

// Offline support. sw.js is generated after `flutter build web` by
// tools/flutter-sw.ts (pnpm flutter:sw). A new version installs in the
// background and waits; it takes over only while the page is hidden, so code
// never changes under someone mid-review.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').then((registration) => {
    let reloading = false
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (reloading) return
      reloading = true
      location.reload()
    })
    const activateWaiting = () => {
      if (document.visibilityState === 'hidden' && registration.waiting) {
        registration.waiting.postMessage({ type: 'SKIP_WAITING' })
      }
    }
    document.addEventListener('visibilitychange', activateWaiting)
    setInterval(() => {
      if (navigator.onLine) registration.update()
    }, 60 * 60 * 1000)
  }).catch(() => {
    // No sw.js in `flutter run`; the app works without it.
  })
}

_flutter.loader.load()
