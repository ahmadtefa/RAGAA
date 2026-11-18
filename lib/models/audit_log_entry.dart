/// Categories of audited entities.
enum AuditEntityType {
  outlet('outlet', 'منفذ'),
  collection('collection', 'تحصيل وردية'),
  system('system', 'النظام');

  final String code;
  final String arabicLabel;
  const AuditEntityType(this.code, this.arabicLabel);

  static AuditEntityType fromCode(String code) =>
      AuditEntityType.values.firstWhere(
        (e) => e.code == code,
        orElse: () => AuditEntityType.system,
      );
}

/// Audited action types.
enum AuditAction {
  create('create', 'إضافة'),
  update('update', 'تعديل'),
  restore('restore', 'استعادة نسخة'),
  migrate('migrate', 'ترحيل بيانات');

  final String code;
  final String arabicLabel;
  const AuditAction(this.code, this.arabicLabel);

  static AuditAction fromCode(String code) => AuditAction.values.firstWhere(
        (e) => e.code == code,
        orElse: () => AuditAction.update,
      );
}

/// Immutable audit log record tracking every create, edit, schedule update,
/// legacy migration, and backup restoration.
class AuditLogEntry {
  final int id;
  final AuditEntityType entityType;
  final String entityId;
  final AuditAction action;
  final String? outletId;
  final String? outletName;
  final String? operationalDate;
  final int? shiftNumber;
  final int? oldAmountPiastres;
  final int? newAmountPiastres;
  final String summary;
  final String reason;
  final String? beforeJson;
  final String? afterJson;
  final String createdAt;

  const AuditLogEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    this.outletId,
    this.outletName,
    this.operationalDate,
    this.shiftNumber,
    this.oldAmountPiastres,
    this.newAmountPiastres,
    required this.summary,
    required this.reason,
    this.beforeJson,
    this.afterJson,
    required this.createdAt,
  });

  int? get amountDeltaPiastres {
    if (oldAmountPiastres == null || newAmountPiastres == null) return null;
    return newAmountPiastres! - oldAmountPiastres!;
  }

  factory AuditLogEntry.fromRow(Map<String, Object?> row) => AuditLogEntry(
        id: row['id'] as int,
        entityType: AuditEntityType.fromCode(row['entity_type'] as String),
        entityId: row['entity_id'] as String,
        action: AuditAction.fromCode(row['action'] as String),
        outletId: row['outlet_id'] as String?,
        outletName: row['outlet_name'] as String?,
        operationalDate: row['operational_date'] as String?,
        shiftNumber: row['shift_number'] as int?,
        oldAmountPiastres: row['old_amount_piastres'] as int?,
        newAmountPiastres: row['new_amount_piastres'] as int?,
        summary: row['summary'] as String,
        reason: (row['reason'] as String?) ?? '',
        beforeJson: row['before_json'] as String?,
        afterJson: row['after_json'] as String?,
        createdAt: row['created_at'] as String,
      );
}
