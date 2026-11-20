import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../core/date_ranges.dart';
import '../core/exceptions.dart';
import '../core/formatters.dart';
import '../models/audit_log_entry.dart';
import '../models/collection_record.dart';
import '../models/collection_amounts.dart';
import '../models/daily_journal.dart';
import '../models/outlet.dart';
import '../models/outlet_shift.dart';
import '../models/report_models.dart';
import 'app_database.dart';

/// Central accounting repository backed by SQLite.
///
/// Guarantees transactional writes, integer-piastre precision, strict prevention
/// of duplicate `(outlet, operational_date, shift_number)` records, lossless
/// outlet shift reconfiguration, and an immutable audit trail.
class RagaaRepository {
  final AppDatabase appDatabase;
  final DateTime Function() _clock;
  int _idSequence = 0;

  static const String _legacyOutletsKey = 'ragaa_outlets_v1';
  static const String _legacyCollectionsKey = 'ragaa_collections_v1';
  static const String _legacyMigratedMetaKey = 'legacy_prefs_migrated_v1';

  RagaaRepository(
    this.appDatabase, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  String _nowIso() => _clock().toUtc().toIso8601String();

  String _generateOutletId() {
    _idSequence++;
    return 'out_${_clock().microsecondsSinceEpoch}_$_idSequence';
  }

  // ---------------------------------------------------------------------------
  // One-time Phase 1 SharedPreferences -> SQLite Migration
  // ---------------------------------------------------------------------------

  /// Migrates any outlets and collections previously stored in Phase 1
  /// `SharedPreferences` into SQLite without deleting the legacy keys.
  /// Returns the number of migrated records (outlets + collections).
  Future<int> migrateLegacySharedPreferencesIfNeeded() async {
    final db = await appDatabase.database;
    final meta = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: [_legacyMigratedMetaKey],
      limit: 1,
    );
    if (meta.isNotEmpty) return 0;

    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return 0;
    }

    final rawOutlets = prefs.getString(_legacyOutletsKey);
    final rawCollections = prefs.getString(_legacyCollectionsKey);

    var migratedOutlets = 0;
    var migratedCollections = 0;
    final now = _nowIso();

    await db.transaction((txn) async {
      if (rawOutlets != null && rawOutlets.trim().isNotEmpty) {
        final decoded = jsonDecode(rawOutlets);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final map = Map<String, dynamic>.from(item);
            final id = (map['id']?.toString() ?? '').trim();
            final name = (map['name']?.toString() ?? '').trim();
            final rawShifts = map['shiftCount'];
            final shiftCount = (rawShifts == 3) ? 3 : 2;
            if (id.isEmpty || name.isEmpty) continue;

            final existing = await txn.query(
              'outlets',
              where: 'id = ? OR LOWER(name) = LOWER(?)',
              whereArgs: [id, name],
              limit: 1,
            );
            if (existing.isNotEmpty) continue;

            await txn.insert('outlets', {
              'id': id,
              'name': name,
              'shift_count': shiftCount,
              'is_active': 1,
              'notes': '',
              'created_at': now,
              'updated_at': now,
            });

            for (var s = 1; s <= 3; s++) {
              final defaults = defaultShiftTimes(s, shiftCount);
              await txn.insert('outlet_shifts', {
                'outlet_id': id,
                'shift_number': s,
                'label': defaultShiftLabel(s),
                'start_time': defaults.start,
                'end_time': defaults.end,
                'is_enabled': s <= shiftCount ? 1 : 0,
                'updated_at': now,
              });
            }
            migratedOutlets++;
          }
        }
      }

      if (rawCollections != null && rawCollections.trim().isNotEmpty) {
        final decoded = jsonDecode(rawCollections);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final map = Map<String, dynamic>.from(item);
            final outletId = (map['outletId']?.toString() ?? '').trim();
            final day = (map['day']?.toString() ?? '').trim();
            final shift = map['shift'];
            final piastres = map['piastres'];
            if (outletId.isEmpty ||
                !isValidOperationalDate(day) ||
                shift is! int ||
                shift < 1 ||
                shift > 3 ||
                piastres is! int ||
                piastres < 0) {
              continue;
            }

            final outletRows = await txn.query(
              'outlets',
              where: 'id = ?',
              whereArgs: [outletId],
              limit: 1,
            );
            if (outletRows.isEmpty) continue;

            final shiftRows = await txn.query(
              'outlet_shifts',
              where: 'outlet_id = ? AND shift_number = ?',
              whereArgs: [outletId, shift],
              limit: 1,
            );
            final shiftLabel = shiftRows.isNotEmpty
                ? shiftRows.first['label'] as String
                : defaultShiftLabel(shift);
            final shiftStart = shiftRows.isNotEmpty
                ? shiftRows.first['start_time'] as String
                : '';
            final shiftEnd = shiftRows.isNotEmpty
                ? shiftRows.first['end_time'] as String
                : '';

            final inserted = await txn.insert(
              'collections',
              {
                'outlet_id': outletId,
                'operational_date': day,
                'shift_number': shift,
                'amount_piastres': piastres,
                'shift_label_snapshot': shiftLabel,
                'shift_start_snapshot': shiftStart,
                'shift_end_snapshot': shiftEnd,
                'notes': 'مرحّل من بيانات المرحلة الأولى',
                'revision': 1,
                'created_at': now,
                'updated_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            if (inserted > 0) {
              migratedCollections++;
            }
          }
        }
      }

      if (migratedOutlets > 0 || migratedCollections > 0) {
        await _insertAudit(
          txn,
          entityType: AuditEntityType.system,
          entityId: 'legacy_migration_v1',
          action: AuditAction.migrate,
          summary:
              'ترحيل بيانات المرحلة الأولى إلى SQLite ($migratedOutlets منفذ، $migratedCollections سجل تحصيل)',
          afterMap: {
            'migrated_outlets': migratedOutlets,
            'migrated_collections': migratedCollections,
          },
          createdAt: now,
        );
      }

      await txn.insert(
        'app_meta',
        {'key': _legacyMigratedMetaKey, 'value': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    return migratedOutlets + migratedCollections;
  }

  // ---------------------------------------------------------------------------
  // Outlets & Per-Outlet Shift Configuration
  // ---------------------------------------------------------------------------

  /// Lists all outlets in the user-defined printable order (`sort_order`), with
  /// the historical creation order as a stable tie-breaker, including all saved
  /// shift schedules.
  Future<List<Outlet>> listOutlets({bool includeInactive = true}) async {
    final db = await appDatabase.database;
    final outletRows = await db.query(
      'outlets',
      where: includeInactive ? null : 'is_active = 1',
      orderBy: 'sort_order ASC, created_at ASC, id ASC',
    );
    if (outletRows.isEmpty) return const [];

    final shiftRows = await db.query(
      'outlet_shifts',
      orderBy: 'outlet_id ASC, shift_number ASC',
    );
    final shiftsByOutlet = <String, List<OutletShift>>{};
    for (final row in shiftRows) {
      final shift = OutletShift.fromRow(row);
      shiftsByOutlet.putIfAbsent(shift.outletId, () => []).add(shift);
    }

    return outletRows
        .map(
          (row) => Outlet.fromRow(
            row,
            shifts: shiftsByOutlet[row['id'] as String] ?? const [],
          ),
        )
        .toList();
  }

  /// Fetches a single outlet by [outletId], or returns `null`.
  Future<Outlet?> getOutletById(String outletId) async {
    final db = await appDatabase.database;
    return _loadOutlet(db, outletId);
  }

  Future<Outlet?> _loadOutlet(DatabaseExecutor exec, String outletId) async {
    final rows = await exec.query(
      'outlets',
      where: 'id = ?',
      whereArgs: [outletId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final shiftRows = await exec.query(
      'outlet_shifts',
      where: 'outlet_id = ?',
      whereArgs: [outletId],
      orderBy: 'shift_number ASC',
    );
    return Outlet.fromRow(
      rows.first,
      shifts: shiftRows.map(OutletShift.fromRow).toList(),
    );
  }

  /// Creates a new outlet with 2 or 3 shifts and independent shift schedules.
  Future<Outlet> createOutlet({
    required String name,
    required int shiftCount,
    List<ShiftScheduleInput>? schedules,
    String notes = '',
  }) async {
    final cleanName = name.trim();
    final cleanNotes = notes.trim();
    if (cleanName.isEmpty) {
      throw const ValidationException('يرجى إدخال اسم المنفذ');
    }
    if (cleanName.length > 100) {
      throw const ValidationException(
          'اسم المنفذ طويل جدًا (الحد الأقصى 100 حرف)');
    }
    if (shiftCount != 2 && shiftCount != 3) {
      throw const ValidationException('عدد الورديات يجب أن يكون 2 أو 3');
    }

    final normalizedSchedules = _normalizeSchedules(
      shiftCount: shiftCount,
      provided: schedules,
      existingOutlet: null,
    );

    final db = await appDatabase.database;
    final id = _generateOutletId();
    final now = _nowIso();

    return db.transaction((txn) async {
      await _assertUniqueOutletName(txn, cleanName);
      final nextOrder = await _nextOutletSortOrder(txn);

      await txn.insert('outlets', {
        'id': id,
        'name': cleanName,
        'shift_count': shiftCount,
        'is_active': 1,
        'notes': cleanNotes,
        'sort_order': nextOrder,
        'created_at': now,
        'updated_at': now,
      });

      for (final s in normalizedSchedules) {
        await txn.insert('outlet_shifts', {
          'outlet_id': id,
          'shift_number': s.shiftNumber,
          'label': s.label,
          'start_time': s.startTime,
          'end_time': s.endTime,
          'is_enabled': s.shiftNumber <= shiftCount ? 1 : 0,
          'updated_at': now,
        });
      }

      final created = (await _loadOutlet(txn, id))!;
      await _insertAudit(
        txn,
        entityType: AuditEntityType.outlet,
        entityId: id,
        action: AuditAction.create,
        outletId: id,
        outletName: created.name,
        summary: 'إضافة منفذ "${created.name}" (${created.shiftCountArabic})',
        afterMap: created.toAuditMap(),
        createdAt: now,
      );
      return created;
    });
  }

  /// Updates an outlet's name, shift count (2 or 3), shift times/labels, notes,
  /// or active state WITHOUT losing any historical collection data or previously
  /// saved shift schedules.
  Future<Outlet> updateOutlet({
    required String outletId,
    required String name,
    required int shiftCount,
    List<ShiftScheduleInput>? schedules,
    bool? isActive,
    String? notes,
    String reason = '',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const ValidationException('يرجى إدخال اسم المنفذ');
    }
    if (cleanName.length > 100) {
      throw const ValidationException(
          'اسم المنفذ طويل جدًا (الحد الأقصى 100 حرف)');
    }
    if (shiftCount != 2 && shiftCount != 3) {
      throw const ValidationException('عدد الورديات يجب أن يكون 2 أو 3');
    }

    final db = await appDatabase.database;
    final now = _nowIso();

    return db.transaction((txn) async {
      final before = await _loadOutlet(txn, outletId);
      if (before == null) {
        throw const ValidationException('المنفذ المطلوب تعديله غير موجود');
      }

      await _assertUniqueOutletName(txn, cleanName, excludeOutletId: outletId);

      final normalizedSchedules = _normalizeSchedules(
        shiftCount: shiftCount,
        provided: schedules,
        existingOutlet: before,
      );
      final nextActive = isActive ?? before.isActive;
      final nextNotes = notes != null ? notes.trim() : before.notes;

      await txn.update(
        'outlets',
        {
          'name': cleanName,
          'shift_count': shiftCount,
          'is_active': nextActive ? 1 : 0,
          'notes': nextNotes,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [outletId],
      );

      for (final s in normalizedSchedules) {
        final enabled = s.shiftNumber <= shiftCount ? 1 : 0;
        final updatedCount = await txn.update(
          'outlet_shifts',
          {
            'label': s.label,
            'start_time': s.startTime,
            'end_time': s.endTime,
            'is_enabled': enabled,
            'updated_at': now,
          },
          where: 'outlet_id = ? AND shift_number = ?',
          whereArgs: [outletId, s.shiftNumber],
        );
        if (updatedCount == 0) {
          await txn.insert('outlet_shifts', {
            'outlet_id': outletId,
            'shift_number': s.shiftNumber,
            'label': s.label,
            'start_time': s.startTime,
            'end_time': s.endTime,
            'is_enabled': enabled,
            'updated_at': now,
          });
        }
      }

      final after = (await _loadOutlet(txn, outletId))!;
      final changes = _describeOutletChanges(before, after);
      if (changes.isNotEmpty || reason.trim().isNotEmpty) {
        final detailsText =
            changes.isEmpty ? 'تحديث بيانات المنفذ' : changes.join(' | ');
        await _insertAudit(
          txn,
          entityType: AuditEntityType.outlet,
          entityId: outletId,
          action: AuditAction.update,
          outletId: outletId,
          outletName: after.name,
          summary: 'تعديل منفذ "${after.name}": $detailsText',
          reason: reason.trim(),
          beforeMap: before.toAuditMap(),
          afterMap: after.toAuditMap(),
          createdAt: now,
        );
      }

      return after;
    });
  }

  /// Counts existing historical collection records for a specific outlet shift.
  /// Used to reassure users that reducing shifts (3 -> 2) retains all history.
  Future<int> countCollectionsForOutletShift(
    String outletId,
    int shiftNumber,
  ) async {
    final db = await appDatabase.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM collections WHERE outlet_id = ? AND shift_number = ?',
      [outletId, shiftNumber],
    );
    return (rows.first['cnt'] as int?) ?? 0;
  }

  Future<int> _nextOutletSortOrder(DatabaseExecutor exec) async {
    final rows = await exec.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM outlets',
    );
    final maxOrder = (rows.isEmpty ? -1 : (rows.first['max_order'] as int?) ?? -1);
    return maxOrder + 1;
  }

  /// Persists a new printable outlet order (first entry prints first).
  ///
  /// Historical collections, shifts and audit entries are never touched; only
  /// the presentation order changes. The new order is written to `audit_logs`.
  Future<List<Outlet>> reorderOutlets(
    List<String> orderedOutletIds, {
    String reason = '',
  }) async {
    final db = await appDatabase.database;
    final now = _nowIso();
    await db.transaction((txn) async {
      final rows = await txn.query('outlets', columns: ['id', 'name']);
      final existingIds = rows.map((row) => row['id'] as String).toSet();
      final requested = <String>[
        for (final id in orderedOutletIds)
          if (existingIds.contains(id)) id,
      ];
      final requestedSet = requested.toSet();
      for (final row in rows) {
        final id = row['id'] as String;
        if (!requestedSet.contains(id)) requested.add(id);
      }
      for (var index = 0; index < requested.length; index++) {
        await txn.update(
          'outlets',
          {'sort_order': index},
          where: 'id = ?',
          whereArgs: [requested[index]],
        );
      }
      await _insertAudit(
        txn,
        entityType: AuditEntityType.outlet,
        entityId: 'outlet_order',
        action: AuditAction.update,
        summary: 'إعادة ترتيب المنافذ (${requested.length} منفذ) للطباعة والتقارير',
        reason: reason.trim(),
        afterMap: {'order': requested},
        createdAt: now,
      );
    });
    return listOutlets(includeInactive: true);
  }

  /// Moves a single outlet one position up (-1) or down (+1) in the printed
  /// order and returns the refreshed outlet list.
  Future<List<Outlet>> moveOutlet(String outletId, int delta) async {
    final current = await listOutlets(includeInactive: true);
    final index = current.indexWhere((outlet) => outlet.id == outletId);
    if (index < 0 || delta == 0) return current;
    final target = index + delta;
    if (target < 0 || target >= current.length) return current;
    final ids = current.map((outlet) => outlet.id).toList();
    final moved = ids.removeAt(index);
    ids.insert(target, moved);
    return reorderOutlets(ids, reason: 'تحريك منفذ في ترتيب الطباعة');
  }

  Future<void> _assertUniqueOutletName(
    DatabaseExecutor exec,
    String candidateName, {
    String? excludeOutletId,
  }) async {
    final rows = await exec.query(
      'outlets',
      columns: ['id', 'name'],
    );
    final target = candidateName.toLowerCase();
    for (final row in rows) {
      final id = row['id'] as String;
      if (excludeOutletId != null && id == excludeOutletId) continue;
      final existingName = (row['name'] as String).trim().toLowerCase();
      if (existingName == target) {
        throw ValidationException(
            'يوجد منفذ آخر مسجل بنفس الاسم "$candidateName"');
      }
    }
  }

  List<ShiftScheduleInput> _normalizeSchedules({
    required int shiftCount,
    required List<ShiftScheduleInput>? provided,
    required Outlet? existingOutlet,
  }) {
    final byNumber = <int, ShiftScheduleInput>{};
    if (provided != null) {
      for (final item in provided) {
        if (item.shiftNumber < 1 || item.shiftNumber > 3) {
          throw const ValidationException('رقم الوردية يجب أن يكون بين 1 و 3');
        }
        if (!isValidTime24(item.startTime) || !isValidTime24(item.endTime)) {
          throw ValidationException(
            'موعد ${defaultShiftLabel(item.shiftNumber)} غير صالح (استخدم صيغة HH:mm)',
          );
        }
        final cleanLabel = item.label.trim().isEmpty
            ? defaultShiftLabel(item.shiftNumber)
            : item.label.trim();
        byNumber[item.shiftNumber] = ShiftScheduleInput(
          shiftNumber: item.shiftNumber,
          label: cleanLabel,
          startTime: item.startTime,
          endTime: item.endTime,
        );
      }
    }

    final result = <ShiftScheduleInput>[];
    for (var s = 1; s <= 3; s++) {
      if (byNumber.containsKey(s)) {
        result.add(byNumber[s]!);
      } else {
        final prev = existingOutlet?.shiftByNumber(s);
        if (prev != null) {
          // Preserve existing saved schedule seamlessly!
          result.add(
            ShiftScheduleInput(
              shiftNumber: s,
              label: prev.label,
              startTime: prev.startTime,
              endTime: prev.endTime,
            ),
          );
        } else {
          result.add(ShiftScheduleInput.defaultFor(s, shiftCount));
        }
      }
    }
    return result;
  }

  List<String> _describeOutletChanges(Outlet before, Outlet after) {
    final changes = <String>[];
    if (before.name != after.name) {
      changes.add('الاسم من "${before.name}" إلى "${after.name}"');
    }
    if (before.shiftCount != after.shiftCount) {
      changes.add(
        'عدد الورديات من ${before.shiftCountArabic} إلى ${after.shiftCountArabic}',
      );
    }
    if (before.isActive != after.isActive) {
      changes.add(after.isActive ? 'تفعيل المنفذ' : 'إيقاف المنفذ مؤقتًا');
    }
    if (before.notes != after.notes) {
      changes.add('تحديث الملاحظات');
    }
    for (var s = 1; s <= after.shiftCount; s++) {
      final b = before.shiftByNumber(s);
      final a = after.shiftByNumber(s);
      if (b != null && a != null) {
        if (b.startTime != a.startTime || b.endTime != a.endTime) {
          changes.add(
            'موعد ${a.label} (${b.timeRange} -> ${a.timeRange})',
          );
        } else if (b.label != a.label) {
          changes.add('مسمى الوردية $s ("${b.label}" -> "${a.label}")');
        }
      }
    }
    return changes;
  }

  // ---------------------------------------------------------------------------
  // Collections Recording, Duplicate Guard & Audited Updates
  // ---------------------------------------------------------------------------

  static const String _collectionSelectSql = '''
    SELECT
      c.id,
      c.outlet_id,
      o.name AS outlet_name,
      c.operational_date,
      c.shift_number,
      c.amount_piastres,
      c.manual_fees_piastres,
      c.automatic_fees_piastres,
      c.total_fees_piastres,
      c.general_total_piastres,
      c.nfc_piastres,
      c.visa_piastres,
      c.shift_label_snapshot,
      c.shift_start_snapshot,
      c.shift_end_snapshot,
      c.notes,
      c.revision,
      c.created_at,
      c.updated_at
    FROM collections c
    INNER JOIN outlets o ON o.id = c.outlet_id
  ''';

  /// Finds an existing collection record for `(outletId, operationalDate, shiftNumber)`.
  Future<CollectionRecord?> findCollection({
    required String outletId,
    required String operationalDate,
    required int shiftNumber,
  }) async {
    final db = await appDatabase.database;
    return _findCollectionExec(db, outletId, operationalDate, shiftNumber);
  }

  Future<CollectionRecord?> _findCollectionExec(
    DatabaseExecutor exec,
    String outletId,
    String operationalDate,
    int shiftNumber,
  ) async {
    final rows = await exec.rawQuery(
      '$_collectionSelectSql WHERE c.outlet_id = ? AND c.operational_date = ? AND c.shift_number = ? LIMIT 1',
      [outletId, operationalDate, shiftNumber],
    );
    if (rows.isEmpty) return null;
    return CollectionRecord.fromRow(rows.first);
  }

  Future<CollectionRecord?> _getCollectionByIdExec(
    DatabaseExecutor exec,
    int id,
  ) async {
    final rows = await exec.rawQuery(
      '$_collectionSelectSql WHERE c.id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return CollectionRecord.fromRow(rows.first);
  }

  /// Records a new collection entry.
  ///
  /// Throws [DuplicateCollectionException] if a record already exists for the
  /// same `(outletId, operationalDate, shiftNumber)` — duplicates are strictly
  /// forbidden and edits must go through [updateCollection] to record an audit entry.
  Future<CollectionRecord> createCollection({
    required String outletId,
    required String operationalDate,
    required int shiftNumber,
    int? amountPiastres,
    CollectionAmounts? amounts,
    String notes = '',
  }) async {
    if (!isValidOperationalDate(operationalDate)) {
      throw const ValidationException('التاريخ التشغيلي غير صالح');
    }
    final normalizedAmounts = amounts ??
        CollectionAmounts(
          manualFeesPiastres: 0,
          automaticFeesPiastres: 0,
          totalFeesPiastres: 0,
          generalTotalPiastres: amountPiastres ?? -1,
        );
    if (!normalizedAmounts.isValid) {
      throw const ValidationException('مبلغ التحصيل غير صالح');
    }

    final db = await appDatabase.database;
    final now = _nowIso();
    final cleanNotes = notes.trim();

    return db.transaction((txn) async {
      final outlet = await _loadOutlet(txn, outletId);
      if (outlet == null) {
        throw const ValidationException('المنفذ المحدد غير موجود');
      }
      if (!outlet.isActive) {
        throw ValidationException(
          'المنفذ "${outlet.name}" متوقف حاليًا؛ قم بتفعيله أولًا لتسجيل تحصيل جديد',
        );
      }
      if (shiftNumber < 1 || shiftNumber > outlet.shiftCount) {
        throw ValidationException(
          'رقم الوردية غير متاح لهذا المنفذ (الحد الأقصى ${outlet.shiftCountArabic})',
        );
      }

      final duplicate = await _findCollectionExec(
        txn,
        outletId,
        operationalDate,
        shiftNumber,
      );
      if (duplicate != null) {
        throw DuplicateCollectionException(duplicate);
      }

      final shiftDef = outlet.shiftByNumber(shiftNumber);
      final labelSnapshot = shiftDef?.label ?? defaultShiftLabel(shiftNumber);
      final startSnapshot = shiftDef?.startTime ?? '';
      final endSnapshot = shiftDef?.endTime ?? '';

      final insertedId = await txn.insert('collections', {
        'outlet_id': outletId,
        'operational_date': operationalDate,
        'shift_number': shiftNumber,
        'amount_piastres': normalizedAmounts.generalTotalPiastres,
        ...normalizedAmounts.toDatabaseMap(),
        'shift_label_snapshot': labelSnapshot,
        'shift_start_snapshot': startSnapshot,
        'shift_end_snapshot': endSnapshot,
        'notes': cleanNotes,
        'revision': 1,
        'created_at': now,
        'updated_at': now,
      });

      final created = (await _getCollectionByIdExec(txn, insertedId))!;
      await _insertAudit(
        txn,
        entityType: AuditEntityType.collection,
        entityId: created.id.toString(),
        action: AuditAction.create,
        outletId: created.outletId,
        outletName: created.outletName,
        operationalDate: created.operationalDate,
        shiftNumber: created.shiftNumber,
        newAmountPiastres: created.generalTotalPiastres,
        summary:
            'تسجيل تحصيل "${created.outletName}" — ${created.shiftTitle} (${created.operationalDate}) بمبلغ ${formatMoney(created.amountPiastres, withCurrency: true)}',
        afterMap: created.toAuditMap(),
        createdAt: now,
      );

      return created;
    });
  }

  /// Updates an existing collection entry (including historical Shift 3 records
  /// even if the outlet was later changed to 2 shifts) and writes a complete
  /// immutable entry to `audit_logs`.
  Future<CollectionRecord> updateCollection({
    required int collectionId,
    int? newAmountPiastres,
    CollectionAmounts? newAmounts,
    String? notes,
    String reason = '',
  }) async {
    if (newAmounts == null &&
        (newAmountPiastres == null ||
            newAmountPiastres < 0 ||
            newAmountPiastres > kMaxAmountPiastres)) {
      throw const ValidationException('مبلغ التحصيل الجديد غير صالح');
    }

    final db = await appDatabase.database;
    final now = _nowIso();
    final cleanReason = reason.trim();

    return db.transaction((txn) async {
      final before = await _getCollectionByIdExec(txn, collectionId);
      if (before == null) {
        throw const ValidationException('سجل التحصيل المطلوب تعديله غير موجود');
      }

      final normalizedAmounts = newAmounts ??
          CollectionAmounts(
            manualFeesPiastres: before.manualFeesPiastres,
            automaticFeesPiastres: before.automaticFeesPiastres,
            totalFeesPiastres: before.totalFeesPiastres,
            generalTotalPiastres:
                newAmountPiastres ?? before.generalTotalPiastres,
            nfcPiastres: before.nfcPiastres,
            visaPiastres: before.visaPiastres,
          );
      if (!normalizedAmounts.isValid) {
        throw const ValidationException('Invalid updated collection amount');
      }
      final nextNotes = notes != null ? notes.trim() : before.notes;
      final amountChanged = before.amounts.toDatabaseMap().toString() !=
          normalizedAmounts.toDatabaseMap().toString();
      final notesChanged = before.notes != nextNotes;

      if (!amountChanged && !notesChanged) {
        return before;
      }

      await txn.update(
        'collections',
        {
          'amount_piastres': normalizedAmounts.generalTotalPiastres,
          ...normalizedAmounts.toDatabaseMap(),
          'notes': nextNotes,
          'revision': before.revision + 1,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [collectionId],
      );

      final after = (await _getCollectionByIdExec(txn, collectionId))!;
      final summary = amountChanged
          ? 'تعديل تحصيل "${after.outletName}" — ${after.shiftTitle} (${after.operationalDate}) من ${formatMoney(before.amountPiastres, withCurrency: true)} إلى ${formatMoney(after.amountPiastres, withCurrency: true)}'
          : 'تعديل ملاحظات تحصيل "${after.outletName}" — ${after.shiftTitle} (${after.operationalDate})';

      await _insertAudit(
        txn,
        entityType: AuditEntityType.collection,
        entityId: after.id.toString(),
        action: AuditAction.update,
        outletId: after.outletId,
        outletName: after.outletName,
        operationalDate: after.operationalDate,
        shiftNumber: after.shiftNumber,
        oldAmountPiastres: before.amountPiastres,
        newAmountPiastres: after.amountPiastres,
        summary: summary,
        reason: cleanReason,
        beforeMap: before.toAuditMap(),
        afterMap: after.toAuditMap(),
        createdAt: now,
      );

      return after;
    });
  }

  /// Queries collection records across an inclusive operational date range with
  /// optional outlet and shift filters.
  Future<List<CollectionRecord>> queryCollections({
    required String startDate,
    required String endDate,
    Set<String> outletIds = const {},
    int? shiftNumber,
  }) async {
    if (!isValidOperationalDate(startDate) ||
        !isValidOperationalDate(endDate)) {
      throw const ValidationException('نطاق التاريخ غير صالح');
    }
    if (startDate.compareTo(endDate) > 0) {
      return const [];
    }

    final db = await appDatabase.database;
    final whereParts = <String>[
      'c.operational_date >= ?',
      'c.operational_date <= ?',
    ];
    final args = <Object?>[startDate, endDate];

    if (outletIds.isNotEmpty) {
      final sortedIds = outletIds.toList()..sort();
      final placeholders = List.filled(sortedIds.length, '?').join(', ');
      whereParts.add('c.outlet_id IN ($placeholders)');
      args.addAll(sortedIds);
    }

    if (shiftNumber != null) {
      whereParts.add('c.shift_number = ?');
      args.add(shiftNumber);
    }

    final sql = '''
      $_collectionSelectSql
      WHERE ${whereParts.join(' AND ')}
      ORDER BY c.operational_date DESC, o.name ASC, c.shift_number ASC
    ''';

    final rows = await db.rawQuery(sql, args);
    return rows.map(CollectionRecord.fromRow).toList();
  }

  // ---------------------------------------------------------------------------
  // Reports & Dashboard Aggregations
  // ---------------------------------------------------------------------------

  /// Computes a comprehensive [ReportData] object for the specified [filter].
  ///
  /// Includes all configured outlets (when matching the outlet filter) and all
  /// historical records — including historical Shift 3 records for outlets that
  /// may later have been switched to 2 shifts.
  Future<ReportData> buildReport(ReportFilter filter) async {
    final outlets = await listOutlets(includeInactive: true);
    final details = await queryCollections(
      startDate: filter.range.startKey,
      endDate: filter.range.endKey,
      outletIds: filter.outletIds,
      shiftNumber: filter.shiftNumber,
    );

    final outletNamesById = {for (final o in outlets) o.id: o.name};

    // Aggregate per outlet (include matching active outlets even with 0 collection,
    // and include inactive outlets whenever they have collections in the period).
    final outletAccum = <String, _OutletAccum>{};
    for (final o in outlets) {
      if (filter.outletIds.isNotEmpty && !filter.outletIds.contains(o.id)) {
        continue;
      }
      if (o.isActive || filter.outletIds.contains(o.id)) {
        outletAccum[o.id] = _OutletAccum(
          outletId: o.id,
          outletName: o.name,
          configuredShiftCount: o.shiftCount,
          isActive: o.isActive,
        );
      }
    }

    final shiftTotals = <int, int>{1: 0, 2: 0, 3: 0};
    final shiftCounts = <int, int>{1: 0, 2: 0, 3: 0};
    final dayAccum = <String, _DayAccum>{};
    var grandTotal = 0;
    var modifiedCount = 0;

    for (final rec in details) {
      grandTotal += rec.amountPiastres;
      if (rec.wasModified) modifiedCount++;

      final oAcc = outletAccum.putIfAbsent(
        rec.outletId,
        () {
          final found = outlets.where((o) => o.id == rec.outletId).firstOrNull;
          return _OutletAccum(
            outletId: rec.outletId,
            outletName: found?.name ?? rec.outletName,
            configuredShiftCount: found?.shiftCount ?? 2,
            isActive: found?.isActive ?? false,
          );
        },
      );
      oAcc.add(rec.shiftNumber, rec.amountPiastres);

      shiftTotals[rec.shiftNumber] =
          (shiftTotals[rec.shiftNumber] ?? 0) + rec.amountPiastres;
      shiftCounts[rec.shiftNumber] = (shiftCounts[rec.shiftNumber] ?? 0) + 1;

      final dAcc = dayAccum.putIfAbsent(
        rec.operationalDate,
        () => _DayAccum(rec.operationalDate),
      );
      dAcc.add(rec.shiftNumber, rec.amountPiastres);
    }

    final byOutlet = outletAccum.values.map((a) => a.toRow()).toList()
      ..sort((a, b) {
        final cmp = b.totalPiastres.compareTo(a.totalPiastres);
        if (cmp != 0) return cmp;
        return a.outletName.compareTo(b.outletName);
      });

    final shiftsToInclude =
        filter.shiftNumber != null ? [filter.shiftNumber!] : const [1, 2, 3];
    final byShift = shiftsToInclude
        .map(
          (s) => ShiftReportRow(
            shiftNumber: s,
            totalPiastres: shiftTotals[s] ?? 0,
            entriesCount: shiftCounts[s] ?? 0,
          ),
        )
        .toList();

    final byDay = dayAccum.values.map((d) => d.toRow()).toList()
      ..sort((a, b) => a.operationalDate.compareTo(b.operationalDate));

    return ReportData(
      filter: filter,
      generatedAt: _nowIso(),
      outletNamesById: outletNamesById,
      grandTotalPiastres: grandTotal,
      totalEntries: details.length,
      activeDaysCount: byDay.length,
      modifiedEntriesCount: modifiedCount,
      byOutlet: byOutlet,
      byShift: byShift,
      byDay: byDay,
      details: details,
      outlets: List.unmodifiable(outlets),
    );
  }

  /// Builds the complete electronic daily journal for one operational day.
  ///
  /// The same [DailyJournal] instance feeds the PDF, the Excel sheet and the
  /// on-screen preview, which guarantees identical values everywhere.
  Future<DailyJournal> buildDailyJournal(
    String operationalDate, {
    Set<String> outletIds = const {},
    String title = kDailyJournalTitle,
  }) async {
    if (!isValidOperationalDate(operationalDate)) {
      throw const ValidationException('التاريخ التشغيلي غير صالح');
    }
    final report = await buildReport(
      ReportFilter(
        range: OperationalDateRange.daily(
          parseOperationalDate(operationalDate)!,
        ),
        outletIds: outletIds,
      ),
    );
    return DailyJournal.fromReport(report, title: title);
  }

  /// Returns active outlet shifts that have not yet been recorded on [operationalDate].
  Future<List<MissingShiftItem>> findMissingShiftsForDate(
    String operationalDate,
  ) async {
    if (!isValidOperationalDate(operationalDate)) return const [];
    final activeOutlets = await listOutlets(includeInactive: false);
    if (activeOutlets.isEmpty) return const [];

    final recorded = await queryCollections(
      startDate: operationalDate,
      endDate: operationalDate,
    );
    final recordedKeys = {
      for (final c in recorded) '${c.outletId}|${c.shiftNumber}',
    };

    final missing = <MissingShiftItem>[];
    for (final outlet in activeOutlets) {
      for (var s = 1; s <= outlet.shiftCount; s++) {
        if (!recordedKeys.contains('${outlet.id}|$s')) {
          final def = outlet.shiftByNumber(s);
          missing.add(
            MissingShiftItem(
              outletId: outlet.id,
              outletName: outlet.name,
              operationalDate: operationalDate,
              shiftNumber: s,
              shiftLabel: def?.label ?? defaultShiftLabel(s),
              timeRange: def?.timeRange ?? '',
            ),
          );
        }
      }
    }
    return missing;
  }

  // ---------------------------------------------------------------------------
  // Audit Log
  // ---------------------------------------------------------------------------

  /// Records a system-level audit event (e.g. database restore).
  Future<void> recordSystemAudit({
    required AuditAction action,
    required String entityId,
    required String summary,
    String reason = '',
    Map<String, dynamic>? afterMap,
  }) async {
    final db = await appDatabase.database;
    await _insertAudit(
      db,
      entityType: AuditEntityType.system,
      entityId: entityId,
      action: action,
      summary: summary,
      reason: reason.trim(),
      afterMap: afterMap,
      createdAt: _nowIso(),
    );
  }

  /// Queries audit log records in reverse chronological order.
  Future<List<AuditLogEntry>> queryAuditLogs({
    String? outletId,
    AuditEntityType? entityType,
    AuditAction? action,
    String? entityId,
    String? startOperationalDate,
    String? endOperationalDate,
    int limit = 250,
  }) async {
    final db = await appDatabase.database;
    final whereParts = <String>[];
    final args = <Object?>[];

    if (outletId != null && outletId.isNotEmpty) {
      whereParts.add('outlet_id = ?');
      args.add(outletId);
    }
    if (entityType != null) {
      whereParts.add('entity_type = ?');
      args.add(entityType.code);
    }
    if (action != null) {
      whereParts.add('action = ?');
      args.add(action.code);
    }
    if (entityId != null && entityId.isNotEmpty) {
      whereParts.add('entity_id = ?');
      args.add(entityId);
    }
    if (startOperationalDate != null &&
        isValidOperationalDate(startOperationalDate)) {
      whereParts.add(
        '(operational_date >= ? OR (operational_date IS NULL AND substr(created_at, 1, 10) >= ?))',
      );
      args.addAll([startOperationalDate, startOperationalDate]);
    }
    if (endOperationalDate != null &&
        isValidOperationalDate(endOperationalDate)) {
      whereParts.add(
        '(operational_date <= ? OR (operational_date IS NULL AND substr(created_at, 1, 10) <= ?))',
      );
      args.addAll([endOperationalDate, endOperationalDate]);
    }

    final rows = await db.query(
      'audit_logs',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(AuditLogEntry.fromRow).toList();
  }

  Future<void> _insertAudit(
    DatabaseExecutor exec, {
    required AuditEntityType entityType,
    required String entityId,
    required AuditAction action,
    String? outletId,
    String? outletName,
    String? operationalDate,
    int? shiftNumber,
    int? oldAmountPiastres,
    int? newAmountPiastres,
    required String summary,
    String reason = '',
    Map<String, dynamic>? beforeMap,
    Map<String, dynamic>? afterMap,
    required String createdAt,
  }) async {
    await exec.insert('audit_logs', {
      'entity_type': entityType.code,
      'entity_id': entityId,
      'action': action.code,
      'outlet_id': outletId,
      'outlet_name': outletName,
      'operational_date': operationalDate,
      'shift_number': shiftNumber,
      'old_amount_piastres': oldAmountPiastres,
      'new_amount_piastres': newAmountPiastres,
      'summary': summary,
      'reason': reason,
      'before_json': beforeMap != null ? jsonEncode(beforeMap) : null,
      'after_json': afterMap != null ? jsonEncode(afterMap) : null,
      'created_at': createdAt,
    });
  }
}

class _OutletAccum {
  final String outletId;
  final String outletName;
  final int configuredShiftCount;
  final bool isActive;
  int shift1 = 0;
  int shift2 = 0;
  int shift3 = 0;
  int count = 0;

  _OutletAccum({
    required this.outletId,
    required this.outletName,
    required this.configuredShiftCount,
    required this.isActive,
  });

  void add(int shift, int piastres) {
    if (shift == 1) {
      shift1 += piastres;
    } else if (shift == 2) {
      shift2 += piastres;
    } else if (shift == 3) {
      shift3 += piastres;
    }
    count++;
  }

  OutletReportRow toRow() => OutletReportRow(
        outletId: outletId,
        outletName: outletName,
        configuredShiftCount: configuredShiftCount,
        isActive: isActive,
        shift1Piastres: shift1,
        shift2Piastres: shift2,
        shift3Piastres: shift3,
        totalPiastres: shift1 + shift2 + shift3,
        recordedShiftsCount: count,
      );
}

class _DayAccum {
  final String operationalDate;
  int shift1 = 0;
  int shift2 = 0;
  int shift3 = 0;
  int count = 0;

  _DayAccum(this.operationalDate);

  void add(int shift, int piastres) {
    if (shift == 1) {
      shift1 += piastres;
    } else if (shift == 2) {
      shift2 += piastres;
    } else if (shift == 3) {
      shift3 += piastres;
    }
    count++;
  }

  DailyReportRow toRow() => DailyReportRow(
        operationalDate: operationalDate,
        shift1Piastres: shift1,
        shift2Piastres: shift2,
        shift3Piastres: shift3,
        totalPiastres: shift1 + shift2 + shift3,
        entriesCount: count,
      );
}
