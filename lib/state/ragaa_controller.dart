import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/date_ranges.dart';
import '../core/formatters.dart';
import '../data/app_database.dart';
import '../data/backup_service.dart';
import '../data/ragaa_repository.dart';
import '../models/audit_log_entry.dart';
import '../models/backup_info.dart';
import '../models/collection_record.dart';
import '../models/outlet.dart';
import '../models/outlet_shift.dart';
import '../models/report_models.dart';
import '../services/excel_export_service.dart';
import '../services/file_dialog_helper.dart';
import '../services/pdf_export_service.dart';

/// Application-level state coordinator wiring SQLite repository, reports,
/// PDF/Excel exports, audit logs, and backup/restore operations.
class RagaaController extends ChangeNotifier {
  final AppDatabase appDatabase;
  final RagaaRepository repository;
  final BackupService backupService;
  final PdfExportService pdfExportService;
  final ExcelExportService excelExportService;
  final FileDialogHelper fileDialogHelper;

  bool isInitialized = false;
  bool isBusy = false;
  String? startupError;

  List<Outlet> outlets = const [];
  DatabaseStats? databaseStats;
  List<BackupInfo> managedBackups = const [];
  List<MissingShiftItem> todayMissingShifts = const [];
  int dataRevision = 0;

  RagaaController({
    required this.appDatabase,
    required this.repository,
    required this.backupService,
    PdfExportService? pdfExportService,
    ExcelExportService? excelExportService,
    required this.fileDialogHelper,
  })  : pdfExportService = pdfExportService ?? PdfExportService(),
        excelExportService = excelExportService ?? ExcelExportService();

  /// Creates and initializes a production controller backed by on-disk SQLite.
  static Future<RagaaController> createDefault() async {
    final db = await AppDatabase.openDefault();
    final backupsDir = await AppDatabase.resolveDefaultBackupsDirectory();
    final exportsDir = await AppDatabase.resolveDefaultExportsDirectory();
    final repo = RagaaRepository(db);
    final backup = BackupService(
      appDatabase: db,
      repository: repo,
      managedBackupsDir: backupsDir,
    );
    final controller = RagaaController(
      appDatabase: db,
      repository: repo,
      backupService: backup,
      fileDialogHelper: FileDialogHelper(
        defaultExportsDir: exportsDir,
        defaultBackupsDir: backupsDir,
      ),
    );
    await controller.initialize();
    return controller;
  }

  List<Outlet> get activeOutlets =>
      outlets.where((o) => o.isActive).toList(growable: false);

  Map<String, String> get outletNamesById => {
        for (final o in outlets) o.id: o.name,
      };

  Future<void> initialize() async {
    try {
      await appDatabase.open();
      await repository.migrateLegacySharedPreferencesIfNeeded();
      await refreshAll();
      isInitialized = true;
      startupError = null;
    } catch (e) {
      startupError = e.toString();
      isInitialized = true;
    }
    notifyListeners();
  }

  Future<void> refreshAll() async {
    outlets = await repository.listOutlets(includeInactive: true);
    todayMissingShifts =
        await repository.findMissingShiftsForDate(dateKey(DateTime.now()));
    databaseStats = await backupService.getLiveDatabaseStats();
    managedBackups = await backupService.listManagedBackups();
    dataRevision++;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Outlet operations
  // ---------------------------------------------------------------------------

  Future<Outlet> createOutlet({
    required String name,
    required int shiftCount,
    List<ShiftScheduleInput>? schedules,
    String notes = '',
  }) async {
    final created = await repository.createOutlet(
      name: name,
      shiftCount: shiftCount,
      schedules: schedules,
      notes: notes,
    );
    await refreshAll();
    return created;
  }

  Future<Outlet> updateOutlet({
    required String outletId,
    required String name,
    required int shiftCount,
    List<ShiftScheduleInput>? schedules,
    bool? isActive,
    String? notes,
    String reason = '',
  }) async {
    final updated = await repository.updateOutlet(
      outletId: outletId,
      name: name,
      shiftCount: shiftCount,
      schedules: schedules,
      isActive: isActive,
      notes: notes,
      reason: reason,
    );
    await refreshAll();
    return updated;
  }

  Future<int> countCollectionsForOutletShift(
    String outletId,
    int shiftNumber,
  ) =>
      repository.countCollectionsForOutletShift(outletId, shiftNumber);

  // ---------------------------------------------------------------------------
  // Collection operations
  // ---------------------------------------------------------------------------

  Future<CollectionRecord?> findExistingCollection({
    required String outletId,
    required String operationalDate,
    required int shiftNumber,
  }) =>
      repository.findCollection(
        outletId: outletId,
        operationalDate: operationalDate,
        shiftNumber: shiftNumber,
      );

  Future<CollectionRecord> createCollection({
    required String outletId,
    required String operationalDate,
    required int shiftNumber,
    required int amountPiastres,
    String notes = '',
  }) async {
    final created = await repository.createCollection(
      outletId: outletId,
      operationalDate: operationalDate,
      shiftNumber: shiftNumber,
      amountPiastres: amountPiastres,
      notes: notes,
    );
    await refreshAll();
    return created;
  }

  Future<CollectionRecord> updateCollection({
    required int collectionId,
    required int newAmountPiastres,
    String? notes,
    String reason = '',
  }) async {
    final updated = await repository.updateCollection(
      collectionId: collectionId,
      newAmountPiastres: newAmountPiastres,
      notes: notes,
      reason: reason,
    );
    await refreshAll();
    return updated;
  }

  Future<List<CollectionRecord>> queryCollections({
    required OperationalDateRange range,
    Set<String> outletIds = const {},
    int? shiftNumber,
  }) =>
      repository.queryCollections(
        startDate: range.startKey,
        endDate: range.endKey,
        outletIds: outletIds,
        shiftNumber: shiftNumber,
      );

  // ---------------------------------------------------------------------------
  // Reports & PDF / Excel export
  // ---------------------------------------------------------------------------

  Future<ReportData> buildReport(ReportFilter filter) =>
      repository.buildReport(filter);

  /// Exports [report] as an Arabic RTL PDF file. Returns the saved file path,
  /// or `null` if the user cancelled the save dialog.
  Future<String?> exportReportPdf(
    ReportData report, {
    String? overridePath,
  }) async {
    final suggested = FileDialogHelper.suggestedReportFileName(
      report,
      extension: 'pdf',
    );
    final path = overridePath ??
        await fileDialogHelper.pickSavePath(
          suggestedName: suggested,
          extension: 'pdf',
          typeLabel: 'PDF Report',
        );
    if (path == null) return null;

    isBusy = true;
    notifyListeners();
    try {
      final file = await pdfExportService.exportReportToFile(report, path);
      return file.path;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Exports [report] as a multi-sheet Arabic RTL `.xlsx` file. Returns the
  /// saved file path, or `null` if the user cancelled the save dialog.
  Future<String?> exportReportExcel(
    ReportData report, {
    String? overridePath,
  }) async {
    final suggested = FileDialogHelper.suggestedReportFileName(
      report,
      extension: 'xlsx',
    );
    final path = overridePath ??
        await fileDialogHelper.pickSavePath(
          suggestedName: suggested,
          extension: 'xlsx',
          typeLabel: 'Excel Workbook (.xlsx)',
        );
    if (path == null) return null;

    isBusy = true;
    notifyListeners();
    try {
      final file = await excelExportService.exportReportToFile(report, path);
      return file.path;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Saves a report directly into the default exports directory without opening
  /// a dialog (handy for one-click quick exports).
  Future<String> quickExportReport(
    ReportData report, {
    required bool asPdf,
  }) async {
    final ext = asPdf ? 'pdf' : 'xlsx';
    final fileName = FileDialogHelper.suggestedReportFileName(
      report,
      extension: ext,
    );
    await Directory(fileDialogHelper.defaultExportsDir).create(recursive: true);
    final targetPath = p.join(fileDialogHelper.defaultExportsDir, fileName);
    final saved = asPdf
        ? await exportReportPdf(report, overridePath: targetPath)
        : await exportReportExcel(report, overridePath: targetPath);
    return saved!;
  }

  // ---------------------------------------------------------------------------
  // Audit Log
  // ---------------------------------------------------------------------------

  Future<List<AuditLogEntry>> queryAuditLogs({
    String? outletId,
    AuditEntityType? entityType,
    AuditAction? action,
    String? entityId,
    String? startOperationalDate,
    String? endOperationalDate,
    int limit = 250,
  }) =>
      repository.queryAuditLogs(
        outletId: outletId,
        entityType: entityType,
        action: action,
        entityId: entityId,
        startOperationalDate: startOperationalDate,
        endOperationalDate: endOperationalDate,
        limit: limit,
      );

  // ---------------------------------------------------------------------------
  // Backup & Restore
  // ---------------------------------------------------------------------------

  Future<BackupInfo> createManagedBackup() async {
    isBusy = true;
    notifyListeners();
    try {
      final info = await backupService.createBackup();
      await refreshAll();
      return info;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<BackupInfo?> exportBackupToCustomPath() async {
    final chosenPath = await fileDialogHelper.pickSavePath(
      suggestedName: backupService.suggestedBackupFileName(),
      extension: 'db',
      typeLabel: 'RAGAA SQLite Backup',
      isBackup: true,
    );
    if (chosenPath == null) return null;

    isBusy = true;
    notifyListeners();
    try {
      final info = await backupService.createBackup(destinationPath: chosenPath);
      await refreshAll();
      return info;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<String?> pickExternalBackupFile() =>
      fileDialogHelper.pickBackupFileToRestore();

  Future<DatabaseStats> inspectBackupFile(String filePath) =>
      backupService.validateBackupFile(filePath);

  Future<RestoreOutcome> restoreBackup(
    String filePath, {
    String reason = '',
  }) async {
    isBusy = true;
    notifyListeners();
    try {
      final outcome = await backupService.restoreFromFile(
        filePath,
        reason: reason,
      );
      await refreshAll();
      return outcome;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> deleteManagedBackup(String filePath) async {
    await backupService.deleteManagedBackup(filePath);
    managedBackups = await backupService.listManagedBackups();
    notifyListeners();
  }
}
