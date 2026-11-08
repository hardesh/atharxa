/// Product identity — the ONLY place the app's display name lives in Dart.
///
/// Code (classes, files, providers) uses generic names (`App`, `AppTopBar`,
/// `AppTextScaler`); user-facing strings interpolate [AppInfo.name]. To rename
/// the app, change it here plus the platform identifiers listed in CLAUDE.md.
abstract final class AppInfo {
  static const name = 'Atharxa';

  /// Shown on the AI button ("Ask Atharxa") and assistant screens.
  static const assistantName = name;
}
