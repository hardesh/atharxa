import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily repeating local reminders. Settings are per-device (not synced),
/// so you can e.g. keep water reminders on the phone and off on the Mac.
class NotificationService extends ChangeNotifier {
  NotificationService(this.prefs);

  final SharedPreferences prefs;
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _waterBase = 100, _calorieBase = 200;

  bool get waterEnabled => prefs.getBool('notif_water') ?? false;
  int get waterIntervalH => prefs.getInt('notif_water_interval') ?? 2;
  int get waterStartH => prefs.getInt('notif_water_start') ?? 8;
  int get waterEndH => prefs.getInt('notif_water_end') ?? 21;

  bool get calorieEnabled => prefs.getBool('notif_cal') ?? false;
  List<TimeOfDay> get calorieTimes => (prefs.getStringList('notif_cal_times') ?? ['11:00', '16:30', '20:00']).map((s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }).toList()..sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {}
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        macOS: darwin,
      ),
    );
    await reschedule();
  }

  Future<bool> _requestPermission() async {
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isMacOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }
    return true;
  }

  Future<void> update({
    bool? waterEnabled,
    int? waterIntervalH,
    int? waterStartH,
    int? waterEndH,
    bool? calorieEnabled,
    List<TimeOfDay>? calorieTimes,
  }) async {
    if ((waterEnabled ?? false) || (calorieEnabled ?? false)) await _requestPermission();
    if (waterEnabled != null) await prefs.setBool('notif_water', waterEnabled);
    if (waterIntervalH != null) await prefs.setInt('notif_water_interval', waterIntervalH);
    if (waterStartH != null) await prefs.setInt('notif_water_start', waterStartH);
    if (waterEndH != null) await prefs.setInt('notif_water_end', waterEndH);
    if (calorieEnabled != null) await prefs.setBool('notif_cal', calorieEnabled);
    if (calorieTimes != null) {
      await prefs.setStringList('notif_cal_times', calorieTimes.map((t) => '${t.hour}:${t.minute}').toList());
    }
    await reschedule();
    notifyListeners();
  }

  Future<void> reschedule() async {
    await _plugin.cancelAll();
    if (waterEnabled) {
      var i = 0;
      for (var h = waterStartH; h <= waterEndH; h += waterIntervalH) {
        await _daily(
          _waterBase + i++,
          h,
          0,
          'water',
          'Water reminders',
          '💧 Time for water',
          'Drink a glass of water to stay on track with your goal.',
        );
      }
    }
    if (calorieEnabled) {
      var i = 0;
      for (final t in calorieTimes) {
        await _daily(
          _calorieBase + i++,
          t.hour,
          t.minute,
          'calories',
          'Calorie reminders',
          '🍽️ Fuel up',
          'Have you eaten enough today? Log a meal or add a snack to reach your calorie goal.',
        );
      }
    }
  }

  Future<void> _daily(
    int id,
    int hour,
    int minute,
    String channel,
    String channelName,
    String title,
    String body,
  ) async {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: when,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(channel, channelName, importance: Importance.high),
        macOS: const DarwinNotificationDetails(),
      ),
      // Inexact avoids needing the "exact alarm" permission; may drift a few minutes.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> test() async {
    await _requestPermission();
    await _plugin.show(
      id: 1,
      title: 'Notifications work ✅',
      body: 'You will get reminders at the times you set.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('test', 'Test', importance: Importance.high),
        macOS: DarwinNotificationDetails(),
      ),
    );
  }
}
