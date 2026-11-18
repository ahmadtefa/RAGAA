import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../models/report_models.dart';

/// Handles platform-appropriate file save and open dialogs across
/// Windows, Linux, and Android, with safe local directory fallbacks.
class FileDialogHelper {
  final String defaultExportsDir;
  final String defaultBackupsDir;

  const FileDialogHelper({
    required this.defaultExportsDir,
    required this.defaultBackupsDir,
  });

  /// Builds a clean ASCII-safe filename for a report export.
  static String suggestedReportFileName(
    ReportData report, {
    required String extension,
  }) {
    final range = report.filter.range;
    final periodSlug = range.type.name;
    final dateSlug = range.startKey == range.endKey
        ? range.startKey
        : '${range.startKey}_to_${range.endKey}';
    final shiftSlug = report.filter.shiftNumber != null
        ? '_shift${report.filter.shiftNumber}'
        : '';
    return 'ragaa_${periodSlug}_$dateSlug$shiftSlug.$extension';
  }

  /// Resolves a target path for saving a file.
  /// On Windows/Linux/macOS opens the native save dialog; on Android saves
  /// directly inside the app's exports/backups directory and returns the path.
  /// Returns `null` if the user explicitly cancelled the desktop save dialog.
  Future<String?> pickSavePath({
    required String suggestedName,
    required String extension,
    required String typeLabel,
    bool isBackup = false,
  }) async {
    final baseDir = isBackup ? defaultBackupsDir : defaultExportsDir;
    await Directory(baseDir).create(recursive: true);

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final location = await getSaveLocation(
        initialDirectory: baseDir,
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          XTypeGroup(label: typeLabel, extensions: [extension]),
        ],
      );
      if (location == null) return null;
      var chosen = location.path;
      if (!chosen.toLowerCase().endsWith('.${extension.toLowerCase()}')) {
        chosen = '$chosen.$extension';
      }
      return chosen;
    }

    // Mobile fallback (Android/iOS): write into accessible app documents directory.
    return p.join(baseDir, suggestedName);
  }

  /// Opens a native file picker to select an existing SQLite backup file.
  Future<String?> pickBackupFileToRestore() async {
    await Directory(defaultBackupsDir).create(recursive: true);
    final selected = await openFile(
      initialDirectory: defaultBackupsDir,
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'RAGAA SQLite Backup',
          extensions: ['db', 'sqlite', 'sqlite3'],
        ),
      ],
    );
    return selected?.path;
  }

  /// Best-effort opening of the parent folder in the desktop file manager
  /// (Windows Explorer or Linux `xdg-open`).
  static Future<bool> revealContainingFolder(String filePath) async {
    try {
      final folder = p.dirname(filePath);
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [folder]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [folder]);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [folder]);
        return true;
      }
    } catch (_) {
      // Ignore if file manager utility is unavailable.
    }
    return false;
  }
}
