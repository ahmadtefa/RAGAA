// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/date_ranges.dart';
import '../../core/formatters.dart';
import '../../models/daily_journal.dart';
import '../../models/report_models.dart';
import '../../state/ragaa_controller.dart';
import '../widgets/common_widgets.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/daily_journal_preview.dart';

enum _ReportSubView { outlets, shifts, days, details, journal }

/// Comprehensive reporting page supporting Daily, Weekly, Monthly, and Custom
/// periods, multi-outlet and shift filters, and Arabic RTL PDF & Excel (.xlsx) export.
class ReportsPage extends StatefulWidget {
  final RagaaController controller;

  const ReportsPage({super.key, required this.controller});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportPeriodType _periodType = ReportPeriodType.daily;
  DateTime _dailyDate = dateOnly(DateTime.now());
  DateTime _weeklyAnchor = dateOnly(DateTime.now());
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  DateTime _customStart = dateOnly(
    DateTime(DateTime.now().year, DateTime.now().month, 1),
  );
  DateTime _customEnd = dateOnly(DateTime.now());

  final Set<String> _selectedOutletIds = {};
  int? _selectedShift;
  _ReportSubView _subView = _ReportSubView.outlets;

  ReportData? _report;
  DailyJournal? _journal;
  bool _journalLoading = false;
  int _reportRequest = 0;
  int _journalRequest = 0;
  bool _loading = true;
  String? _lastExportedPath;
  String? _lastExportLabel;
  int _lastSeenRevision = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _reload();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller.dataRevision != _lastSeenRevision) {
      _reload();
    }
  }

  OperationalDateRange _computeRange() {
    switch (_periodType) {
      case ReportPeriodType.daily:
        return OperationalDateRange.daily(_dailyDate);
      case ReportPeriodType.weekly:
        return OperationalDateRange.weekly(_weeklyAnchor);
      case ReportPeriodType.monthly:
        return OperationalDateRange.monthly(_selectedYear, _selectedMonth);
      case ReportPeriodType.custom:
        final safeEnd =
            _customEnd.isBefore(_customStart) ? _customStart : _customEnd;
        return OperationalDateRange.custom(_customStart, safeEnd);
    }
  }

  Future<void> _reload() async {
    _lastSeenRevision = widget.controller.dataRevision;
    final request = ++_reportRequest;
    ++_journalRequest;
    setState(() {
      _loading = true;
      _journal = null;
      _journalLoading = false;
    });
    final filter = ReportFilter(
      range: _computeRange(),
      outletIds: Set.unmodifiable(_selectedOutletIds),
      shiftNumber: _selectedShift,
    );
    final data = await widget.controller.buildReport(filter);
    if (mounted && request == _reportRequest) {
      setState(() {
        _report = data;
        _loading = false;
      });
      if (_subView == _ReportSubView.journal) {
        await _loadJournal();
      }
    }
  }

  Future<void> _exportPdf() async {
    final report = _report;
    if (report == null) return;
    try {
      final path = await widget.controller.exportReportPdf(report);
      if (path != null && mounted) {
        setState(() {
          _lastExportedPath = path;
          _lastExportLabel = 'تم تصدير تقرير PDF بنجاح:';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تصدير PDF: $e')),
        );
      }
    }
  }

  Future<void> _exportExcel() async {
    final report = _report;
    if (report == null) return;
    try {
      final path = await widget.controller.exportReportExcel(report);
      if (path != null && mounted) {
        setState(() {
          _lastExportedPath = path;
          _lastExportLabel = 'تم تصدير تقرير Excel (.xlsx) بنجاح:';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تصدير Excel: $e')),
        );
      }
    }
  }

  /// Builds the electronic daily journal for the first day of the selected
  /// period (the paper journal is always a single operational day).
  Future<void> _loadJournal() async {
    final request = ++_journalRequest;
    setState(() => _journalLoading = true);
    final journal = await _journalOrNull();
    if (mounted && request == _journalRequest) {
      setState(() {
        _journal = journal;
        _journalLoading = false;
      });
    }
  }

  Future<void> _exportJournal({required bool asPdf}) async {
    final journal = await _journalOrNull();
    if (journal == null) return;
    try {
      final path = await widget.controller.quickExportJournal(
        journal,
        asPdf: asPdf,
      );
      if (!mounted) return;
      setState(() {
        _lastExportedPath = path;
        _lastExportLabel = asPdf
            ? 'تم تصدير اليومية PDF بنجاح:'
            : 'تم تصدير اليومية Excel (.xlsx) بنجاح:';
      });
      final shared = await widget.controller.shareFile(path);
      if (!mounted) return;
      if (!shared) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ اليومية في: $path')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تصدير اليومية: $e')),
        );
      }
    }
  }

  Future<DailyJournal?> _journalOrNull() async {
    try {
      return await widget.controller.buildDailyJournal(
        _computeRange().start,
        outletIds: Set.unmodifiable(_selectedOutletIds),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر بناء اليومية: $e')),
        );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final busy = widget.controller.isBusy;
    final outlets = widget.controller.outlets;

    return ListView(
      padding: responsivePagePadding(context, withFabInset: true),
      children: [
        // Header & Export Buttons
        Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'التقارير وتصدير PDF وExcel',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                Text(
                  'تقارير يومية وأسبوعية وشهرية وفترات مخصصة مع دعم كامل للعربية واتجاه RTL',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('export_pdf_button'),
                  onPressed: (report == null || busy) ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('تصدير PDF'),
                ),
                FilledButton.tonalIcon(
                  key: const Key('export_excel_button'),
                  onPressed: (report == null || busy) ? null : _exportExcel,
                  icon: const Icon(Icons.table_view, size: 18),
                  label: const Text('تصدير Excel (.xlsx)'),
                ),
                FilledButton.tonalIcon(
                  key: const Key('export_journal_pdf_button'),
                  onPressed: busy ? null : () => _exportJournal(asPdf: true),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('اليومية PDF'),
                ),
                FilledButton.tonalIcon(
                  key: const Key('export_journal_excel_button'),
                  onPressed: busy ? null : () => _exportJournal(asPdf: false),
                  icon: const Icon(Icons.grid_on_outlined, size: 18),
                  label: const Text('اليومية Excel'),
                ),
              ],
            ),
          ],
        ),
        if (_lastExportedPath != null) ...[
          const SizedBox(height: 12),
          SavedFileBanner(
            label: _lastExportLabel ?? 'تم حفظ الملف:',
            filePath: _lastExportedPath!,
            onOpen: () => widget.controller.openSavedFile(_lastExportedPath!),
            onShare: () => widget.controller.shareFile(
              widget.controller.lastSavedLocalPath ?? _lastExportedPath!,
            ),
            onDismiss: () => setState(() => _lastExportedPath = null),
          ),
        ],
        const SizedBox(height: 16),

        // Period & Filter Controls Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 520) {
                          // Phones: a dropdown can never overflow.
                          return SizedBox(
                            width: constraints.maxWidth,
                            child: PeriodDropdown<ReportPeriodType>(
                              value: _periodType,
                              hint: 'اختر الفترة',
                              options: const [
                                PeriodOption(ReportPeriodType.daily, 'يومي'),
                                PeriodOption(ReportPeriodType.weekly, 'أسبوعي'),
                                PeriodOption(ReportPeriodType.monthly, 'شهري'),
                                PeriodOption(
                                  ReportPeriodType.custom,
                                  'فترة مخصصة',
                                ),
                              ],
                              onChanged: (value) {
                                setState(() => _periodType = value);
                                _reload();
                              },
                            ),
                          );
                        }
                        return SegmentedButton<ReportPeriodType>(
                          segments: const [
                            ButtonSegment(
                              value: ReportPeriodType.daily,
                              label: Text('يومي'),
                            ),
                            ButtonSegment(
                              value: ReportPeriodType.weekly,
                              label: Text('أسبوعي'),
                            ),
                            ButtonSegment(
                              value: ReportPeriodType.monthly,
                              label: Text('شهري'),
                            ),
                            ButtonSegment(
                              value: ReportPeriodType.custom,
                              label: Text('فترة مخصصة'),
                            ),
                          ],
                          selected: {_periodType},
                          onSelectionChanged: (s) {
                            setState(() => _periodType = s.first);
                            _reload();
                          },
                        );
                      },
                    ),
                    _buildPeriodSpecificPicker(),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: DropdownButtonFormField<int?>(
                        key: ValueKey('rep_shift_$_selectedShift'),
                        isExpanded: true,
                        initialValue: _selectedShift,
                        decoration: const InputDecoration(
                          labelText: 'فلتر الوردية',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: null,
                            child: Text('كل الورديات', maxLines: 1),
                          ),
                          DropdownMenuItem(
                            value: 1,
                            child: Text(
                              'الوردية الأولى',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text(
                              'الوردية الثانية',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text(
                              'الوردية الثالثة',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedShift = v);
                          _reload();
                        },
                      ),
                    ),
                    if (outlets.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'المنافذ:',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          FilterChip(
                            label: const Text('كل المنافذ'),
                            selected: _selectedOutletIds.isEmpty,
                            onSelected: (_) {
                              setState(_selectedOutletIds.clear);
                              _reload();
                            },
                          ),
                          for (final o in outlets)
                            FilterChip(
                              label: Text(o.name),
                              selected: _selectedOutletIds.contains(o.id),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedOutletIds.add(o.id);
                                  } else {
                                    _selectedOutletIds.remove(o.id);
                                  }
                                });
                                _reload();
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (_loading || report == null)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          // Summary Strip
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              KpiMetricCard(
                title: 'إجمالي التحصيل',
                value: formatMoney(
                  report.grandTotalPiastres,
                  withCurrency: true,
                ),
                subtitle: report.filter.range.arabicDescription,
                icon: Icons.summarize,
                highlighted: true,
              ),
              KpiMetricCard(
                title: 'عدد السجلات',
                value: '${report.totalEntries}',
                subtitle: 'موزعة على ${report.activeDaysCount} يوم تشغيلي',
                icon: Icons.receipt_long,
              ),
              KpiMetricCard(
                title: 'متوسط الوردية',
                value: formatMoney(
                  report.shiftAveragePiastres,
                  withCurrency: true,
                ),
                subtitle:
                    'متوسط اليوم: ${formatMoney(report.dailyAveragePiastres, withCurrency: true)}',
                icon: Icons.analytics_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sub-view Switcher (horizontally scrollable on narrow phones)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_ReportSubView>(
              segments: const [
                ButtonSegment(
                  value: _ReportSubView.outlets,
                  label: Text('حسب المنفذ'),
                ),
                ButtonSegment(
                  value: _ReportSubView.shifts,
                  label: Text('حسب الوردية'),
                ),
                ButtonSegment(
                  value: _ReportSubView.days,
                  label: Text('حسب اليوم'),
                ),
                ButtonSegment(
                  value: _ReportSubView.details,
                  label: Text('التفاصيل'),
                ),
                ButtonSegment(
                  value: _ReportSubView.journal,
                  label: Text('اليومية'),
                ),
              ],
              selected: {_subView},
              onSelectionChanged: (s) {
                setState(() => _subView = s.first);
                if (s.first == _ReportSubView.journal) {
                  _loadJournal();
                }
              },
            ),
          ),
          const SizedBox(height: 14),

          _buildActiveSubView(report),
        ],
      ],
    );
  }

  Widget _buildPeriodSpecificPicker() {
    switch (_periodType) {
      case ReportPeriodType.daily:
        // A wrap instead of a row: the two chevrons and the date button spread
        // over two lines on a narrow phone instead of overflowing.
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'اليوم السابق',
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() {
                  _dailyDate = DateTime(
                    _dailyDate.year,
                    _dailyDate.month,
                    _dailyDate.day - 1,
                  );
                });
                _reload();
              },
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dailyDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null && mounted) {
                  setState(() => _dailyDate = dateOnly(d));
                  await _reload();
                }
              },
              icon: const Icon(Icons.calendar_month, size: 16),
              label: Text(
                '${arabicWeekday(_dailyDate)} ${dateKey(_dailyDate)}',
              ),
            ),
            IconButton(
              tooltip: 'اليوم التالي',
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                setState(() {
                  _dailyDate = DateTime(
                    _dailyDate.year,
                    _dailyDate.month,
                    _dailyDate.day + 1,
                  );
                });
                _reload();
              },
            ),
          ],
        );

      case ReportPeriodType.weekly:
        final w = OperationalDateRange.weekly(_weeklyAnchor);
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'الأسبوع السابق',
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() {
                  _weeklyAnchor = DateTime(
                    _weeklyAnchor.year,
                    _weeklyAnchor.month,
                    _weeklyAnchor.day - 7,
                  );
                });
                _reload();
              },
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _weeklyAnchor,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null && mounted) {
                  setState(() => _weeklyAnchor = dateOnly(d));
                  await _reload();
                }
              },
              icon: const Icon(Icons.date_range, size: 16),
              label: Text('${w.startKey} إلى ${w.endKey}'),
            ),
            IconButton(
              tooltip: 'الأسبوع التالي',
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                setState(() {
                  _weeklyAnchor = DateTime(
                    _weeklyAnchor.year,
                    _weeklyAnchor.month,
                    _weeklyAnchor.day + 7,
                  );
                });
                _reload();
              },
            ),
          ],
        );

      case ReportPeriodType.monthly:
        final currentYear = DateTime.now().year;
        final years = List.generate(12, (i) => currentYear - 6 + i);
        return Wrap(
          spacing: 8,
          children: [
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<int>(
                key: ValueKey('month_$_selectedMonth'),
                isExpanded: true,
                initialValue: _selectedMonth,
                decoration: const InputDecoration(
                  labelText: 'الشهر',
                  isDense: true,
                ),
                items: List.generate(
                  12,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text(
                      kArabicMonthNames[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedMonth = v);
                  _reload();
                },
              ),
            ),
            SizedBox(
              width: 120,
              child: DropdownButtonFormField<int>(
                key: ValueKey('year_$_selectedYear'),
                isExpanded: true,
                initialValue: _selectedYear,
                decoration: const InputDecoration(
                  labelText: 'السنة',
                  isDense: true,
                ),
                items: years
                    .map(
                      (y) => DropdownMenuItem(value: y, child: Text('$y')),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedYear = v);
                  _reload();
                },
              ),
            ),
          ],
        );

      case ReportPeriodType.custom:
        return Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _customStart,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null && mounted) {
                  setState(() {
                    _customStart = dateOnly(d);
                    if (_customEnd.isBefore(_customStart)) {
                      _customEnd = _customStart;
                    }
                  });
                  await _reload();
                }
              },
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text('من: ${dateKey(_customStart)}'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _customEnd,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null && mounted) {
                  setState(() {
                    _customEnd = dateOnly(d);
                    if (_customStart.isAfter(_customEnd)) {
                      _customStart = _customEnd;
                    }
                  });
                  await _reload();
                }
              },
              icon: const Icon(Icons.event, size: 16),
              label: Text('إلى: ${dateKey(_customEnd)}'),
            ),
          ],
        );
    }
  }

  Widget _buildActiveSubView(ReportData report) {
    switch (_subView) {
      case _ReportSubView.journal:
        if (_journalLoading && _journal == null) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final journal = _journal;
        if (journal == null) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'اضغط لعرض يومية اليوم المحدد بالتصميم الورقي الكامل',
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const Key('load_journal_button'),
                    onPressed: _loadJournal,
                    icon: const Icon(Icons.refresh),
                    label: const Text('عرض اليومية'),
                  ),
                ],
              ),
            ),
          );
        }
        return SizedBox(
          height: 520,
          child: DailyJournalPreview(journal: journal),
        );
      case _ReportSubView.outlets:
        if (report.byOutlet.isEmpty) {
          return const EmptyStateBox(
            icon: Icons.storefront_outlined,
            title: 'لا توجد بيانات منافذ لعرضها',
          );
        }
        return Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              columns: const [
                DataColumn(label: Text('المنفذ')),
                DataColumn(label: Text('نظام الورديات')),
                DataColumn(numeric: true, label: Text('الوردية الأولى')),
                DataColumn(numeric: true, label: Text('الوردية الثانية')),
                DataColumn(numeric: true, label: Text('الوردية الثالثة')),
                DataColumn(numeric: true, label: Text('السجلات')),
                DataColumn(numeric: true, label: Text('الإجمالي (ج.م)')),
                DataColumn(numeric: true, label: Text('النسبة')),
              ],
              rows: [
                for (final r in report.byOutlet)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          r.isActive ? r.outletName : '${r.outletName} (متوقف)',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        Text(
                          r.configuredShiftCount == 2 ? 'ورديتان' : '3 ورديات',
                        ),
                      ),
                      DataCell(Text(formatMoney(r.shift1Piastres))),
                      DataCell(Text(formatMoney(r.shift2Piastres))),
                      DataCell(Text(formatMoney(r.shift3Piastres))),
                      DataCell(Text('${r.recordedShiftsCount}')),
                      DataCell(
                        Text(
                          formatMoney(r.totalPiastres),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandPrimary,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${(r.shareOf(report.grandTotalPiastres) * 100).toStringAsFixed(1)}%',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );

      case _ReportSubView.shifts:
        return Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              columns: const [
                DataColumn(label: Text('الوردية')),
                DataColumn(numeric: true, label: Text('عدد السجلات')),
                DataColumn(numeric: true, label: Text('المتوسط (ج.م)')),
                DataColumn(numeric: true, label: Text('الإجمالي (ج.م)')),
                DataColumn(numeric: true, label: Text('النسبة')),
              ],
              rows: [
                for (final s in report.byShift)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          s.shiftLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(Text('${s.entriesCount}')),
                      DataCell(Text(formatMoney(s.averagePiastres))),
                      DataCell(
                        Text(
                          formatMoney(s.totalPiastres),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandPrimary,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${(s.shareOf(report.grandTotalPiastres) * 100).toStringAsFixed(1)}%',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );

      case _ReportSubView.days:
        if (report.byDay.isEmpty) {
          return const EmptyStateBox(
            icon: Icons.calendar_today_outlined,
            title: 'لا توجد أيام بها تحصيل في الفترة المحددة',
          );
        }
        return Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              columns: const [
                DataColumn(label: Text('التاريخ التشغيلي')),
                DataColumn(label: Text('اليوم')),
                DataColumn(numeric: true, label: Text('الوردية الأولى')),
                DataColumn(numeric: true, label: Text('الوردية الثانية')),
                DataColumn(numeric: true, label: Text('الوردية الثالثة')),
                DataColumn(numeric: true, label: Text('السجلات')),
                DataColumn(numeric: true, label: Text('إجمالي اليوم (ج.م)')),
              ],
              rows: [
                for (final d in report.byDay)
                  DataRow(
                    cells: [
                      DataCell(Text(d.operationalDate)),
                      DataCell(Text(d.weekdayLabel)),
                      DataCell(Text(formatMoney(d.shift1Piastres))),
                      DataCell(Text(formatMoney(d.shift2Piastres))),
                      DataCell(Text(formatMoney(d.shift3Piastres))),
                      DataCell(Text('${d.entriesCount}')),
                      DataCell(
                        Text(
                          formatMoney(d.totalPiastres),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );

      case _ReportSubView.details:
        if (report.details.isEmpty) {
          return const EmptyStateBox(
            icon: Icons.list_alt_outlined,
            title: 'لا توجد سجلات تفصيلية في الفترة المحددة',
          );
        }
        return Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              columns: const [
                DataColumn(label: Text('التاريخ التشغيلي')),
                DataColumn(label: Text('المنفذ')),
                DataColumn(label: Text('الوردية')),
                DataColumn(label: Text('الموعد')),
                DataColumn(numeric: true, label: Text('المبلغ (ج.م)')),
                DataColumn(label: Text('الحالة')),
                DataColumn(label: Text('ملاحظات')),
              ],
              rows: [
                for (final c in report.details)
                  DataRow(
                    cells: [
                      DataCell(Text(c.operationalDate)),
                      DataCell(
                        Text(
                          c.outletName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(Text(c.shiftTitle)),
                      DataCell(
                        Text(
                          c.shiftScheduleDisplay.isEmpty
                              ? '-'
                              : c.shiftScheduleDisplay,
                        ),
                      ),
                      DataCell(
                        Text(
                          formatMoney(c.amountPiastres),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        Text(c.wasModified ? 'معدّل (${c.revision})' : 'أصلي'),
                      ),
                      DataCell(Text(c.notes.isEmpty ? '-' : c.notes)),
                    ],
                  ),
              ],
            ),
          ),
        );
    }
  }
}
