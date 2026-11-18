/// Core formatting, validation, and money utilities for RAGAA.
///
/// All monetary values are stored and processed as integer piastres (1 EGP = 100 piastres)
/// to completely eliminate IEEE-754 floating-point rounding errors.
library;

/// Maximum single collection entry: 999,999,999.99 EGP (in piastres).
const int kMaxAmountPiastres = 99999999999;

/// Strips time-of-day from a [DateTime], returning local midnight.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// Formats a [DateTime] as a canonical operational date key `yyyy-MM-dd`.
String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Strictly validates a calendar date formatted as `yyyy-MM-dd`.
bool isValidOperationalDate(String value) => parseOperationalDate(value) != null;

/// Parses a strict `yyyy-MM-dd` calendar date, or returns `null` if invalid.
DateTime? parseOperationalDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (year < 2000 || year > 2200) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

/// Validates a 24-hour clock string formatted as `HH:mm` (`00:00`..`23:59`).
bool isValidTime24(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

/// Formats hour and minute integers as `HH:mm`.
String formatTime24(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// Parses `HH:mm` into `(hour, minute)`, or returns `null`.
({int hour, int minute})? parseTime24(String value) {
  if (!isValidTime24(value)) return null;
  final parts = value.split(':');
  return (hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

/// Returns `true` if the shift crosses or ends at midnight (e.g. `16:00` -> `00:00`
/// or `22:00` -> `06:00`). Under RAGAA's operational date rule, the entire shift
/// still belongs to its starting operational day.
bool isOvernightShift(String startTime, String endTime) {
  if (!isValidTime24(startTime) || !isValidTime24(endTime)) return false;
  return endTime.compareTo(startTime) <= 0;
}

/// Returns a readable schedule label like `08:00 - 16:00` or `22:00 - 06:00 (بعد منتصف الليل)`.
String formatShiftRange(
  String startTime,
  String endTime, {
  bool includeOvernightNote = false,
}) {
  final base = '$startTime - $endTime';
  if (includeOvernightNote &&
      isOvernightShift(startTime, endTime) &&
      endTime != '00:00') {
    return '$base (تمتد لليوم التالي)';
  }
  return base;
}

/// Normalizes Arabic-Indic (`٠-٩`) and Eastern Arabic (`۰-۹`) digits and decimal
/// separators into standard ASCII numeric strings.
String normalizeDigits(String input) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final idx1 = arabicIndic.indexOf(ch);
    if (idx1 != -1) {
      buffer.write(idx1);
      continue;
    }
    final idx2 = easternArabic.indexOf(ch);
    if (idx2 != -1) {
      buffer.write(idx2);
      continue;
    }
    if (ch == '٫' || ch == ',') {
      buffer.write('.');
      continue;
    }
    if (ch == '٬' || ch == ' ' || ch == '\u00A0') {
      continue;
    }
    buffer.write(ch);
  }
  return buffer.toString();
}

/// Parses a user-entered EGP amount into integer piastres.
///
/// Accepts up to 2 decimal places and Arabic or Latin digits.
/// Returns `null` if invalid, negative, or exceeding [kMaxAmountPiastres].
int? tryParsePiastres(String raw) {
  final cleaned = normalizeDigits(raw.trim());
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(cleaned)) return null;
  final parts = cleaned.split('.');
  if (parts[0].length > 9) return null;
  final pounds = int.tryParse(parts[0]);
  if (pounds == null || pounds < 0) return null;
  final fraction =
      parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;
  final total = pounds * 100 + fraction;
  if (total < 0 || total > kMaxAmountPiastres) return null;
  return total;
}

String _groupThousands(String digits) {
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buf.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buf.write(',');
    }
  }
  return buf.toString();
}

/// Formats integer [piastres] as exact EGP string using pure integer arithmetic.
String formatMoney(
  int piastres, {
  bool withCurrency = false,
  bool grouped = true,
}) {
  final isNegative = piastres < 0;
  final abs = piastres.abs();
  final whole = (abs ~/ 100).toString();
  final frac = (abs % 100).toString().padLeft(2, '0');
  final formattedWhole = grouped ? _groupThousands(whole) : whole;
  final sign = isNegative ? '-' : '';
  final amount = '$sign$formattedWhole.$frac';
  return withCurrency ? '$amount ج.م' : amount;
}

/// Formats integer [piastres] into a plain editable decimal string (no grouping).
String formatEditableAmount(int piastres) =>
    formatMoney(piastres, withCurrency: false, grouped: false);

/// Formats a signed piastre delta (`+120.00 ج.م` / `-50.00 ج.م` / `0.00 ج.م`).
String formatMoneyDelta(int deltaPiastres, {bool withCurrency = true}) {
  final base = formatMoney(deltaPiastres, withCurrency: withCurrency);
  if (deltaPiastres > 0) return '+$base';
  return base;
}

/// Converts integer piastres to an exact decimal double for Excel numeric cells.
double piastresToUnits(int piastres) => piastres / 100.0;

/// Returns the canonical Arabic name for a shift number (1..3).
String defaultShiftLabel(int shiftNumber) {
  switch (shiftNumber) {
    case 1:
      return 'الوردية الأولى';
    case 2:
      return 'الوردية الثانية';
    case 3:
      return 'الوردية الثالثة';
    default:
      return 'الوردية $shiftNumber';
  }
}

/// Returns default start/end times for shift [shiftNumber] given [shiftCount].
({String start, String end}) defaultShiftTimes(int shiftNumber, int shiftCount) {
  if (shiftCount == 2) {
    switch (shiftNumber) {
      case 1:
        return (start: '08:00', end: '20:00');
      case 2:
        return (start: '20:00', end: '08:00');
      default:
        return (start: '00:00', end: '08:00');
    }
  }
  switch (shiftNumber) {
    case 1:
      return (start: '08:00', end: '16:00');
    case 2:
      return (start: '16:00', end: '00:00');
    default:
      return (start: '00:00', end: '08:00');
  }
}

/// Formats an ISO-8601 timestamp into `yyyy-MM-dd HH:mm` in local time.
String formatTimestamp(String isoString) {
  final parsed = DateTime.tryParse(isoString);
  if (parsed == null) return isoString;
  final local = parsed.toLocal();
  return '${dateKey(local)} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// Arabic month names (Gregorian calendar, commonly used in Egyptian accounting).
const List<String> kArabicMonthNames = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// Arabic weekday names matching `DateTime.weekday` (1 = Monday .. 7 = Sunday).
String arabicWeekday(DateTime date) {
  switch (date.weekday) {
    case DateTime.saturday:
      return 'السبت';
    case DateTime.sunday:
      return 'الأحد';
    case DateTime.monday:
      return 'الاثنين';
    case DateTime.tuesday:
      return 'الثلاثاء';
    case DateTime.wednesday:
      return 'الأربعاء';
    case DateTime.thursday:
      return 'الخميس';
    case DateTime.friday:
      return 'الجمعة';
    default:
      return '';
  }
}

/// Formats a byte count into a concise Arabic human-readable size.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes بايت';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} ك.ب';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(2)} م.ب';
}
