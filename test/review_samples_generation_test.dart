import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ragaa/core/date_ranges.dart';
import 'package:ragaa/data/app_database.dart';
import 'package:ragaa/data/ragaa_repository.dart';
import 'package:ragaa/models/report_models.dart';
import 'package:ragaa/services/daily_journal_pdf_service.dart';
import 'package:ragaa/services/excel_export_service.dart';
import 'package:ragaa/services/pdf_export_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/journal_demo_data.dart';

/// Generates real (non-mocked) PDF and Excel documents from a deterministic demo
/// dataset into `review/`, so the produced files can be inspected visually and
/// compared with the paper daily journal.
///
/// CI commits the regenerated files back to the working branch, which makes the
/// exact deliverables reviewable without a local Flutter toolchain.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final reviewDir = Directory('review');

  test('generates the review daily-journal and report samples', () async {
    await reviewDir.create(recursive: true);

    final db = AppDatabase.atPath(
      inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    await db.open();
    addTearDown(db.close);
    final repo = RagaaRepository(db);

    await JournalDemoDataset.seed(repo);

    final journalDate = JournalDemoDataset.operationalDate;
    final journal = await repo.buildDailyJournal(journalDate);

    // 1. Daily journal PDF (A4 landscape, Arabic RTL, paper-form layout).
    final journalPdf = await DailyJournalPdfService()
        .buildJournalPdfBytes(journal);
    await File('${reviewDir.path}/ragaa_journal_$journalDate.pdf')
        .writeAsBytes(journalPdf, flush: true);

    // 2. Daily journal Excel (same values, real formulas, RTL, print setup).
    final journalXlsx =
        ExcelExportService().buildJournalExcelBytes(journal);
    await File('${reviewDir.path}/ragaa_journal_$journalDate.xlsx')
        .writeAsBytes(journalXlsx, flush: true);

    // 3. Full daily report PDF/Excel (weekly view keeps every sheet).
    final report = await repo.buildReport(
      ReportFilter(range: OperationalDateRange.daily(DateTime(2026, 11, 19))),
    );
    final reportPdf = await PdfExportService().buildReportPdfBytes(report);
    await File('${reviewDir.path}/ragaa_report_$journalDate.pdf')
        .writeAsBytes(reportPdf, flush: true);

    final reportXlsx = ExcelExportService().buildReportExcelBytes(report);
    await File('${reviewDir.path}/ragaa_report_$journalDate.xlsx')
        .writeAsBytes(reportXlsx, flush: true);

    // 4. Weekly report sample (multi-day, no single-day journal sheet).
    final weekly = await repo.buildReport(
      ReportFilter(
        range: OperationalDateRange.weekly(DateTime(2026, 11, 19)),
      ),
    );
    final weeklyPdf = await PdfExportService().buildReportPdfBytes(weekly);
    await File('${reviewDir.path}/ragaa_report_weekly_2026-11-19.pdf')
        .writeAsBytes(weeklyPdf, flush: true);

    expect(journalPdf.length, greaterThan(5000));
    expect(journalXlsx.length, greaterThan(5000));
    expect(reportPdf.length, greaterThan(5000));
    expect(reportXlsx.length, greaterThan(5000));
    expect(weeklyPdf.length, greaterThan(5000));

    // The journal must be self-consistent even in the sample files.
    expect(
      journal.dayTotals.generalTotalPiastres,
      journal.outletDayTotals.fold<int>(
        0,
        (sum, row) => sum + row.amounts.generalTotalPiastres,
      ),
    );

    // ignore: avoid_print
    print(
      'review samples: ${journal.outletDayTotals.length} outlets, '
      '${journal.recordedShiftsCount} recorded shifts, '
      'grand total ${journal.dayTotals.generalTotalPiastres} piastres',
    );
  });
}
