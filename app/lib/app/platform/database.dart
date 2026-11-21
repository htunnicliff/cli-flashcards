/// Opens the app's database: IndexedDB on the web, a file elsewhere.
library;

export 'database_io.dart' if (dart.library.js_interop) 'database_web.dart';
