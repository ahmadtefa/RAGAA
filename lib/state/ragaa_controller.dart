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
import '../models/collection_amounts.dart';
import '../models/outlet.dart';
import '../models/outlet_shift.dart';
import '../models/daily_journal.dart';
import '../models/report_models.dart';
import '../services/daily_journal_pdf_service.dart';
import '../services/excel_export_service.dart';
import '../services/file_dialog_helper.dart';
import '../services/file_share_service.dart';
import '../services/pdf_export_service.dart';

/// Application-level state coordinator wiring SQLite repository, reports,
/// PDF/Excel exports, audit logs, and backup/restore operations.
class RagaaController extends ChangeNotifier {
  final AppDatabase appDatabase;
  final RagaaRepository repository;
  final BackupService backupService;
  final PdfExportService pdfExportService;
  final ExcelExportService excelExportService;
  final DailyJournalPdfService dailyJournalPdfService;
  final FileDialogHelper fileDialogHelper;
  final FileShareService fileShareService;

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
    DailyJournalPdfService? dailyJournalPdfService,
    FileShareService? fileShareService,
    required this.fileDialogHelper,
  })  : pdfExportService = pdfExportService ?? PdfExportService(),
        excelExportService = excelExportService ?? ExcelExportService(),
        dailyJournalPdfService =
            dailyJournalPdfService ?? DailyJournalPdfService(),
        fileShareService = fileShareService ?? const FileShareService();

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

  /// Moves an outlet one position up (-1) or down (+1) in the printed order.
  Future<void> moveOutlet(String outletId, int delta) async {
    await repository.moveOutlet(outletId, delta);
    await refreshAll();
  }

  /// Persists an explicit outlet order (used by drag & drop / settings screens).
  Future<void> reorderOutlets(List<String> orderedOutletIds) async {
    await repository.reorderOutlets(orderedOutletIds);
    await refreshAll();
  }

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
    int? amountPiastres,
    CollectionAmounts? amounts,
    String notes = '',
  }) async {
    final created = await repository.createCollection(
      outletId: outletId,
      operationalDate: operationalDate,
      shiftNumber: shiftNumber,
      amountPiastres: amountPiastres,
      amounts: amounts,
      notes: notes,
    );
    await refreshAll();
    return created;
  }

  Future<CollectionRecord> updateCollection({
    required int collectionId,
    int? newAmountPiastres,
    CollectionAmounts? newAmounts,
    String? notes,
    String reason = '',
  }) async {
    final updated = await repository.updateCollection(
      collectionId: collectionId,
      newAmountPiastres: newAmountPiastres,
      newAmounts: newAmounts,
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
      return _deliverSaved(
        file.path,
        mimeType: 'application/pdf',
      );
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
      return _deliverSaved(
        file.path,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
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
    return saved ?? targetPath;
  }

  /// Hands a finished file to the operator.
  ///
  /// On Windows and Linux the file is already at the path the operator chose in
  /// the Save-as dialog, so this only returns it. On Android the bytes are
  /// written to the program's exports folder first, and this opens the system
  /// dialog that copies them to the folder and name the operator picks — which
  /// is the only way to save there without asking for a storage-wide
  /// permission. A cancelled dialog returns `null`, so the screens can say
  /// "لم يتم الحفظ" instead of pretending the file was saved.
  Future<String?> _deliverSaved(
    String writtenPath, {
    required String mimeType,
  }) async {
    final delivered = await fileDialogHelper.deliverToChosenLocation(
      writtenPath: writtenPath,
      fileName: p.basename(writtenPath),
      mimeType: mimeType,
    );
    lastSavedLocalPath = writtenPath;
    lastSavedPath = delivered;
    return delivered;
  }

  /// The place the last saved export landed, for the banner that offers to open
  /// it, reveal its folder or share it.
  String? lastSavedPath;

  /// The same file as it exists inside the program's own folder. On Android the
  /// saved location is a document URI, which the share sheet cannot read, so the
  /// local copy is what gets shared.
  String? lastSavedLocalPath;

  /// Opens a saved export with the program the system associates with it.
  Future<bool> openSavedFile(String pathOrUri) =>
      FileDialogHelper.openFileWithSystem(pathOrUri);

  // ---------------------------------------------------------------------------
  // Daily journal (اليومية)
  // ---------------------------------------------------------------------------

  /// Builds the electronic daily journal for [date]. The very same model is
  /// printed to PDF, written to Excel and rendered on screen.
  Future<DailyJournal> buildDailyJournal(
    DateTime date, {
    Set<String> outletIds = const {},
  }) =>
      repository.buildDailyJournal(
        dateKey(date),
        outletIds: outletIds,
      );

  /// Exports [journal] as a print-ready A4 landscape PDF.
  Future<String?> exportJournalPdf(
    DailyJournal journal, {
    String? overridePath,
  }) async {
    final path = overridePath ??
        await fileDialogHelper.pickSavePath(
          suggestedName: suggestedJournalFileName(journal, extension: 'pdf'),
          extension: 'pdf',
          typeLabel: 'PDF Daily Journal',
        );
    if (path == null) return null;

    isBusy = true;
    notifyListeners();
    try {
      final file = await dailyJournalPdfService.exportJournalToFile(
        journal,
        path,
      );
      return _deliverSaved(
        file.path,
        mimeType: 'application/pdf',
      );
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Exports [journal] as an RTL `.xlsx` sheet with real Excel formulas.
  Future<String?> exportJournalExcel(
    DailyJournal journal, {
    String? overridePath,
  }) async {
    final path = overridePath ??
        await fileDialogHelper.pickSavePath(
          suggestedName: suggestedJournalFileName(journal, extension: 'xlsx'),
          extension: 'xlsx',
          typeLabel: 'Excel Workbook (.xlsx)',
        );
    if (path == null) return null;

    isBusy = true;
    notifyListeners();
    try {
      final file = await excelExportService.exportJournalToFile(journal, path);
      return _deliverSaved(
        file.path,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Saves the journal straight into the default exports directory.
  Future<String> quickExportJournal(
    DailyJournal journal, {
    required bool asPdf,
  }) async {
    final extension = asPdf ? 'pdf' : 'xlsx';
    await Directory(fileDialogHelper.defaultExportsDir).create(recursive: true);
    final targetPath = p.join(
      fileDialogHelper.defaultExportsDir,
      suggestedJournalFileName(journal, extension: extension),
    );
    final saved = asPdf
        ? await exportJournalPdf(journal, overridePath: targetPath)
        : await exportJournalExcel(journal, overridePath: targetPath);
    return saved ?? targetPath;
  }

  static String suggestedJournalFileName(
    DailyJournal journal, {
    required String extension,
  }) =>
      'ragaa_journal_${journal.operationalDate}.$extension';

  /// Opens the native share sheet for [filePath] (Android/iOS only).
  Future<bool> shareFile(String filePath) =>
      fileShareService.shareFile(filePath);

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
      final info =
          await backupService.createBackup(destinationPath: chosenPath);
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
