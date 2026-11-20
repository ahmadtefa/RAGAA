import '../core/formatters.dart';
import 'collection_amounts.dart';

/// Represents the recorded total collection for a single (outlet, operationalDate, shiftNumber).
///
/// Snapshot columns retain the shift label and schedule active at the moment of recording,
/// so future changes to outlet shift schedules never corrupt historical records.
class CollectionRecord {
  final int id;
  final String outletId;
  final String outletName;
  final String operationalDate; // yyyy-MM-dd
  final int shiftNumber; // 1, 2, or 3
  final int amountPiastres; // >= 0
  final CollectionAmounts amounts;
  final String shiftLabelSnapshot;
  final String shiftStartSnapshot;
  final String shiftEndSnapshot;
  final String notes;
  final int revision;
  final String createdAt;
  final String updatedAt;

  const CollectionRecord({
    required this.id,
    required this.outletId,
    required this.outletName,
    required this.operationalDate,
    required this.shiftNumber,
    required this.amountPiastres,
    required this.amounts,
    required this.shiftLabelSnapshot,
    required this.shiftStartSnapshot,
    required this.shiftEndSnapshot,
    required this.notes,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  String get uniqueKey => '$outletId|$operationalDate|$shiftNumber';

  int get manualFeesPiastres => amounts.manualFeesPiastres;
  int get automaticFeesPiastres => amounts.automaticFeesPiastres;
  int get totalFeesPiastres => amounts.totalFeesPiastres;
  int get generalTotalPiastres => amounts.generalTotalPiastres;
  int get scalesTotalPiastres => amounts.scalesTotalPiastres;
  int get nfcPiastres => amounts.nfcPiastres;
  int get visaPiastres => amounts.visaPiastres;

  bool get wasModified => revision > 1;

  String get shiftScheduleDisplay =>
      (shiftStartSnapshot.isNotEmpty && shiftEndSnapshot.isNotEmpty)
          ? '$shiftStartSnapshot - $shiftEndSnapshot'
          : '';

  String get shiftTitle => shiftLabelSnapshot.isNotEmpty
      ? shiftLabelSnapshot
      : defaultShiftLabel(shiftNumber);

  Map<String, dynamic> toAuditMap() => {
        'id': id,
        'outlet_id': outletId,
        'outlet_name': outletName,
        'operational_date': operationalDate,
        'shift_number': shiftNumber,
        'amount_piastres': amountPiastres,
        'amount_egp': formatMoney(amountPiastres, grouped: false),
        ...amounts.toDatabaseMap(),
        'shift_label': shiftLabelSnapshot,
        'shift_start': shiftStartSnapshot,
        'shift_end': shiftEndSnapshot,
        'notes': notes,
        'revision': revision,
        'updated_at': updatedAt,
      };

  factory CollectionRecord.fromRow(Map<String, Object?> row) =>
      CollectionRecord(
        id: row['id'] as int,
        outletId: row['outlet_id'] as String,
        outletName: (row['outlet_name'] as String?) ?? 'منفذ غير معروف',
        operationalDate: row['operational_date'] as String,
        shiftNumber: row['shift_number'] as int,
        amountPiastres: row['amount_piastres'] as int,
        amounts: CollectionAmounts(
          manualFeesPiastres: (row['manual_fees_piastres'] as int?) ?? 0,
          automaticFeesPiastres: (row['automatic_fees_piastres'] as int?) ?? 0,
          totalFeesPiastres: (row['total_fees_piastres'] as int?) ?? 0,
          generalTotalPiastres: (row['general_total_piastres'] as int?) ??
              (row['amount_piastres'] as int),
          nfcPiastres: (row['nfc_piastres'] as int?) ?? 0,
          visaPiastres: (row['visa_piastres'] as int?) ?? 0,
        ),
        shiftLabelSnapshot: (row['shift_label_snapshot'] as String?) ?? '',
        shiftStartSnapshot: (row['shift_start_snapshot'] as String?) ?? '',
        shiftEndSnapshot: (row['shift_end_snapshot'] as String?) ?? '',
        notes: (row['notes'] as String?) ?? '',
        revision: (row['revision'] as int?) ?? 1,
        createdAt: row['created_at'] as String,
        updatedAt: row['updated_at'] as String,
      );
}
