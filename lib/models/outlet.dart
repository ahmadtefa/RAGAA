import 'outlet_shift.dart';

/// Represents a physical/operational collection outlet registered on the central device.
class Outlet {
  final String id;
  final String name;
  final int shiftCount; // 2 or 3
  final bool isActive;
  final String notes;
  final String createdAt;
  final String updatedAt;
  final List<OutletShift> shifts;

  const Outlet({
    required this.id,
    required this.name,
    required this.shiftCount,
    required this.isActive,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.shifts,
  });

  /// Shifts currently active for new collection recording (1..shiftCount).
  List<OutletShift> get activeShifts =>
      shifts.where((s) => s.isEnabled && s.shiftNumber <= shiftCount).toList()
        ..sort((a, b) => a.shiftNumber.compareTo(b.shiftNumber));

  /// Looks up a shift definition (enabled or preserved disabled) by number.
  OutletShift? shiftByNumber(int number) {
    for (final s in shifts) {
      if (s.shiftNumber == number) return s;
    }
    return null;
  }

  String get shiftCountArabic => shiftCount == 2 ? 'ورديتان' : '3 ورديات';

  Map<String, dynamic> toAuditMap() => {
        'id': id,
        'name': name,
        'shift_count': shiftCount,
        'is_active': isActive,
        'notes': notes,
        'shifts': shifts
            .map(
              (s) => {
                'shift_number': s.shiftNumber,
                'label': s.label,
                'start_time': s.startTime,
                'end_time': s.endTime,
                'is_enabled': s.isEnabled,
              },
            )
            .toList(),
      };

  factory Outlet.fromRow(
    Map<String, Object?> row, {
    required List<OutletShift> shifts,
  }) {
    final sorted = [...shifts]
      ..sort((a, b) => a.shiftNumber.compareTo(b.shiftNumber));
    return Outlet(
      id: row['id'] as String,
      name: row['name'] as String,
      shiftCount: row['shift_count'] as int,
      isActive: (row['is_active'] as int) == 1,
      notes: (row['notes'] as String?) ?? '',
      createdAt: row['created_at'] as String,
      updatedAt: row['updated_at'] as String,
      shifts: List.unmodifiable(sorted),
    );
  }
}
