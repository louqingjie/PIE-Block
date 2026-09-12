import 'dart:io';

/// Returns the conventional desktop directory when it exists.
///
/// File dialogs remain the source of truth: this is only an initial suggestion
/// for the desktop text fields.
String? defaultDesktopDirectory() {
  if (Platform.isAndroid) return null;

  final home = Platform.isWindows
      ? Platform.environment['USERPROFILE']
      : Platform.environment['HOME'];
  if (home == null || home.isEmpty) return null;

  final desktop = '$home${Platform.pathSeparator}Desktop';
  return Directory(desktop).existsSync() ? desktop : null;
}
