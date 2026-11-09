import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Saving and opening user files (exports, backups, shared plans) through
/// the official file_selector plugin.

/// Saves [bytes] where the user can find them.
/// * macOS: the system Save panel.
/// * Android: the public Download folder (allowed without a permission on
///   Android 11+), falling back to the app's own files folder.
///
/// Returns where it was saved (for the confirmation message), or null when
/// the user cancelled.
Future<String?> saveExportedFile(String fileName, Uint8List bytes) async {
  if (Platform.isMacOS) {
    final ext = p.extension(fileName).replaceFirst('.', '');
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [
        XTypeGroup(label: ext.toUpperCase(), extensions: [ext]),
      ],
    );
    if (location == null) return null;
    await File(location.path).writeAsBytes(bytes);
    return location.path;
  }
  if (Platform.isAndroid) {
    try {
      await File('/storage/emulated/0/Download/$fileName').writeAsBytes(bytes);
      return 'Downloads/$fileName';
    } on FileSystemException {
      // Fall through to the app folder below.
    }
  }
  final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
  final f = File(p.join(dir.path, fileName));
  await f.writeAsBytes(bytes);
  return f.path;
}

/// Lets the user pick a text file (system picker on Android and macOS) and
/// returns its contents, or null if cancelled.
Future<String?> openTextFile({List<String> extensions = const ['json', 'txt']}) async {
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: 'Files',
        extensions: extensions,
        mimeTypes: const ['application/json', 'text/plain', 'application/octet-stream'],
        uniformTypeIdentifiers: const ['public.json', 'public.plain-text'],
      ),
    ],
  );
  return file?.readAsString();
}
