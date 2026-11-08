/// Product identity — the ONLY place the app's display name lives in Dart.
///
/// Code (classes, files, providers) uses generic names (`App`, `AppTopBar`,
/// `AppTextScaler`); user-facing strings interpolate [AppInfo.name]. To rename
/// the app, change it here plus the platform identifiers listed in CLAUDE.md.
abstract final class AppInfo {
  static const name = 'Atharxa';

  /// Shown on the AI button ("Ask Atharxa") and assistant screens.
  static const assistantName = name;

  /// mDNS/DNS-SD service type devices advertise for Wi-Fi sync. Changing it
  /// stops old and new versions from finding each other; keep it stable and
  /// in sync with NSBonjourServices in macos/Runner/Info.plist.
  static const syncServiceType = '_atharxa-sync._tcp';
}
