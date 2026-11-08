import 'package:flutter_test/flutter_test.dart';

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
    await mac.merge(await phone.changesSince(0));
    expect((await mac.query('water_logs', where: 'id = ?', args: [id])).single['ml'], 250);

    // Mac edits later -> wins on the phone.
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await mac.save('water_logs', {'id': id, 'day': '2026-11-08', 'ml': 500, 'logged_at': 1, 'source': 'today'});
    await phone.merge(await mac.changesSince(0));
    expect((await phone.query('water_logs', where: 'id = ?', args: [id])).single['ml'], 500);

    // An older copy arriving late does not overwrite the newer one.
    final stale = await phone.changesSince(0);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await mac.delete('water_logs', id);
    await mac.merge(stale);
    expect(await mac.query('water_logs', where: 'id = ?', args: [id]), isEmpty);

    // The delete (tombstone) propagates.
    await phone.merge(await mac.changesSince(0));
    expect(await phone.query('water_logs', where: 'id = ?', args: [id]), isEmpty);
  });

  test('prefs round-trip', () async {
    final db = await openTestDb();
    await db.setPref('theme', 'ocean');
    expect(await db.getPref('theme'), 'ocean');
  });
}
