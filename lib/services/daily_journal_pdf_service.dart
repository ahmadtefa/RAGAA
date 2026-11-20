import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formatters.dart';
import '../models/daily_journal.dart';

/// Renders the daily journal as a print-ready, right-to-left A4 landscape PDF
/// that mirrors the real paper form used at the collection office.
///
/// Design rules taken from the paper form:
/// - title + weekday + Gregorian date header;
/// - RTL column order: البيان | الرسوم اليدوية | الرسوم الآلية | إجمالي الرسوم |
///   إجمالي الموازين | NFC | VISA | الإجمالي العام;
/// - one block per shift followed by its yellow «إجمالي الوردية» row;
/// - a mandatory «إجمالي اليوم لكل منفذ» block (one independent row per outlet);
/// - a brown-tinted «إجمالي الموازين» column and purple total rows.
///
/// Excluded deliberately: the green grouping of the first five outlets,
/// «مسلم الإداري», «مسلم الرقابة», «المتبقي» and the cash hand-over columns.
///
/// Layout safety: every column has a fixed width, the column header row is a
/// repeating row of the table (`TableRow.repeat`), and the table is allowed to
/// span as many pages as needed, so extra outlets or shifts never clip data.
class DailyJournalPdfService {
  pw.Font? _regularFont;
  pw.Font? _boldFont;

  // ---------------------------------------------------------------------------
  // Palette (kept close to the printed form)
  // ---------------------------------------------------------------------------
  static const PdfColor _headerBg = PdfColor.fromInt(0xFF0F5C54);
  static const PdfColor _headerText = PdfColors.white;
  static const PdfColor _border = PdfColor.fromInt(0xFF1F2937);
  static const PdfColor _ink = PdfColor.fromInt(0xFF111827);
  static const PdfColor _muted = PdfColor.fromInt(0xFF475569);
  static const PdfColor _bandBg = PdfColor.fromInt(0xFFE3EFEC);
  static const PdfColor _yellow = PdfColor.fromInt(0xFFF7EC00);
  static const PdfColor _purple = PdfColor.fromInt(0xFFE2D9EC);
  static const PdfColor _scalesCell = PdfColor.fromInt(0xFFD9BE8A);

  static const double _nameColumnWidth = 190;
  static const double _horizontalMargin = 14;
  static const double _verticalMargin = 14;

  static const List<String> _columnHeaders = <String>[
    'البيان',
    'الرسوم اليدوية',
    'الرسوم الآلية',
    'إجمالي الرسوم',
    'إجمالي الموازين',
    'NFC',
    'VISA',
    'الإجمالي العام',
  ];

  Future<(pw.Font regular, pw.Font bold)> _loadFonts() async {
    if (_regularFont != null && _boldFont != null) {
      return (_regularFont!, _boldFont!);
    }
    final regularData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Amiri-Bold.ttf');
    _regularFont = pw.Font.ttf(regularData);
    _boldFont = pw.Font.ttf(boldData);
    return (_regularFont!, _boldFont!);
  }

  /// Portrait/landscape aware page format used for the journal.
  static PdfPageFormat get pageFormat => PdfPageFormat.a4.landscape;

  /// Generates the journal PDF bytes.
  Future<Uint8List> buildJournalPdfBytes(DailyJournal journal) async {
    final (regularFont, boldFont) = await _loadFonts();

    final doc = pw.Document(
      title: '${journal.title} — ${journal.operationalDate}',
      author: 'RAGAA',
      creator: 'RAGAA',
      subject: 'يومية التحصيل الإلكترونية',
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(
          horizontal: _horizontalMargin,
          vertical: _verticalMargin,
        ),
        textDirection: pw.TextDirection.rtl,
        header: (context) => _buildPageHeader(context, journal),
        footer: _buildPageFooter,
        build: (context) => <pw.Widget>[_buildJournalTable(journal)],
      ),
    );

    return doc.save();
  }

  /// Writes the journal PDF to [outputPath].
  Future<File> exportJournalToFile(
    DailyJournal journal,
    String outputPath,
  ) async {
    final bytes = await buildJournalPdfBytes(journal);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  // ---------------------------------------------------------------------------
  // Page chrome
  // ---------------------------------------------------------------------------

  pw.Widget _buildPageHeader(pw.Context context, DailyJournal journal) {
    final isFirstPage = context.pageNumber == 1;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.only(bottom: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _headerBg, width: 1.4),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                journal.title,
                style: pw.TextStyle(
                  fontSize: isFirstPage ? 16 : 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _headerBg,
                ),
              ),
              if (isFirstPage)
                pw.Text(
                  journal.headerLine,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                )
              else
                pw.Text(
                  'تكملة — ${journal.headerLine}',
                  style: const pw.TextStyle(fontSize: 9, color: _muted),
                ),
              pw.Text(
                isFirstPage
                    ? 'تاريخ الطباعة: ${formatTimestamp(journal.generatedAt)}'
                    : 'صفحة ${context.pageNumber}',
                style: const pw.TextStyle(fontSize: 8.5, color: _muted),
              ),
            ],
          ),
          if (isFirstPage) ...[
            pw.SizedBox(height: 3),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'المنافذ: ${journal.outletsFilterLabel} (${journal.outletCount} منفذ)',
                  style: const pw.TextStyle(fontSize: 8.5, color: _muted),
                ),
                pw.Text(
                  'الورديات المفعّلة: ${journal.configuredShiftCount}',
                  style: const pw.TextStyle(fontSize: 8.5, color: _muted),
                ),
                pw.Text(
                  'الورديات المسجّلة: ${journal.recordedShiftsCount}',
                  style: const pw.TextStyle(fontSize: 8.5, color: _muted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildPageFooter(pw.Context context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 5),
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _border, width: 0.6)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'RAGAA — نظام إدارة تحصيل المنافذ',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
            pw.Text(
              'صفحة ${context.pageNumber} من ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------------------
  // Table
  // ---------------------------------------------------------------------------

  Map<int, pw.TableColumnWidth> _columnWidths() {
    final available = pageFormat.availableWidth -
        (_horizontalMargin * 2);
    final moneyWidth = (available - _nameColumnWidth) / 7;
    // Visual (left-to-right) order is the mirror of the logical Arabic order so
    // that «البيان» always sits on the far right of the page in RTL.
    return <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(moneyWidth), // الإجمالي العام
      1: pw.FixedColumnWidth(moneyWidth), // VISA
      2: pw.FixedColumnWidth(moneyWidth), // NFC
      3: pw.FixedColumnWidth(moneyWidth), // إجمالي الموازين
      4: pw.FixedColumnWidth(moneyWidth), // إجمالي الرسوم
      5: pw.FixedColumnWidth(moneyWidth), // الرسوم الآلية
      6: pw.FixedColumnWidth(moneyWidth), // الرسوم اليدوية
      7: pw.FixedColumnWidth(_nameColumnWidth), // البيان
    };
  }

  pw.Widget _buildJournalTable(DailyJournal journal) {
    final rows = <pw.TableRow>[
      _headerRow(),
      for (final section in journal.sections) ...[
        _bandRow(section.shiftLabel),
        for (final row in section.rows) _dataRow(row),
        _totalsRow(
          'إجمالي ${defaultShiftLabel(section.shiftNumber)}',
          section.totals,
          _yellow,
        ),
      ],
      _bandRow('إجمالي اليوم لكل منفذ'),
      for (final total in journal.outletDayTotals) _dayTotalRow(total),
      _totalsRow('الإجمالي العام لليوم', journal.dayTotals, _purple),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.6),
      columnWidths: _columnWidths(),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  pw.TableRow _headerRow() => pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: _headerBg),
        children: [
          for (final header in _columnHeaders.reversed)
            _cell(
              header,
              bold: true,
              color: _headerText,
              rightAligned: header == 'البيان',
              fontSize: 8.8,
            ),
        ],
      );

  pw.TableRow _bandRow(String label) => pw.TableRow(
        decoration: const pw.BoxDecoration(color: _bandBg),
        children: [
          for (var index = 0; index < 7; index++) _cell(''),
          _cell(
            label,
            bold: true,
            color: _headerBg,
            rightAligned: true,
            fontSize: 9,
          ),
        ],
      );

  pw.TableRow _dataRow(JournalRow row) {
    final values = row.hasRecord
        ? <String>[
            formatMoney(row.amounts.manualFeesPiastres),
            formatMoney(row.amounts.automaticFeesPiastres),
            formatMoney(row.amounts.totalFeesPiastres),
            formatMoney(row.amounts.scalesTotalPiastres),
            row.amounts.nfcPiastres == 0
                ? formatMoney(0)
                : formatMoney(row.amounts.nfcPiastres),
            row.amounts.visaPiastres == 0
                ? formatMoney(0)
                : formatMoney(row.amounts.visaPiastres),
            formatMoney(row.amounts.generalTotalPiastres),
          ]
        : <String>['', '', '', '', '', '', ''];
    return pw.TableRow(
      children: _valueCells(
        label: row.outletName,
        values: values,
        labelRightAligned: true,
      ),
    );
  }

  pw.TableRow _dayTotalRow(JournalOutletDayTotal total) {
    final values = <String>[
      formatMoney(total.amounts.manualFeesPiastres),
      formatMoney(total.amounts.automaticFeesPiastres),
      formatMoney(total.amounts.totalFeesPiastres),
      formatMoney(total.amounts.scalesTotalPiastres),
      formatMoney(total.amounts.nfcPiastres),
      formatMoney(total.amounts.visaPiastres),
      formatMoney(total.amounts.generalTotalPiastres),
    ];
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: _purple),
      children: _valueCells(
        label: total.outletName,
        values: values,
        labelRightAligned: true,
        bold: true,
      ),
    );
  }

  pw.TableRow _totalsRow(String label, JournalAmounts amounts, PdfColor fill) {
    final values = <String>[
      formatMoney(amounts.manualFeesPiastres),
      formatMoney(amounts.automaticFeesPiastres),
      formatMoney(amounts.totalFeesPiastres),
      formatMoney(amounts.scalesTotalPiastres),
      formatMoney(amounts.nfcPiastres),
      formatMoney(amounts.visaPiastres),
      formatMoney(amounts.generalTotalPiastres),
    ];
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: fill),
      children: _valueCells(
        label: label,
        values: values,
        labelRightAligned: true,
        bold: true,
        fill: fill,
      ),
    );
  }

  /// Builds the eight visual cells (mirrored order) for a journal row.
  List<pw.Widget> _valueCells({
    required String label,
    required List<String> values,
    bool labelRightAligned = false,
    bool bold = false,
    PdfColor? fill,
  }) {
    final cells = <pw.Widget>[];
    // values[0] = الرسوم اليدوية ... values[6] = الإجمالي العام (logical order),
    // so the visual order (LTR) is values reversed, then the label last (right).
    for (var index = values.length - 1; index >= 0; index--) {
      final isScales = index == 3;
      cells.add(
        _cell(
          values[index],
          bold: bold,
          fill: fill,
          rowBand: isScales && fill == null ? _scalesCell : null,
          fontSize: 8.6,
        ),
      );
    }
    cells.add(
      _cell(
        label,
        bold: bold,
        fill: fill,
        rightAligned: labelRightAligned,
        fontSize: 8.8,
      ),
    );
    return cells;
  }

  pw.Widget _cell(
    String text, {
    bool bold = false,
    bool rightAligned = false,
    PdfColor? color,
    PdfColor? fill,
    PdfColor? rowBand,
    double fontSize = 8.6,
  }) =>
      pw.Container(
        alignment: rightAligned ? pw.Alignment.centerRight : pw.Alignment.center,
        color: fill ?? rowBand,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
        child: pw.Text(
          text,
          textAlign: rightAligned ? pw.TextAlign.right : pw.TextAlign.center,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(
            fontSize: fontSize,
            color: color ?? _ink,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
}
