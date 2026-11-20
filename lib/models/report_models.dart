import '../core/date_ranges.dart';
import '../core/formatters.dart';
import 'collection_record.dart';
import 'outlet.dart';

/// Filter parameters for report generation and dashboard aggregation.
class ReportFilter {
  final OperationalDateRange range;

  /// Empty set means all outlets. Otherwise restricts to matching outlet IDs.
  final Set<String> outletIds;

  /// Null means all shifts. Otherwise restricts to shift 1, 2, or 3.
  final int? shiftNumber;

  const ReportFilter({
    required this.range,
    this.outletIds = const {},
    this.shiftNumber,
  });

  ReportFilter copyWith({
    OperationalDateRange? range,
    Set<String>? outletIds,
    int? Function()? shiftNumber,
  }) =>
      ReportFilter(
        range: range ?? this.range,
        outletIds: outletIds ?? this.outletIds,
        shiftNumber: shiftNumber != null ? shiftNumber() : this.shiftNumber,
      );

  String shiftFilterArabic() =>
      shiftNumber == null ? 'كل الورديات' : defaultShiftLabel(shiftNumber!);

  String outletsFilterArabic(Map<String, String> outletNamesById) {
    if (outletIds.isEmpty) return 'كل المنافذ';
    final names = outletIds
        .map((id) => outletNamesById[id] ?? id)
        .toList()
      ..sort();
    return names.join('، ');
  }
}

/// Aggregated collection totals for a single outlet in a report period.
class OutletReportRow {
  final String outletId;
  final String outletName;
  final int configuredShiftCount;
  final bool isActive;
  final int shift1Piastres;
  final int shift2Piastres;
  final int shift3Piastres;
  final int totalPiastres;
  final int recordedShiftsCount;

  const OutletReportRow({
    required this.outletId,
    required this.outletName,
    required this.configuredShiftCount,
    required this.isActive,
    required this.shift1Piastres,
    required this.shift2Piastres,
    required this.shift3Piastres,
    required this.totalPiastres,
    required this.recordedShiftsCount,
  });

  double shareOf(int grandTotalPiastres) {
    if (grandTotalPiastres <= 0) return 0;
    return totalPiastres / grandTotalPiastres;
  }
}

/// Aggregated collection totals for a shift number (1, 2, or 3).
class ShiftReportRow {
  final int shiftNumber;
  final int totalPiastres;
  final int entriesCount;

  const ShiftReportRow({
    required this.shiftNumber,
    required this.totalPiastres,
    required this.entriesCount,
  });

  String get shiftLabel => defaultShiftLabel(shiftNumber);

  int get averagePiastres =>
      entriesCount > 0 ? totalPiastres ~/ entriesCount : 0;

  double shareOf(int grandTotalPiastres) {
    if (grandTotalPiastres <= 0) return 0;
    return totalPiastres / grandTotalPiastres;
  }
}

/// Aggregated collection totals for a single operational date.
class DailyReportRow {
  final String operationalDate;
  final int shift1Piastres;
  final int shift2Piastres;
  final int shift3Piastres;
  final int totalPiastres;
  final int entriesCount;

  const DailyReportRow({
    required this.operationalDate,
    required this.shift1Piastres,
    required this.shift2Piastres,
    required this.shift3Piastres,
    required this.totalPiastres,
    required this.entriesCount,
  });

  String get weekdayLabel {
    final parsed = parseOperationalDate(operationalDate);
    return parsed != null ? arabicWeekday(parsed) : '';
  }
}

/// Represents an active outlet shift not yet recorded on a given operational day.
class MissingShiftItem {
  final String outletId;
  final String outletName;
  final String operationalDate;
  final int shiftNumber;
  final String shiftLabel;
  final String timeRange;

  const MissingShiftItem({
    required this.outletId,
    required this.outletName,
    required this.operationalDate,
    required this.shiftNumber,
    required this.shiftLabel,
    required this.timeRange,
  });
}

/// Full structured report ready for UI rendering, PDF export, and Excel export.
class ReportData {
  final ReportFilter filter;
  final String generatedAt;
  final Map<String, String> outletNamesById;
  final int grandTotalPiastres;
  final int totalEntries;
  final int activeDaysCount;
  final int modifiedEntriesCount;
  final List<OutletReportRow> byOutlet;
  final List<ShiftReportRow> byShift;
  final List<DailyReportRow> byDay;
  final List<CollectionRecord> details;

  /// All outlets in the user-defined printable order (`sort_order`), including
  /// inactive ones that still own historical records. The daily journal uses
  /// this order so printed rows always match the paper form.
  final List<Outlet> outlets;

  const ReportData({
    required this.filter,
    required this.generatedAt,
    required this.outletNamesById,
    required this.grandTotalPiastres,
    required this.totalEntries,
    required this.activeDaysCount,
    required this.modifiedEntriesCount,
    required this.byOutlet,
    required this.byShift,
    required this.byDay,
    required this.details,
    this.outlets = const [],
  });

  int get dailyAveragePiastres =>
      activeDaysCount > 0 ? grandTotalPiastres ~/ activeDaysCount : 0;

  int get shiftAveragePiastres =>
      totalEntries > 0 ? grandTotalPiastres ~/ totalEntries : 0;

  String get outletsFilterLabel => filter.outletsFilterArabic(outletNamesById);

  String get shiftFilterLabel => filter.shiftFilterArabic();

  bool get hasShift3Data =>
      byShift.any((s) => s.shiftNumber == 3 && s.entriesCount > 0) ||
      byOutlet.any((o) => o.configuredShiftCount == 3);
}
