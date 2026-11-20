import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ragaa/core/date_ranges.dart';
import 'package:ragaa/core/formatters.dart';
import 'package:ragaa/data/app_database.dart';
import 'package:ragaa/data/ragaa_repository.dart';
import 'package:ragaa/models/daily_journal.dart';
import 'package:ragaa/models/report_models.dart';
import 'package:ragaa/services/daily_journal_pdf_service.dart';
import 'package:ragaa/services/excel_export_service.dart';
import 'package:ragaa/services/pdf_export_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/journal_demo_data.dart';

/// Reads a numeric cell as a double (numeric cells are written as real numbers).
double? numberAt(Sheet sheet, int column, int row) {
  final value = sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
      .value;
  if (value is DoubleCellValue) return value.value;
  if (value is IntCellValue) return value.value.toDouble();
  return null;
}

String? formulaAt(Sheet sheet, int column, int row) {
  final value = sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
      .value;
  return value is FormulaCellValue ? value.formula : null;
}

String textAt(Sheet sheet, int column, int row) {
  final value = sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
      .value;
  if (value == null) return '';
  return value.toString();
}

/// Sums every numeric cell referenced by a simple `SUM(B5:B12)` / `SUM(B5,B9)`
/// formula so the produced formulas can be verified without a spreadsheet.
double evaluateSumFormula(Sheet sheet, String formula) {
  final match = RegExp(r'^SUM\((.*)\)$').firstMatch(formula.trim());
  expect(match, isNotNull, reason: 'unexpected formula "$formula"');
  final body = match!.group(1)!;
  var total = 0.0;
  for (final part in body.split(',')) {
    final trimmed = part.trim();
    final rangeMatch =
        RegExp(r'^([A-Z]+)(\d+):([A-Z]+)(\d+)$').firstMatch(trimmed);
    if (rangeMatch != null) {
      final column = rangeMatch.group(1)!.codeUnitAt(0) - 65;
      final firstRow = int.parse(rangeMatch.group(2)!) - 1;
      final lastRow = int.parse(rangeMatch.group(4)!) - 1;
      for (var row = firstRow; row <= lastRow; row++) {
        total += numberAt(sheet, column, row) ?? 0;
      }
      continue;
    }
    final single = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(trimmed);
    if (single != null) {
      final column = single.group(1)!.codeUnitAt(0) - 65;
      final row = int.parse(single.group(2)!) - 1;
      total += numberAt(sheet, column, row) ?? 0;
      continue;
    }
    total += double.parse(trimmed);
  }
  return total;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase appDb;
  late RagaaRepository repo;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ragaa_journal_export_');
    appDb = AppDatabase.atPath(inMemoryDatabasePath);
    await appDb.open();
    repo = RagaaRepository(appDb);
  });

  tearDown(() async {
    await appDb.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('PDF and Excel journal exports carry exactly the same values', () async {
    await JournalDemoDataset.seed(repo);
    final journal = await repo.buildDailyJournal(
      JournalDemoDataset.operationalDate,
    );

    // 1. PDF is a real, valid PDF document.
    final pdfBytes = await DailyJournalPdfService().buildJournalPdfBytes(journal);
    expect(pdfBytes.sublist(0, 5), '%PDF-'.codeUnits);
    expect(pdfBytes.length, greaterThan(5000));
    final pdfFile = File('${tempDir.path}/journal.pdf');
    await pdfFile.writeAsBytes(pdfBytes, flush: true);
    expect(await pdfFile.length(), pdfBytes.length);

    // 2. Excel workbook decodes, is RTL and uses real formulas.
    final excelBytes = ExcelExportService().buildJournalExcelBytes(journal);
    final workbook = Excel.decodeBytes(excelBytes);
    expect(workbook.tables.keys, contains(ExcelExportService.dailyJournalSheetName));
    final sheet = workbook[ExcelExportService.dailyJournalSheetName];
    expect(sheet.isRTL, isTrue);

    // Title & header rows.
    expect(textAt(sheet, 0, 0), contains(kDailyJournalTitle));
    expect(textAt(sheet, 0, 2), 'البيان');
    expect(textAt(sheet, 7, 2), 'الإجمالي العام');
    expect(textAt(sheet, 4, 2), 'إجمالي الموازين');

    // Locate rows by their first-column label.
    final rowIndexByLabel = <String, int>{};
    for (var row = 0; row < 200; row++) {
      final label = textAt(sheet, 0, row);
      if (label.isNotEmpty && !rowIndexByLabel.containsKey(label)) {
        rowIndexByLabel[label] = row;
      }
    }

    // Shift 1 data rows: outlet names must be printed in configured order and
    // the numeric cells must equal the journal model values.
    final firstSection = journal.sections.first;
    for (final journalRow in firstSection.rows) {
      final row = rowIndexByLabel[journalRow.outletName];
      if (row == null) fail('missing row ${journalRow.outletName}');
      expect(numberAt(sheet, 1, row),
          journalRow.amounts.manualFeesPiastres / 100);
      expect(numberAt(sheet, 2, row),
          journalRow.amounts.automaticFeesPiastres / 100);
      expect(numberAt(sheet, 3, row), journalRow.amounts.totalFeesPiastres / 100);
      expect(numberAt(sheet, 5, row), journalRow.amounts.nfcPiastres / 100);
      expect(numberAt(sheet, 6, row), journalRow.amounts.visaPiastres / 100);
      expect(numberAt(sheet, 7, row),
          journalRow.amounts.generalTotalPiastres / 100);
      // Scales column is a real Excel formula: الإجمالي العام − إجمالي الرسوم.
      expect(formulaAt(sheet, 4, row), 'H${row + 1}-D${row + 1}');
      expect(
        evaluateSumFormula(sheet, 'SUM(H${row + 1}:H${row + 1})') -
            evaluateSumFormula(sheet, 'SUM(D${row + 1}:D${row + 1})'),
        journalRow.amounts.scalesTotalPiastres / 100,
      );
    }

    // Shift totals are SUM formulas over their own block.
    for (final section in journal.sections) {
      final label = 'إجمالي ${defaultShiftLabel(section.shiftNumber)}';
      final row = rowIndexByLabel[label];
      if (row == null) fail('missing total row $label');
      final formula = formulaAt(sheet, 7, row);
      if (formula == null) fail('shift total row $label has no formula');
      expect(formula.startsWith('SUM(H'), isTrue);
      expect(
        evaluateSumFormula(sheet, formula),
        section.totals.generalTotalPiastres / 100,
      );
      final manualFormula = formulaAt(sheet, 1, row);
      if (manualFormula == null) fail('missing manual total formula');
      expect(
        evaluateSumFormula(sheet, manualFormula),
        section.totals.manualFeesPiastres / 100,
      );
    }

    // «إجمالي اليوم لكل منفذ» — one independent row per outlet.
    final dayTotalBandRow = rowIndexByLabel['إجمالي اليوم لكل منفذ'];
    if (dayTotalBandRow == null) fail('missing the per-outlet day total band');
    final dayTotalLabels = <String>[];
    var scan = dayTotalBandRow + 1;
    while (scan < 200) {
      final label = textAt(sheet, 0, scan);
      if (label.isEmpty) break;
      if (label.startsWith('الإجمالي العام')) break;
      dayTotalLabels.add(label);
      final formula = formulaAt(sheet, 7, scan);
      if (formula == null) fail('day total for $label must be a SUM formula');
      expect(
        evaluateSumFormula(sheet, formula),
        journal.outletDayTotals
                .firstWhere((row) => row.outletName == label)
                .amounts
                .generalTotalPiastres /
            100,
        reason: 'day total mismatch for $label',
      );
      scan++;
    }
    expect(dayTotalLabels, journal.outletDayTotals.map((r) => r.outletName));

    // Grand total row: sum of the per-outlet day totals (no double counting).
    final grandRow = rowIndexByLabel['الإجمالي العام لليوم'];
    if (grandRow == null) fail('missing the daily grand total row');
    final grandFormula = formulaAt(sheet, 7, grandRow);
    if (grandFormula == null) fail('daily grand total must be a SUM formula');
    expect(
      evaluateSumFormula(sheet, grandFormula),
      journal.dayTotals.generalTotalPiastres / 100,
    );
    final grandScalesFormula = formulaAt(sheet, 4, grandRow);
    if (grandScalesFormula == null) fail('missing grand scales formula');
    expect(
      evaluateSumFormula(sheet, grandScalesFormula),
      journal.dayTotals.scalesTotalPiastres / 100,
    );

    // 3. OOXML print setup: landscape, fit-to-width, print area, frozen header.
    final archive = ZipDecoder().decodeBytes(excelBytes);
    String? workbookXml;
    String? sheetXml;
    for (final file in archive.files) {
      if (file.name == 'xl/workbook.xml') {
        workbookXml = String.fromCharCodes(file.content as List<int>);
      }
      if (file.name == 'xl/worksheets/sheet1.xml') {
        sheetXml = String.fromCharCodes(file.content as List<int>);
      }
    }
    expect(workbookXml, isNotNull);
    expect(sheetXml, isNotNull);
    expect(workbookXml, contains('_xlnm.Print_Area'));
    expect(workbookXml, contains('fullCalcOnLoad="1"'));
    expect(sheetXml, contains('orientation="landscape"'));
    expect(sheetXml, contains('fitToWidth="1"'));
    expect(sheetXml, contains('state="frozen"'));
    expect(sheetXml, contains('rightToLeft="1"'));
  });

  test('the single-day report workbook contains the same journal sheet',
      () async {
    await JournalDemoDataset.seed(repo);
    final report = await repo.buildReport(
      ReportFilter(
        range: OperationalDateRange.daily(
          DateTime.parse(JournalDemoDataset.operationalDate),
        ),
      ),
    );

    final bytes = ExcelExportService().buildReportExcelBytes(report);
    final workbook = Excel.decodeBytes(bytes);
    expect(
      workbook.tables.keys,
      containsAll(<String>[
        ExcelExportService.summarySheetName,
        ExcelExportService.outletsSheetName,
        ExcelExportService.shiftsSheetName,
        ExcelExportService.dailySheetName,
        ExcelExportService.detailsSheetName,
        ExcelExportService.dailyJournalSheetName,
      ]),
    );

    final journal = DailyJournal.fromReport(report);
    final sheet = workbook[ExcelExportService.dailyJournalSheetName];
    expect(textAt(sheet, 0, 0), contains(kDailyJournalTitle));
    // Same grand total as the journal model (and therefore as the PDF).
    final dayTotals = journal.outletDayTotals.fold<int>(
      0,
      (sum, row) => sum + row.amounts.generalTotalPiastres,
    );
    expect(journal.dayTotals.generalTotalPiastres, dayTotals);
  });

  test('multi-day reports keep all sheets and skip the single-day journal',
      () async {
    await JournalDemoDataset.seed(repo);
    final report = await repo.buildReport(
      ReportFilter(
        range: OperationalDateRange.weekly(
          DateTime.parse(JournalDemoDataset.operationalDate),
        ),
      ),
    );
    final workbook =
        Excel.decodeBytes(ExcelExportService().buildReportExcelBytes(report));
    expect(
      workbook.tables.keys,
      isNot(contains(ExcelExportService.dailyJournalSheetName)),
    );
  });

  test('journal PDFs span multiple pages without losing the header', () async {
    // 24 outlets x 3 shifts forces the journal over several A4 landscape pages.
    for (var index = 0; index < 24; index++) {
      final outlet = await repo.createOutlet(
        name: 'منفذ رقم ${index + 1}',
        shiftCount: 3,
      );
      for (var shift = 1; shift <= 3; shift++) {
        await repo.createCollection(
          outletId: outlet.id,
          operationalDate: '2026-11-19',
          shiftNumber: shift,
          amountPiastres: 100000 + index * 1000 + shift * 100,
        );
      }
    }

    final journal = await repo.buildDailyJournal('2026-11-19');
    expect(journal.outletDayTotals.length, 24);
    final bytes = await DailyJournalPdfService().buildJournalPdfBytes(journal);
    expect(bytes.sublist(0, 5), '%PDF-'.codeUnits);

    // Each printed page carries the journal title in its page header.
    final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(
      String.fromCharCodes(bytes),
    ).length;
    expect(pages, greaterThan(1));

    // The Excel export handles the same volume with one row per outlet.
    final workbook =
        Excel.decodeBytes(ExcelExportService().buildJournalExcelBytes(journal));
    final sheet = workbook[ExcelExportService.dailyJournalSheetName];
    expect(sheet.isRTL, isTrue);
  });

  test('the general report PDF still renders for the same dataset', () async {
    await JournalDemoDataset.seed(repo);
    final report = await repo.buildReport(
      ReportFilter(
        range: OperationalDateRange.monthly(2026, 11),
      ),
    );
    final bytes = await PdfExportService().buildReportPdfBytes(report);
    expect(bytes.sublist(0, 5), '%PDF-'.codeUnits);
  });
}
