# CLAUDE.md

Personal offline-first app (current name: **Atharxa**) for Android phones and macOS, built with Flutter (Material 3).
It covers calories, meal plan, water, workouts and finance, with peer-to-peer Wi-Fi sync and a planned on-device AI assistant.

## Design source of truth
- **`docs/design/DESIGN.md`** is the spec for behaviour, numbers, tokens and layout. Read the relevant section before building or changing a screen.
- `docs/design/boards/*.dc.html` are the visual mockups (Claude Design canvas exports). Use them as a visual reference only; they don't run on their own. `docs/design/boards/m3.css` has the exact tokens.
- If a board and DESIGN.md disagree, follow DESIGN.md and point out the conflict.
- Decisions made after the handoff:
  - Fat goal default is 75 g.
  - Sync conflicts: last write wins, per row.
  - Finance: one default currency plus a currency per transaction; totals are kept separate per currency, with no FX conversion.
  - AI: Gemma 4 by default, with Qwen models as an option.
  - Workout videos are embedded YouTube links, with no API key.
  - The "Today" tab is called **Overview**.

## Principle: keep names generic
The app's name may change, so **don't build the product name into code identifiers**.
- Classes, files, providers, widgets and keys get generic names: `App`, `AppTopBar`, `AppTextScaler`, `AppShell`, `overviewProvider`. Never `AtharxaTopBar`.
- User-facing strings take the name from **`lib/app_info.dart`** (`AppInfo.name`, `AppInfo.assistantName`). Don't hard-code it in widgets.
- Stored keys and protocol identifiers that must stay stable (database columns, pref keys, water `source` values) are generic too.
- The name currently also appears in places that can't read a Dart constant. A rename means updating these:
  - `pubspec.yaml` `name:` (the package import prefix)
  - Android `applicationId`/`namespace` (`android/app/build.gradle.kts`), the `android:label`, and the Kotlin package folder
  - macOS `PRODUCT_NAME` / `PRODUCT_BUNDLE_IDENTIFIER` (`macos/Runner/Configs/AppInfo.xcconfig`) and `project.pbxproj`
  - The database file name (`lib/data/db.dart`), plus the mDNS service type `AppInfo.syncServiceType` together with its copy in `NSBonjourServices` in `macos/Runner/Info.plist`
  - App icons (`assets/icon/`)

## Principle: no hand-written native code
- `macos/Runner/*.swift` and the Android `MainActivity` stay exactly as Flutter generates them. Platform features come from plugins, or from `nativeapi_flutter` (Dart FFI covering windows, tray, menus and login items), or from config (`Info.plist`, entitlements, `AndroidManifest.xml`, Gradle).
- If something truly can't be done without native code, ask the user first.

## Architecture
- **State: Riverpod 3** (`flutter_riverpod`, no code generation). Don't add new `ChangeNotifier`s, `InheritedWidget`s or hand-rolled reload widgets.
  - `lib/state/core_providers.dart`: `dbProvider`, `prefsProvider` and the service providers, overridden in `main.dart` (`appOverrides`). Also `tableVersionProvider(table)`, which ticks whenever a table changes, locally or through sync. Data providers call `ref.watchTables([...])` to re-query.
  - `lib/state/settings_providers.dart`:
    - `syncedSettingsProvider`: goals, palette, currency and name, stored in the `prefs` table and synced.
    - `deviceSettingsProvider`: mode, text size and first run, stored in SharedPreferences and never synced.
    - `selectedDayProvider`: shared by Overview and Water.
  - `lib/state/data_providers.dart`: per-screen `FutureProvider.family`s keyed by day key, plus `AsyncBody`.
  - Callbacks without a `ref` can use `context.db` / `context.readProvider(...)` for imperative reads only.
  - `lib/state/sync_controller.dart` (`syncControllerProvider`): Wi-Fi sync state and actions.
  - `lib/state/reminders_controller.dart` (`remindersProvider`): reminder settings stored per device. It re-plans notifications about 1 s after any food, water, plan or goal change, and on app resume.
- **Reminders** (`lib/services/`):
  - `reminder_plan.dart`: pure planning of one-shot notifications for the next 7 days. Logged meals are skipped, water stops once the goal is met, and today's text uses live numbers.
  - `notification_service.dart`: wraps flutter_local_notifications.
    - Action buttons (+250 ml, Log or Add meal, Snooze) run in a background isolate when the app isn't open (`notificationActionInBackground`).
    - It also runs the Android foreground service for "Keep syncing while locked".
- **Data**: SQLite through `sqflite` (`lib/data/db.dart`).
  - Every synced table has `id` (a UUID), `updated_at` (a hybrid logical clock), `device_id`, `deleted` (a tombstone) and `rev` (a local change counter).
  - Always write through `AppDb.save` and `AppDb.delete`, never with raw SQL writes, so that sync sees the change.
  - Food logs and plans store a **per-100 g snapshot** plus grams. Macros may be `null`, meaning unknown; show them as "—", never as 0.
  - Repositories: `FoodRepo`, `WaterRepo`.
- **Wi-Fi sync** (`lib/sync/`), peer to peer with no cloud:
  - `sync_auth.dart`: a key derived from the 6-digit pairing code (PBKDF2), and HMAC-signed requests and responses.
  - `sync_protocol.dart`: an HTTP server with hello, pull and push, and a client that sends paged changes with cursors per peer. Errors are typed (code mismatch, unreachable, interrupted).
  - `discovery.dart`: mDNS through bonsoir.
  - `peers.dart`: per-device prefs.
  - `background_sync.dart`: an Android workmanager task every 15 minutes.
  - Edits made on the device itself (`AppDb.localChanges`) trigger auto-sync. Rows merged from a peer don't, and rows last edited by a peer are never sent back to it.
- **UI**:
  - `lib/ui/shell.dart` is the responsive shell: `NavigationBar` under 600 dp, `NavigationRail` (with You) at 600 dp and up.
  - The theme is in `lib/ui/theme/`. Colour schemes are explicit, from DESIGN.md §3.1 (never `fromSeed`). Semantic colours are a `ThemeExtension` (`context.sem`).
  - Text size uses the app-level `AppTextScaler`.
  - macOS: `lib/state/desktop_controller.dart` uses `nativeapi_flutter` to hide the title bar, set the minimum window size, hide the window on close while sync is on, add the menu bar item and handle open at login. App Nap is off through `NSAppSleepDisabled` in `Info.plist`. `AppChrome` adds the top inset for the window buttons.

## Workflow
- Branches: `main` (stable) ← `dev/v1` (integration) ← `feat/*`.
- **Work one feature at a time. Don't push or open PRs until the user asks.** Never merge without being asked.
- **For now, keep all work on the current branch (`feat/sync`).** Don't create new branches until the user asks.
- Before committing: `dart format lib test` (page width 120), then `flutter analyze` (must be clean) and `flutter test`.
- Render tests in `test/screens/` produce PNGs in `test/screens/goldens/` at phone size (412 dp, 130 % text) and Mac size (1200 px). Refresh them with `flutter test --update-goldens test/screens` and compare against the boards.
- Use the latest stable versions of packages and tools.
- Running the app: `flutter run -d macos`, and on the Pixel `flutter run -d <id>` (`adb` is at `~/Library/Android/sdk/platform-tools`).
