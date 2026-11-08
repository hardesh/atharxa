import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../app_info.dart';
import '../data/db.dart';
import '../data/food_repo.dart';
import '../data/models.dart';
import '../data/water_repo.dart';
import '../state/settings_providers.dart';
import 'reminder_plan.dart';

/// Local notifications: reminders (DESIGN.md §5 Notifications, §7.3) and the
/// Android foreground service that keeps Wi-Fi sync alive while locked.
///
/// Reminders are one-shot notifications recomputed by `RemindersController`
/// whenever food or water changes. Action buttons (+250 ml, Log lunch,
/// Snooze) run without opening the app: in a background isolate when the app
/// isn't running ([notificationActionInBackground]).
class NotificationService {
  final plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called for taps and foreground-visible actions (e.g. "Add lunch").
  void Function(NotificationResponse)? onOpen;

  // Reminder ids live in [_firstId, _lastId] (see planReminders).
  static const _firstId = 1000, _lastId = 1799, _testId = 1, _syncServiceId = 2;

  static const _actWater = 'water_250', _actLogMeal = 'meal_log', _actAddMeal = 'meal_add', _actSnooze = 'snooze';
  static const _catWater = 'water', _catMealLog = 'meal_log', _catMealAdd = 'meal_add', _catCheckin = 'checkin';

  bool get ready => _ready;

  Future<void>? _init;

  /// Safe to call more than once (sync may start before `main` calls it).
  Future<void> init() => _init ??= _initOnce();

  Future<void> _initOnce() async {
    await initTimeZone();
    await plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _catWater,
              actions: [
                DarwinNotificationAction.plain(_actWater, '+250 ml'),
                DarwinNotificationAction.plain(_actSnooze, 'Snooze 15 min'),
              ],
            ),
            DarwinNotificationCategory(
              _catMealLog,
              actions: [
                DarwinNotificationAction.plain(_actLogMeal, 'Log planned meal'),
                DarwinNotificationAction.plain(_actSnooze, 'Snooze 15 min'),
              ],
            ),
            DarwinNotificationCategory(
              _catMealAdd,
              actions: [
                DarwinNotificationAction.plain(
                  _actAddMeal,
                  'Add food',
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(_actSnooze, 'Snooze 15 min'),
              ],
            ),
            const DarwinNotificationCategory(_catCheckin),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationActionInBackground,
    );
    _ready = true;
    // Launched by tapping a notification while the app wasn't running.
    final launch = await plugin.getNotificationAppLaunchDetails();
    final r = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && r != null) onOpen?.call(r);
  }

  static Future<void> initTimeZone() async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {}
  }

  Future<void> _onResponse(NotificationResponse r) async {
    // Actions that work in the background are handled the same way when the
    // app is running; everything else (taps, "Add food") opens the app.
    if (r.actionId == _actWater || r.actionId == _actLogMeal || r.actionId == _actSnooze) {
      await handleReminderAction(r, plugin: plugin);
    } else {
      onOpen?.call(r);
    }
  }

  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      return await plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isMacOS) {
      return await plugin
              .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }
    return true;
  }

  /// Replaces all scheduled reminders with [reminders].
  Future<void> schedule(List<PlannedReminder> reminders) async {
    if (!_ready) return;
    for (final p in await plugin.pendingNotificationRequests()) {
      if (p.id >= _firstId && p.id <= _lastId) await plugin.cancel(id: p.id);
    }
    for (final r in reminders) {
      await plugin.zonedSchedule(
        id: r.id,
        scheduledDate: tz.TZDateTime.from(r.at, tz.local),
        title: r.title,
        body: r.body,
        payload: _payload(r.kind, r.title, r.body, meal: r.meal, day: r.day, planned: r.mealPlanned),
        notificationDetails: details(r.kind, mealPlanned: r.mealPlanned, meal: r.meal),
        // Inexact: no exact-alarm permission needed; may drift a few minutes.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> showTest() async {
    await requestPermission();
    await plugin.show(
      id: _testId,
      title: 'Reminders work',
      body: 'You will get reminders at the times you set.',
      notificationDetails: details(ReminderKind.checkin),
    );
  }

  // ------------------------------------------------- Android foreground service

  /// Keeps the app (and Wi-Fi sync) running while the phone is locked, with
  /// a quiet ongoing notification. Android only.
  Future<void> startSyncService() async {
    if (!Platform.isAndroid) return;
    await init();
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.startForegroundService(
          id: _syncServiceId,
          title: 'Wi-Fi sync is on',
          body: 'Keeps ${AppInfo.name} in sync with your other devices while the phone is locked.',
          notificationDetails: const AndroidNotificationDetails(
            'sync',
            'Wi-Fi sync',
            channelDescription: 'Shown while sync keeps running in the background',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            showWhen: false,
          ),
          foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeSpecialUse},
        );
  }

  Future<void> stopSyncService() async {
    if (!Platform.isAndroid) return;
    await init();
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.stopForegroundService();
  }

  // ------------------------------------------------------------------ shared

  static NotificationDetails details(ReminderKind kind, {bool mealPlanned = false, Meal? meal}) {
    final (channel, name) = switch (kind) {
      ReminderKind.water => ('water', 'Water reminders'),
      ReminderKind.meal => ('meals', 'Meal reminders'),
      ReminderKind.checkin => ('checkin', 'Calorie check-ins'),
    };
    final mealLabel = meal?.label.toLowerCase() ?? 'meal';
    final actions = switch (kind) {
      ReminderKind.water => const [
        AndroidNotificationAction(_actWater, '+250 ml', cancelNotification: false),
        AndroidNotificationAction(_actSnooze, 'Snooze'),
      ],
      ReminderKind.meal => [
        mealPlanned
            ? AndroidNotificationAction(_actLogMeal, 'Log $mealLabel', cancelNotification: false)
            : AndroidNotificationAction(_actAddMeal, 'Add $mealLabel', showsUserInterface: true),
        const AndroidNotificationAction(_actSnooze, 'Snooze 15 min'),
      ],
      ReminderKind.checkin => const <AndroidNotificationAction>[],
    };
    return NotificationDetails(
      android: AndroidNotificationDetails(channel, name, importance: Importance.high, actions: actions),
      macOS: DarwinNotificationDetails(
        categoryIdentifier: switch (kind) {
          ReminderKind.water => _catWater,
          ReminderKind.meal => mealPlanned ? _catMealLog : _catMealAdd,
          ReminderKind.checkin => _catCheckin,
        },
      ),
    );
  }

  static String _payload(
    ReminderKind kind,
    String title,
    String body, {
    Meal? meal,
    String? day,
    bool planned = false,
  }) =>
      jsonEncode({'kind': kind.name, 'title': title, 'body': body, 'meal': meal?.name, 'day': day, 'planned': planned});

  /// The meal a notification is about (for "Add lunch" / tapping a meal reminder).
  static Meal? mealOf(NotificationResponse r) {
    try {
      final m = (jsonDecode(r.payload ?? '{}') as Map)['meal'] as String?;
      return m == null ? null : Meal.parse(m);
    } catch (_) {
      return null;
    }
  }
}

/// Runs a reminder action (+250 ml, Log meal, Snooze) and updates the
/// notification. Works in the app or in a background isolate.
Future<void> handleReminderAction(
  NotificationResponse r, {
  required FlutterLocalNotificationsPlugin plugin,
  AppDb? db,
}) async {
  final p = jsonDecode(r.payload ?? '{}') as Map<String, dynamic>;
  final kind = ReminderKind.values.firstWhere((k) => k.name == p['kind'], orElse: () => ReminderKind.checkin);
  final id = r.id ?? 0;
  final meal = p['meal'] == null ? null : Meal.parse(p['meal'] as String);
  final details = NotificationService.details(kind, mealPlanned: p['planned'] == true, meal: meal);

  if (r.actionId == NotificationService._actSnooze) {
    await plugin.cancel(id: id);
    await plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.now(tz.local).add(const Duration(minutes: 15)),
      title: p['title'] as String?,
      body: p['body'] as String?,
      payload: r.payload,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    return;
  }

  final ownDb = db == null;
  final d = db ?? await AppDb.open();
  try {
    final goals = (await SyncedSettings.load(d)).goals;
    final today = DateTime.now();
    if (r.actionId == NotificationService._actWater) {
      final water = WaterRepo(d);
      await water.add(today, 250, 'notification');
      final total = await water.total(dayKey(today));
      await plugin.show(
        id: id,
        title: 'Added 250 ml',
        body: ReminderText.waterBody(total, goals.waterMl),
        notificationDetails: details,
      );
    } else if (r.actionId == NotificationService._actLogMeal && meal != null) {
      final repo = FoodRepo(d);
      final day = p['day'] as String? ?? dayKey(today);
      final planned = (await repo.entries(FoodRepo.plans, day)).where((e) => e.meal == meal).toList();
      await repo.copy(planned, FoodRepo.logs, day: day);
      final eaten = Nutrients.sum((await repo.entries(FoodRepo.logs, day)).map((e) => e.totals)).kcal;
      final kcal = Nutrients.sum(planned.map((e) => e.totals)).kcal;
      await plugin.show(
        id: id,
        title: 'Logged ${meal.label.toLowerCase()} · ${kcal.round()} kcal',
        body: ReminderText.mealBody(goals.kcal - eaten),
        notificationDetails: NotificationService.details(ReminderKind.checkin),
      );
    }
  } finally {
    if (ownDb) await d.close();
  }
}

/// Entry point for notification actions while the app isn't running.
@pragma('vm:entry-point')
Future<void> notificationActionInBackground(NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.initTimeZone();
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
  );
  try {
    await handleReminderAction(r, plugin: plugin);
  } catch (e) {
    debugPrint('[reminders] background action failed: $e');
  }
}
