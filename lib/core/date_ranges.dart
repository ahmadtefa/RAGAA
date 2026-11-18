import 'formatters.dart';

/// Supported reporting period modes.
enum ReportPeriodType {
  daily,
  weekly,
  monthly,
  custom;

  String get arabicLabel {
    switch (this) {
      case ReportPeriodType.daily:
        return 'يومي';
      case ReportPeriodType.weekly:
        return 'أسبوعي';
      case ReportPeriodType.monthly:
        return 'شهري';
      case ReportPeriodType.custom:
        return 'فترة مخصصة';
    }
  }
}

/// Represents an inclusive operational date range `[start, end]`.
class OperationalDateRange {
  final ReportPeriodType type;
  final DateTime start;
  final DateTime end;

  OperationalDateRange._({
    required this.type,
    required DateTime start,
    required DateTime end,
  })  : start = dateOnly(start),
        end = dateOnly(end);

  /// Single operational day `[day, day]`.
  factory OperationalDateRange.daily(DateTime day) {
    final d = dateOnly(day);
    return OperationalDateRange._(
      type: ReportPeriodType.daily,
      start: d,
      end: d,
    );
  }

  /// Operational week (Saturday through Friday) containing [anchor].
  factory OperationalDateRange.weekly(DateTime anchor) {
    final d = dateOnly(anchor);
    // DateTime.saturday == 6, sunday == 7, monday == 1 ... friday == 5.
    final daysSinceSaturday = (d.weekday - DateTime.saturday + 7) % 7;
    final weekStart = d.subtract(Duration(days: daysSinceSaturday));
    final weekEnd = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + 6,
    );
    return OperationalDateRange._(
      type: ReportPeriodType.weekly,
      start: weekStart,
      end: weekEnd,
    );
  }

  /// Full calendar month `[yyyy-MM-01, yyyy-MM-lastDay]`.
  factory OperationalDateRange.monthly(int year, int month) {
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    return OperationalDateRange._(
      type: ReportPeriodType.monthly,
      start: first,
      end: last,
    );
  }

  /// Arbitrary inclusive date range `[start, end]`.
  factory OperationalDateRange.custom(DateTime start, DateTime end) {
    final s = dateOnly(start);
    final e = dateOnly(end);
    if (s.isAfter(e)) {
      throw ArgumentError('تاريخ البداية يجب ألا يكون بعد تاريخ النهاية');
    }
    return OperationalDateRange._(
      type: ReportPeriodType.custom,
      start: s,
      end: e,
    );
  }

  String get startKey => dateKey(start);
  String get endKey => dateKey(end);

  /// Number of inclusive calendar days in the period.
  int get dayCount {
    final startUtc = DateTime.utc(start.year, start.month, start.day);
    final endUtc = DateTime.utc(end.year, end.month, end.day);
    return endUtc.difference(startUtc).inDays + 1;
  }

  /// Human-readable Arabic description for UI headers and PDF/Excel exports.
  String get arabicDescription {
    switch (type) {
      case ReportPeriodType.daily:
        return 'تقرير يومي — ${arabicWeekday(start)} $startKey';
      case ReportPeriodType.weekly:
        return 'تقرير أسبوعي — من $startKey إلى $endKey';
      case ReportPeriodType.monthly:
        final monthName = kArabicMonthNames[start.month - 1];
        return 'تقرير شهري — $monthName ${start.year} ($startKey إلى $endKey)';
      case ReportPeriodType.custom:
        if (startKey == endKey) {
          return 'فترة مخصصة — $startKey';
        }
        return 'فترة مخصصة — من $startKey إلى $endKey';
    }
  }
}
