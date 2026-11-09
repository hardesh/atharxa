import 'dart:io';
import 'dart:typed_data';

import 'package:nativeapi_flutter/nativeapi_flutter.dart'
    show DialogModality, FileDialog, FileDialogMode, FileDialogResult;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Saves an exported file where the user can find it.
/// * macOS: the system Save panel (via nativeapi, no extra plugin).
/// * Android: the public Download folder (allowed without a permission on
///   Android 11+), falling back to the app's own files folder.
///
/// Returns where it was saved (for the confirmation message), or null when
/// the user cancelled.
Future<String?> saveExportedFile(String fileName, Uint8List bytes) async {
  if (Platform.isMacOS) {
    final dialog = FileDialog.create(FileDialogMode.saveFile);
    if (dialog == null) return null;
    try {
      dialog
        ..setSuggestedFileName(fileName)
        ..setFileTypes([p.extension(fileName).replaceFirst('.', '')])
        ..modality = DialogModality.application;
      if (!dialog.open() || dialog.result != FileDialogResult.accepted || dialog.paths.isEmpty) return null;
      final path = dialog.paths.first;
      await File(path).writeAsBytes(bytes);
      return path;
    } finally {
      dialog.dispose();
    }
  }
  if (Platform.isAndroid) {
    try {
      final f = File('/storage/emulated/0/Download/$fileName');
      await f.writeAsBytes(bytes);
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

/// macOS: pick a file with the system Open panel and return its text, or
/// null if cancelled / unsupported (other platforms paste text instead).
Future<String?> openTextFile({List<String> extensions = const ['json', 'txt']}) async {
  if (!Platform.isMacOS) return null;
  final dialog = FileDialog.create(FileDialogMode.openFile);
  if (dialog == null) return null;
  try {
    dialog
      ..setFileTypes(extensions)
      ..modality = DialogModality.application;
    if (!dialog.open() || dialog.result != FileDialogResult.accepted || dialog.paths.isEmpty) return null;
    return await File(dialog.paths.first).readAsString();
  } finally {
    dialog.dispose();
  }
}
