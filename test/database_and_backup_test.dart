import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ragaa/core/date_ranges.dart';
import 'package:ragaa/core/exceptions.dart';
import 'package:ragaa/core/formatters.dart';
import 'package:ragaa/data/app_database.dart';
import 'package:ragaa/data/backup_service.dart';
import 'package:ragaa/data/ragaa_repository.dart';
import 'package:ragaa/models/audit_log_entry.dart';
import 'package:ragaa/models/outlet_shift.dart';
import 'package:ragaa/models/report_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;
  late AppDatabase appDb;
  late RagaaRepository repo;
  late BackupService backupService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ragaa_db_test_');
    final dbPath = p.join(tempDir.path, 'data', 'ragaa_test.db');
    final backupsDir = p.join(tempDir.path, 'backups');
    appDb = AppDatabase.atPath(dbPath);
    await appDb.open();
    repo = RagaaRepository(appDb);
    backupService = BackupService(
      appDatabase: appDb,
      repository: repo,
      managedBackupsDir: backupsDir,
    );
  });

  tearDown(() async {
    await appDb.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('creates outlets with 2 or 3 independent shifts and custom schedules',
      () async {
    final o1 = await repo.createOutlet(
      name: 'منفذ المعادي',
      shiftCount: 2,
      schedules: const [
        ShiftScheduleInput(
          shiftNumber: 1,
          label: 'صباحية',
          startTime: '07:00',
          endTime: '19:00',
        ),
        ShiftScheduleInput(
          shiftNumber: 2,
          label: 'مسائية',
          startTime: '19:00',
          endTime: '07:00',
        ),
      ],
    );

    final o2 = await repo.createOutlet(
      name: 'منفذ مدينة نصر',
      shiftCount: 3,
      schedules: const [
        ShiftScheduleInput(
          shiftNumber: 1,
          label: 'أولى',
          startTime: '08:00',
          endTime: '16:00',
        ),
        ShiftScheduleInput(
          shiftNumber: 2,
          label: 'ثانية',
          startTime: '16:00',
          endTime: '00:00',
        ),
        ShiftScheduleInput(
          shiftNumber: 3,
          label: 'ليلية',
          startTime: '00:00',
          endTime: '08:00',
        ),
      ],
    );

    expect(o1.activeShifts.length, 2);
    expect(o1.shiftByNumber(2)!.isOvernight, isTrue);
    expect(o2.activeShifts.length, 3);

    // Reject duplicate name and invalid shift count.
    await expectLater(
      repo.createOutlet(name: 'منفذ المعادي', shiftCount: 2),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      repo.createOutlet(name: 'منفذ ثالث', shiftCount: 4),
      throwsA(isA<ValidationException>()),
    );
  });

  test(
      'updating shift count (3 -> 2 -> 3) and shift times preserves all historical data',
      () async {
    final outlet = await repo.createOutlet(
      name: 'منفذ الجيزة',
      shiftCount: 3,
      schedules: const [
        ShiftScheduleInput(
          shiftNumber: 1,
          label: 'الوردية الأولى',
          startTime: '08:00',
          endTime: '16:00',
        ),
        ShiftScheduleInput(
          shiftNumber: 2,
          label: 'الوردية الثانية',
          startTime: '16:00',
          endTime: '00:00',
        ),
        ShiftScheduleInput(
          shiftNumber: 3,
          label: 'الوردية الليلية',
          startTime: '00:00',
          endTime: '08:00',
        ),
      ],
    );

    final s1 = await repo.createCollection(
      outletId: outlet.id,
      operationalDate: '2026-11-18',
      shiftNumber: 1,
      amountPiastres: 100000,
    );
    final s3 = await repo.createCollection(
      outletId: outlet.id,
      operationalDate: '2026-11-18',
      shiftNumber: 3,
      amountPiastres: 75050,
    );

    expect(await repo.countCollectionsForOutletShift(outlet.id, 3), 1);

    // Change outlet from 3 shifts to 2 shifts and modify shift 1 hours.
    final updatedTo2 = await repo.updateOutlet(
      outletId: outlet.id,
      name: 'منفذ الجيزة الرئيسي',
      shiftCount: 2,
      schedules: const [
        ShiftScheduleInput(
          shiftNumber: 1,
          label: 'الوردية الأولى',
          startTime: '09:00',
          endTime: '21:00',
        ),
        ShiftScheduleInput(
          shiftNumber: 2,
          label: 'الوردية الثانية',
          startTime: '21:00',
          endTime: '09:00',
        ),
      ],
      reason: 'تعديل نظام العمل الشتوي',
    );
    expect(updatedTo2.shiftCount, 2);
    expect(updatedTo2.activeShifts.length, 2);

    // New shift-3 entry is rejected while configured as 2 shifts.
    await expectLater(
      repo.createCollection(
        outletId: outlet.id,
        operationalDate: '2026-11-19',
        shiftNumber: 3,
        amountPiastres: 50000,
      ),
      throwsA(isA<ValidationException>()),
    );

    // All prior collections (including shift 3 and original schedule snapshots) remain intact!
    final allCols = await repo.queryCollections(
      startDate: '2026-11-18',
      endDate: '2026-11-18',
    );
    expect(allCols.length, 2);
    final keptS1 = allCols.firstWhere((c) => c.id == s1.id);
    expect(keptS1.shiftStartSnapshot, '08:00');
    expect(keptS1.shiftEndSnapshot, '16:00');

    final report = await repo.buildReport(
      ReportFilter(range: OperationalDateRange.daily(DateTime(2026, 11, 18))),
    );
    expect(report.grandTotalPiastres, 175050);
    expect(report.byOutlet.single.shift3Piastres, 75050);

    // Historical shift-3 record can still be audited/adjusted if required.
    final adjustedS3 = await repo.updateCollection(
      collectionId: s3.id,
      newAmountPiastres: 80000,
      reason: 'مراجعة إيصال متأخر',
    );
    expect(adjustedS3.amountPiastres, 80000);

    // Re-enabling 3 shifts restores the previously saved shift-3 custom label & schedule.
    final backTo3 = await repo.updateOutlet(
      outletId: outlet.id,
      name: 'منفذ الجيزة الرئيسي',
      shiftCount: 3,
    );
    expect(backTo3.shiftByNumber(3)!.label, 'الوردية الليلية');
    expect(backTo3.shiftByNumber(3)!.isEnabled, isTrue);
  });

  test(
      'strictly prevents duplicate collection and logs all edits in audit_logs',
      () async {
    final outlet =
        await repo.createOutlet(name: 'منفذ الدقي', shiftCount: 2);

    final created = await repo.createCollection(
      outletId: outlet.id,
      operationalDate: '2026-11-18',
      shiftNumber: 1,
      amountPiastres: 250000,
      notes: 'تحصيل نقدي',
    );

    // Duplicate (outlet + date + shift) must throw DuplicateCollectionException.
    await expectLater(
      repo.createCollection(
        outletId: outlet.id,
        operationalDate: '2026-11-18',
        shiftNumber: 1,
        amountPiastres: 300000,
      ),
      throwsA(
        isA<DuplicateCollectionException>().having(
          (e) => e.existing.id,
          'existing.id',
          created.id,
        ),
      ),
    );

    // Explicit audited update increments revision and writes before/after amounts.
    final updated = await repo.updateCollection(
      collectionId: created.id,
      newAmountPiastres: 275025,
      notes: 'بعد إضافة فرق الفكة',
      reason: 'تصحيح جرد الخزينة',
    );
    expect(updated.revision, 2);
    expect(updated.wasModified, isTrue);
    expect(formatMoney(updated.amountPiastres), '2,750.25');

    final audits = await repo.queryAuditLogs(
      entityType: AuditEntityType.collection,
      entityId: created.id.toString(),
    );
    expect(audits.length, 2);
    final updateAudit = audits.first;
    expect(updateAudit.action, AuditAction.update);
    expect(updateAudit.oldAmountPiastres, 250000);
    expect(updateAudit.newAmountPiastres, 275025);
    expect(updateAudit.amountDeltaPiastres, 25025);
    expect(updateAudit.reason, 'تصحيح جرد الخزينة');
  });

  test('migrates legacy Phase 1 SharedPreferences data into SQLite once',
      () async {
    SharedPreferences.setMockInitialValues({
      'ragaa_outlets_v1': jsonEncode([
        {'id': 'legacy_1', 'name': 'منفذ قديم 1', 'shiftCount': 2},
        {'id': 'legacy_2', 'name': 'منفذ قديم 2', 'shiftCount': 3},
      ]),
      'ragaa_collections_v1': jsonEncode([
        {
          'outletId': 'legacy_1',
          'day': '2026-11-15',
          'shift': 1,
          'piastres': 50000,
        },
        {
          'outletId': 'legacy_2',
          'day': '2026-11-15',
          'shift': 3,
          'piastres': 99999,
        },
      ]),
    });

    final firstCount = await repo.migrateLegacySharedPreferencesIfNeeded();
    expect(firstCount, 4);

    // Second invocation must be a no-op.
    final secondCount = await repo.migrateLegacySharedPreferencesIfNeeded();
    expect(secondCount, 0);

    final outlets = await repo.listOutlets();
    expect(outlets.length, 2);
    final cols = await repo.queryCollections(
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    );
    expect(cols.length, 2);
    expect(
      cols.fold<int>(0, (s, c) => s + c.amountPiastres),
      149999,
    );
  });

  test(
      'creates verified backups, rejects corrupted files, and restores safely with safety snapshot',
      () async {
    final outlet =
        await repo.createOutlet(name: 'منفذ الزمالك', shiftCount: 2);
    await repo.createCollection(
      outletId: outlet.id,
      operationalDate: '2026-11-18',
      shiftNumber: 1,
      amountPiastres: 420000,
    );

    // Create verified snapshot v1.
    final backup = await backupService.createBackup();
    expect(await File(backup.filePath).exists(), isTrue);
    expect(backup.sha256.length, 64);
    expect(backup.outletsCount, 1);
    expect(backup.collectionsCount, 1);

    // Mutate live DB after backup.
    await repo.createOutlet(name: 'منفذ مؤقت', shiftCount: 3);
    await repo.createCollection(
      outletId: outlet.id,
      operationalDate: '2026-11-18',
      shiftNumber: 2,
      amountPiastres: 180000,
    );
    expect((await repo.listOutlets()).length, 2);

    // Reject a corrupt/non-SQLite file without harming live DB.
    final badFile = File(p.join(tempDir.path, 'corrupt.db'));
    await badFile.writeAsString('not a valid sqlite database');
    await expectLater(
      backupService.restoreFromFile(badFile.path),
      throwsA(isA<BackupIntegrityException>()),
    );
    expect((await repo.listOutlets()).length, 2);

    // Restore from valid snapshot v1.
    final outcome = await backupService.restoreFromFile(
      backup.filePath,
      reason: 'اختبار الاستعادة',
    );
    expect(await File(outcome.safetyBackupPath).exists(), isTrue);
    expect(outcome.restoredStats.outletsCount, 1);
    expect(outcome.restoredStats.collectionsCount, 1);
    expect(outcome.restoredStats.totalPiastres, 420000);

    // Verify restore action is logged in audit_logs and DB remains writable.
    final audits = await repo.queryAuditLogs(action: AuditAction.restore);
    expect(audits.length, 1);
    expect(audits.first.reason, 'اختبار الاستعادة');

    await repo.createCollection(
      outletId: outlet.id,
      operationalDate: '2026-11-19',
      shiftNumber: 1,
      amountPiastres: 110000,
    );
    expect((await backupService.getLiveDatabaseStats()).collectionsCount, 2);
  });
}
