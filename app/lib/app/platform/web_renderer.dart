/// The experimental Wasm renderer switch on the web (see
/// web/flutter_bootstrap.js). Elsewhere these do nothing.
library;

export 'web_renderer_io.dart'
    if (dart.library.js_interop) 'web_renderer_web.dart';

/// Whether this build is running as WebAssembly (the skwasm renderer).
const runningWasm = bool.fromEnvironment('dart.tool.dart2wasm');
