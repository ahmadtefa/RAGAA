import '../core/formatters.dart';

/// Input model when creating or updating a single shift schedule for an outlet.
class ShiftScheduleInput {
  final int shiftNumber; // 1, 2, or 3
  final String label;
  final String startTime; // HH:mm
  final String endTime; // HH:mm

  const ShiftScheduleInput({
    required this.shiftNumber,
    required this.label,
    required this.startTime,
    required this.endTime,
  });

  factory ShiftScheduleInput.defaultFor(int shiftNumber, int shiftCount) {
    final times = defaultShiftTimes(shiftNumber, shiftCount);
    return ShiftScheduleInput(
      shiftNumber: shiftNumber,
      label: defaultShiftLabel(shiftNumber),
      startTime: times.start,
      endTime: times.end,
    );
  }
}

/// Persisted shift definition belonging to an [Outlet].
class OutletShift {
  final int id;
  final String outletId;
  final int shiftNumber;
  final String label;
  final String startTime;
  final String endTime;
  final bool isEnabled;
  final String updatedAt;

  const OutletShift({
    required this.id,
    required this.outletId,
    required this.shiftNumber,
    required this.label,
    required this.startTime,
    required this.endTime,
    required this.isEnabled,
    required this.updatedAt,
  });

  bool get isOvernight => isOvernightShift(startTime, endTime);

  String get timeRange => formatShiftRange(startTime, endTime);

  String get displayLabel => '$label ($timeRange)';

  Map<String, dynamic> toMap() => {
        'id': id,
        'outlet_id': outletId,
        'shift_number': shiftNumber,
        'label': label,
        'start_time': startTime,
        'end_time': endTime,
        'is_enabled': isEnabled ? 1 : 0,
        'updated_at': updatedAt,
      };

  factory OutletShift.fromRow(Map<String, Object?> row) => OutletShift(
        id: row['id'] as int,
        outletId: row['outlet_id'] as String,
        shiftNumber: row['shift_number'] as int,
        label: row['label'] as String,
        startTime: row['start_time'] as String,
        endTime: row['end_time'] as String,
        isEnabled: (row['is_enabled'] as int) == 1,
        updatedAt: row['updated_at'] as String,
      );
}
