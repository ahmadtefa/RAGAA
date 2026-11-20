import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// Shares generated report/backup files through the native mobile share sheet
/// (Android `ACTION_SEND`), which is the only practical way for a user on a
/// modern Android device to move a PDF/Excel file out of the app sandbox.
///
/// On Windows/Linux/macOS this is a no-op that returns `false`; those platforms
/// use the native save dialog plus "open containing folder" instead.
class FileShareService {
  const FileShareService();

  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// Shares [filePath]. Returns `true` when the share sheet was opened.
  Future<bool> shareFile(
    String filePath, {
    String? subject,
    String? text,
  }) async {
    if (!isSupported) return false;
    final file = File(filePath);
    if (!await file.exists()) return false;
    await Share.shareXFiles(
      [XFile(filePath, mimeType: mimeTypeFor(filePath), name: file.uri.pathSegments.last)],
      subject: subject,
      text: text,
    );
    return true;
  }

  /// Best-effort MIME type for the exported accounting files.
  static String mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.db') ||
        lower.endsWith('.sqlite') ||
        lower.endsWith('.sqlite3')) {
      return 'application/octet-stream';
    }
    return 'application/octet-stream';
  }
}
