import 'dart:convert';

import 'package:atharxa/services/backup.dart';
import 'package:atharxa/sync/peers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'finance_test.dart' show seedNovember;
import 'helpers.dart';
import 'workout_test.dart' show seedLowerBodyA;

void main() {
  test('backup → restore on a fresh device brings everything back', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark', 'text_scale': 1.15, 'sync_code': '123456'});
    final prefs = await SharedPreferences.getInstance();
    final phone = await openTestDb();
    await seedNovember(phone);
    await seedLowerBodyA(phone);
    await phone.save('water_logs', {'day': '2026-11-09', 'ml': 500, 'logged_at': 1, 'source': 'water'});
    await phone.setPref('goal_kcal', '1900');
    final bytes = await Backup.create(phone, prefs, deviceName: 'Android phone');
    expect(Backup.fileName(DateTime(2026, 11, 9)), 'atharxa-backup-2026-11-09.json');

    SharedPreferences.setMockInitialValues({});
    final freshPrefs = await SharedPreferences.getInstance();
    final fresh = await openTestDb();
    final contents = Backup.read(utf8.decode(bytes));
    expect(contents.device, 'Android phone');
    expect(contents.counts['transactions'], 12);
    expect(contents.counts['exercises'], 6);
    await Backup.restore(fresh, freshPrefs, contents);

    expect((await fresh.query('transactions')).length, 12);
    expect((await fresh.query('exercises')).length, 6);
    expect((await fresh.query('water_logs')).single['ml'], 500);
    expect(await fresh.getPref('goal_kcal'), '1900');
    expect(freshPrefs.getString('theme_mode'), 'dark');
    expect(freshPrefs.getDouble('text_scale'), 1.15);
    expect(freshPrefs.getString('sync_code'), isNull); // pairing stays per device

    // Restoring again changes nothing (no duplicates).
    expect(await Backup.restore(fresh, freshPrefs, contents), 0);
  });

  test('an older backup never overwrites a newer edit', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = await openTestDb();
    final id = await db.save('water_logs', {'day': '2026-11-09', 'ml': 250, 'logged_at': 1, 'source': 'water'});
    final backup = Backup.read(utf8.decode(await Backup.create(db, prefs, deviceName: 'Mac')));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await db.save('water_logs', {'id': id, 'day': '2026-11-09', 'ml': 750, 'logged_at': 1, 'source': 'water'});
    await Backup.restore(db, prefs, backup);
    expect((await db.query('water_logs')).single['ml'], 750);
  });

  test('not-a-backup files give clear messages', () {
    expect(() => Backup.read('nope'), throwsA(isA<FormatException>()));
    expect(() => Backup.read('{"format":"workout-plans"}'), throwsA(isA<FormatException>()));
    expect(
      () => Backup.read('{"format":"app-backup","version":99,"tables":{}}'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('newer version'))),
    );
  });

  test('sync result text says "Up to date" when nothing moved', () {
    expect(syncResultText(0, 0), 'Up to date');
    expect(syncResultText(4, 12), 'Sent 4, received 12');
  });
}
