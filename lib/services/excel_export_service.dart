import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../core/exceptions.dart';
import '../core/formatters.dart';
import '../models/daily_journal.dart';
import '../models/report_models.dart';
import 'xlsx_print_setup.dart';

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

    // 6. Daily journal sheet (single-day reports mirror the paper form exactly).
    if (report.filter.range.startKey == report.filter.range.endKey) {
      final journalSheet = excel[dailyJournalSheetName];
      journalSheet.isRTL = true;
      _buildJournalSheet(
        sheet: journalSheet,
        journal: DailyJournal.fromReport(report),
      );
    }

    if (defaultSheet != null && defaultSheet != summarySheetName) {
      excel.delete(defaultSheet);
    }

    return _finalizeWorkbook(excel);
  }

  /// Builds a standalone `.xlsx` workbook that contains only the daily journal
  /// sheet, formatted exactly like the PDF journal.
  Uint8List buildJournalExcelBytes(DailyJournal journal) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();

    final sheet = excel[dailyJournalSheetName];
    sheet.isRTL = true;
    _buildJournalSheet(sheet: sheet, journal: journal);

    if (defaultSheet != null) {
      excel.delete(defaultSheet);
    }
    return _finalizeWorkbook(excel);
  }

  /// Writes the standalone journal workbook to [outputPath].
  Future<File> exportJournalToFile(
    DailyJournal journal,
    String outputPath,
  ) async {
    final bytes = buildJournalExcelBytes(journal);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Encodes the workbook, forces RTL on every sheet and applies the printable
  /// page setup (landscape, fit-to-width, frozen header, print area) to the
  /// journal sheet.
  Uint8List _finalizeWorkbook(Excel excel) {
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
    var encoded = Uint8List.fromList(finalBytes);

    // Formulas are written without cached results, so ask the spreadsheet app
    // to recalculate everything when the file is opened.
    final recalc = XlsxPrintSetup.ensureFullRecalc(encoded);
    if (recalc.applied && _decodesCleanly(recalc.bytes)) {
      encoded = recalc.bytes;
    }

    // Give every sheet a print-ready page setup (landscape, fit-to-width,
    // frozen header rows, repeating header and an explicit print area) so the
    // workbook prints exactly like the PDF.
    final patched = XlsxPrintSetup.applyAll(encoded);
    if (patched.applied && _decodesCleanly(patched.bytes)) {
      return patched.bytes;
    }
    return encoded;
  }

  /// Safety net: never ship a workbook we cannot read back.
  bool _decodesCleanly(Uint8List bytes) {
    try {
      Excel.decodeBytes(bytes);
      return true;
    } catch (_) {
      return false;
    }
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

  // ---------------------------------------------------------------------------
  // Daily journal (اليومية) — mirrors the paper form and the PDF export
  // ---------------------------------------------------------------------------

  /// Column headers of the daily journal, in logical (right-to-left) order.
  static const List<String> journalHeaders = <String>[
    'البيان',
    'الرسوم اليدوية',
    'الرسوم الآلية',
    'إجمالي الرسوم',
    'إجمالي الموازين',
    'NFC',
    'VISA',
    'الإجمالي العام',
  ];

  static final CellStyle _journalHeaderStyle = CellStyle(
    bold: true,
    fontSize: 10,
    
    
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    leftBorder: _journalBorder,
    rightBorder: _journalBorder,
    topBorder: _journalBorder,
    bottomBorder: _journalBorder,
  );

  static final CellStyle _journalMoneyStyle = CellStyle(
    fontSize: 10,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    numberFormat: NumFormat.custom(formatCode: '#,##0.00'),
    leftBorder: _journalBorder,
    rightBorder: _journalBorder,
    topBorder: _journalBorder,
    bottomBorder: _journalBorder,
  );

  static final CellStyle _journalLabelStyle = CellStyle(
    fontSize: 10,
    horizontalAlign: HorizontalAlign.Right,
    verticalAlign: VerticalAlign.Center,
    leftBorder: _journalBorder,
    rightBorder: _journalBorder,
    topBorder: _journalBorder,
    bottomBorder: _journalBorder,
  );

  static final CellStyle _journalScalesStyle = CellStyle(
    fontSize: 10,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    backgroundColorHex: ExcelColor.fromHexString('#DDC19B'),
    numberFormat: NumFormat.custom(formatCode: '#,##0.00'),
    leftBorder: _journalBorder,
    rightBorder: _journalBorder,
    topBorder: _journalBorder,
    bottomBorder: _journalBorder,
  );

  static final CellStyle _journalBandStyle = CellStyle(
    bold: true,
    fontSize: 10,
    fontColorHex: ExcelColor.fromHexString('#111111'),
    backgroundColorHex: ExcelColor.fromHexString('#F2F0EE'),
    horizontalAlign: HorizontalAlign.Right,
    verticalAlign: VerticalAlign.Center,
    leftBorder: _journalBorder,
    rightBorder: _journalBorder,
    topBorder: _journalBorder,
    bottomBorder: _journalBorder,
  );

  static final CellStyle _journalShiftTotalMoneyStyle = CellStyle(
    bold: true,
    fontSize: 10,
    backgroundColorHex: ExcelColor.fromHexString('#FFEB35'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    numberFormat: NumFormat.custom(formatCode: '#,##0.00'),
    leftBorder: _journalBorder,
    rightBorder: _journalBorder,
    topBorder: _journalBorder,
    bottomBorder: _journalBorder,
  );

  static final CellStyle _journalDayTotalLabelStyle = CellStyle(
    bold: true,
    fontSize: 10,
    backgroundColorHex: ExcelColor.fromHexString('#E2DAE9'),
    horizontalAlign: HorizontalAlign.Right,
    verticalAlign: VerticalAlign.Center,
    leftBorder: _journalBorder,
    rightBorder: _journalBorder,
    topBorder: _journalBorder,
    bottomBorder: _journalBorder,
  );

  static final CellStyle _journalDayTotalMoneyStyle = CellStyle(
    bold: true,
    fontSize: 10,
    backgroundColorHex: ExcelColor.fromHexString('#E2DAE9'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    numberFormat: NumFormat.custom(formatCode: '#,##0.00'),
    leftBorder: _journalBorder,
    rightBorder: _journalBorder,
    topBorder: _journalBorder,
    bottomBorder: _journalBorder,
  );

  static final CellStyle _journalTitleStyle = CellStyle(
    bold: true,
    fontSize: 14,
    
    
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );

  static final CellStyle _greenStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    fontSize: 10,
    backgroundColorHex: ExcelColor.fromHexString('#38743A'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    numberFormat: NumFormat.custom(formatCode: '#,##0.00'),
    leftBorder: _journalBorder,
    rightBorder: _journalBorder,
    topBorder: _journalBorder,
    bottomBorder: _journalBorder,
  );

  static final Border _journalBorder = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.fromHexString('#1F2937'),
  );

  /// Writes the journal sheet and returns the index of its last used row.
  int _buildJournalSheet({
    required Sheet sheet,
    required DailyJournal journal,
  }) {
    var row = 0;

    void merge(int left, int top, int right, int bottom) {
      if (left == right && top == bottom) return;
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: left, rowIndex: top),
        CellIndex.indexByColumnRow(columnIndex: right, rowIndex: bottom),
      );
    }

    merge(0, 0, 8, 0);
    _setCell(sheet, 0, 0, TextCellValue('${journal.title} ${journal.headerLine}'),
        _journalTitleStyle);
    sheet.setRowHeight(0, 23);
    for (final col in [0, 3, 4, 5, 6, 7]) {
      merge(col, 1, col == 7 ? 8 : col, 2);
      _setCell(sheet, col, 1, TextCellValue(col == 7 ? 'إجمالي عام' : journalHeaders[col]),
          _journalHeaderStyle);
    }
    merge(1, 1, 2, 1);
    _setCell(sheet, 1, 1, TextCellValue('رسوم'), _journalHeaderStyle);
    _setCell(sheet, 1, 2, TextCellValue('يدوي'), _journalHeaderStyle);
    _setCell(sheet, 2, 2, TextCellValue('آلي'), _journalHeaderStyle);
    row = 3;

    final outletRows = <String, List<int>>{};

    for (final section in journal.sections) {
      // Shift band.
      _setCell(
        sheet,
        0,
        row,
        TextCellValue(defaultShiftLabel(section.shiftNumber)),
        _journalBandStyle,
      );
      for (var column = 1; column < journalHeaders.length; column++) {
        _setCell(sheet, column, row, TextCellValue(''), _journalBandStyle);
      }
      _mergeRow(sheet, row, 8);
      row++;

      final firstDataRow = row;
      for (final journalRow in section.rows) {
        _setCell(
          sheet,
          0,
          row,
          TextCellValue(journalRow.outletName),
          _journalLabelStyle,
        );
        if (journalRow.hasRecord) {
          final amounts = journalRow.amounts;
          _setCell(sheet, 1, row,
              DoubleCellValue(piastresToUnits(amounts.manualFeesPiastres)),
              _journalMoneyStyle);
          _setCell(sheet, 2, row,
              DoubleCellValue(piastresToUnits(amounts.automaticFeesPiastres)),
              _journalMoneyStyle);
          _setCell(sheet, 3, row,
              DoubleCellValue(piastresToUnits(amounts.totalFeesPiastres)),
              _journalMoneyStyle);
          // Real Excel formula: الإجمالي العام − إجمالي الرسوم
          _setCell(
            sheet,
            4,
            row,
            FormulaCellValue('H${row + 1}-D${row + 1}'),
            _journalScalesStyle,
          );
          _setCell(sheet, 5, row,
              DoubleCellValue(piastresToUnits(amounts.nfcPiastres)),
              _journalMoneyStyle);
          _setCell(sheet, 6, row,
              DoubleCellValue(piastresToUnits(amounts.visaPiastres)),
              _journalMoneyStyle);
          _setCell(sheet, 7, row,
              DoubleCellValue(piastresToUnits(amounts.generalTotalPiastres)),
              _journalMoneyStyle);
        } else {
          for (var column = 1; column < journalHeaders.length; column++) {
            _setCell(sheet, column, row, TextCellValue(''),
                column == 4 ? _journalScalesStyle : _journalMoneyStyle);
          }
        }
        if (row - firstDataRow >= section.greenRowCount) merge(7, row, 8, row);
        outletRows.putIfAbsent(journalRow.outletId, () => <int>[]).add(row);
        row++;
      }

      final end = firstDataRow + section.greenRowCount;
      if (end > firstDataRow) {
        merge(8, firstDataRow, 8, end - 1);
        _setCell(sheet, 8, firstDataRow,
            FormulaCellValue('SUM(H${firstDataRow + 1}:H$end)'), _greenStyle);
      }
      merge(7, row, 8, row);
      // Yellow shift total row built with SUM formulas.
      _setCell(
        sheet,
        0,
        row,
        TextCellValue('إجمالي ${defaultShiftLabel(section.shiftNumber)}'),
        _journalDayTotalLabelStyle,
      );
      for (var column = 1; column < journalHeaders.length; column++) {
        final letter = _columnLetter(column);
        _setCell(
          sheet,
          column,
          row,
          FormulaCellValue(
            'SUM($letter${firstDataRow + 1}:$letter$row)',
          ),
          column == 7 ? _journalShiftTotalMoneyStyle : _journalDayTotalMoneyStyle,
        );
      }
      row++;
    }

    // Section 6 — «إجمالي اليوم لكل منفذ» (mandatory, one row per outlet).
    _setCell(
      sheet,
      0,
      row,
      TextCellValue('إجمالي اليوم'),
      _journalBandStyle,
    );
    for (var column = 1; column < journalHeaders.length; column++) {
      _setCell(sheet, column, row, TextCellValue(''), _journalBandStyle);
    }
    _mergeRow(sheet, row, 8);
    row++;

    final firstDayTotalRow = row;
    for (final total in journal.outletDayTotals) {
      merge(7, row, 8, row);
      _setCell(
        sheet,
        0,
        row,
        TextCellValue(total.outletName),
        _journalLabelStyle,
      );
      final rowsForOutlet = outletRows[total.outletId] ?? const <int>[];
      for (var column = 1; column < journalHeaders.length; column++) {
        final letter = _columnLetter(column);
        final references = rowsForOutlet
            .map((dataRow) => '$letter${dataRow + 1}')
            .join(',');
        _setCell(
          sheet,
          column,
          row,
          references.isEmpty
              ? const IntCellValue(0)
              : FormulaCellValue('SUM($references)'),
          column == 4 ? _journalScalesStyle : _journalMoneyStyle,
        );
      }
      row++;
    }

    // Section 7 — «الإجمالي العام لليوم»: sum of the independent outlet totals.
    merge(7, row, 8, row);
    final lastDayTotalRow = row - 1;
    _setCell(
      sheet,
      0,
      row,
      TextCellValue('الإجمالي العام لليوم'),
      _journalDayTotalLabelStyle,
    );
    for (var column = 1; column < journalHeaders.length; column++) {
      final letter = _columnLetter(column);
      _setCell(
        sheet,
        column,
        row,
        journal.outletDayTotals.isEmpty ? const IntCellValue(0) : FormulaCellValue(
          'SUM($letter${firstDayTotalRow + 1}:$letter${lastDayTotalRow + 1})',
        ),
        column == 7 ? _journalShiftTotalMoneyStyle : _journalDayTotalMoneyStyle,
      );
    }
    final lastRow = row;

    for (var r = 3; r <= row; r++) {
      sheet.setRowHeight(r, 17);
    }
    const widths = <double>[24, 15, 15, 19, 19, 15, 15, 14, 11];
    for (var index = 0; index < widths.length; index++) {
      sheet.setColumnWidth(index, widths[index]);
    }
    return lastRow;
  }

  void _mergeRow(Sheet sheet, int rowIndex, int lastColumn) {
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
      CellIndex.indexByColumnRow(
        columnIndex: lastColumn,
        rowIndex: rowIndex,
      ),
    );
  }

  static String _columnLetter(int index) {
    var current = index;
    final letters = StringBuffer();
    while (current >= 0) {
      letters.write(String.fromCharCode(65 + (current % 26)));
      current = (current ~/ 26) - 1;
    }
    return letters.toString().split('').reversed.join();
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
    // Every approved financial field is exported as a real numeric column.
    const headers = [
      'رقم السجل',
      'التاريخ التشغيلي',
      'المنفذ',
      'رقم الوردية',
      'مسمى الوردية',
      'موعد الوردية',
      'الرسوم اليدوية',
      'الرسوم الآلية',
      'إجمالي الرسوم',
      'إجمالي الموازين',
      'NFC',
      'VISA',
      'الإجمالي العام',
      'الحالة',
      'ملاحظات',
      'آخر تحديث',
    ];
    const firstMoneyColumn = 6;
    const lastMoneyColumn = 12;

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
    final firstDataRow = r;
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
      _setCell(sheet, 6, r,
          DoubleCellValue(piastresToUnits(item.manualFeesPiastres)), moneyStyle);
      _setCell(
        sheet,
        7,
        r,
        DoubleCellValue(piastresToUnits(item.automaticFeesPiastres)),
        moneyStyle,
      );
      _setCell(sheet, 8, r,
          DoubleCellValue(piastresToUnits(item.totalFeesPiastres)), moneyStyle);
      _setCell(
        sheet,
        9,
        r,
        // Computed column: الإجمالي العام − إجمالي الرسوم.
        FormulaCellValue('M${r + 1}-I${r + 1}'),
        moneyStyle,
      );
      _setCell(sheet, 10, r,
          DoubleCellValue(piastresToUnits(item.nfcPiastres)), moneyStyle);
      _setCell(sheet, 11, r,
          DoubleCellValue(piastresToUnits(item.visaPiastres)), moneyStyle);
      _setCell(
        sheet,
        12,
        r,
        DoubleCellValue(piastresToUnits(item.generalTotalPiastres)),
        moneyStyle,
      );
      _setCell(
        sheet,
        13,
        r,
        TextCellValue(
          item.wasModified ? 'معدّل (نسخة ${item.revision})' : 'أصلي',
        ),
        centerStyle,
      );
      _setCell(sheet, 14, r, TextCellValue(item.notes), textStyle);
      _setCell(
        sheet,
        15,
        r,
        TextCellValue(formatTimestamp(item.updatedAt)),
        centerStyle,
      );
      r++;
    }

    _setCell(sheet, 0, r, TextCellValue('الإجمالي'), totalTextStyle);
    _setCell(sheet, 1, r, IntCellValue(report.totalEntries), totalTextStyle);
    for (var c = 2; c < firstMoneyColumn; c++) {
      _setCell(sheet, c, r, TextCellValue(''), totalTextStyle);
    }
    for (var c = firstMoneyColumn; c <= lastMoneyColumn; c++) {
      final letter = _columnLetter(c);
      _setCell(
        sheet,
        c,
        r,
        report.details.isEmpty
            ? DoubleCellValue(0)
            : FormulaCellValue(
                // r is the 0-based totals row index; its Excel row number is
                // exactly the last data row number, hence the range below.
                'SUM($letter${firstDataRow + 1}:$letter$r)',
              ),
        totalMoneyStyle,
      );
    }
    for (var c = lastMoneyColumn + 1; c < headers.length; c++) {
      _setCell(sheet, c, r, TextCellValue(''), totalTextStyle);
    }

    const widths = <double>[
      12,
      18,
      24,
      13,
      18,
      18,
      18,
      18,
      18,
      20,
      14,
      14,
      20,
      16,
      28,
      20,
    ];
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }
  }
}
