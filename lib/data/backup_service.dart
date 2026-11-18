import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/exceptions.dart';
import '../models/audit_log_entry.dart';
import '../models/backup_info.dart';
import 'app_database.dart';
import 'database_factory_init.dart';
import 'ragaa_repository.dart';

/// SQLite 3 file header signature (`"SQLite format 3\x00"`).
const List<int> _kSqliteMagicHeader = [
  0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
  0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3\0"
];

/// Provides transactionally consistent SQLite backups, SHA-256 verification,
/// schema/integrity checks, and safe restoration with automatic pre-restore
/// safety snapshots.
class BackupService {
  final AppDatabase appDatabase;
  final RagaaRepository repository;
  final String managedBackupsDir;
  final DatabaseFactory _factory;
  final DateTime Function() _clock;
  int _backupSeq = 0;

  BackupService({
    required this.appDatabase,
    required this.repository,
    required this.managedBackupsDir,
    DatabaseFactory? factory,
    DateTime Function()? clock,
  })  : _factory = factory ?? resolveDatabaseFactory(),
        _clock = clock ?? DateTime.now;

  /// Computes a SHA-256 hex digest of a file on disk.
  Future<String> computeFileSha256(String filePath) async {
    final digest = await sha256.bind(File(filePath).openRead()).first;
    return digest.toString();
  }

  /// Returns current record counts and file size for the live database.
  Future<DatabaseStats> getLiveDatabaseStats() async {
    final db = await appDatabase.database;
    await appDatabase.checkpoint();
    var size = 0;
    if (appDatabase.dbPath != inMemoryDatabasePath) {
      final f = File(appDatabase.dbPath);
      if (await f.exists()) {
        size = await f.length();
      }
    }
    return _readStatsFromExecutor(db, appDatabase.dbPath, size);
  }

  Future<DatabaseStats> _readStatsFromExecutor(
    Database db,
    String filePath,
    int fileSizeBytes,
  ) async {
    final outletsRes =
        await db.rawQuery('SELECT COUNT(*) AS cnt FROM outlets;');
    final colsRes = await db.rawQuery(
      'SELECT COUNT(*) AS cnt, COALESCE(SUM(amount_piastres), 0) AS total FROM collections;',
    );
    final auditsRes =
        await db.rawQuery('SELECT COUNT(*) AS cnt FROM audit_logs;');
    final versionRes = await db.rawQuery('PRAGMA user_version;');

    final schemaVer = versionRes.isNotEmpty
        ? ((versionRes.first.values.first as int?) ?? 0)
        : 0;

    return DatabaseStats(
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      outletsCount: (outletsRes.first['cnt'] as int?) ?? 0,
      collectionsCount: (colsRes.first['cnt'] as int?) ?? 0,
      auditLogsCount: (auditsRes.first['cnt'] as int?) ?? 0,
      totalPiastres: (colsRes.first['total'] as int?) ?? 0,
      schemaVersion: schemaVer,
    );
  }

  String _timestampSlug(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year.toString().padLeft(4, '0')}'
        '${l.month.toString().padLeft(2, '0')}'
        '${l.day.toString().padLeft(2, '0')}_'
        '${l.hour.toString().padLeft(2, '0')}'
        '${l.minute.toString().padLeft(2, '0')}'
        '${l.second.toString().padLeft(2, '0')}';
  }

  /// Generates a recommended default filename for user-exported backups.
  String suggestedBackupFileName() =>
      'ragaa_backup_${_timestampSlug(_clock())}.ragaa.db';

  /// Creates a clean, standalone, verified SQLite backup.
  ///
  /// If [destinationPath] is null, stores the backup inside [managedBackupsDir].
  Future<BackupInfo> createBackup({
    String? destinationPath,
    bool isPreRestoreSafety = false,
  }) async {
    final now = _clock();
    _backupSeq++;
    final prefix = isPreRestoreSafety ? 'pre_restore' : 'ragaa_backup';
    final targetPath = destinationPath ??
        p.join(
          managedBackupsDir,
          '${prefix}_${_timestampSlug(now)}_$_backupSeq.ragaa.db',
        );

    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);

    // Prevent overwriting the live database file itself.
    if (appDatabase.dbPath != inMemoryDatabasePath &&
        p.canonicalize(targetPath) == p.canonicalize(appDatabase.dbPath)) {
      throw const BackupIntegrityException(
        'لا يمكن حفظ النسخة الاحتياطية فوق ملف قاعدة البيانات الحالي مباشرة',
      );
    }

    final tempPath = '$targetPath.tmp_${now.microsecondsSinceEpoch}';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final db = await appDatabase.database;
    try {
      await appDatabase.checkpoint();
      // VACUUM INTO creates a self-contained, defragmented, consistent SQLite DB
      // without interrupting the active connection or needing WAL/SHM sidecars.
      final escaped = tempPath.replaceAll("'", "''");
      await db.execute("VACUUM INTO '$escaped';");

      // Verify the newly produced backup before moving it into final position.
      final stats = await validateBackupFile(tempPath, checkSidecarHash: false);

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetPath);

      final digest = await computeFileSha256(targetPath);
      final sidecarFile = File('$targetPath.sha256');
      await sidecarFile.writeAsString('$digest  ${p.basename(targetPath)}\n');

      final stat = await targetFile.stat();
      return BackupInfo(
        filePath: targetPath,
        fileName: p.basename(targetPath),
        fileSizeBytes: stat.size,
        createdAt: stat.modified,
        sha256: digest,
        isPreRestoreSafety: isPreRestoreSafety,
        outletsCount: stats.outletsCount,
        collectionsCount: stats.collectionsCount,
      );
    } catch (e) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      if (e is RagaaException) rethrow;
      throw BackupIntegrityException('تعذر إنشاء النسخة الاحتياطية: $e');
    }
  }

  /// Thoroughly validates a candidate backup file:
  /// 1. Exists, non-empty, valid SQLite 3 magic header.
  /// 2. Matches `.sha256` sidecar file if present and [checkSidecarHash] is true.
  /// 3. Passes `PRAGMA integrity_check` and `PRAGMA foreign_key_check`.
  /// 4. Contains all required RAGAA schema tables and compatible schema version.
  Future<DatabaseStats> validateBackupFile(
    String filePath, {
    bool checkSidecarHash = true,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const BackupIntegrityException('ملف النسخة الاحتياطية غير موجود');
    }
    final length = await file.length();
    if (length < _kSqliteMagicHeader.length) {
      throw const BackupIntegrityException(
        'ملف النسخة الاحتياطية فارغ أو تالف (حجم غير صالح)',
      );
    }

    // Verify 16-byte SQLite header before attempting to open.
    final headerBytes = await file.openRead(0, _kSqliteMagicHeader.length).fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    for (var i = 0; i < _kSqliteMagicHeader.length; i++) {
      if (headerBytes[i] != _kSqliteMagicHeader[i]) {
        throw const BackupIntegrityException(
          'الملف المحدد ليس قاعدة بيانات SQLite صالحة',
        );
      }
    }

    if (checkSidecarHash) {
      final sidecar = File('$filePath.sha256');
      if (await sidecar.exists()) {
        final raw = (await sidecar.readAsString()).trim();
        final expected = raw.split(RegExp(r'\s+')).first.toLowerCase();
        if (RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
          final actual = (await computeFileSha256(filePath)).toLowerCase();
          if (actual != expected) {
            throw const BackupIntegrityException(
              'فشل التحقق من البصمة الرقمية (SHA-256): الملف قد يكون تالفًا أو معدّلًا',
            );
          }
        }
      }
    }

    Database? checkDb;
    try {
      checkDb = await _factory.openDatabase(
        filePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );

      final integrityRows = await checkDb.rawQuery('PRAGMA integrity_check;');
      final integrityResult = integrityRows.isNotEmpty
          ? integrityRows.first.values.first?.toString().toLowerCase()
          : null;
      if (integrityResult != 'ok') {
        throw BackupIntegrityException(
          'فشل فحص سلامة قاعدة البيانات: ${integrityResult ?? "غير معروف"}',
        );
      }

      final tableRows = await checkDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table';",
      );
      final existingTables = {
        for (final r in tableRows) r['name'] as String,
      };
      for (final requiredTable in kRequiredDatabaseTables) {
        if (!existingTables.contains(requiredTable)) {
          throw BackupIntegrityException(
            'ملف النسخة الاحتياطية لا يطابق هيكل برنامج RAGAA (ينقص الجدول: $requiredTable)',
          );
        }
      }

      final fkIssues = await checkDb.rawQuery('PRAGMA foreign_key_check;');
      if (fkIssues.isNotEmpty) {
        throw const BackupIntegrityException(
          'ملف النسخة الاحتياطية يحتوي على تعارض في المراجع المحاسبية',
        );
      }

      final stats = await _readStatsFromExecutor(checkDb, filePath, length);
      if (stats.schemaVersion > kDatabaseSchemaVersion) {
        throw BackupIntegrityException(
          'النسخة الاحتياطية منشأة بإصدار أحدث من البرنامج (v${stats.schemaVersion})؛ حدّث البرنامج أولًا',
        );
      }
      return stats;
    } on RagaaException {
      rethrow;
    } catch (e) {
      throw BackupIntegrityException('تعذر قراءة ملف النسخة الاحتياطية: $e');
    } finally {
      if (checkDb != null && checkDb.isOpen) {
        await checkDb.close();
      }
    }
  }

  /// Restores the live database from [sourcePath]:
  /// 1. Validates [sourcePath] completely before making any change.
  /// 2. Takes an automatic pre-restore safety snapshot of current live data.
  /// 3. Closes the live connection, replaces the DB file atomically, removes stale
  ///    WAL/SHM files, reopens the DB, and logs the restore in `audit_logs`.
  Future<RestoreOutcome> restoreFromFile(
    String sourcePath, {
    String reason = '',
  }) async {
    if (appDatabase.dbPath == inMemoryDatabasePath) {
      throw const BackupIntegrityException(
        'الاستعادة تتطلب قاعدة بيانات مخزنة على القرص',
      );
    }
    if (p.canonicalize(sourcePath) == p.canonicalize(appDatabase.dbPath)) {
      throw const BackupIntegrityException(
        'الملف المحدد هو قاعدة البيانات الحالية بالفعل',
      );
    }

    // Step 1: Validate candidate backup strictly before touching live data.
    await validateBackupFile(sourcePath, checkSidecarHash: true);

    // Step 2: Take an automatic pre-restore safety snapshot.
    final safetyBackup = await createBackup(isPreRestoreSafety: true);

    // Step 3: Stage a clean copy next to live DB before closing.
    final livePath = appDatabase.dbPath;
    final stagedPath = '$livePath.restore_staging';
    final stagedFile = File(stagedPath);
    await File(sourcePath).copy(stagedPath);

    // Step 4: Close live DB, clean WAL/SHM sidecars, swap in staged copy, reopen.
    await appDatabase.close();
    try {
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final sidecar = File('$livePath$suffix');
        if (await sidecar.exists()) {
          await sidecar.delete();
        }
      }
      final liveFile = File(livePath);
      if (await liveFile.exists()) {
        await liveFile.delete();
      }
      await stagedFile.rename(livePath);
    } catch (e) {
      // Attempt emergency rollback from safety backup if swap failed mid-flight.
      final liveFile = File(livePath);
      if (!await liveFile.exists() && await File(safetyBackup.filePath).exists()) {
        await File(safetyBackup.filePath).copy(livePath);
      }
      await appDatabase.open();
      throw BackupIntegrityException('فشلت عملية استبدال قاعدة البيانات: $e');
    }

    await appDatabase.open();

    await repository.recordSystemAudit(
      action: AuditAction.restore,
      entityId: p.basename(sourcePath),
      summary:
          'استعادة قاعدة البيانات من النسخة "${p.basename(sourcePath)}" (تم حفظ نسخة أمان تلقائية: ${safetyBackup.fileName})',
      reason: reason,
      afterMap: {
        'restored_from': sourcePath,
        'safety_backup': safetyBackup.filePath,
      },
    );

    final restoredStats = await getLiveDatabaseStats();
    return RestoreOutcome(
      restoredFromPath: sourcePath,
      safetyBackupPath: safetyBackup.filePath,
      restoredStats: restoredStats,
    );
  }

  /// Lists all `.db` / `.sqlite` snapshots inside [managedBackupsDir], newest first.
  Future<List<BackupInfo>> listManagedBackups() async {
    final dir = Directory(managedBackupsDir);
    if (!await dir.exists()) return const [];

    final items = <BackupInfo>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.db') && !name.endsWith('.sqlite')) continue;

      final stat = await entity.stat();
      var hash = '';
      final sidecar = File('${entity.path}.sha256');
      if (await sidecar.exists()) {
        hash = (await sidecar.readAsString()).trim().split(RegExp(r'\s+')).first;
      }

      int? outletsCount;
      int? collectionsCount;
      try {
        final stats = await validateBackupFile(
          entity.path,
          checkSidecarHash: false,
        );
        outletsCount = stats.outletsCount;
        collectionsCount = stats.collectionsCount;
      } catch (_) {
        // Leave counts null if unreadable; validation catches it on restore.
      }

      items.add(
        BackupInfo(
          filePath: entity.path,
          fileName: name,
          fileSizeBytes: stat.size,
          createdAt: stat.modified,
          sha256: hash,
          isPreRestoreSafety: name.startsWith('pre_restore_'),
          outletsCount: outletsCount,
          collectionsCount: collectionsCount,
        ),
      );
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// Deletes a backup snapshot and its `.sha256` sidecar from [managedBackupsDir].
  Future<void> deleteManagedBackup(String filePath) async {
    final canonicalDir = p.canonicalize(managedBackupsDir);
    final canonicalFile = p.canonicalize(filePath);
    if (!p.isWithin(canonicalDir, canonicalFile)) {
      throw const ValidationException('لا يمكن حذف ملفات خارج مجلد النسخ الاحتياطي');
    }
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
    final sidecar = File('$filePath.sha256');
    if (await sidecar.exists()) {
      await sidecar.delete();
    }
  }
}
