import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ragaa/data/app_database.dart';
import 'package:ragaa/data/ragaa_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// SQL of the very first released schema (v1): a single `amount_piastres`
/// column and no printable outlet order.
const String _legacyV1Schema = '''
CREATE TABLE app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE outlets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL COLLATE NOCASE UNIQUE,
  shift_count INTEGER NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1,
  notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE outlet_shifts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  outlet_id TEXT NOT NULL,
  shift_number INTEGER NOT NULL,
  label TEXT NOT NULL,
  start_time TEXT NOT NULL,
  end_time TEXT NOT NULL,
  is_enabled INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (outlet_id, shift_number)
);
CREATE TABLE collections (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  outlet_id TEXT NOT NULL,
  operational_date TEXT NOT NULL,
  shift_number INTEGER NOT NULL,
  amount_piastres INTEGER NOT NULL,
  shift_label_snapshot TEXT NOT NULL DEFAULT '',
  shift_start_snapshot TEXT NOT NULL DEFAULT '',
  shift_end_snapshot TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  revision INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (outlet_id, operational_date, shift_number)
);
CREATE TABLE audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL,
  outlet_id TEXT,
  outlet_name TEXT,
  operational_date TEXT,
  shift_number INTEGER,
  old_amount_piastres INTEGER,
  new_amount_piastres INTEGER,
  summary TEXT NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  before_json TEXT,
  after_json TEXT,
  created_at TEXT NOT NULL
);
INSERT INTO app_meta (key, value) VALUES ('app_name', 'RAGAA');
INSERT INTO outlets VALUES
  ('out_a', 'نقل ١', 2, 1, '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('out_b', 'الدهسا', 3, 1, '', '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z'),
  ('out_c', 'رقابة', 2, 1, '', '2026-01-03T00:00:00Z', '2026-01-03T00:00:00Z');
INSERT INTO outlet_shifts (outlet_id, shift_number, label, start_time, end_time, is_enabled, updated_at) VALUES
  ('out_a', 1, 'الوردية الأولى', '08:00', '20:00', 1, '2026-01-01T00:00:00Z'),
  ('out_a', 2, 'الوردية الثانية', '20:00', '08:00', 1, '2026-01-01T00:00:00Z'),
  ('out_b', 1, 'الوردية الأولى', '08:00', '16:00', 1, '2026-01-01T00:00:00Z'),
  ('out_b', 3, 'الوردية الثالثة', '00:00', '08:00', 1, '2026-01-01T00:00:00Z');
INSERT INTO collections (outlet_id, operational_date, shift_number, amount_piastres, shift_label_snapshot, notes, revision, created_at, updated_at) VALUES
  ('out_a', '2026-11-15', 1, 125000, 'الوردية الأولى', 'سجل قديم', 1, '2026-11-15T10:00:00Z', '2026-11-15T10:00:00Z'),
  ('out_b', '2026-11-15', 3, 98050, 'الوردية الثالثة', '', 2, '2026-11-15T11:00:00Z', '2026-11-15T12:00:00Z');
INSERT INTO audit_logs (entity_type, entity_id, action, summary, reason, created_at) VALUES
  ('collection', '1', 'create', 'تسجيل تحصيل قديم', '', '2026-11-15T10:00:00Z');
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ragaa_migration_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('upgrades a legacy v1 database to the current schema without data loss',
      () async {
    final dbPath = p.join(tempDir.path, 'legacy_v1.db');

    final legacy = raw.sqlite3.open(dbPath);
    legacy.execute(_legacyV1Schema);
    legacy.execute('PRAGMA user_version = 1;');
    legacy.dispose();

    final appDb = AppDatabase.atPath(
      dbPath,
      factory: databaseFactoryFfiNoIsolate,
    );
    final db = await appDb.open();
    expect(kDatabaseSchemaVersion, 3);
    expect(await db.getVersion(), kDatabaseSchemaVersion);

    // Schema additions are present.
    final columns = await db.rawQuery('PRAGMA table_info(outlets)');
    expect(columns.any((column) => column['name'] == 'sort_order'), isTrue);
    final collectionColumns = await db.rawQuery('PRAGMA table_info(collections)');
    for (final name in <String>[
      'manual_fees_piastres',
      'automatic_fees_piastres',
      'total_fees_piastres',
      'general_total_piastres',
      'nfc_piastres',
      'visa_piastres',
    ]) {
      expect(
        collectionColumns.any((column) => column['name'] == name),
        isTrue,
        reason: 'missing migrated column $name',
      );
    }

    final repo = RagaaRepository(appDb);

    // Every legacy outlet survived, in its historical creation order.
    final outlets = await repo.listOutlets();
    expect(outlets.map((outlet) => outlet.name), ['نقل ١', 'الدهسا', 'رقابة']);
    expect(outlets.map((outlet) => outlet.sortOrder), [0, 1, 2]);

    // Legacy collections survived. The historical single amount becomes the
    // general total, all new components stay zero (no invented money).
    final records = await repo.queryCollections(
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    );
    expect(records.length, 2);
    final first = records.firstWhere((record) => record.outletId == 'out_a');
    expect(first.amountPiastres, 125000);
    expect(first.generalTotalPiastres, 125000);
    expect(first.manualFeesPiastres, 0);
    expect(first.totalFeesPiastres, 0);
    expect(first.nfcPiastres, 0);
    expect(first.visaPiastres, 0);
    expect(first.scalesTotalPiastres, 125000);
    expect(first.notes, 'سجل قديم');
    expect(first.revision, 1);

    final second = records.firstWhere((record) => record.outletId == 'out_b');
    expect(second.amountPiastres, 98050);
    expect(second.revision, 2);
    expect(second.wasModified, isTrue);

    // Audit history is preserved.
    final audits = await repo.queryAuditLogs();
    expect(audits.any((entry) => entry.summary == 'تسجيل تحصيل قديم'), isTrue);

    // The upgraded database accepts new journal entries immediately.
    final journal = await repo.buildDailyJournal('2026-11-15');
    expect(journal.hasData, isTrue);
    expect(journal.dayTotals.generalTotalPiastres, 125000 + 98050);
    expect(journal.outletDayTotals.length, 3);

    // And the app can keep writing on top of the migrated data.
    await repo.createCollection(
      outletId: 'out_a',
      operationalDate: '2026-11-16',
      shiftNumber: 2,
      amountPiastres: 50000,
    );
    expect((await repo.queryCollections(
      startDate: '2026-11-01',
      endDate: '2026-11-30',
    )).length, 3);

    await appDb.close();
  });

  test('upgrades a v2 database (daily-journal fields) and keeps outlet order',
      () async {
    // Build a v2 database using the current code, then re-open it.
    final dbPath = p.join(tempDir.path, 'legacy_v2.db');
    final first = AppDatabase.atPath(
      dbPath,
      factory: databaseFactoryFfiNoIsolate,
    );
    await first.open();
    final repo = RagaaRepository(first);
    await repo.createOutlet(name: 'منفذ أ', shiftCount: 2);
    await repo.createOutlet(name: 'منفذ ب', shiftCount: 3);
    await first.close();

    // Simulate an older installation: drop sort_order and reset the version.
    final legacy = raw.sqlite3.open(dbPath);
    legacy.execute('ALTER TABLE outlets DROP COLUMN sort_order;');
    legacy.execute('PRAGMA user_version = 2;');
    legacy.dispose();

    final reopened = AppDatabase.atPath(
      dbPath,
      factory: databaseFactoryFfiNoIsolate,
    );
    await reopened.open();
    final reopenedRepo = RagaaRepository(reopened);
    final outlets = await reopenedRepo.listOutlets();
    expect(outlets.map((outlet) => outlet.name), ['منفذ أ', 'منفذ ب']);
    expect(outlets.map((outlet) => outlet.sortOrder), [0, 1]);
    await reopened.close();
  });
}
