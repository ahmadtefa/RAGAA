// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../models/daily_journal.dart';

/// On-screen rendering of the daily journal: same sections, same column order
/// (right to left) and same colours as the printed PDF / Excel journal.
///
/// It is horizontally scrollable so that narrow Android screens keep every
/// column readable without shrinking the Arabic text.
class DailyJournalPreview extends StatelessWidget {
  final DailyJournal journal;

  const DailyJournalPreview({super.key, required this.journal});

  static const List<String> _headers = <String>[
    'البيان',
    'الرسوم اليدوية',
    'الرسوم الآلية',
    'إجمالي الرسوم',
    'إجمالي الموازين',
    'NFC',
    'VISA',
    'الإجمالي العام',
  ];

  static const Color _headerColor = Color(0xFF0F5C54);
  static const Color _bandColor = Color(0xFFE3EFEC);
  static const Color _yellow = Color(0xFFF7EC00);
  static const Color _purple = Color(0xFFE2D9EC);
  static const Color _scales = Color(0xFFD9BE8A);
  static const Color _border = Color(0xFF1F2937);

  @override
  Widget build(BuildContext context) {
    if (!journal.hasData) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Text(
          'لا توجد تحصيلات مسجّلة في ${journal.operationalDate}',
          style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _headerColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                journal.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                journal.headerLine,
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: _table(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _table() {
    final rows = <TableRow>[
      _headerRow(),
      for (final section in journal.sections) ...[
        _bandRow('${section.shiftLabel} — ${section.recordedCount}/${section.rows.length}'),
        for (final row in section.rows) _dataRow(row),
        _totalRow(
          'إجمالي ${defaultShiftLabel(section.shiftNumber)}',
          section.totals,
          _yellow,
        ),
      ],
      _bandRow('إجمالي اليوم لكل منفذ'),
      for (final total in journal.outletDayTotals)
        _totalRow(total.outletName, total.amounts, _purple),
      _totalRow('الإجمالي العام لليوم', journal.dayTotals, _purple),
    ];

    return Table(
      border: TableBorder.all(color: _border, width: 0.7),
      defaultColumnWidth: const FixedColumnWidth(120),
      columnWidths: const <int, TableColumnWidth>{0: FixedColumnWidth(150)},
      children: rows,
    );
  }

  TableRow _headerRow() => TableRow(
        decoration: const BoxDecoration(color: _headerColor),
        children: [
          for (final header in _headers)
            _cell(
              header,
              color: Colors.white,
              bold: true,
              align: header == 'البيان' ? TextAlign.right : TextAlign.center,
            ),
        ],
      );

  TableRow _bandRow(String label) => TableRow(
        decoration: const BoxDecoration(color: _bandColor),
        children: [
          for (var index = 0; index < _headers.length; index++)
            _cell(
              index == 0 ? label : '',
              bold: true,
              color: _headerColor,
              align: index == 0 ? TextAlign.right : TextAlign.center,
            ),
        ],
      );

  TableRow _dataRow(JournalRow row) {
    final values = row.hasRecord
        ? row.amounts.columnsInOrder.map(formatMoney).toList()
        : List<String>.filled(7, '');
    return TableRow(
      children: [
        _cell(row.outletName, align: TextAlign.right),
        for (var index = 0; index < values.length; index++)
          _cell(
            values[index],
            background: index == 3 ? _scales : null,
          ),
      ],
    );
  }

  TableRow _totalRow(String label, JournalAmounts amounts, Color background) =>
      TableRow(
        decoration: BoxDecoration(color: background),
        children: [
          _cell(label, bold: true, align: TextAlign.right),
          for (final value in amounts.columnsInOrder)
            _cell(formatMoney(value), bold: true),
        ],
      );

  Widget _cell(
    String text, {
    bool bold = false,
    Color? color,
    Color? background,
    TextAlign align = TextAlign.center,
  }) =>
      Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text(
          text,
          textAlign: align,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            color: color ?? const Color(0xFF111827),
          ),
        ),
      );
}
