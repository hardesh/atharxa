import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../state/core_providers.dart';

/// Full backup of this device's data (You › Data and backup).
///
/// * Everything that syncs (foods, logs, plans, water, transactions,
///   categories, workouts, goals/theme) with ids and edit times, so a
///   restore *merges*: newest edit wins, nothing is duplicated, and an old
///   backup never overwrites newer entries.
/// * This device's own settings (reminders, light/dark mode, text size).
abstract final class Backup {
  static const format = 'app-backup';
  static const version = 1;

  static String fileName(DateTime now) => '${AppInfo.name.toLowerCase()}-backup-${dayKey(now)}.json';

  static Future<Uint8List> create(AppDb db, SharedPreferences prefs, {required String deviceName}) async {
    final rows = await db.allRows();
    final tables = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      (tables[r.table] ??= []).add(Map.of(r.row)..remove('rev'));
    }
    return JsonUtf8Encoder().convert({
          'format': format,
          'version': version,
          'app': AppInfo.name,
          'createdAt': DateTime.now().toIso8601String(),
          'device': deviceName,
          'tables': tables,
          'deviceSettings': {for (final k in DeviceKeys.backedUp) k: ?prefs.get(k)},
        })
        as Uint8List;
  }

  /// Reads a backup file; throws [FormatException] with a user-facing message.
  static BackupContents read(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      throw const FormatException('That file isn’t a backup (it isn’t valid JSON).');
    }
    if (j is! Map || j['format'] != format || j['tables'] is! Map) {
      throw const FormatException('That file isn’t a backup made by this app.');
    }
    if ((j['version'] as num? ?? 0) > version) {
      throw const FormatException('This backup is from a newer version of the app — update the app first.');
    }
    final rows = <SyncRow>[];
    final counts = <String, int>{};
    for (final e in (j['tables'] as Map).entries) {
      final table = e.key as String;
      for (final r in (e.value as List? ?? const []).whereType<Map>()) {
        rows.add(SyncRow(table, r.cast<String, Object?>()));
        counts[table] = (counts[table] ?? 0) + 1;
      }
    }
    return BackupContents(
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
      device: j['device'] as String?,
      rows: rows,
      counts: counts,
      deviceSettings: (j['deviceSettings'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  /// Merges [c] into the database (newest edit wins) and applies its device
  /// settings. Returns how many rows changed.
  static Future<int> restore(AppDb db, SharedPreferences prefs, BackupContents c) async {
    final applied = await db.merge(c.rows);
    for (final e in c.deviceSettings.entries) {
      switch (e.value) {
        case final String v:
          await prefs.setString(e.key, v);
        case final bool v:
          await prefs.setBool(e.key, v);
        case final int v:
          await prefs.setInt(e.key, v);
        case final double v:
          await prefs.setDouble(e.key, v);
      }
    }
    return applied;
  }
}

class BackupContents {
  const BackupContents({
    required this.createdAt,
    required this.device,
    required this.rows,
    required this.counts,
    required this.deviceSettings,
  });
  final DateTime? createdAt;
  final String? device;
  final List<SyncRow> rows;

  /// Rows per table.
  final Map<String, int> counts;
  final Map<String, Object?> deviceSettings;
}
