import 'dart:io';

import 'package:atharxa/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a fresh on-disk test database (each call gets its own file, so two
/// "devices" can be simulated side by side).
Future<AppDb> openTestDb() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('atharxa_test');
  return AppDb.openAt(p.join(dir.path, 'test.db'), factory: databaseFactoryFfi);
}
