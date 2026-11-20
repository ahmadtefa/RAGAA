import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database_factory_init.dart';

/// Current SQLite schema version.
const int kDatabaseSchemaVersion = 2;

/// Required tables checked during backup verification.
const List<String> kRequiredDatabaseTables = [
  'app_meta',
  'outlets',
  'outlet_shifts',
  'collections',
  'audit_logs',
];

/// Manages the lifecycle, schema creation, migrations, and safe closure of
/// RAGAA's local SQLite database.
class AppDatabase {
  final String dbPath;
  final DatabaseFactory _factory;
  Database? _db;

  AppDatabase._({
    required this.dbPath,
    required DatabaseFactory factory,
  }) : _factory = factory;

  /// Creates an [AppDatabase] pointing at [dbPath] (opened lazily or via [open]).
  factory AppDatabase.atPath(String dbPath, {DatabaseFactory? factory}) {
    return AppDatabase._(
      dbPath: dbPath,
      factory: factory ?? resolveDatabaseFactory(),
    );
  }

  /// Resolves the production database location in the OS application support folder
  /// so upgrades or app directory moves never wipe accounting data.
  static Future<AppDatabase> openDefault() async {
    final factory = resolveDatabaseFactory();
    String baseDir;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final supportDir = await getApplicationSupportDirectory();
      baseDir = p.join(supportDir.path, 'data');
    } else {
      baseDir = await factory.getDatabasesPath();
    }
    await Directory(baseDir).create(recursive: true);
    final dbPath = p.join(baseDir, 'ragaa_accounting.db');
    final instance = AppDatabase._(dbPath: dbPath, factory: factory);
    await instance.open();
    return instance;
  }

  /// Resolves the default directory for local automated/manual backups.
  static Future<String> resolveDefaultBackupsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'RAGAA', 'backups'));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Resolves the default directory for exported PDF and Excel reports.
  static Future<String> resolveDefaultExportsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'RAGAA', 'exports'));
    await dir.create(recursive: true);
    return dir.path;
  }

  bool get isOpen => _db != null && _db!.isOpen;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    return open();
  }

  Future<Database> open() async {
    if (_db != null && _db!.isOpen) return _db!;
    if (dbPath != inMemoryDatabasePath) {
      final parent = Directory(p.dirname(dbPath));
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
    }
    final opened = await _factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: kDatabaseSchemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
          if (dbPath != inMemoryDatabasePath) {
            // WAL provides crash-resilience and concurrent read integrity on desktop & Android.
            await db.rawQuery('PRAGMA journal_mode = WAL;');
            await db.execute('PRAGMA synchronous = NORMAL;');
          }
        },
        onCreate: (db, version) async {
          await _createSchemaV1(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // Reserved for forward-only non-destructive schema migrations.
          if (oldVersion < 1) {
            await _createSchemaV1(db);
          }
          if (oldVersion < 2) {
            await _migrateToV2(db);
          }
        },
      ),
    );
    _db = opened;
    return opened;
  }

  static Future<void> _createSchemaV1(Database db) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE IF NOT EXISTS app_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS outlets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        shift_count INTEGER NOT NULL CHECK (shift_count IN (2, 3)),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS outlet_shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        outlet_id TEXT NOT NULL REFERENCES outlets(id) ON DELETE RESTRICT,
        shift_number INTEGER NOT NULL CHECK (shift_number IN (1, 2, 3)),
        label TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        is_enabled INTEGER NOT NULL CHECK (is_enabled IN (0, 1)),
        updated_at TEXT NOT NULL,
        UNIQUE (outlet_id, shift_number)
      );
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS collections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        outlet_id TEXT NOT NULL REFERENCES outlets(id) ON DELETE RESTRICT,
        operational_date TEXT NOT NULL,
        shift_number INTEGER NOT NULL CHECK (shift_number IN (1, 2, 3)),
        amount_piastres INTEGER NOT NULL CHECK (amount_piastres >= 0),
        manual_fees_piastres INTEGER NOT NULL DEFAULT 0 CHECK (manual_fees_piastres >= 0),
        automatic_fees_piastres INTEGER NOT NULL DEFAULT 0 CHECK (automatic_fees_piastres >= 0),
        total_fees_piastres INTEGER NOT NULL DEFAULT 0 CHECK (total_fees_piastres >= 0),
        general_total_piastres INTEGER NOT NULL DEFAULT 0 CHECK (general_total_piastres >= 0),
        nfc_piastres INTEGER NOT NULL DEFAULT 0 CHECK (nfc_piastres >= 0),
        visa_piastres INTEGER NOT NULL DEFAULT 0 CHECK (visa_piastres >= 0),
        shift_label_snapshot TEXT NOT NULL DEFAULT '',
        shift_start_snapshot TEXT NOT NULL DEFAULT '',
        shift_end_snapshot TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (outlet_id, operational_date, shift_number)
      );
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
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
    ''');

    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_collections_date
      ON collections (operational_date);
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_collections_outlet_date
      ON collections (outlet_id, operational_date);
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_collections_shift
      ON collections (shift_number);
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_outlet_shifts_outlet
      ON outlet_shifts (outlet_id, shift_number);
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_audit_logs_created
      ON audit_logs (created_at DESC, id DESC);
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_audit_logs_outlet
      ON audit_logs (outlet_id);
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_audit_logs_entity
      ON audit_logs (entity_type, entity_id);
    ''');

    batch.insert(
      'app_meta',
      {
        'key': 'schema_created_at',
        'value': DateTime.now().toUtc().toIso8601String()
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    batch.insert(
      'app_meta',
      {'key': 'app_name', 'value': 'RAGAA'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await batch.commit(noResult: true);
  }

  /// Adds daily-journal fields without rewriting or discarding existing rows.
  /// A legacy single amount is the historical general total; all unavailable
  /// component values remain zero.
  static Future<void> _migrateToV2(Database db) async {
    await db.transaction((txn) async {
      await txn.execute(
          'ALTER TABLE collections ADD COLUMN manual_fees_piastres INTEGER NOT NULL DEFAULT 0');
      await txn.execute(
          'ALTER TABLE collections ADD COLUMN automatic_fees_piastres INTEGER NOT NULL DEFAULT 0');
      await txn.execute(
          'ALTER TABLE collections ADD COLUMN total_fees_piastres INTEGER NOT NULL DEFAULT 0');
      await txn.execute(
          'ALTER TABLE collections ADD COLUMN general_total_piastres INTEGER NOT NULL DEFAULT 0');
      await txn.execute(
          'ALTER TABLE collections ADD COLUMN nfc_piastres INTEGER NOT NULL DEFAULT 0');
      await txn.execute(
          'ALTER TABLE collections ADD COLUMN visa_piastres INTEGER NOT NULL DEFAULT 0');
      await txn.execute(
          'UPDATE collections SET general_total_piastres = amount_piastres');
    });
  }

  /// Flushes WAL frames cleanly into the main database file.
  Future<void> checkpoint() async {
    if (_db != null && _db!.isOpen && dbPath != inMemoryDatabasePath) {
      await _db!.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');
    }
  }

  /// Safely checkpoints and closes the underlying SQLite connection.
  Future<void> close() async {
    final current = _db;
    _db = null;
    if (current != null && current.isOpen) {
      if (dbPath != inMemoryDatabasePath) {
        try {
          await current.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');
        } catch (_) {
          // Best-effort checkpoint prior to close.
        }
      }
      await current.close();
    }
  }
}
