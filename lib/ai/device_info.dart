import 'dart:io';

import 'ai_models.dart';

/// Reads RAM, chip and free space with system tools (no native code):
/// Android `/proc/meminfo` and `getprop`, macOS `sysctl`, and `df` on both.
/// Anything unreadable is left null.
Future<DeviceCapabilities> readDeviceCapabilities(String modelDir) async {
  final desktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  int? ram;
  String? chip;
  if (Platform.isAndroid) {
    ram = parseMemTotal(await _read('/proc/meminfo'));
    final maker = await _run('getprop', ['ro.soc.manufacturer']);
    final model = await _run('getprop', ['ro.soc.model']);
    chip = model == null || model.isEmpty ? null : (model.toLowerCase().startsWith('tensor') ? model : '$maker $model');
  } else if (Platform.isMacOS) {
    ram = int.tryParse(await _run('/usr/sbin/sysctl', ['-n', 'hw.memsize']) ?? '');
    chip = await _run('/usr/sbin/sysctl', ['-n', 'machdep.cpu.brand_string']);
  }
  return DeviceCapabilities(
    desktop: desktop,
    ramBytes: ram,
    chip: chip == null || chip.isEmpty ? null : chip,
    freeBytes: parseDfAvailable(await _run('df', ['-k', modelDir])),
  );
}

/// Bytes from `/proc/meminfo`'s "MemTotal: 11840768 kB".
int? parseMemTotal(String? meminfo) {
  final m = RegExp(r'MemTotal:\s+(\d+)\s*kB').firstMatch(meminfo ?? '');
  return m == null ? null : int.parse(m.group(1)!) * 1024;
}

/// Bytes available from `df -k <dir>` (the last line's 4th column).
int? parseDfAvailable(String? df) {
  final lines = (df ?? '').trim().split('\n');
  if (lines.length < 2) return null;
  final cols = lines.last.trim().split(RegExp(r'\s+'));
  return cols.length < 4 ? null : (int.tryParse(cols[3]) ?? 0) * 1024;
}

Future<String?> _read(String path) async {
  try {
    return await File(path).readAsString();
  } on FileSystemException {
    return null;
  }
}

Future<String?> _run(String exe, List<String> args) async {
  try {
    final r = await Process.run(exe, args);
    return r.exitCode == 0 ? '${r.stdout}'.trim() : null;
  } on ProcessException {
    return null;
  }
}
