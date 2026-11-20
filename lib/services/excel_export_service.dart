import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../core/exceptions.dart';
import '../core/formatters.dart';
import '../models/report_models.dart';

/// Generates multi-sheet Arabic RTL Excel (`.xlsx`) accounting workbooks.
///
/// Every worksheet has `isRTL = true` (`<sheetView rightToLeft="1"/>`),
/// formatted headers, exact currency values, percentage ratios, and total rows.
class ExcelExportService {
  static const String summarySheetName = 'ملخص التقرير';
  static const String outletsSheetName = 'حسب المنفذ';
  static const String shiftsSheetName = 'حسب الوردية';
  static const String dailySheetName = 'حسب اليوم';
  static const String detailsSheetName = 'تفاصيل التحصيل';
  static const String dailyJournalSheetName = 'اليومية';

  /// Builds `.xlsx` file bytes for [report].
  Uint8List buildReportExcelBytes(ReportData report) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();

    final titleStyle = CellStyle(
      bold: true,
      fontSize: 14,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('#0F5C54'),
      horizontalAlign: HorizontalAlign.Right,
      verticalAlign: VerticalAlign.Center,
    );

    final headerStyle = CellStyle(
      bold: true,
      fontSize: 11,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('#115E59'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final labelStyle = CellStyle(
      bold: true,
      fontSize: 10,
      backgroundColorHex: ExcelColor.fromHexString('#F1F5F9'),
      horizontalAlign: HorizontalAlign.Right,
      verticalAlign: VerticalAlign.Center,
    );

    final textCellStyle = CellStyle(
      fontSize: 10,
      horizontalAlign: HorizontalAlign.Right,
      verticalAlign: VerticalAlign.Center,
    );

    final centerCellStyle = CellStyle(
      fontSize: 10,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    final moneyFormat = NumFormat.custom(formatCode: '#,##0.00');
    final moneyCellStyle = CellStyle(
      fontSize: 10,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      numberFormat: moneyFormat,
    );

    final totalTextStyle = CellStyle(
      bold: true,
      fontSize: 11,
      fontColorHex: ExcelColor.fromHexString('#064E3B'),
      backgroundColorHex: ExcelColor.fromHexString('#ECFDF5'),
      horizontalAlign: HorizontalAlign.Right,
      verticalAlign: VerticalAlign.Center,
    );

    final totalMoneyStyle = CellStyle(
      bold: true,
      fontSize: 11,
      fontColorHex: ExcelColor.fromHexString('#064E3B'),
      backgroundColorHex: ExcelColor.fromHexString('#ECFDF5'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      numberFormat: moneyFormat,
    );

    // 1. Summary Sheet
    final summary = excel[summarySheetName];
    summary.isRTL = true;
    _buildSummarySheet(
      sheet: summary,
      report: report,
      titleStyle: titleStyle,
      labelStyle: labelStyle,
      textStyle: textCellStyle,
      moneyStyle: moneyCellStyle,
      totalMoneyStyle: totalMoneyStyle,
    );

    // 2. Outlets Breakdown Sheet
    final outletsSheet = excel[outletsSheetName];
    outletsSheet.isRTL = true;
    _buildOutletsSheet(
      sheet: outletsSheet,
      report: report,
      titleStyle: titleStyle,
      headerStyle: headerStyle,
      textStyle: textCellStyle,
      centerStyle: centerCellStyle,
      moneyStyle: moneyCellStyle,
      totalTextStyle: totalTextStyle,
      totalMoneyStyle: totalMoneyStyle,
    );

    // 3. Shifts Breakdown Sheet
    final shiftsSheet = excel[shiftsSheetName];
    shiftsSheet.isRTL = true;
    _buildShiftsSheet(
      sheet: shiftsSheet,
      report: report,
      titleStyle: titleStyle,
      headerStyle: headerStyle,
      textStyle: textCellStyle,
      centerStyle: centerCellStyle,
      moneyStyle: moneyCellStyle,
      totalTextStyle: totalTextStyle,
      totalMoneyStyle: totalMoneyStyle,
    );

    // 4. Daily Breakdown Sheet
    final dailySheet = excel[dailySheetName];
    dailySheet.isRTL = true;
    _buildDailySheet(
      sheet: dailySheet,
      report: report,
      titleStyle: titleStyle,
      headerStyle: headerStyle,
      textStyle: textCellStyle,
      centerStyle: centerCellStyle,
      moneyStyle: moneyCellStyle,
      totalTextStyle: totalTextStyle,
      totalMoneyStyle: totalMoneyStyle,
    );

    // 5. Detailed Collections Sheet
    final detailsSheet = excel[detailsSheetName];
    detailsSheet.isRTL = true;
    _buildDetailsSheet(
      sheet: detailsSheet,
      report: report,
      titleStyle: titleStyle,
      headerStyle: headerStyle,
      textStyle: textCellStyle,
      centerStyle: centerCellStyle,
      moneyStyle: moneyCellStyle,
      totalTextStyle: totalTextStyle,
      totalMoneyStyle: totalMoneyStyle,
    );

    final journal = excel[dailyJournalSheetName];
    journal.isRTL = true;
    _buildDailyJournalSheet(
        sheet: journal,
        report: report,
        titleStyle: titleStyle,
        headerStyle: headerStyle,
        textStyle: textCellStyle,
        moneyStyle: moneyCellStyle,
        totalTextStyle: totalTextStyle,
        totalMoneyStyle: totalMoneyStyle);

    if (defaultSheet != null && defaultSheet != summarySheetName) {
      excel.delete(defaultSheet);
    }

    final initialBytes = excel.encode();
    if (initialBytes == null || initialBytes.isEmpty) {
      throw const RagaaException('تعذر إنشاء ملف Excel');
    }

    // Re-open to bind newly created sheet XML IDs so every worksheet writes
    // `<sheetView rightToLeft="1" workbookViewId="0"/>` cleanly in OOXML.
    final rtlWorkbook = Excel.decodeBytes(initialBytes);
    for (final name in rtlWorkbook.tables.keys) {
      rtlWorkbook[name].isRTL = true;
    }
    final finalBytes = rtlWorkbook.encode();
    if (finalBytes == null || finalBytes.isEmpty) {
      throw const RagaaException('تعذر حفظ اتجاه RTL في ملف Excel');
    }
    return Uint8List.fromList(finalBytes);
  }

  /// Writes the generated Arabic RTL `.xlsx` workbook directly to [outputPath].
  Future<File> exportReportToFile(ReportData report, String outputPath) async {
    final bytes = buildReportExcelBytes(report);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  void _setCell(
    Sheet sheet,
    int col,
    int row,
    CellValue value,
    CellStyle style,
  ) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = value;
    cell.cellStyle = style;
  }

  void _buildDailyJournalSheet(
      {required Sheet sheet,
      required ReportData report,
      required CellStyle titleStyle,
      required CellStyle headerStyle,
      required CellStyle textStyle,
      required CellStyle moneyStyle,
      required CellStyle totalTextStyle,
      required CellStyle totalMoneyStyle}) {
    const headers = [
      'المنفذ',
      'يدوي',
      'آلي',
      'إجمالي الرسوم',
      'الموازين',
      'NFC',
      'VISA',
      'الإجمالي العام'
    ];
    _setCell(
        sheet,
        0,
        0,
        TextCellValue(
            'يومية التحصيلات — ${report.filter.range.arabicDescription}'),
        titleStyle);
    for (var c = 1; c < headers.length; c++) {
      _setCell(sheet, c, 0, TextCellValue(''), titleStyle);
    }
    sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(
            columnIndex: headers.length - 1, rowIndex: 0));
    var r = 2;
    final yellow = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#FFF200'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        numberFormat: NumFormat.custom(formatCode: '#,##0.00'));
    for (final shift in [1, 2, 3]) {
      final rows = report.details.where((e) => e.shiftNumber == shift).toList();
      if (rows.isEmpty) continue;
      _setCell(sheet, 0, r, TextCellValue('الوردية $shift'), titleStyle);
      for (var c = 1; c < headers.length; c++) {
        _setCell(sheet, c, r, TextCellValue(''), titleStyle);
      }
      sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
          CellIndex.indexByColumnRow(
              columnIndex: headers.length - 1, rowIndex: r));
      r++;
      for (var c = 0; c < headers.length; c++) {
        _setCell(sheet, c, r, TextCellValue(headers[c]), headerStyle);
      }
      r++;
      final first = r + 1;
      for (final e in rows) {
        _setCell(sheet, 0, r, TextCellValue(e.outletName), textStyle);
        final vals = [
          e.manualFeesPiastres,
          e.automaticFeesPiastres,
          e.totalFeesPiastres,
          e.scalesTotalPiastres,
          e.nfcPiastres,
          e.visaPiastres,
          e.generalTotalPiastres
        ];
        for (var c = 0; c < vals.length; c++) {
          _setCell(sheet, c + 1, r, DoubleCellValue(piastresToUnits(vals[c])),
              moneyStyle);
        }
        r++;
      }
      _setCell(
          sheet, 0, r, TextCellValue('إجمالي الوردية'), totalTextStyle);
      for (var c = 1; c < headers.length; c++) {
        _setCell(
            sheet,
            c,
            r,
            FormulaCellValue(
                'SUM(${String.fromCharCode(65 + c)}$first:${String.fromCharCode(65 + c)}$r)'),
            yellow);
      }
      r += 2;
    }
    _setCell(sheet, 0, r, TextCellValue('الإجمالي العام لليوم'),
        totalTextStyle);
    for (var c = 1; c < headers.length; c++) {
      _setCell(
          sheet,
          c,
          r,
          FormulaCellValue(
              'SUM(${String.fromCharCode(65 + c)}1:${String.fromCharCode(65 + c)}$r)'),
          yellow);
      sheet.setColumnWidth(c, 16);
    }
    sheet.setColumnWidth(0, 24);
  }

  void _buildSummarySheet({
    required Sheet sheet,
    required ReportData report,
    required CellStyle titleStyle,
    required CellStyle labelStyle,
    required CellStyle textStyle,
    required CellStyle moneyStyle,
    required CellStyle totalMoneyStyle,
  }) {
    _setCell(
      sheet,
      0,
      0,
      TextCellValue('نظام رجاء لإدارة تحصيل المنافذ (RAGAA)'),
      titleStyle,
    );
    _setCell(sheet, 1, 0, TextCellValue(''), titleStyle);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0),
    );

    final metaRows = <(String, CellValue, CellStyle)>[
      (
        'نوع التقرير',
        TextCellValue(report.filter.range.type.arabicLabel),
        textStyle,
      ),
      (
        'وصف الفترة',
        TextCellValue(report.filter.range.arabicDescription),
        textStyle,
      ),
      ('من تاريخ', TextCellValue(report.filter.range.startKey), textStyle),
      ('إلى تاريخ', TextCellValue(report.filter.range.endKey), textStyle),
      (
        'عدد أيام الفترة',
        IntCellValue(report.filter.range.dayCount),
        textStyle,
      ),
      ('فلتر المنافذ', TextCellValue(report.outletsFilterLabel), textStyle),
      ('فلتر الوردية', TextCellValue(report.shiftFilterLabel), textStyle),
      (
        'تاريخ استخراج التقرير',
        TextCellValue(formatTimestamp(report.generatedAt)),
        textStyle,
      ),
      (
        'إجمالي التحصيل (ج.م)',
        DoubleCellValue(piastresToUnits(report.grandTotalPiastres)),
        totalMoneyStyle,
      ),
      (
        'إجمالي التحصيل (بالقروش)',
        IntCellValue(report.grandTotalPiastres),
        textStyle,
      ),
      (
        'عدد سجلات التحصيل',
        IntCellValue(report.totalEntries),
        textStyle,
      ),
      (
        'عدد الأيام النشطة',
        IntCellValue(report.activeDaysCount),
        textStyle,
      ),
      (
        'متوسط اليوم التشغيلي (ج.م)',
        DoubleCellValue(piastresToUnits(report.dailyAveragePiastres)),
        moneyStyle,
      ),
      (
        'متوسط الوردية الواحدة (ج.م)',
        DoubleCellValue(piastresToUnits(report.shiftAveragePiastres)),
        moneyStyle,
      ),
      (
        'عدد السجلات المعدّلة',
        IntCellValue(report.modifiedEntriesCount),
        textStyle,
      ),
    ];

    for (var i = 0; i < metaRows.length; i++) {
      final rowIdx = i + 2;
      _setCell(sheet, 0, rowIdx, TextCellValue(metaRows[i].$1), labelStyle);
      _setCell(sheet, 1, rowIdx, metaRows[i].$2, metaRows[i].$3);
    }

    sheet.setColumnWidth(0, 28);
    sheet.setColumnWidth(1, 42);
  }

  void _buildOutletsSheet({
    required Sheet sheet,
    required ReportData report,
    required CellStyle titleStyle,
    required CellStyle headerStyle,
    required CellStyle textStyle,
    required CellStyle centerStyle,
    required CellStyle moneyStyle,
    required CellStyle totalTextStyle,
    required CellStyle totalMoneyStyle,
  }) {
    final headers = [
      'المنفذ',
      'الحالة',
      'عدد الورديات المعتمد',
      'الوردية الأولى (ج.م)',
      'الوردية الثانية (ج.م)',
      'الوردية الثالثة (ج.م)',
      'عدد السجلات',
      'إجمالي التحصيل (ج.م)',
      'النسبة المئوية',
    ];

    _setCell(
      sheet,
      0,
      0,
      TextCellValue(
          'ملخص التحصيل حسب المنفذ — ${report.filter.range.arabicDescription}'),
      titleStyle,
    );
    for (var c = 1; c < headers.length; c++) {
      _setCell(sheet, c, 0, TextCellValue(''), titleStyle);
    }
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: 0),
    );

    for (var c = 0; c < headers.length; c++) {
      _setCell(sheet, c, 2, TextCellValue(headers[c]), headerStyle);
    }

    var r = 3;
    for (final row in report.byOutlet) {
      _setCell(sheet, 0, r, TextCellValue(row.outletName), textStyle);
      _setCell(
        sheet,
        1,
        r,
        TextCellValue(row.isActive ? 'نشط' : 'متوقف'),
        centerStyle,
      );
      _setCell(
        sheet,
        2,
        r,
        IntCellValue(row.configuredShiftCount),
        centerStyle,
      );
      _setCell(
        sheet,
        3,
        r,
        DoubleCellValue(piastresToUnits(row.shift1Piastres)),
        moneyStyle,
      );
      _setCell(
        sheet,
        4,
        r,
        DoubleCellValue(piastresToUnits(row.shift2Piastres)),
        moneyStyle,
      );
      _setCell(
        sheet,
        5,
        r,
        DoubleCellValue(piastresToUnits(row.shift3Piastres)),
        moneyStyle,
      );
      _setCell(
        sheet,
        6,
        r,
        IntCellValue(row.recordedShiftsCount),
        centerStyle,
      );
      _setCell(
        sheet,
        7,
        r,
        DoubleCellValue(piastresToUnits(row.totalPiastres)),
        moneyStyle,
      );
      _setCell(
        sheet,
        8,
        r,
        TextCellValue(
          '${(row.shareOf(report.grandTotalPiastres) * 100).toStringAsFixed(1)}%',
        ),
        centerStyle,
      );
      r++;
    }

    // Totals row
    final totalS1 = report.byOutlet.fold(0, (s, e) => s + e.shift1Piastres);
    final totalS2 = report.byOutlet.fold(0, (s, e) => s + e.shift2Piastres);
    final totalS3 = report.byOutlet.fold(0, (s, e) => s + e.shift3Piastres);
    _setCell(sheet, 0, r, TextCellValue('الإجمالي الكلي'), totalTextStyle);
    _setCell(
      sheet,
      1,
      r,
      TextCellValue('${report.byOutlet.length} منفذ'),
      totalTextStyle,
    );
    _setCell(sheet, 2, r, TextCellValue('-'), totalTextStyle);
    _setCell(
      sheet,
      3,
      r,
      DoubleCellValue(piastresToUnits(totalS1)),
      totalMoneyStyle,
    );
    _setCell(
      sheet,
      4,
      r,
      DoubleCellValue(piastresToUnits(totalS2)),
      totalMoneyStyle,
    );
    _setCell(
      sheet,
      5,
      r,
      DoubleCellValue(piastresToUnits(totalS3)),
      totalMoneyStyle,
    );
    _setCell(sheet, 6, r, IntCellValue(report.totalEntries), totalTextStyle);
    _setCell(
      sheet,
      7,
      r,
      DoubleCellValue(piastresToUnits(report.grandTotalPiastres)),
      totalMoneyStyle,
    );
    _setCell(
      sheet,
      8,
      r,
      TextCellValue(report.grandTotalPiastres > 0 ? '100.0%' : '0.0%'),
      totalTextStyle,
    );

    const widths = [26.0, 12.0, 20.0, 20.0, 20.0, 20.0, 14.0, 22.0, 15.0];
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }
  }

  void _buildShiftsSheet({
    required Sheet sheet,
    required ReportData report,
    required CellStyle titleStyle,
    required CellStyle headerStyle,
    required CellStyle textStyle,
    required CellStyle centerStyle,
    required CellStyle moneyStyle,
    required CellStyle totalTextStyle,
    required CellStyle totalMoneyStyle,
  }) {
    const headers = [
      'الوردية',
      'عدد السجلات',
      'متوسط الوردية (ج.م)',
      'إجمالي التحصيل (ج.م)',
      'النسبة المئوية',
    ];

    _setCell(
      sheet,
      0,
      0,
      TextCellValue(
          'ملخص التحصيل حسب الوردية — ${report.filter.range.arabicDescription}'),
      titleStyle,
    );
    for (var c = 1; c < headers.length; c++) {
      _setCell(sheet, c, 0, TextCellValue(''), titleStyle);
    }
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: 0),
    );

    for (var c = 0; c < headers.length; c++) {
      _setCell(sheet, c, 2, TextCellValue(headers[c]), headerStyle);
    }

    var r = 3;
    for (final s in report.byShift) {
      _setCell(sheet, 0, r, TextCellValue(s.shiftLabel), textStyle);
      _setCell(sheet, 1, r, IntCellValue(s.entriesCount), centerStyle);
      _setCell(
        sheet,
        2,
        r,
        DoubleCellValue(piastresToUnits(s.averagePiastres)),
        moneyStyle,
      );
      _setCell(
        sheet,
        3,
        r,
        DoubleCellValue(piastresToUnits(s.totalPiastres)),
        moneyStyle,
      );
      _setCell(
        sheet,
        4,
        r,
        TextCellValue(
          '${(s.shareOf(report.grandTotalPiastres) * 100).toStringAsFixed(1)}%',
        ),
        centerStyle,
      );
      r++;
    }

    _setCell(sheet, 0, r, TextCellValue('الإجمالي الكلي'), totalTextStyle);
    _setCell(sheet, 1, r, IntCellValue(report.totalEntries), totalTextStyle);
    _setCell(
      sheet,
      2,
      r,
      DoubleCellValue(piastresToUnits(report.shiftAveragePiastres)),
      totalMoneyStyle,
    );
    _setCell(
      sheet,
      3,
      r,
      DoubleCellValue(piastresToUnits(report.grandTotalPiastres)),
      totalMoneyStyle,
    );
    _setCell(
      sheet,
      4,
      r,
      TextCellValue(report.grandTotalPiastres > 0 ? '100.0%' : '0.0%'),
      totalTextStyle,
    );

    const widths = [22.0, 16.0, 22.0, 24.0, 16.0];
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }
  }

  void _buildDailySheet({
    required Sheet sheet,
    required ReportData report,
    required CellStyle titleStyle,
    required CellStyle headerStyle,
    required CellStyle textStyle,
    required CellStyle centerStyle,
    required CellStyle moneyStyle,
    required CellStyle totalTextStyle,
    required CellStyle totalMoneyStyle,
  }) {
    const headers = [
      'التاريخ التشغيلي',
      'اليوم',
      'الوردية الأولى (ج.م)',
      'الوردية الثانية (ج.م)',
      'الوردية الثالثة (ج.م)',
      'عدد السجلات',
      'إجمالي اليوم (ج.م)',
    ];

    _setCell(
      sheet,
      0,
      0,
      TextCellValue(
          'التجميع اليومي للتحصيل — ${report.filter.range.arabicDescription}'),
      titleStyle,
    );
    for (var c = 1; c < headers.length; c++) {
      _setCell(sheet, c, 0, TextCellValue(''), titleStyle);
    }
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: 0),
    );

    for (var c = 0; c < headers.length; c++) {
      _setCell(sheet, c, 2, TextCellValue(headers[c]), headerStyle);
    }

    var r = 3;
    for (final d in report.byDay) {
      _setCell(sheet, 0, r, TextCellValue(d.operationalDate), centerStyle);
      _setCell(sheet, 1, r, TextCellValue(d.weekdayLabel), textStyle);
      _setCell(
        sheet,
        2,
        r,
        DoubleCellValue(piastresToUnits(d.shift1Piastres)),
        moneyStyle,
      );
      _setCell(
        sheet,
        3,
        r,
        DoubleCellValue(piastresToUnits(d.shift2Piastres)),
        moneyStyle,
      );
      _setCell(
        sheet,
        4,
        r,
        DoubleCellValue(piastresToUnits(d.shift3Piastres)),
        moneyStyle,
      );
      _setCell(sheet, 5, r, IntCellValue(d.entriesCount), centerStyle);
      _setCell(
        sheet,
        6,
        r,
        DoubleCellValue(piastresToUnits(d.totalPiastres)),
        moneyStyle,
      );
      r++;
    }

    final totalS1 = report.byDay.fold(0, (s, d) => s + d.shift1Piastres);
    final totalS2 = report.byDay.fold(0, (s, d) => s + d.shift2Piastres);
    final totalS3 = report.byDay.fold(0, (s, d) => s + d.shift3Piastres);
    _setCell(sheet, 0, r, TextCellValue('الإجمالي الكلي'), totalTextStyle);
    _setCell(
      sheet,
      1,
      r,
      TextCellValue('${report.byDay.length} يوم'),
      totalTextStyle,
    );
    _setCell(
      sheet,
      2,
      r,
      DoubleCellValue(piastresToUnits(totalS1)),
      totalMoneyStyle,
    );
    _setCell(
      sheet,
      3,
      r,
      DoubleCellValue(piastresToUnits(totalS2)),
      totalMoneyStyle,
    );
    _setCell(
      sheet,
      4,
      r,
      DoubleCellValue(piastresToUnits(totalS3)),
      totalMoneyStyle,
    );
    _setCell(sheet, 5, r, IntCellValue(report.totalEntries), totalTextStyle);
    _setCell(
      sheet,
      6,
      r,
      DoubleCellValue(piastresToUnits(report.grandTotalPiastres)),
      totalMoneyStyle,
    );

    const widths = [18.0, 14.0, 20.0, 20.0, 20.0, 14.0, 22.0];
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }
  }

  void _buildDetailsSheet({
    required Sheet sheet,
    required ReportData report,
    required CellStyle titleStyle,
    required CellStyle headerStyle,
    required CellStyle textStyle,
    required CellStyle centerStyle,
    required CellStyle moneyStyle,
    required CellStyle totalTextStyle,
    required CellStyle totalMoneyStyle,
  }) {
    const headers = [
      'رقم السجل',
      'التاريخ التشغيلي',
      'المنفذ',
      'رقم الوردية',
      'مسمى الوردية',
      'موعد الوردية',
      'المبلغ (ج.م)',
      'الحالة',
      'ملاحظات',
      'آخر تحديث',
    ];

    _setCell(
      sheet,
      0,
      0,
      TextCellValue(
          'تفاصيل سجلات التحصيل — ${report.filter.range.arabicDescription}'),
      titleStyle,
    );
    for (var c = 1; c < headers.length; c++) {
      _setCell(sheet, c, 0, TextCellValue(''), titleStyle);
    }
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: headers.length - 1, rowIndex: 0),
    );

    for (var c = 0; c < headers.length; c++) {
      _setCell(sheet, c, 2, TextCellValue(headers[c]), headerStyle);
    }

    var r = 3;
    for (final item in report.details) {
      _setCell(sheet, 0, r, IntCellValue(item.id), centerStyle);
      _setCell(sheet, 1, r, TextCellValue(item.operationalDate), centerStyle);
      _setCell(sheet, 2, r, TextCellValue(item.outletName), textStyle);
      _setCell(sheet, 3, r, IntCellValue(item.shiftNumber), centerStyle);
      _setCell(sheet, 4, r, TextCellValue(item.shiftTitle), textStyle);
      _setCell(
        sheet,
        5,
        r,
        TextCellValue(item.shiftScheduleDisplay),
        centerStyle,
      );
      _setCell(
        sheet,
        6,
        r,
        DoubleCellValue(piastresToUnits(item.amountPiastres)),
        moneyStyle,
      );
      _setCell(
        sheet,
        7,
        r,
        TextCellValue(
          item.wasModified ? 'معدّل (نسخة ${item.revision})' : 'أصلي',
        ),
        centerStyle,
      );
      _setCell(sheet, 8, r, TextCellValue(item.notes), textStyle);
      _setCell(
        sheet,
        9,
        r,
        TextCellValue(formatTimestamp(item.updatedAt)),
        centerStyle,
      );
      r++;
    }

    _setCell(sheet, 0, r, TextCellValue('الإجمالي'), totalTextStyle);
    _setCell(
      sheet,
      1,
      r,
      TextCellValue('${report.totalEntries} سجل'),
      totalTextStyle,
    );
    for (var c = 2; c <= 5; c++) {
      _setCell(sheet, c, r, TextCellValue(''), totalTextStyle);
    }
    _setCell(
      sheet,
      6,
      r,
      DoubleCellValue(piastresToUnits(report.grandTotalPiastres)),
      totalMoneyStyle,
    );
    for (var c = 7; c < headers.length; c++) {
      _setCell(sheet, c, r, TextCellValue(''), totalTextStyle);
    }

    const widths = [
      12.0,
      18.0,
      24.0,
      13.0,
      18.0,
      18.0,
      20.0,
      16.0,
      28.0,
      20.0,
    ];
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }
  }
}
