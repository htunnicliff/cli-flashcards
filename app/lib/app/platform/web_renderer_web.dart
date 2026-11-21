import 'dart:js_interop';

@JS('localStorage.getItem')
external String? _getItem(String key);

@JS('localStorage.setItem')
external void _setItem(String key, String value);

@JS('location.reload')
external void _reload();

/// The same key flutter_bootstrap.js reads before it picks a build.
const _key = 'recall:wasm';

bool wasmRequested() {
  try {
    return _getItem(_key) == '1';
  } catch (_) {
    return false;
  }
}

/// Saves the choice and reloads, since the renderer is picked at startup.
void requestWasm(bool on) {
  try {
    _setItem(_key, on ? '1' : '0');
  } catch (_) {
    return;
  }
  _reload();
}
