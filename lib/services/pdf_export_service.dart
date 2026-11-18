import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formatters.dart';
import '../models/report_models.dart';

/// Generates print-ready Arabic RTL accounting PDF reports using bundled Amiri TTF fonts.
class PdfExportService {
  pw.Font? _regularFont;
  pw.Font? _boldFont;

  Future<(pw.Font regular, pw.Font bold)> _loadFonts() async {
    if (_regularFont != null && _boldFont != null) {
      return (_regularFont!, _boldFont!);
    }
    final regData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Amiri-Bold.ttf');
    _regularFont = pw.Font.ttf(regData);
    _boldFont = pw.Font.ttf(boldData);
    return (_regularFont!, _boldFont!);
  }

  /// Generates raw PDF bytes for [report].
  Future<Uint8List> buildReportPdfBytes(ReportData report) async {
    final (regularFont, boldFont) = await _loadFonts();

    const primaryColor = PdfColor.fromInt(0xFF0F5C54);
    const primaryLight = PdfColor.fromInt(0xFFE6F2F0);
    const borderColor = PdfColor.fromInt(0xFFCBD5E1);
    const zebraColor = PdfColor.fromInt(0xFFF8FAFC);
    const totalRowColor = PdfColor.fromInt(0xFFECFDF5);
    const mutedText = PdfColor.fromInt(0xFF475569);
    const darkText = PdfColor.fromInt(0xFF0F172A);

    final doc = pw.Document(
      title: 'RAGAA - ${report.filter.range.arabicDescription}',
      author: 'RAGAA Central Collection System',
      creator: 'RAGAA',
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
    );

    final showShift3 = report.filter.shiftNumber == null ||
        report.filter.shiftNumber == 3;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        textDirection: pw.TextDirection.rtl,
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox.shrink()
            : pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 12),
                padding: const pw.EdgeInsets.only(bottom: 6),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: borderColor, width: 0.7),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'نظام رجاء (RAGAA) — ${report.filter.range.arabicDescription}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    pw.Text(
                      'المنافذ: ${report.outletsFilterLabel} | الوردية: ${report.shiftFilterLabel}',
                      style: const pw.TextStyle(fontSize: 8.5, color: mutedText),
                    ),
                  ],
                ),
              ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: borderColor, width: 0.7),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'تاريخ استخراج التقرير: ${formatTimestamp(report.generatedAt)}',
                style: const pw.TextStyle(fontSize: 8.5, color: mutedText),
              ),
              pw.Text(
                'صفحة ${context.pageNumber} من ${context.pagesCount}',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: mutedText,
                ),
              ),
            ],
          ),
        ),
        build: (context) => [
          // Title Banner
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: primaryColor,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'نظام رجاء لإدارة تحصيل المنافذ (RAGAA)',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      report.filter.range.arabicDescription,
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'إجمالي التحصيل',
                        style: const pw.TextStyle(
                          color: mutedText,
                          fontSize: 8.5,
                        ),
                      ),
                      pw.Text(
                        formatMoney(
                          report.grandTotalPiastres,
                          withCurrency: true,
                        ),
                        style: pw.TextStyle(
                          color: primaryColor,
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),

          // Filter Metadata Bar
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: pw.BoxDecoration(
              color: primaryLight,
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(color: borderColor, width: 0.6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'المنافذ: ${report.outletsFilterLabel}',
                    style: const pw.TextStyle(fontSize: 9.5, color: darkText),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Text(
                  'الوردية: ${report.shiftFilterLabel}',
                  style: const pw.TextStyle(fontSize: 9.5, color: darkText),
                ),
                pw.SizedBox(width: 12),
                pw.Text(
                  'أيام الفترة: ${report.filter.range.dayCount}',
                  style: const pw.TextStyle(fontSize: 9.5, color: darkText),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // Summary KPI Row
          pw.Row(
            children: [
              pw.Expanded(
                child: _kpiBox(
                  title: 'إجمالي التحصيل',
                  value: formatMoney(
                    report.grandTotalPiastres,
                    withCurrency: true,
                  ),
                  borderColor: borderColor,
                  accent: primaryColor,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _kpiBox(
                  title: 'عدد الورديات المسجلة',
                  value: '${report.totalEntries}',
                  borderColor: borderColor,
                  accent: darkText,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _kpiBox(
                  title: 'متوسط اليوم التشغيلي',
                  value: formatMoney(
                    report.dailyAveragePiastres,
                    withCurrency: true,
                  ),
                  borderColor: borderColor,
                  accent: darkText,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _kpiBox(
                  title: 'سجلات خضعت للتعديل',
                  value: '${report.modifiedEntriesCount}',
                  borderColor: borderColor,
                  accent: darkText,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // 1. Outlet Summary Table
          _sectionTitle('أولًا: ملخص التحصيل حسب المنفذ', primaryColor),
          pw.SizedBox(height: 6),
          if (report.byOutlet.isEmpty)
            _emptyNotice('لا توجد منافذ مطابقة لمعايير التقرير', borderColor)
          else
            _buildRtlTable(
              headers: [
                'المنفذ',
                'النظام',
                if (report.filter.shiftNumber == null) ...[
                  'الوردية الأولى',
                  'الوردية الثانية',
                  if (showShift3) 'الوردية الثالثة',
                ],
                'السجلات',
                'الإجمالي (ج.م)',
                'النسبة',
              ],
              rows: [
                for (final row in report.byOutlet)
                  [
                    row.isActive ? row.outletName : '${row.outletName} (متوقف)',
                    row.configuredShiftCount == 2 ? 'ورديتان' : '3 ورديات',
                    if (report.filter.shiftNumber == null) ...[
                      formatMoney(row.shift1Piastres),
                      formatMoney(row.shift2Piastres),
                      if (showShift3) formatMoney(row.shift3Piastres),
                    ],
                    '${row.recordedShiftsCount}',
                    formatMoney(row.totalPiastres),
                    '${(row.shareOf(report.grandTotalPiastres) * 100).toStringAsFixed(1)}%',
                  ],
              ],
              footerRow: [
                'الإجمالي الكلي',
                '${report.byOutlet.length} منفذ',
                if (report.filter.shiftNumber == null) ...[
                  formatMoney(
                    report.byOutlet.fold(0, (s, r) => s + r.shift1Piastres),
                  ),
                  formatMoney(
                    report.byOutlet.fold(0, (s, r) => s + r.shift2Piastres),
                  ),
                  if (showShift3)
                    formatMoney(
                      report.byOutlet.fold(0, (s, r) => s + r.shift3Piastres),
                    ),
                ],
                '${report.totalEntries}',
                formatMoney(report.grandTotalPiastres),
                report.grandTotalPiastres > 0 ? '100.0%' : '0.0%',
              ],
              headerBg: primaryColor,
              zebraBg: zebraColor,
              footerBg: totalRowColor,
              borderColor: borderColor,
            ),
          pw.SizedBox(height: 16),

          // 2. Shift Summary Table
          _sectionTitle('ثانيًا: ملخص التحصيل حسب الوردية', primaryColor),
          pw.SizedBox(height: 6),
          _buildRtlTable(
            headers: const [
              'الوردية',
              'عدد السجلات',
              'متوسط الوردية (ج.م)',
              'الإجمالي (ج.م)',
              'النسبة',
            ],
            rows: [
              for (final s in report.byShift)
                [
                  s.shiftLabel,
                  '${s.entriesCount}',
                  formatMoney(s.averagePiastres),
                  formatMoney(s.totalPiastres),
                  '${(s.shareOf(report.grandTotalPiastres) * 100).toStringAsFixed(1)}%',
                ],
            ],
            footerRow: [
              'الإجمالي',
              '${report.totalEntries}',
              formatMoney(report.shiftAveragePiastres),
              formatMoney(report.grandTotalPiastres),
              report.grandTotalPiastres > 0 ? '100.0%' : '0.0%',
            ],
            headerBg: primaryColor,
            zebraBg: zebraColor,
            footerBg: totalRowColor,
            borderColor: borderColor,
          ),

          // 3. Daily Summary Table (when spanning multiple days or having data)
          if (report.byDay.length > 1) ...[
            pw.SizedBox(height: 16),
            _sectionTitle('ثالثًا: التجميع اليومي للتحصيل', primaryColor),
            pw.SizedBox(height: 6),
            _buildRtlTable(
              headers: [
                'التاريخ التشغيلي',
                'اليوم',
                if (report.filter.shiftNumber == null) ...[
                  'الوردية الأولى',
                  'الوردية الثانية',
                  'الوردية الثالثة',
                ],
                'السجلات',
                'إجمالي اليوم (ج.م)',
              ],
              rows: [
                for (final d in report.byDay)
                  [
                    d.operationalDate,
                    d.weekdayLabel,
                    if (report.filter.shiftNumber == null) ...[
                      formatMoney(d.shift1Piastres),
                      formatMoney(d.shift2Piastres),
                      formatMoney(d.shift3Piastres),
                    ],
                    '${d.entriesCount}',
                    formatMoney(d.totalPiastres),
                  ],
              ],
              footerRow: [
                'الإجمالي',
                '${report.byDay.length} يوم',
                if (report.filter.shiftNumber == null) ...[
                  formatMoney(
                    report.byDay.fold(0, (s, d) => s + d.shift1Piastres),
                  ),
                  formatMoney(
                    report.byDay.fold(0, (s, d) => s + d.shift2Piastres),
                  ),
                  formatMoney(
                    report.byDay.fold(0, (s, d) => s + d.shift3Piastres),
                  ),
                ],
                '${report.totalEntries}',
                formatMoney(report.grandTotalPiastres),
              ],
              headerBg: primaryColor,
              zebraBg: zebraColor,
              footerBg: totalRowColor,
              borderColor: borderColor,
            ),
          ],

          pw.SizedBox(height: 16),

          // 4. Detailed Records Table
          _sectionTitle(
            report.byDay.length > 1
                ? 'رابعًا: السجل التفصيلي لعمليات التحصيل'
                : 'ثالثًا: السجل التفصيلي لعمليات التحصيل',
            primaryColor,
          ),
          pw.SizedBox(height: 6),
          if (report.details.isEmpty)
            _emptyNotice(
              'لا توجد سجلات تحصيل مسجلة في الفترة المحددة',
              borderColor,
            )
          else
            _buildRtlTable(
              headers: const [
                'التاريخ التشغيلي',
                'المنفذ',
                'الوردية',
                'الموعد',
                'المبلغ (ج.م)',
                'الحالة',
                'ملاحظات',
              ],
              rows: [
                for (final c in report.details)
                  [
                    c.operationalDate,
                    c.outletName,
                    c.shiftTitle,
                    c.shiftScheduleDisplay.isEmpty
                        ? '-'
                        : c.shiftScheduleDisplay,
                    formatMoney(c.amountPiastres),
                    c.wasModified ? 'معدّل (${c.revision})' : 'أصلي',
                    c.notes.isEmpty ? '-' : c.notes,
                  ],
              ],
              footerRow: [
                'الإجمالي الكلي',
                '',
                '',
                '${report.totalEntries} سجل',
                formatMoney(report.grandTotalPiastres),
                '',
                '',
              ],
              headerBg: primaryColor,
              zebraBg: zebraColor,
              footerBg: totalRowColor,
              borderColor: borderColor,
            ),
        ],
      ),
    );

    return doc.save();
  }

  /// Writes the generated Arabic RTL PDF report directly to [outputPath].
  Future<File> exportReportToFile(ReportData report, String outputPath) async {
    final bytes = await buildReportPdfBytes(report);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  pw.Widget _sectionTitle(String text, PdfColor color) => pw.Container(
        padding: const pw.EdgeInsets.only(right: 6, bottom: 2),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            right: pw.BorderSide(color: color, width: 3),
          ),
        ),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      );

  pw.Widget _kpiBox({
    required String title,
    required String value,
    required PdfColor borderColor,
    required PdfColor accent,
  }) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(color: borderColor, width: 0.7),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColor.fromInt(0xFF475569),
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
            ),
          ],
        ),
      );

  pw.Widget _emptyNotice(String message, PdfColor borderColor) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: borderColor, width: 0.6),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(
          message,
          style: const pw.TextStyle(
            fontSize: 10,
            color: PdfColor.fromInt(0xFF64748B),
          ),
        ),
      );

  /// Builds an RTL table by reversing visual column order so the first logical
  /// Arabic column appears on the far right of the page.
  pw.Widget _buildRtlTable({
    required List<String> headers,
    required List<List<String>> rows,
    required List<String> footerRow,
    required PdfColor headerBg,
    required PdfColor zebraBg,
    required PdfColor footerBg,
    required PdfColor borderColor,
  }) {
    final reversedHeaders = headers.reversed.toList();
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [
          for (final h in reversedHeaders)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 5,
              ),
              child: pw.Text(
                h,
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    ];

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i].reversed.toList();
      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isOdd ? zebraBg : PdfColors.white,
          ),
          children: [
            for (var c = 0; c < r.length; c++)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 4,
                ),
                child: pw.Text(
                  r[c],
                  textAlign: c == r.length - 1
                      ? pw.TextAlign.right
                      : pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl,
                  style: const pw.TextStyle(
                    fontSize: 8.8,
                    color: PdfColor.fromInt(0xFF0F172A),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final revFooter = footerRow.reversed.toList();
    tableRows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: footerBg),
        children: [
          for (var c = 0; c < revFooter.length; c++)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 5,
              ),
              child: pw.Text(
                revFooter[c],
                textAlign: c == revFooter.length - 1
                    ? pw.TextAlign.right
                    : pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF064E3B),
                ),
              ),
            ),
        ],
      ),
    );

    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: 0.5),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: tableRows,
    );
  }
}
