import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

/// Returns the appropriate cross-platform SQLite [DatabaseFactory]:
/// - On Windows, Linux, and macOS (including `flutter test`): `databaseFactoryFfi`
///   backed by bundled native SQLite (`sqlite3_flutter_libs` / system `libsqlite3`).
/// - On Android and iOS: native platform `sqflite` factory.
DatabaseFactory resolveDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    if (!_ffiInitialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
    }
    return databaseFactoryFfi;
  }
  return databaseFactory;
}
