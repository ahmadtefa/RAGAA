import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ragaa/core/date_ranges.dart';
import 'package:ragaa/data/app_database.dart';
import 'package:ragaa/data/ragaa_repository.dart';
import 'package:ragaa/models/collection_amounts.dart';
import 'package:ragaa/models/report_models.dart';
import 'package:ragaa/services/excel_export_service.dart';
import 'package:ragaa/services/pdf_export_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Generates real (non-mocked) PDF and Excel files from a deterministic demo
/// dataset into `review/` so the produced documents can be inspected visually
/// and compared against the paper daily journal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final reviewDir = Directory('review');

  test('generates review PDF/Excel samples from real data', () async {
    await reviewDir.create(recursive: true);

    final db = AppDatabase.atPath(inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate);
    await db.open();
    addTearDown(db.close);
    final repo = RagaaRepository(db);

    final outlets = <String, String>{};
    for (final spec in <(String, int)>[
      ('نقل ١', 3),
      ('نقل ٢', 3),
      ('ملاكي', 3),
      ('خروج ١', 3),
      ('رقابة', 2),
      ('المنيا ٢', 2),
      ('المنيا ٣', 2),
      ('الدهسا', 2),
    ]) {
      final outlet = await repo.createOutlet(name: spec.$1, shiftCount: spec.$2);
      outlets[spec.$1] = outlet.id;
    }

    const demoDate = '2026-11-19';
    final samples = <String, List<int>>{
      'نقل ١': [1000000, 1200000, 900000],
      'نقل ٢': [800000, 950000, 700000],
      'ملاكي': [600000, 640000, 610000],
      'خروج ١': [450000, 470000, 0],
      'رقابة': [1000000, 1000000],
      'المنيا ٢': [550000, 520000],
      'المنيا ٣': [480000, 500000],
      'الدهسا': [2100000, 2050000],
    };
    final feeSamples = <String, List<(int, int, int, int, int)>>{
      'نقل ١': [tuple(200000, 300000, 550000, 100000, 50000), tuple(0, 0, 0, 0, 0), tuple(0, 0, 0, 0, 0)],
    };

    for (final entry in samples.entries) {
      final outletId = outlets[entry.key]!;
      for (var i = 0; i < entry.value.length; i++) {
        final shift = i + 1;
        final general = entry.value[i];
        if (general == 0) continue;
        final extra = feeSamples[entry.key] != null && shift == 1
            ? feeSamples[entry.key]![0]
            : tuple(0, 0, 0, 0, 0);
        await repo.createCollection(
          outletId: outletId,
          operationalDate: demoDate,
          shiftNumber: shift,
          amounts: CollectionAmounts(
            manualFeesPiastres: extra.$1,
            automaticFeesPiastres: extra.$2,
            totalFeesPiastres: extra.$3,
            generalTotalPiastres: general,
            nfcPiastres: extra.$4,
            visaPiastres: extra.$5,
          ),
        );
      }
    }

    final report = await repo.buildReport(
      ReportFilter(range: OperationalDateRange.daily(DateTime(2026, 11, 19))),
    );

    final pdfService = PdfExportService();
    final pdfBytes = await pdfService.buildReportPdfBytes(report);
    await File('${reviewDir.path}/ragaa_report_2026-11-19.pdf')
        .writeAsBytes(pdfBytes, flush: true);

    final excelService = ExcelExportService();
    final excelBytes = excelService.buildReportExcelBytes(report);
    await File('${reviewDir.path}/ragaa_report_2026-11-19.xlsx')
        .writeAsBytes(excelBytes, flush: true);

    expect(pdfBytes.length, greaterThan(1000));
    expect(excelBytes.length, greaterThan(1000));
  });
}

(int, int, int, int, int) tuple(int a, int b, int c, int d, int e) =>
    (a, b, c, d, e);
