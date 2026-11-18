/// High-level record statistics for a live or backup RAGAA SQLite database.
class DatabaseStats {
  final String filePath;
  final int fileSizeBytes;
  final int outletsCount;
  final int collectionsCount;
  final int auditLogsCount;
  final int totalPiastres;
  final int schemaVersion;

  const DatabaseStats({
    required this.filePath,
    required this.fileSizeBytes,
    required this.outletsCount,
    required this.collectionsCount,
    required this.auditLogsCount,
    required this.totalPiastres,
    required this.schemaVersion,
  });
}

/// Metadata for a saved local backup snapshot.
class BackupInfo {
  final String filePath;
  final String fileName;
  final int fileSizeBytes;
  final DateTime createdAt;
  final String sha256;
  final bool isPreRestoreSafety;
  final int? outletsCount;
  final int? collectionsCount;

  const BackupInfo({
    required this.filePath,
    required this.fileName,
    required this.fileSizeBytes,
    required this.createdAt,
    required this.sha256,
    required this.isPreRestoreSafety,
    this.outletsCount,
    this.collectionsCount,
  });
}

/// Outcome returned after a successful database restore operation.
class RestoreOutcome {
  final String restoredFromPath;
  final String safetyBackupPath;
  final DatabaseStats restoredStats;

  const RestoreOutcome({
    required this.restoredFromPath,
    required this.safetyBackupPath,
    required this.restoredStats,
  });
}
