import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formatters.dart';
import '../models/daily_journal.dart';

/// One PDF source for export, printing and the in-app preview.
class DailyJournalPdfService {
  pw.Font? _regularFont;
  pw.Font? _boldFont;
  static const _green = PdfColor.fromInt(0xFF38743A);
  static const _yellow = PdfColor.fromInt(0xFFFFEB35);
  static const _purple = PdfColor.fromInt(0xFFE2DAE9);
  static const _scales = PdfColor.fromInt(0xFFDDC19B);
  static const _band = PdfColor.fromInt(0xFFF2F0EE);
  static const _height = 15.5;

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
          horizontal: 19,
          vertical: 12,
        ),
        textDirection: pw.TextDirection.ltr,
        header: (_) => _header(journal),
        build: (_) => _rows(journal),
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

  // Physical widths follow the printed sheet from its left edge to the right.
  static const _widths = [11, 14, 15, 15, 19, 19, 15, 15, 24];
  double _width(int units) => (pageFormat.width - 38) * units / 147;

  pw.Widget _cell(String text, int units, {double height = _height,
      PdfColor? fill, bool bold = false, bool right = false}) {
    return pw.Container(
      width: _width(units), height: height,
      alignment: right ? pw.Alignment.centerRight : pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 0.3),
      decoration: pw.BoxDecoration(color: fill,
        border: pw.Border.all(width: 0.35, color: PdfColors.black)),
      child: pw.FittedBox(fit: pw.BoxFit.scaleDown, child: pw.Text(text,
        textDirection: RegExp(r'[\u0600-\u06ff]').hasMatch(text)
            ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        style: pw.TextStyle(fontSize: 10,
          color: fill == _green ? PdfColors.white : PdfColors.black,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
    );
  }

  pw.Widget _header(DailyJournal journal) {
    const h = 24.0;
    return pw.Column(children: [
      pw.Text('${journal.title} ${journal.headerLine}', textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.Row(children: [
        _cell('إجمالي عام', 25, height: h, bold: true),
        _cell('VISA', 15, height: h, bold: true),
        _cell('NFC', 15, height: h, bold: true),
        _cell('إجمالي الموازين', 19, height: h, bold: true),
        _cell('إجمالي الرسوم', 19, height: h, bold: true),
        pw.Column(children: [
          _cell('رسوم', 30, height: h / 2, bold: true),
          pw.Row(children: [
            _cell('آلي', 15, height: h / 2, bold: true),
            _cell('يدوي', 15, height: h / 2, bold: true),
          ]),
        ]),
        _cell('البيان', 24, height: h, bold: true),
      ]),
    ]);
  }

  pw.Widget _line(String label, JournalAmounts? amounts,
      {bool split = false, bool total = false}) {
    final values = amounts?.columnsInOrder.reversed.map(formatMoney).toList()
        ?? List<String>.filled(7, '');
    return pw.Row(children: [
      for (var i = 0; i < values.length; i++)
        _cell(values[i], i == 0 && !split ? 25 : _widths[i + 1],
            bold: total, fill: total ? (i == 0 ? _yellow : _purple)
                : i == 3 ? _scales : null),
      _cell(label, 24, bold: total, fill: total ? _purple : null),
    ]);
  }

  List<pw.Widget> _rows(DailyJournal journal) {
    final rows = <pw.Widget>[];
    for (final section in journal.sections) {
      final shift = defaultShiftLabel(section.shiftNumber);
      final count = section.greenRowCount;
      // Keep the five rows and their vertically merged cell on the same page.
      rows.add(pw.Container(child: pw.Column(children: [
        _cell(shift, 147, right: true, bold: true, fill: _band),
        if (count > 0) pw.Row(children: [
          _cell(formatMoney(section.firstFivePiastres), 11,
              height: _height * count, fill: _green, bold: true),
          pw.Column(children: [
            for (final row in section.rows.take(count))
              _line(row.outletName, row.hasRecord ? row.amounts : null, split: true),
          ]),
        ]),
      ])));
      for (final row in section.rows.skip(count)) {
        rows.add(_line(row.outletName, row.hasRecord ? row.amounts : null));
      }
      rows.add(_line('إجمالي $shift', section.totals, total: true));
    }
    rows.add(_cell('إجمالي اليوم', 147, right: true, bold: true, fill: _band));
    for (final outlet in journal.outletDayTotals) {
      rows.add(_line(outlet.outletName, outlet.amounts));
    }
    rows.add(_line('الإجمالي العام لليوم', journal.dayTotals, total: true));
    return rows;
  }
}
