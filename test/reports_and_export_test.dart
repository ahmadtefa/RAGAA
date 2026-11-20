import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ragaa/core/date_ranges.dart';
import 'package:ragaa/data/app_database.dart';
import 'package:ragaa/data/ragaa_repository.dart';
import 'package:ragaa/models/report_models.dart';
import 'package:ragaa/services/excel_export_service.dart';
import 'package:ragaa/services/pdf_export_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDb;
  late RagaaRepository repo;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ragaa_export_test_');
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

  test(
      'computes daily, weekly, monthly, and custom reports with outlet/shift filters',
      () async {
    final maadi = await repo.createOutlet(name: 'منفذ المعادي', shiftCount: 2);
    final nasr = await repo.createOutlet(name: 'منفذ مدينة نصر', shiftCount: 3);

    // Week of Saturday 2026-11-14 .. Friday 2026-11-20
    await repo.createCollection(
      outletId: maadi.id,
      operationalDate: '2026-11-14',
      shiftNumber: 1,
      amountPiastres: 100000, // 1,000.00
    );
    await repo.createCollection(
      outletId: maadi.id,
      operationalDate: '2026-11-18',
      shiftNumber: 2,
      amountPiastres: 150050, // 1,500.50
    );
    await repo.createCollection(
      outletId: nasr.id,
      operationalDate: '2026-11-18',
      shiftNumber: 1,
      amountPiastres: 200000, // 2,000.00
    );
    await repo.createCollection(
      outletId: nasr.id,
      operationalDate: '2026-11-18',
      shiftNumber: 3,
      amountPiastres: 300025, // 3,000.25
    );
    // Earlier in November (outside that week, inside monthly report)
    await repo.createCollection(
      outletId: nasr.id,
      operationalDate: '2026-11-02',
      shiftNumber: 2,
      amountPiastres: 50000, // 500.00
    );

    // 1. Daily report (2026-11-18)
    final daily = await repo.buildReport(
      ReportFilter(range: OperationalDateRange.daily(DateTime(2026, 11, 18))),
    );
    expect(daily.grandTotalPiastres, 650075);
    expect(daily.totalEntries, 3);

    // Missing shifts on 2026-11-18: Maadi shift 1 + Nasr shift 2 = 2 missing.
    final missing = await repo.findMissingShiftsForDate('2026-11-18');
    expect(missing.length, 2);

    // 2. Weekly report (Sat 2026-11-14 .. Fri 2026-11-20)
    final weeklyRange = OperationalDateRange.weekly(DateTime(2026, 11, 18));
    expect(weeklyRange.startKey, '2026-11-14');
    expect(weeklyRange.endKey, '2026-11-20');
    expect(weeklyRange.dayCount, 7);
    final weekly = await repo.buildReport(ReportFilter(range: weeklyRange));
    expect(weekly.grandTotalPiastres, 750075);
    expect(weekly.totalEntries, 4);

    // 3. Monthly report (November 2026: 30 days)
    final monthlyRange = OperationalDateRange.monthly(2026, 11);
    expect(monthlyRange.startKey, '2026-11-01');
    expect(monthlyRange.endKey, '2026-11-30');
    expect(monthlyRange.dayCount, 30);
    final monthly = await repo.buildReport(ReportFilter(range: monthlyRange));
    expect(monthly.grandTotalPiastres, 800075);
    expect(monthly.totalEntries, 5);

    // 4. Custom range + outlet filter + shift filter
    final customFiltered = await repo.buildReport(
      ReportFilter(
        range: OperationalDateRange.custom(
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 20),
        ),
        outletIds: {nasr.id},
        shiftNumber: 3,
      ),
    );
    expect(customFiltered.grandTotalPiastres, 300025);
    expect(customFiltered.totalEntries, 1);
    expect(customFiltered.byOutlet.single.outletName, 'منفذ مدينة نصر');
  });

  test('exports valid Arabic RTL PDF and multi-sheet RTL Excel (.xlsx)',
      () async {
    final maadi = await repo.createOutlet(name: 'منفذ المعادي', shiftCount: 2);
    final nasr = await repo.createOutlet(name: 'منفذ مدينة نصر', shiftCount: 3);

    final c1 = await repo.createCollection(
      outletId: maadi.id,
      operationalDate: '2026-11-17',
      shiftNumber: 1,
      amountPiastres: 125000,
      notes: 'وردية صباحية منتظمة',
    );
    await repo.updateCollection(
      collectionId: c1.id,
      newAmountPiastres: 130050,
      notes: 'تمت مراجعة الخزينة',
      reason: 'إضافة إيصال متأخر',
    );
    await repo.createCollection(
      outletId: maadi.id,
      operationalDate: '2026-11-18',
      shiftNumber: 2,
      amountPiastres: 210000,
    );
    await repo.createCollection(
      outletId: nasr.id,
      operationalDate: '2026-11-18',
      shiftNumber: 1,
      amountPiastres: 340075,
    );
    await repo.createCollection(
      outletId: nasr.id,
      operationalDate: '2026-11-18',
      shiftNumber: 3,
      amountPiastres: 195000,
      notes: 'وردية ليلية بعد منتصف الليل',
    );

    final report = await repo.buildReport(
      ReportFilter(range: OperationalDateRange.monthly(2026, 11)),
    );
    expect(report.grandTotalPiastres, 875125); // 8,751.25 EGP

    // Export PDF
    final pdfService = PdfExportService();
    final pdfPath = p.join(tempDir.path, 'report_ar.pdf');
    final pdfFile = await pdfService.exportReportToFile(report, pdfPath);
    expect(await pdfFile.exists(), isTrue);
    final pdfBytes = await pdfFile.readAsBytes();
    expect(pdfBytes.length, greaterThan(5000));
    expect(String.fromCharCodes(pdfBytes.take(5)), '%PDF-');

    // Export Excel (.xlsx)
    final excelService = ExcelExportService();
    final xlsxPath = p.join(tempDir.path, 'report_ar.xlsx');
    final xlsxFile = await excelService.exportReportToFile(report, xlsxPath);
    expect(await xlsxFile.exists(), isTrue);
    final xlsxBytes = await xlsxFile.readAsBytes();
    // ZIP signature PK\x03\x04
    expect(xlsxBytes[0], 0x50);
    expect(xlsxBytes[1], 0x4B);

    final decoded = Excel.decodeBytes(xlsxBytes);
    expect(
      decoded.tables.keys,
      containsAll([
        ExcelExportService.summarySheetName,
        ExcelExportService.outletsSheetName,
        ExcelExportService.shiftsSheetName,
        ExcelExportService.dailySheetName,
        ExcelExportService.detailsSheetName,
      ]),
    );
    // The paper-form journal sheet belongs to single-day journals only.
    expect(
      decoded.tables.keys,
      isNot(contains(ExcelExportService.dailyJournalSheetName)),
    );

    // Every sheet must be RTL.
    for (final entry in decoded.tables.entries) {
      expect(
        entry.value.isRTL,
        isTrue,
        reason: 'Sheet "${entry.key}" must have RTL enabled',
      );
    }

    // Verify exact grand total in summary sheet (col 1, row 10 => 8751.25).
    final summarySheet = decoded.tables[ExcelExportService.summarySheetName]!;
    final totalCell = summarySheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 10))
        .value;
    expect(totalCell, isA<DoubleCellValue>());
    expect((totalCell as DoubleCellValue).value, closeTo(8751.25, 0.0001));

    // Verify details sheet has header + 4 collection rows + totals row.
    final detailsSheet = decoded.tables[ExcelExportService.detailsSheetName]!;
    final detailsTotal = detailsSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: 7))
        .value;
    expect((detailsTotal as DoubleCellValue).value, closeTo(8751.25, 0.0001));

    // The scales column is a real formula (الإجمالي العام − إجمالي الرسوم).
    final scalesCell = detailsSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: 3))
        .value;
    expect(scalesCell, isA<FormulaCellValue>());
    expect((scalesCell as FormulaCellValue).formula, 'M4-I4');
  });
}
