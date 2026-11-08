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
  - The database file name (`lib/data/db.dart`) and the mDNS service type (`lib/sync/sync_service.dart`)
  - App icons (`assets/icon/`)

## Architecture
- **State: Riverpod 3** (`flutter_riverpod`, no code generation). Don't add new `ChangeNotifier`s, `InheritedWidget`s or hand-rolled reload widgets.
  - `lib/state/core_providers.dart`: `dbProvider`, `prefsProvider` and the service providers, overridden in `main.dart` (`appOverrides`). Also `tableVersionProvider(table)`, which ticks whenever a table changes, locally or through sync. Data providers call `ref.watchTables([...])` to re-query.
  - `lib/state/settings_providers.dart`:
    - `syncedSettingsProvider`: goals, palette, currency and name, stored in the `prefs` table and synced.
    - `deviceSettingsProvider`: mode, text size and first run, stored in SharedPreferences and never synced.
    - `selectedDayProvider`: shared by Overview and Water.
  - `lib/state/data_providers.dart`: per-screen `FutureProvider.family`s keyed by day key, plus `AsyncBody`.
  - Callbacks without a `ref` can use `context.db` / `context.readProvider(...)` for imperative reads only.
  - `SyncService` and `NotificationService` are still `ChangeNotifier` classes. They move to notifiers in the sync and reminders features.
- **Data**: SQLite through `sqflite` (`lib/data/db.dart`).
  - Every synced table has `id` (a UUID), `updated_at` (a hybrid logical clock), `device_id`, `deleted` (a tombstone) and `rev` (a local change counter).
  - Always write through `AppDb.save` and `AppDb.delete`, never with raw SQL writes, so that sync sees the change.
  - Food logs and plans store a **per-100 g snapshot** plus grams. Macros may be `null`, meaning unknown; show them as "—", never as 0.
  - Repositories: `FoodRepo`, `WaterRepo`.
- **UI**:
  - `lib/ui/shell.dart` is the responsive shell: `NavigationBar` under 600 dp, `NavigationRail` (with You) at 600 dp and up.
  - The theme is in `lib/ui/theme/`. Colour schemes are explicit, from DESIGN.md §3.1 (never `fromSeed`). Semantic colours are a `ThemeExtension` (`context.sem`).
  - Text size uses the app-level `AppTextScaler`.
  - The macOS title bar is transparent; `AppChrome` adds the top inset.

## Workflow
- Branches: `main` (stable) ← `dev/v1` (integration) ← `feat/*`.
- **Work one feature at a time. Don't push or open PRs until the user asks.** Never merge without being asked.
- Before committing: `dart format lib test` (page width 120), then `flutter analyze` (must be clean) and `flutter test`.
- Render tests in `test/screens/` produce PNGs in `test/screens/goldens/` at phone size (412 dp, 130 % text) and Mac size (1200 px). Refresh them with `flutter test --update-goldens test/screens` and compare against the boards.
- Use the latest stable versions of packages and tools.
- Running the app: `flutter run -d macos`, and on the Pixel `flutter run -d <id>` (`adb` is at `~/Library/Android/sdk/platform-tools`).
