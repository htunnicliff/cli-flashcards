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

// Experimental: the Wasm renderer (skwasm), switched on per browser from
// Settings or with ?wasm=1 (?wasm=0 switches it off). Off by default, so every
// browser runs the JavaScript build with CanvasKit, which is what sw.js
// precaches. Where the browser can't run Wasm, Flutter falls back to that.
const wasm = (() => {
  try {
    const asked = new URLSearchParams(location.search).get('wasm')
    if (asked === '1' || asked === '0') localStorage.setItem('recall:wasm', asked)
    return localStorage.getItem('recall:wasm') === '1'
  } catch {
    return false
  }
})()

_flutter.loader.load({
  config: { wasmAllowList: { blink: wasm, gecko: wasm, webkit: wasm } },
})
