import 'dart:ffi';
import 'dart:io';

import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

/// Registers SQLCipher as the SQLite implementation that `package:sqlite3`
/// (and therefore Drift) will load on each platform.
///
/// Must be called:
/// - Once during app startup (main isolate), before any DB is opened.
/// - Inside `NativeDatabase.isolateSetup` so the Drift background isolate
///   resolves to the same encrypted library.
class SqlCipherLoader {
  SqlCipherLoader._();

  static bool _registered = false;

  static void registerOpenOverride() {
    if (_registered) return;
    _registered = true;

    if (Platform.isAndroid) {
      open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
    } else if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlcipher.so'),
      );
    } else if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('sqlcipher.dll'),
      );
    }
    // iOS / macOS: sqlcipher_flutter_libs links SQLCipher statically into the
    // main binary, so no override is necessary — the default loader picks it up.
  }
}
