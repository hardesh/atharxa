# CLAUDE.md

Personal offline-first app (current name: **Atharxa**) for Android phones and macOS, built with Flutter (Material 3).
It covers calories, meal plan, water, workouts and finance, with peer-to-peer Wi-Fi sync and an on-device AI assistant.

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
  - `app_name` / `app_id` at the top of the `justfile`

## Principle: no hand-written native code
- `macos/Runner/*.swift` and the Android `MainActivity` stay exactly as Flutter generates them. Platform features come from plugins, or from `nativeapi_flutter` (Dart FFI covering windows, tray, menus and login items), or from config (`Info.plist`, entitlements, `AndroidManifest.xml`, Gradle).
- If something truly can't be done without native code, ask the user first.
- Approved exception: `MainActivity` extends `FlutterFragmentActivity` (Health Connect permissions need it).
- macOS window: the title bar blends in through `MainMenu.xib` (transparent title bar, full-size content); don't use nativeapi's `TitleBarStyle.hidden`, which removes the window buttons. Quitting goes through nativeapi's `ApplicationQuitRequestedEvent` (`desktop_controller.dart`).

## Architecture
- **State: Riverpod 3** (`flutter_riverpod`, no code generation). Don't add new `ChangeNotifier`s, `InheritedWidget`s or hand-rolled reload widgets.
  - `lib/state/core_providers.dart`: `dbProvider`, `prefsProvider` and the service providers, overridden in `main.dart` (`appOverrides`). Also `tableVersionProvider(table)`, which ticks whenever a table changes, locally or through sync. Data providers call `ref.watchTables([...])` to re-query.
  - `lib/state/settings_providers.dart`:
    - `syncedSettingsProvider`: goals, palette, currency and name, stored in the `prefs` table and synced.
    - `deviceSettingsProvider`: mode, text size and first run, stored in SharedPreferences and never synced.
    - `selectedDayProvider`: shared by Overview and Water.
  - `lib/state/data_providers.dart`: per-screen `FutureProvider.autoDispose.family`s keyed by day or month, plus `AsyncBody`.
- **Memory and battery**:
  - Keep screen data providers **auto-dispose**, and have the shell build **only the selected tab**.
  - Measure memory with a release build (`footprint <pid>` on macOS). Debug builds are about 3× larger.
  - Background sync runs every 30 minutes; flush pending edits on hide. Don't add always-on work.
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
  - Repositories: `FoodRepo`, `WaterRepo`, `FinanceRepo` (with `MonthSummary` totals per currency; there's no FX conversion) and `WorkoutRepo` (plans, sessions, set logs).
  - Money is stored as integer minor units plus an ISO currency (`lib/data/currency.dart`).
  - Export (`lib/services/transactions_export.dart`):
    - CSV with a BOM.
    - Excel built by hand as zipped XML with `archive`. Don't add a spreadsheet package.
  - Files are saved and opened through `lib/services/file_saver.dart` (official `file_selector`): the Save panel on macOS, the Downloads folder on Android, the system picker for opening.
  - Per-device pref keys live in `DeviceKeys` (`core_providers.dart`); `DeviceKeys.backedUp` is what a backup carries.
  - Workout form tips live in `assets/data/exercise_tips.json`. Exercise videos are user-added YouTube links, opened through nativeapi `UrlOpener`; the fallback copies the link.
- **Wi-Fi sync** (`lib/sync/`), peer to peer with no cloud:
  - `sync_auth.dart`: a key derived from the 6-digit pairing code (PBKDF2), and HMAC-signed requests and responses.
  - `sync_protocol.dart`: an HTTP server with hello, pull and push, and a client that sends paged changes with cursors per peer. Errors are typed (code mismatch, unreachable, interrupted).
  - `discovery.dart`: mDNS through bonsoir.
  - `peers.dart`: per-device prefs.
  - `background_sync.dart`: an Android workmanager task every 15 minutes.
  - Edits made on the device itself (`AppDb.localChanges`) trigger auto-sync. Rows merged from a peer don't, and rows last edited by a peer are never sent back to it.
- **On-device AI** (`lib/ai/`, DESIGN.md §7.6), through `flutter_edge_ai` (pinned exact versions):
  - Two engines: LiteRT-LM (`flutter_edge_ai_litertlm`, `.litertlm`: GPU, and the Tensor G5 NPU build) for Gemma 4, and llama.cpp (`flutter_edge_ai_llama` → llamadart, `.gguf`: CPU on phones, Metal on the Mac) for Qwen3.5 and Gemma 4 12B.
  - `ai_runtime.dart` is the **only** file that imports the AI packages (`AiRuntime` interface, `EdgeAiRuntime`); tests use a fake.
  - `ai_models.dart`: the catalog (each file pinned to a Hugging Face commit with size and SHA-256) and the "fits this device" rules. The engine checks each download's exact size; desktops also check the SHA-256 (phones skip it: minutes of CPU, frozen in the background).
  - `device_info.dart`: RAM, chip and free space from system tools (`/proc/meminfo`, `getprop`, `sysctl`, `df`).
  - `lib/state/ai_controller.dart` (`aiProvider`, kept alive so downloads continue) and `assistant_controller.dart` (auto-dispose chat). A model loads only while the assistant is open and is freed a minute after it closes.
  - Build setup: `hooks: user_defines` in `pubspec.yaml` (llama.cpp only from llamadart; Tensor NPU dispatch on), Android `minSdk 30` and arm64 only, macOS 14. The engines' native files come from GitHub releases at build time; if GitHub keeps returning 5xx, the LiteRT-LM archives can be downloaded by hand, checked against the checksums in the package's `hook/build.dart`, and extracted to `~/Library/Caches/flutter_gemma/native/<platform>/`.
- **Workouts from other apps** (`lib/services/health_import.dart`, `lib/state/activity_import_controller.dart`): read from Android Health Connect (Strava GPS activities, Pixel Watch / Google Health, Fitbit) with the `health` package; read-only, no Strava API. Rows go to the synced `activities` table (id `hc-<record id>`, `source` = app name, written with `AppDb.saveIfChanged`), imported at most hourly when Workout opens; `Activity.merged` shows a workout recorded by two apps once. The Mac gets them by sync.
- **Assistant chats** are stored in the synced `chats` table (schema v2). `AppDb` migrations live in `_upgrade(db, from)`, which runs for new and existing databases.
  - `lib/ui/shell.dart` is the responsive shell: `NavigationBar` under 600 dp, `NavigationRail` (with You) at 600 dp and up.
  - The theme is in `lib/ui/theme/`. Colour schemes are explicit, from DESIGN.md §3.1 (never `fromSeed`). Semantic colours are a `ThemeExtension` (`context.sem`).
  - Text size uses the app-level `AppTextScaler`.
  - macOS: `lib/state/desktop_controller.dart` uses `nativeapi_flutter` to hide the title bar, set the minimum window size, hide the window on close while sync is on, add the menu bar item and handle open at login. App Nap is off through `NSAppSleepDisabled` in `Info.plist`. `AppChrome` adds the top inset for the window buttons.

## Commands (`just`, see `justfile`) — use these instead of raw flutter/adb commands
Output is short on purpose (failures and errors only; build logs go to `build/logs/`).
- `just check`: format, analyze, full test suite. Run before committing.
- `just test [files…]`: tests (all, or only the given files/dirs). After a small change, run only the related files.
- `just test-name "text" [files…]`: tests whose name contains the text.
- `just goldens [files…]`: refresh screenshot goldens (default `test/screens`); then look at the changed PNGs.
- `just analyze`, `just fmt`.
- `just mac` / `just mac-install` (build, copy to /Applications, open; the free personal install) / `just mac-run` (debug) / `just mac-mem` (memory).
- `just phone` (build, install on the connected phone, open) / `just apk` / `just phone-run` (debug) / `just devices` / `just phone-log [lines]`.
- `just all`: install on the phone and the Mac. `just clean`.

## Workflow
- Branches: `main` (stable) ← `dev/v1` (integration) ← `feat/*`.
- **Work one feature at a time. Don't push or open PRs until the user asks.** Never merge without being asked.
- **For now, keep all work on the current branch (`feat/sync`).** Don't create new branches until the user asks.
- **Time:** use `AppClock.now()` (`lib/app_clock.dart`) for anything the user sees (today, this week, meal times). Only sync/database bookkeeping and signed requests use `DateTime.now()`. `test/flutter_test_config.dart` starts every test at Mon 9 Nov 2026, 12:30, so screenshots don't depend on the day the suite runs.
- Render tests in `test/screens/` produce PNGs in `test/screens/goldens/` at phone size (412 dp, 130 % text) and Mac size (1200 px). Compare refreshed goldens against the boards.
- Use the latest stable versions of packages and tools.
