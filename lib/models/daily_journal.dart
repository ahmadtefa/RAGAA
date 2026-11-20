import '../core/formatters.dart';
import 'collection_amounts.dart';
import 'collection_record.dart';
import 'outlet.dart';
import 'report_models.dart';

/// Title prefix printed on the daily journal. The paper journal used at the
/// collection office is titled «يومية المنيا»; changing this constant changes
/// the title in both the PDF and the Excel exports.
const String kDailyJournalTitle = 'يومية المنيا';

/// The seven approved monetary columns of the daily journal, in piastres.
///
/// Column order (right to left, exactly like the paper form):
///   1. الرسوم اليدوية  (manual fees — user input)
///   2. الرسوم الآلية   (automatic fees — user input)
///   3. إجمالي الرسوم  (total fees — user input, independent of 1 + 2)
///   4. إجمالي الموازين (scales — COMPUTED, never entered)
///   5. NFC             (user input, optional, defaults to 0)
///   6. VISA            (user input, optional, defaults to 0)
///   7. الإجمالي العام  (general total — user input; already includes NFC/VISA)
class JournalAmounts {
  final int manualFeesPiastres;
  final int automaticFeesPiastres;
  final int totalFeesPiastres;
  final int generalTotalPiastres;
  final int nfcPiastres;
  final int visaPiastres;

  const JournalAmounts({
    this.manualFeesPiastres = 0,
    this.automaticFeesPiastres = 0,
    this.totalFeesPiastres = 0,
    this.generalTotalPiastres = 0,
    this.nfcPiastres = 0,
    this.visaPiastres = 0,
  });

  static const JournalAmounts zero = JournalAmounts();

  factory JournalAmounts.fromCollectionAmounts(CollectionAmounts amounts) =>
      JournalAmounts(
        manualFeesPiastres: amounts.manualFeesPiastres,
        automaticFeesPiastres: amounts.automaticFeesPiastres,
        totalFeesPiastres: amounts.totalFeesPiastres,
        generalTotalPiastres: amounts.generalTotalPiastres,
        nfcPiastres: amounts.nfcPiastres,
        visaPiastres: amounts.visaPiastres,
      );

  factory JournalAmounts.fromRecord(CollectionRecord record) =>
      JournalAmounts.fromCollectionAmounts(record.amounts);

  /// The only approved formula: general total − total fees.
  ///
  /// NFC and VISA are already part of the general total and are deliberately
  /// **not** subtracted or added again.
  int get scalesTotalPiastres => generalTotalPiastres - totalFeesPiastres;

  bool get isZero =>
      manualFeesPiastres == 0 &&
      automaticFeesPiastres == 0 &&
      totalFeesPiastres == 0 &&
      generalTotalPiastres == 0 &&
      nfcPiastres == 0 &&
      visaPiastres == 0;

  /// Values in journal column order (see [JournalAmounts] docs).
  List<int> get columnsInOrder => <int>[
        manualFeesPiastres,
        automaticFeesPiastres,
        totalFeesPiastres,
        scalesTotalPiastres,
        nfcPiastres,
        visaPiastres,
        generalTotalPiastres,
      ];

  JournalAmounts operator +(JournalAmounts other) => JournalAmounts(
        manualFeesPiastres:
            manualFeesPiastres + other.manualFeesPiastres,
        automaticFeesPiastres:
            automaticFeesPiastres + other.automaticFeesPiastres,
        totalFeesPiastres: totalFeesPiastres + other.totalFeesPiastres,
        generalTotalPiastres:
            generalTotalPiastres + other.generalTotalPiastres,
        nfcPiastres: nfcPiastres + other.nfcPiastres,
        visaPiastres: visaPiastres + other.visaPiastres,
      );

  static JournalAmounts sum(Iterable<JournalAmounts> items) =>
      items.fold(zero, (acc, item) => acc + item);

  @override
  String toString() => 'JournalAmounts(manual: $manualFeesPiastres, '
      'automatic: $automaticFeesPiastres, fees: $totalFeesPiastres, '
      'scales: $scalesTotalPiastres, nfc: $nfcPiastres, '
      'visa: $visaPiastres, general: $generalTotalPiastres)';
}

/// One printed row of a shift section: a single outlet inside a single shift.
class JournalRow {
  final String outletId;
  final String outletName;
  final int shiftNumber;

  /// `false` when the outlet's shift was not recorded on that day (blank row,
  /// kept so the paper layout keeps every outlet visible).
  final bool hasRecord;
  final JournalAmounts amounts;

  const JournalRow({
    required this.outletId,
    required this.outletName,
    required this.shiftNumber,
    required this.hasRecord,
    required this.amounts,
  });
}

/// A shift block of the journal: header row, outlet rows and the yellow
/// «إجمالي الوردية» row.
class JournalShiftSection {
  final int shiftNumber;
  final String shiftLabel;
  final List<JournalRow> rows;
  final JournalAmounts totals;

  const JournalShiftSection({
    required this.shiftNumber,
    required this.shiftLabel,
    required this.rows,
    required this.totals,
  });

  int get greenRowCount => rows.length < 5 ? rows.length : 5;

  int get firstFivePiastres => rows.take(greenRowCount).fold<int>(
        0, (sum, row) => sum + row.amounts.generalTotalPiastres,
      );

  int get recordedCount => rows.where((row) => row.hasRecord).length;

  bool get isFullyRecorded => rows.isNotEmpty && recordedCount == rows.length;
}

/// Mandatory «إجمالي اليوم لكل منفذ» row: one independent row per outlet that
/// aggregates all of that outlet's shift totals for each financial column.
class JournalOutletDayTotal {
  final String outletId;
  final String outletName;
  final int recordedShifts;
  final JournalAmounts amounts;

  const JournalOutletDayTotal({
    required this.outletId,
    required this.outletName,
    required this.recordedShifts,
    required this.amounts,
  });
}

/// Full electronic rebuild of the paper daily journal for one operational day.
///
/// Section order (identical in the PDF, the Excel sheet and the on-screen
/// preview):
///   1. بيانات منافذ الوردية الأولى
///   2. إجمالي الوردية الأولى
///   3. بيانات منافذ الوردية الثانية
///   4. إجمالي الوردية الثانية
///   5. الوردية الثالثة وإجماليها (when enabled)
///   6. إجمالي اليوم لكل منفذ (mandatory, one row per outlet)
///   7. الإجمالي العام لليوم
///
/// Excluded on purpose (not part of the electronic journal): the green grouping
/// of the first five outlets, «مسلم الإداري», «مسلم الرقابة», «المتبقي» and the
/// cash hand-over calculations.
class DailyJournal {
  final String title;
  final String operationalDate; // yyyy-MM-dd
  final String weekdayLabel;
  final String generatedAt;
  final List<JournalShiftSection> sections;
  final List<JournalOutletDayTotal> outletDayTotals;
  final JournalAmounts dayTotals;
  final int recordedShiftsCount;
  final int configuredShiftCount;
  final Set<String> outletIds;
  final String outletsFilterLabel;

  const DailyJournal({
    required this.title,
    required this.operationalDate,
    required this.weekdayLabel,
    required this.generatedAt,
    required this.sections,
    required this.outletDayTotals,
    required this.dayTotals,
    required this.recordedShiftsCount,
    required this.configuredShiftCount,
    required this.outletIds,
    required this.outletsFilterLabel,
  });

  bool get hasShift3 => sections.any((section) => section.shiftNumber == 3);

  bool get hasData => recordedShiftsCount > 0;

  int get outletCount => outletDayTotals.length;

  /// `dd/MM/yyyy` exactly like the paper header.
  String get dateDisplay {
    final parsed = parseOperationalDate(operationalDate);
    if (parsed == null) return operationalDate;
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  /// «يوم الخميس الموافق 19/11/2026».
  String get headerLine => 'يوم $weekdayLabel الموافق $dateDisplay';

  /// Builds the journal from already-loaded outlets and collection records.
  ///
  /// [outlets] must be ordered the way the office wants the outlets printed
  /// (see the `sort_order` column); records for other days are ignored.
  factory DailyJournal.build({
    required String operationalDate,
    required List<Outlet> outlets,
    required List<CollectionRecord> records,
    String title = kDailyJournalTitle,
    String generatedAt = '',
    Set<String> outletIds = const {},
    String outletsFilterLabel = 'كل المنافذ',
  }) {
    final parsedDate = parseOperationalDate(operationalDate);
    if (parsedDate == null) {
      throw ArgumentError.value(
        operationalDate,
        'operationalDate',
        'invalid operational date (expected yyyy-MM-dd)',
      );
    }

    final dayRecords = records
        .where((record) => record.operationalDate == operationalDate)
        .toList(growable: false);

    final recordByKey = <String, CollectionRecord>{
      for (final record in dayRecords)
        '${record.outletId}|${record.shiftNumber}': record,
    };

    // Outlets in configured order (filter applied), plus any outlet that has a
    // record but is not in the visible list (defensive: never drop real money).
    final orderedOutlets = <Outlet>[
      for (final outlet in outlets)
        if (outletIds.isEmpty || outletIds.contains(outlet.id)) outlet,
    ];
    final knownIds = {for (final outlet in orderedOutlets) outlet.id};
    final unknownNames = <String, String>{};
    for (final record in dayRecords) {
      if (!knownIds.contains(record.outletId)) {
        knownIds.add(record.outletId);
        unknownNames[record.outletId] = record.outletName;
      }
    }

    var configuredShiftCount = 2;
    for (final outlet in orderedOutlets) {
      if (outlet.shiftCount > configuredShiftCount) {
        configuredShiftCount = outlet.shiftCount;
      }
    }

    final sections = <JournalShiftSection>[];
    final perShiftAmounts = <String, List<JournalAmounts>>{};

    for (var shift = 1; shift <= 3; shift++) {
      final rows = <JournalRow>[];

      void addRow({
        required String outletId,
        required String outletName,
        required int configuredShifts,
        required bool isActive,
      }) {
        final record = recordByKey['$outletId|$shift'];
        final configured = isActive && shift <= configuredShifts;
        if (!configured && record == null) return;
        rows.add(
          JournalRow(
            outletId: outletId,
            outletName: outletName,
            shiftNumber: shift,
            hasRecord: record != null,
            amounts: record == null
                ? JournalAmounts.zero
                : JournalAmounts.fromRecord(record),
          ),
        );
      }

      for (final outlet in orderedOutlets) {
        addRow(
          outletId: outlet.id,
          outletName: outlet.name,
          configuredShifts: outlet.shiftCount,
          isActive: outlet.isActive,
        );
      }
      unknownNames.forEach((outletId, outletName) {
        addRow(
          outletId: outletId,
          outletName: outletName,
          configuredShifts: 1,
          isActive: false,
        );
      });

      if (rows.isEmpty) continue;

      for (final row in rows) {
        perShiftAmounts
            .putIfAbsent(row.outletId, () => <JournalAmounts>[])
            .add(row.amounts);
      }

      sections.add(
        JournalShiftSection(
          shiftNumber: shift,
          shiftLabel: _sectionLabel(shift),
          rows: List.unmodifiable(rows),
          totals: JournalAmounts.sum(rows.map((row) => row.amounts)),
        ),
      );
    }

    // «إجمالي اليوم لكل منفذ»: one row per outlet appearing anywhere above.
    final outletOrder = <String>[
      for (final outlet in orderedOutlets) outlet.id,
      ...unknownNames.keys,
    ];
    final outletDayTotals = <JournalOutletDayTotal>[];
    for (final outletId in outletOrder) {
      final shiftAmounts = perShiftAmounts[outletId];
      if (shiftAmounts == null || shiftAmounts.isEmpty) continue;
      final recordedShifts = sections
          .where((section) =>
              section.rows.any((row) => row.outletId == outletId && row.hasRecord))
          .length;
      outletDayTotals.add(
        JournalOutletDayTotal(
          outletId: outletId,
          outletName: _outletName(orderedOutlets, unknownNames, outletId),
          recordedShifts: recordedShifts,
          amounts: JournalAmounts.sum(shiftAmounts),
        ),
      );
    }

    // The day grand total is the sum of the independent per-outlet day totals,
    // so no shift is ever counted twice.
    final dayTotals = JournalAmounts.sum(
      outletDayTotals.map((row) => row.amounts),
    );

    return DailyJournal(
      title: title,
      operationalDate: operationalDate,
      weekdayLabel: arabicWeekday(parsedDate),
      generatedAt: generatedAt,
      sections: List.unmodifiable(sections),
      outletDayTotals: List.unmodifiable(outletDayTotals),
      dayTotals: dayTotals,
      recordedShiftsCount:
          sections.fold(0, (sum, section) => sum + section.recordedCount),
      configuredShiftCount: configuredShiftCount,
      outletIds: Set.unmodifiable(outletIds),
      outletsFilterLabel: outletsFilterLabel,
    );
  }

  /// Convenience builder used by the exporters: a report restricted to a single
  /// operational day produces the same journal values as the UI and Excel.
  factory DailyJournal.fromReport(
    ReportData report, {
    String title = kDailyJournalTitle,
  }) =>
      DailyJournal.build(
        operationalDate: report.filter.range.startKey,
        outlets: report.outlets,
        records: report.details,
        title: title,
        generatedAt: report.generatedAt,
        outletIds: report.filter.outletIds,
        outletsFilterLabel: report.outletsFilterLabel,
      );

  static String _sectionLabel(int shiftNumber) =>
      'بيانات منافذ ${defaultShiftLabel(shiftNumber)}';

  static String _outletName(
    List<Outlet> outlets,
    Map<String, String> unknownNames,
    String outletId,
  ) {
    for (final outlet in outlets) {
      if (outlet.id == outletId) return outlet.name;
    }
    return unknownNames[outletId] ?? outletId;
  }
}
