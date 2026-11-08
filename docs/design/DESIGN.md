# Atharxa — design spec for implementation

Single-user personal "super app": calories, meal plan, water, workouts, finance, and an on-device AI assistant.
One Flutter (Material 3) codebase for **Android phones** and **macOS**. Offline-first, no account, no cloud
(the only online features are Open Food Facts search, Strava and YouTube tips, all optional).

The boards in `boards/` are the visual reference (HTML mockups, not Flutter code). This file is the source of
truth for behaviour, numbers and tokens. When a board and this file disagree, follow this file and flag it.

---

## 1. Principles

- Logging food or water takes at most 2–3 taps from Today.
- Everything works offline; data lives in a local database on each device.
- Calm by default: nothing shouts, numbers never truncate, one clear primary action per screen.
- The AI is visible on every main screen (top bar) but never required.
- Light and dark mode; three themes; text scales well.

---

## 2. Platforms and layout

| | Android phone | macOS |
|---|---|---|
| Target widths | 360–412 dp (Pixel 9a … Pixel 10; "Display size: Large" ≈ 360 dp) | Resizable window, min ~900 × 640 |
| Navigation | Bottom `NavigationBar`, 5 tabs: Today · Meal plan · Water · Workout · Finance | `NavigationRail`, 6 destinations: the 5 + You |
| "You" (profile + settings) | Avatar in the top bar → pushed page | Rail destination; two-pane (section list + page) |
| Content width | Full width, 16 dp side padding | Centred column, **max 760 dp** |
| Default text size | **130 %** (app-level scale, see §3.2) | 100 % |
| System insets | Edge-to-edge; respect status bar and gesture/3-button nav insets (`SafeArea`) | — |

Breakpoints: width ≥ 600 dp (foldables/tablets, small Mac window) → rail layout. Below 360 dp or effective text
scale > ~1.2 → "stacked" variants of dense rows (see Meal plan, macro bars).

---

## 3. Design tokens

### 3.1 Colour themes

Three built-in themes. **Forest is the default on first launch.** The chosen theme **syncs between devices**;
light/dark mode is **per device** (System / Light / Dark). Build `ColorScheme`s explicitly from these values
(do not use `fromSeed`, it will drift).

| Role | Forest light | Forest dark | Teal light | Teal dark | Ocean light | Ocean dark |
|---|---|---|---|---|---|---|
| primary | #4C662B | #B1D18A | #00695C | #83D5C6 | #0061A4 | #9ECAFF |
| onPrimary | #FFFFFF | #1F3701 | #FFFFFF | #003731 | #FFFFFF | #003258 |
| primaryContainer | #CDEDA3 | #354E16 | #A5F2E4 | #005047 | #D1E4FF | #00497D |
| onPrimaryContainer | #102000 | #CDEDA3 | #00201C | #A1F1E2 | #001D36 | #D1E4FF |
| secondaryContainer | #DCE7C8 | #404A33 | #CDE8E2 | #324B47 | #D7E3F7 | #3B4858 |
| onSecondaryContainer | #151E0B | #DCE7C8 | #06201C | #CDE8E2 | #101C2B | #D7E3F7 |
| surface | #F9FAEF | #11140E | #F4FBF8 | #0E1513 | #FDFCFF | #111418 |
| surfaceContainerLow | #EEEFE3 | #1A1D16 | #EAF2EF | #171D1B | #EFF0F5 | #1A1C20 |
| surfaceContainer | #E8E9DE | #1E211A | #E3EBE8 | #1B2220 | #E9EAEF | #1E2024 |
| surfaceContainerHigh | #E0E2D6 | #282B24 | #D9E2DF | #262D2B | #E1E2E8 | #282A2E |
| onSurface | #1A1C16 | #E2E3D8 | #161D1B | #DDE4E1 | #1A1C1E | #E2E2E6 |
| onSurfaceVariant | #44483D | #C5C8BA | #3F4946 | #BEC9C5 | #43474E | #C3C7CF |
| outline | #75796C | #8F9285 | #6F7976 | #899390 | #73777F | #8D9199 |
| outlineVariant | #C5C8BA | #44483D | #BEC9C5 | #3F4946 | #C3C7CF | #43474E |
| error | #BA1A1A | #FFB4AB | (same) | (same) | (same) | (same) |
| errorContainer | #FFDAD6 | #93000A | (same) | (same) | (same) | (same) |

**Semantic colours** (same in every theme unless noted; light / dark):

| Use | Light | Dark |
|---|---|---|
| Protein bar | = primary | = primary |
| Carbs bar | #A35F00 | #FFB95E |
| Fiber bar | #3566BC (Ocean: #6B4FA0) | #AAC7FF (Ocean: #D4BBFF) |
| Fat bar | #9C3F7A | #F4AED6 |
| Water | #1A5FC2, container #D8E2FF (Ocean: #00677D / #B4EBFF) | #ADC6FF, container #00458F (Ocean: #5DD5F9 / #004E5F) |
| Income | #1B6D2F | #8AD89B |
| Expense amounts | #B3261E | #FFB4AB |
| Success tag (Online, Done) | text #1B6D2F on #C3EFC9 | text #8AD89B on #0F5223 |

Bars sit on a track of `onPrimaryContainer` at ~14 % (light) / white at ~16 % (dark) inside the primary-container
summary card, and on `surfaceContainerHigh` elsewhere.

### 3.2 Typography

Font: **Roboto** (Android default; bundle it for macOS). Base sizes (at 100 %):

| Style | Size / line | Weight | Used for |
|---|---|---|---|
| headline (t0) | 28 / 36 | 400–500 | Mac page titles, big numbers |
| title-large (t1) | 22 / 28 | 400–500 | Phone page titles, dialog titles |
| title-medium (t2) | 16 / 24 | 500 | Card titles, meal names |
| title-small (t3) | 14 / 20 | 500 | Row titles, labels |
| body (bd) | 14 / 20 | 400 | Body text, values |
| label-small (sm) | 12 / 16 | 400 | Secondary text, captions |
| display (dl) | 36 / 44 | 400 | "702 kcal left" |

**Text-size setting** (You › Appearance › Text size: 100 / 115 / **130 (default on phones)** / 150 %, per device).
Apply it as an app-level `TextScaler` that multiplies the system font scale (clamp the total at 2.0).
Scale body/label styles fully; scale headline/title-large/display by about half as much (130 % → ×1.15), similar to
Android 14 non-linear scaling. Use tabular figures (`FontFeature.tabularFigures()`) for all numbers.

### 3.3 Shape, spacing, elevation

- Radii: cards 16, dialogs and bottom sheets 28, buttons/pills fully rounded, chips 8, text fields 4 (outlined),
  macro bars 4 (calorie bar 6), app icon per platform mask.
- Spacing: 4-dp grid; screen padding 16 (phone) / 32 (Mac); gap between cards 12 (phone) / 16 (Mac).
- Touch targets ≥ 44 dp. Icon buttons 40 dp; the AI button 44 dp.
- Elevation: flat surfaces with tonal containers; shadows only on FAB, snackbar, menus, dialogs.

---

## 4. Components

- **Top app bar (shared).** Phone: screen title (title-large, 500) · filled circular **AI button** (sparkle icon,
  primary/onPrimary, a11y label "Ask Atharxa") · **avatar** (initial on secondaryContainer) → opens You.
  Mac: title (headline) · filled pill **"Ask Atharxa ⌘K"** · avatar with a small green **sync status dot**.
  Pushed pages (pickers, forms, You sub-pages) use a back arrow + title instead; they keep the AI button where useful.
- **Date / month switcher** under the top bar: ‹ "Today, 8 Nov" › (tap = date picker). Meal plan defaults to tomorrow.
- **Summary card (Today):** "702 kcal left" (display) + "1,498 eaten of 2,200 goal"; a **12 dp calorie bar**;
  a thin divider; then **four 8 dp macro bars** — Protein, Carbs, Fiber, Fat — each "65.9 / 120 g".
  When over goal: "120 kcal over" and the bar shows full in error colour.
- **Nutrient text:** always words + units, never single letters: "227 kcal · Protein 7.9 g · Carbs 40.6 g ·
  Fiber 6.1 g · Fat 3.9 g". It may wrap to two lines.
- **Meal card:** name + kcal subtotal + tonal "+" button; item rows "Rolled oats · 60 g" + nutrient line;
  tap row = edit grams; ✕ = remove (with Undo snackbar). Empty: "Nothing logged yet".
- **Chips** (filter/input), **segmented buttons** (Expense/Income; System/Light/Dark), **switches**,
  **outlined text fields** with floating labels and unit suffixes, **bottom sheets** with drag handle,
  **dialogs**, **snackbars** (above the nav bar), **extended FAB** (Finance "Add", Food picker "New food").
- **Gesture area:** content and the nav bar sit above the system gesture inset; nav bar colour extends under it.

---

## 5. Screens (board references in brackets)

### Today `[Main.dc.html]`
Top bar · date switcher · summary card (§4) · water card (ml vs goal, bar, chips **+250 ml, +500 ml**) ·
meal cards Breakfast, Lunch, Snacks, Dinner. Mac: summary and water side by side, meals in a 2-column grid;
shortcuts ⌘N add food, ⌘W add water.

### Food picker `[FoodPicker.dc.html]`
Full-screen. Title "Add to Lunch" (meal from context) · one search field · tabs **My foods / Online / Ask AI**
(Ask AI disabled, "coming soon"). Results: **two lines** (name; brand) + kcal per 100 g on the right
(the header says "kcal per 100 g" once). Online results are Open Food Facts; picked online foods are
saved to My foods automatically. Extended FAB "New food". Mac: My foods as a table with columns
kcal · Protein · Carbs · Fiber · Fat (per 100 g), name + "brand · serving" in the first column, edit button.

**Portion dialog:** food name + source · grams field (focused) · chips "1 serving (40 g)" (only if the food has a
serving) and "100 g" · a "Per 100 g: …" line · live preview of kcal, Protein, Carbs, Fiber, Fat for the entered
grams · meal selector · Cancel / "Add to Lunch".

### Custom food `[CustomFood.dc.html]`
Create / edit / delete. Fields: Name*, Brand/note, Typical serving (g), per-100 g: kcal*, Protein, Carbs,
Fiber, Fat. Actions: "Save and add to <meal>", "Save to My foods only". Editing changes future logs only
(past log entries keep a snapshot of their values).

### Meal plan `[MealPlan.dc.html]`
Date switcher (default tomorrow) · planned-totals card with goal bars and a ⋮ menu: **Log whole day**,
**Copy plan from another day…**, Clear plan · one card per meal with "+" and **Log** (copies items into
that day's log). Phone rows are **stacked** (name + grams, then the nutrient line); swipe left to remove
with Undo. Mac: full table Component · g · kcal · Protein · Carbs · Fiber · ✕, with a total row.
Logging a meal twice asks for confirmation.

### Water `[Water.dc.html]`
Date switcher · ring (ml vs goal) · quick-add **+250, +500, +750, Custom** (no +150) · last-7-days bar chart
with a goal line, met days highlighted · today's entries (time, amount, source: Today card / Water tab /
Notification) with remove.

### Workout `[Workout.dc.html]`, `[WorkoutSession.dc.html]`
- Week strip with status per day (done / rest / today), today's plan card with **Start workout**,
  week stats (sessions, run km, ride km), "From Strava" list.
- Plan editor: name, repeat days, exercises (sets × reps × kg, rest), drag to reorder, "Add exercise".
- Live session: timer, exercise n of m, set n of 3, reps/kg steppers, **Complete set** (auto rest timer),
  set chips, **Form tips** (short text cues) + video list from YouTube search, "Ask about this exercise", up next.
- Complete: duration, sets, volume (kg), energy estimate, feel (Easy/Good/Hard), notes,
  **Upload to Strava** switch, "Add kcal to Today" switch (off by default).
- Strava connect: explains scopes (read activities incl. private, upload activities), OAuth in the browser,
  token stored only on device, Disconnect.

### Finance `[Finance.dc.html]`, `[Export.dc.html]`
Month switcher · Income / Expenses / Balance · spending by category (phone: bars, top 5 + "others";
Mac: donut + legend) · transactions grouped by day with day net. Add/edit sheet: Expense/Income segmented,
amount (₹ default), category chips (Food, Groceries, Transport, Rent, Bills, Shopping, Health,
Entertainment, Salary, Other + custom), date, note. Snackbar with Undo.
**Export** (⋮ on phone, button on Mac): CSV or Excel (.xlsx); range (this month, last 3 months, this year,
custom); include expenses/income/notes; Excel adds "By category" and "Summary" sheets; option "expenses as
negative amounts"; CSV is UTF-8 with BOM. Columns: `date,type,category,amount,currency,note`.
File name `transactions-YYYY-MM.(csv|xlsx)`. Phone: Share sheet or Save to Downloads. Mac: Save panel.

### You `[You.dc.html]` (full content reference: `[Settings.dc.html]`)
Hub: profile card (name, photo) + rows with one-line summaries → separate pages:
- **Goals** (synced): Calories, Water, Protein, Carbs, Fiber, Fat (defaults 2,200 kcal, 3,000 ml, 120 / 250 / 30 / 70 g);
  "Suggest from body stats".
- **Appearance**: theme (Forest default, Teal, Ocean; synced), mode, text size (per device).
- **Reminders** (per device): Meals (Breakfast 08:30, Lunch 13:00, Snacks 16:30, Dinner 20:30; skip if already
  logged; show kcal still to eat), Water (every N h between start and end), Calorie check-in (times list,
  default 11:00, 16:30, 20:00), "Send test notification". Turning a reminder off keeps its times.
- **Device sync** (see §7.2), **Connected services** (Strava; workout tips sources),
  **AI models** (§7.6), **Body stats**, **Data and backup** (export/restore everything), **About**.
Mac: two-pane (sections left, page right).

### Assistant `[Assistant.dc.html]`, `[Insights.dc.html]`
Chat page titled "Atharxa", opened from the AI button (Mac also ⌘K). Model picker in the header.
Answers show a small "Read …" chip naming the data the assistant used. Action buttons in answers
(e.g. "Add to Dinner"). Suggestion chips above the input. Mac keeps a chat-history list.
One-tap summaries on Finance ("Summarize month") and Workout ("Summarize week").

### Notifications `[Notification.dc.html]`
Water: "Time for a glass of water · 1,250 of 3,000 ml today" with actions **+250 ml** and Snooze; the action
logs in the background and updates the notification ("Added 250 ml · 1,500 of 3,000 ml"). Meal:
"Lunch time · 1,750 kcal still to eat today" with **Log lunch** and Snooze 15 min. macOS banner equivalents.

### Pairing `[Pairing.dc.html]`, empty states `[EmptyStates.dc.html]`, first run
Pairing flow: sync off → turn on, name, pairing code, discovery → code mismatch dialog → paired, first sync
("Sent 38, received 126"). Empty states: no logs, no foods, no transactions, no workout plans, no paired device.
First run: "Welcome to Atharxa", goals (incl. Fat), currency, Start / Skip.

### Other boards
`Sizes.dc.html` (scaling rules), `Palettes.dc.html` (themes; B/C/F explored, not shipped),
`Flows.dc.html` (workflows 1–8), `TopBar.dc.html` (component), `Icons*.dc.html` (icon exploration).

---

## 6. Data model (suggested)

- **Food**: id, name, brand, servingG?, per100: kcal (required), protein, carbs, fiber, fat; source (custom | off),
  offBarcode?, updatedAt, deletedAt?
- **LogEntry**: id, date, meal (breakfast|lunch|snacks|dinner), foodId, grams, **snapshot** of per-100 values,
  createdAt, updatedAt, deletedAt?
- **PlanItem**: id, date, meal, foodId, grams, …same timestamps
- **WaterEntry**: id, timestamp, ml, source (today|water|notification|mac)
- **Transaction**: id, type (expense|income), amount (minor units), currency, category, date, note
- **Category**: id, name, type, isCustom
- **WorkoutPlan / Exercise / Session / SetLog**: plan name, days, exercises (sets, reps, kg, restS);
  session start/end, sets logged, notes, feel, stravaActivityId?
- **StravaActivity** (imported): id, type, start, distanceM, movingTimeS
- **Goals** (synced singleton), **AppearanceTheme** (synced), **DeviceSettings** (not synced: mode, text size,
  reminders, AI model, sync config)

Every synced row carries `id` (UUID), `updatedAt`, `deletedAt` (tombstone) and `deviceId`.

---

## 7. Behaviour

### 7.1 Nutrition maths
`value = per100 × grams / 100`. Store full precision; display kcal as integers and macros to one decimal.
Totals are computed from full precision and then rounded (row sums may differ by 0.1 from the total; that's OK).

### 7.2 Local Wi-Fi sync (no cloud)
Discovery via mDNS/DNS-SD on the LAN, plus "Add device by IP" (default port 47811). Both devices must share the
same **pairing code** (6 digits); the code authenticates the session (derive a key from it). Sync is
incremental by `updatedAt`, **last write wins** per row, tombstones for deletes. Syncs: foods, logs, plans, water,
transactions, categories, workouts, goals, theme. Never syncs: reminders, mode/text size, AI models, Strava tokens.
Errors to surface: code mismatch, device not reachable, interrupted (resumes), sync off on the other device.
Show last sync time and "sent N, received M".

### 7.3 Reminders
Local notifications scheduled per device. Meal reminders are skipped when that meal already has entries.
Notification actions (+250 ml, Log lunch) run without opening the app and update the notification.

### 7.4 Open Food Facts
Online search only; map energy-kcal, proteins, carbohydrates, fiber, fat per 100 g and serving size. Cache picked
items into My foods. Handle missing nutrients (treat as unknown, not zero, in the UI).

### 7.5 Strava and tips
Strava OAuth (activity read + write); import runs/rides; optional upload of finished sessions as private
"Weight training". Tips: curated text cues per exercise (offline) + YouTube search results (online).

### 7.6 On-device AI (Gemma 4)
- Runs locally; model files are downloaded per device (Wi-Fi only by default) and **not synced**.
- **AI models** page: device capabilities (RAM, chip, free space), installed models, available models with
  "fits this device" / "Mac only" states, import a model file. Architecture must allow swapping models later.
- The app computes all numbers itself (SQL) and gives the model small JSON summaries or tool results;
  the model only writes wording. Scopes the user controls: food & water, workouts & Strava, finance,
  transaction notes (off by default).
- Uses: chat, "Summarize month" (finance), "Summarize week" (workout). "Ask AI" food search is a later feature.

### 7.7 Offline
Every screen works offline except Online food search, Strava and video tips, which show a clear offline state.

---

## 8. Sample data used in the mockups (good for tests)

Per-100 g foods: Rolled oats 379 kcal / 13.2 / 67.7 / 10.1 / 6.5 · Toned milk 58 / 3.1 / 4.7 / 0 / 3.0 ·
Banana 89 / 1.1 / 22.8 / 2.6 / 0.3 · Paneer bhurji 220 / 13 / 5 / 1 / 16 · Roti 300 / 10 / 46 / 5 / 8 ·
Dal tadka 120 / 6 / 15 / 4 / 4 · Roasted chana 370 / 20 / 58 / 17 / 5 · Masala chai 60 / 2 / 8 / 0 / 2.

Today (8 Nov): Breakfast oats 60 g, milk 200 g, banana 120 g (450 kcal) · Lunch paneer bhurji 150 g, roti 80 g,
dal 200 g (810) · Snacks chana 40 g, chai 150 g (238) · Dinner empty.
Expected: **1,498 eaten, 702 left**; Protein 65.9 / 120 g; Carbs 186.9 / 250 g; Fiber 29.5 / 30 g; Fat 53.7 / 70 g.
Water 1,250 / 3,000 ml. Adding Rolled Oats (OFF, 389 kcal/100 g) 50 g to Lunch → 195 kcal, Lunch 1,005, **507 left**.

Plan (9 Nov): total **1,841 kcal**, Protein 106.2 g, Carbs 246.5 g, Fiber 43.7 g.

Finance (Nov 2026): income ₹1,35,000; expenses **₹45,139**; balance **₹89,861**; 12 transactions;
Rent ₹28,000 (62 %), Shopping ₹6,499, Groceries ₹3,770, Bills ₹2,340, Transport ₹1,650, Food ₹1,280,
Health ₹860, Entertainment ₹740.

---

## 9. Open decisions (do not guess; ask)

1. App icon: final high-resolution square image (current master is upscaled from ~570 px); themed monochrome
   layer (use the B6 stones vector unless replaced).
2. Gemma 4 variant(s), runtime on Android vs macOS, model file format and download source.
3. Strava API app registration and brand-guideline-compliant "Connect" button; YouTube Data API key and quota.
4. Fat goal default (70 g is a placeholder).
5. Conflict policy beyond last-write-wins (e.g. both devices edit the same log entry offline).

## 10. Files in this package

- `DESIGN.md` — this spec
- `boards/*.dc.html`, `boards/m3.css`, `boards/canvas.json` — the mockups (open in the design canvas; they rely on its
  runtime, so treat them as visual reference rather than runnable pages)
- `assets/atharxa-icon-1024.png` — icon master
