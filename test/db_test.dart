import 'dart:io';

import 'package:atharxa/data/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  test('schema opens and seeds default categories once', () async {
    final db = await openTestDb();
    final cats = await db.query('categories');
    expect(cats.where((c) => c['kind'] == 'expense').map((c) => c['name']), contains('Rent'));
    expect(cats.where((c) => c['kind'] == 'income').map((c) => c['name']), contains('Salary'));
    expect(cats.length, 11);
  });

  test('two devices converge with last-write-wins and tombstones', () async {
    final phone = await openTestDb();
    final mac = await openTestDb();

    final id = await phone.save('water_logs', {'day': '2026-11-08', 'ml': 250, 'logged_at': 1, 'source': 'today'});
    await mac.merge((await phone.changesPage(0)).rows);
    expect((await mac.query('water_logs', where: 'id = ?', args: [id])).single['ml'], 250);

    // Mac edits later -> wins on the phone.
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await mac.save('water_logs', {'id': id, 'day': '2026-11-08', 'ml': 500, 'logged_at': 1, 'source': 'today'});
    await phone.merge((await mac.changesPage(0)).rows);
    expect((await phone.query('water_logs', where: 'id = ?', args: [id])).single['ml'], 500);

    // An older copy arriving late does not overwrite the newer one.
    final stale = (await phone.changesPage(0)).rows;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await mac.delete('water_logs', id);
    await mac.merge(stale);
    expect(await mac.query('water_logs', where: 'id = ?', args: [id]), isEmpty);

    // The delete (tombstone) propagates.
    await phone.merge((await mac.changesPage(0)).rows);
    expect(await phone.query('water_logs', where: 'id = ?', args: [id]), isEmpty);
  });

  test('prefs round-trip', () async {
    final db = await openTestDb();
    await db.setPref('theme', 'ocean');
    expect(await db.getPref('theme'), 'ocean');
  });

  test('hasUserData: false on a fresh install, true after logging', () async {
    final db = await openTestDb();
    expect(await db.hasUserData(), isFalse);
    await db.save('water_logs', {'day': '2026-11-09', 'ml': 250, 'logged_at': 1, 'source': 'water'});
    expect(await db.hasUserData(), isTrue);
  });

  test('a background open/close does not close the app\'s connection', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('atharxa_bg');
    final path = p.join(dir.path, 'app.db');
    final app = await AppDb.openAt(path, factory: databaseFactoryFfi);
    // What the Android background sync job / notification action does:
    final background = await AppDb.openAt(path, factory: databaseFactoryFfi, separateConnection: true);
    await background.save('water_logs', {'day': '2026-11-09', 'ml': 250, 'logged_at': 1, 'source': 'notification'});
    await background.close();
    // The app keeps working and sees the background write.
    expect((await app.query('water_logs')).single['ml'], 250);
  });
}
