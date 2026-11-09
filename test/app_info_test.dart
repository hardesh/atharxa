import 'dart:io';

import 'package:atharxa/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppInfo.version matches pubspec.yaml', () {
    final m = RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(AppInfo.version, m!.group(1));
  });

  test('the icon asset exists', () => expect(File(AppInfo.iconAsset).existsSync(), isTrue));
}
