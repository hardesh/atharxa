# TODO

Working list for the app. Newest decisions at the top of each section; move items to **Done** with the commit when finished.

## In progress
- **Workouts from Health Connect (Android)** — read runs/rides/workouts that Strava (GPS activities), Pixel Watch and Fitbit write to Health Connect; sync them to the Mac. Replaces the Strava API flow (Client ID/Secret, in-app sign-in, upload), which was too complicated.
  - One-time setup on the phone: Strava › You › ⚙ › Manage Apps and Devices › Health Connect.
  - Approved: `MainActivity` extends `FlutterFragmentActivity` (the one native-code exception); location permission for distance if needed.

## Next
- **Ask AI in the food picker** — describe a meal ("2 aloo parathas with curd"); the model splits it into foods and portions, the app fills nutrition from My foods / Open Food Facts and shows an editable estimate before logging.
- **Improve the AI feature's design overall** (user, in Claude Design): assistant, AI models page, download banner, Ask AI tab. Then implement the new boards.

## Device checks (need the phone in hand)
- Pixel 10: "Wi-Fi sync is on" notification and sync while locked; reminders + action buttons (+250 ml, Log lunch, Snooze); workout videos in the app; backup restore with the Android picker; download banner during a real model download; Health Connect permissions and import.
- Pixel 9a: first test of everything; Gemma 4 E2B on the GPU (no NPU build for Tensor G4).

## Known issues
- Model downloads on the phone run at ~1 MB/s vs ~16 MB/s on the Mac for the same file.
- First load of a model is slow (Mac 45 s, Pixel NPU 89 s; later 3–5 s); the UI should say "first time only".
- Phone memory with a model loaded not measured yet (Mac idle: 95 MB).

## Housekeeping
- Android release signing key (needed before installing on other phones, e.g. parents').
- Built-in Kotlin migration once plugins support it (Flutter warning).
- AI engine native files download from GitHub at build time; manual cache fallback is in CLAUDE.md.
- PR `feat/sync` → `dev/v1` only when asked (large: sync, finance, workouts, reminders, backup, AI, Health Connect).

## Done (recent)
- `5f86f76` One app clock; tests run on a fixed date.
- `2a42556` About, Connected services and Strava API (being replaced by Health Connect).
- `06c8291` Assistant food actions and synced chat history.
- `f4f00bb` Assistant reads your data; download banner; Pixel 10 NPU verified.
- `c8f40f6` On-device AI: models page, downloads, assistant chat.
