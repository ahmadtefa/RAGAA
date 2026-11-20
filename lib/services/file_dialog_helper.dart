import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../models/report_models.dart';

/// Handles platform-appropriate file save and open dialogs across
/// Windows, Linux, and Android, with safe local directory fallbacks.
///
/// The two platforms answer "where should this file go?" in opposite orders,
/// and the difference matters to the operator:
///
///   • Windows and Linux have a Save-as dialog, so the destination is known
///     before a single byte is written, and the program writes straight there.
///   • Android has no such thing. The Storage Access Framework hands out a
///     destination only after the finished file exists, so the program writes
///     into its own exports folder first and then copies the bytes to the
///     folder (Downloads, a memory card, Drive…) the operator picks.
///
/// Either way the operator chooses the folder and the file name, a cancelled
/// save is not an error, and no storage-wide permission is ever requested.
class FileDialogHelper {
  final String defaultExportsDir;
  final String defaultBackupsDir;

  const FileDialogHelper({
    required this.defaultExportsDir,
    required this.defaultBackupsDir,
  });

  /// True on the platforms that own a native Save-as dialog.
  static bool get hasNativeSaveDialog =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// True on the platforms where the system save dialog is used after the file
  /// has been written locally (Android, and iOS if it is ever targeted).
  static bool get usesSystemDocumentPicker =>
      Platform.isAndroid || Platform.isIOS;

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
  ///
  /// On Windows/Linux/macOS this opens the native save dialog and returns the
  /// exact path the operator chose. On Android it returns a path inside the
  /// program's own exports folder: the finished bytes are written there and
  /// then handed to [deliverToChosenLocation], which opens the system dialog.
  /// Returns `null` if the operator cancelled the desktop save dialog.
  Future<String?> pickSavePath({
    required String suggestedName,
    required String extension,
    required String typeLabel,
    bool isBackup = false,
  }) async {
    final baseDir = isBackup ? defaultBackupsDir : defaultExportsDir;
    await Directory(baseDir).create(recursive: true);

    if (hasNativeSaveDialog) {
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

    // Mobile: the system dialog comes after the file exists (see
    // deliverToChosenLocation), so the program writes here first.
    return p.join(baseDir, suggestedName);
  }

  /// Writes a finished file where the operator wants it and reports that place.
  ///
  /// Returns the chosen location (an absolute path on the desktop, the document
  /// URI on Android), or `null` when the operator cancelled the save.
  Future<String?> deliverToChosenLocation({
    required String writtenPath,
    required String fileName,
    required String mimeType,
  }) async {
    if (hasNativeSaveDialog) return writtenPath;
    if (!usesSystemDocumentPicker) return writtenPath;
    try {
      final savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: writtenPath,
          fileName: fileName,
          mimeTypesFilter: [mimeType],
        ),
      );
      // Android answers with the document URI the operator chose; a null answer
      // means they backed out of the picker.
      return savedPath;
    } catch (_) {
      // A picker that cannot open is not a reason to lose the export: the file
      // is already saved in the program's exports folder.
      return writtenPath;
    }
  }

  /// Opens a saved PDF/Excel file with whatever the system uses for it.
  ///
  /// On Android the argument may be a `content://` document URI returned by the
  /// save dialog; the system resolves that itself. Returns false when nothing
  /// could be opened, so the caller can offer "share" instead.
  static Future<bool> openFileWithSystem(String pathOrUri) async {
    try {
      final result = await OpenFilex.open(pathOrUri);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  /// Opens a native file picker to select an existing SQLite backup file.
  Future<String?> pickBackupFileToRestore() async {
    await Directory(defaultBackupsDir).create(recursive: true);
    if (usesSystemDocumentPicker) {
      try {
        final picked = await FlutterFileDialog.pickFile(
          params: const OpenFileDialogParams(
            fileExtensionsFilter: ['db', 'sqlite', 'sqlite3'],
          ),
        );
        return picked;
      } catch (_) {
        return null;
      }
    }
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
