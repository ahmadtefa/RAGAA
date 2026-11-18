// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/date_ranges.dart';
import '../../core/formatters.dart';
import '../../models/report_models.dart';
import '../../state/ragaa_controller.dart';
import '../widgets/collection_form_dialog.dart';
import '../widgets/common_widgets.dart';
import '../widgets/outlet_form_dialog.dart';

/// Main accounting dashboard displaying totals by period, outlet, and shift,
/// plus unrecorded shifts for today.
class DashboardPage extends StatefulWidget {
  final RagaaController controller;
  final VoidCallback onNavigateToReports;

  const DashboardPage({
    super.key,
    required this.controller,
    required this.onNavigateToReports,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  ReportPeriodType _periodType = ReportPeriodType.daily;
  DateTime _customStart = dateOnly(DateTime.now());
  DateTime _customEnd = dateOnly(DateTime.now());
  ReportData? _report;
  bool _loading = true;
  int _lastSeenRevision = -1;

  OperationalDateRange _buildRange() {
    final now = dateOnly(DateTime.now());
    switch (_periodType) {
      case ReportPeriodType.daily:
        return OperationalDateRange.daily(now);
      case ReportPeriodType.weekly:
        return OperationalDateRange.weekly(now);
      case ReportPeriodType.monthly:
        return OperationalDateRange.monthly(now.year, now.month);
      case ReportPeriodType.custom:
        final end = _customEnd.isBefore(_customStart) ? _customStart : _customEnd;
        return OperationalDateRange.custom(_customStart, end);
    }
  }

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

  Future<void> _reload() async {
    _lastSeenRevision = widget.controller.dataRevision;
    setState(() => _loading = true);
    final data = await widget.controller.buildReport(
      ReportFilter(range: _buildRange()),
    );
    if (mounted) {
      setState(() {
        _report = data;
        _loading = false;
      });
    }
  }

  Future<void> _openAddOutlet() async {
    final created = await OutletFormDialog.show(
      context,
      controller: widget.controller,
    );
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت إضافة المنفذ "${created.name}" بنجاح')),
      );
    }
  }

  Future<void> _openAddCollection({
    String? outletId,
    int? shiftNumber,
  }) async {
    if (widget.controller.activeOutlets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف منفذًا نشطًا أولًا لتسجيل التحصيل')),
      );
      return;
    }
    final saved = await CollectionFormDialog.show(
      context,
      controller: widget.controller,
      initialOutletId: outletId,
      initialShiftNumber: shiftNumber,
      initialDate: DateTime.now(),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ تحصيل "${saved.outletName}" — ${saved.shiftTitle}: ${formatMoney(saved.amountPiastres, withCurrency: true)}',
          ),
        ),
      );
    }
  }

  Future<void> _pickCustomDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _customStart : _customEnd,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final d = dateOnly(picked);
      if (isStart) {
        _customStart = d;
        if (_customEnd.isBefore(_customStart)) _customEnd = _customStart;
      } else {
        _customEnd = d;
        if (_customStart.isAfter(_customEnd)) _customStart = _customEnd;
      }
    });
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final missingToday = widget.controller.todayMissingShifts;
    final activeOutletsCount = widget.controller.activeOutlets.length;
    final totalOutletsCount = widget.controller.outlets.length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Top Header & Quick Actions
        Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'لوحة التحكم المركزية',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  report?.filter.range.arabicDescription ??
                      'اليوم التشغيلي: ${dateKey(DateTime.now())}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('dashboard_add_collection_btn'),
                  onPressed: () => _openAddCollection(),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('تسجيل تحصيل'),
                ),
                OutlinedButton.icon(
                  key: const Key('dashboard_add_outlet_btn'),
                  onPressed: _openAddOutlet,
                  icon: const Icon(Icons.add_business_outlined, size: 18),
                  label: const Text('إضافة منفذ'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onNavigateToReports,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('التقارير والتصدير'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Period Filter Selector
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<ReportPeriodType>(
              segments: const [
                ButtonSegment(
                  value: ReportPeriodType.daily,
                  label: Text('اليوم'),
                ),
                ButtonSegment(
                  value: ReportPeriodType.weekly,
                  label: Text('الأسبوع'),
                ),
                ButtonSegment(
                  value: ReportPeriodType.monthly,
                  label: Text('الشهر'),
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
            ),
            if (_periodType == ReportPeriodType.custom) ...[
              OutlinedButton.icon(
                onPressed: () => _pickCustomDate(isStart: true),
                icon: const Icon(Icons.calendar_today, size: 15),
                label: Text('من: ${dateKey(_customStart)}'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickCustomDate(isStart: false),
                icon: const Icon(Icons.event, size: 15),
                label: Text('إلى: ${dateKey(_customEnd)}'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),

        if (_loading || report == null)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          // KPI Cards Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 980
                  ? 4
                  : constraints.maxWidth >= 520
                      ? 2
                      : 1;
              final itemWidth =
                  (constraints.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: KpiMetricCard(
                      title: 'إجمالي التحصيل للفترة',
                      value: formatMoney(
                        report.grandTotalPiastres,
                        withCurrency: true,
                      ),
                      subtitle: '${report.totalEntries} وردية مسجلة',
                      icon: Icons.account_balance_wallet,
                      highlighted: true,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: KpiMetricCard(
                      title: 'المنافذ المسجلة',
                      value: '$activeOutletsCount نشط',
                      subtitle: totalOutletsCount == activeOutletsCount
                          ? 'جميع المنافذ مفعّلة'
                          : 'من إجمالي $totalOutletsCount منفذ',
                      icon: Icons.storefront,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: KpiMetricCard(
                      title: 'متوسط اليوم التشغيلي',
                      value: formatMoney(
                        report.dailyAveragePiastres,
                        withCurrency: true,
                      ),
                      subtitle: '${report.activeDaysCount} يوم به تحصيل',
                      icon: Icons.trending_up,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: KpiMetricCard(
                      title: 'ورديات اليوم المتبقية',
                      value: '${missingToday.length}',
                      subtitle: missingToday.isEmpty && activeOutletsCount > 0
                          ? 'اكتمل تسجيل جميع ورديات اليوم'
                          : 'بتاريخ ${dateKey(DateTime.now())}',
                      icon: missingToday.isEmpty
                          ? Icons.task_alt
                          : Icons.pending_actions,
                      accentColor: missingToday.isEmpty
                          ? AppTheme.positiveGreen
                          : AppTheme.warningAmber,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),

          // Shift Totals Cards
          SectionCard(
            title: 'إجمالي التحصيل حسب الوردية',
            subtitle: 'توزيع المبالغ المحصلة عبر الورديات خلال الفترة المحددة',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 700;
                final children = report.byShift.map((s) {
                  final ratio = s.shareOf(report.grandTotalPiastres);
                  final card = Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              s.shiftLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            StatusBadge(
                              text: '${(ratio * 100).toStringAsFixed(1)}%',
                              color: AppTheme.brandPrimary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formatMoney(s.totalPiastres, withCurrency: true),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${s.entriesCount} سجل — المتوسط: ${formatMoney(s.averagePiastres, withCurrency: true)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFE2E8F0),
                            color: AppTheme.brandPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                  return wide
                      ? Expanded(child: card)
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: card,
                        );
                }).toList();

                if (wide) {
                  return Row(
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        children[i],
                      ],
                    ],
                  );
                }
                return Column(children: children);
              },
            ),
          ),
          const SizedBox(height: 18),

          // Outlet Breakdown Section
          SectionCard(
            title: 'إجمالي التحصيل حسب المنفذ',
            subtitle: 'مقارنة تحصيل كل منفذ وتفصيل وردياته في الفترة المختارة',
            child: report.byOutlet.isEmpty
                ? EmptyStateBox(
                    icon: Icons.storefront_outlined,
                    title: 'لم تتم إضافة أي منافذ بعد',
                    subtitle:
                        'ابدأ بإضافة المنافذ وتحديد عدد ورديات كل منفذ (ورديتان أو 3 ورديات)',
                    action: FilledButton.icon(
                      onPressed: _openAddOutlet,
                      icon: const Icon(Icons.add_business),
                      label: const Text('إضافة أول منفذ'),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < report.byOutlet.length; i++) ...[
                        if (i > 0) const Divider(height: 18),
                        _OutletDashboardTile(
                          row: report.byOutlet[i],
                          grandTotal: report.grandTotalPiastres,
                        ),
                      ],
                    ],
                  ),
          ),

          // Missing Shifts for Today
          if (missingToday.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionCard(
              title: 'ورديات اليوم غير المسجلة بعد (${missingToday.length})',
              subtitle:
                  'اليوم التشغيلي ${dateKey(DateTime.now())} — اضغط على أي وردية لتسجيل تحصيلها مباشرة',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in missingToday)
                    ActionChip(
                      avatar: const Icon(
                        Icons.add_circle_outline,
                        size: 18,
                        color: AppTheme.brandPrimary,
                      ),
                      label: Text(
                        '${m.outletName} — ${m.shiftLabel} (${m.timeRange})',
                      ),
                      onPressed: () => _openAddCollection(
                        outletId: m.outletId,
                        shiftNumber: m.shiftNumber,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _OutletDashboardTile extends StatelessWidget {
  final OutletReportRow row;
  final int grandTotal;

  const _OutletDashboardTile({
    required this.row,
    required this.grandTotal,
  });

  @override
  Widget build(BuildContext context) {
    final share = row.shareOf(grandTotal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    row.outletName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  StatusBadge(
                    text: row.configuredShiftCount == 2 ? 'ورديتان' : '3 ورديات',
                    color: const Color(0xFF475569),
                  ),
                  if (!row.isActive)
                    const StatusBadge(
                      text: 'متوقف',
                      color: AppTheme.warningAmber,
                    ),
                ],
              ),
            ),
            Text(
              formatMoney(row.totalPiastres, withCurrency: true),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppTheme.brandPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(
              'أولى: ${formatMoney(row.shift1Piastres)} ج.م',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
            ),
            Text(
              'ثانية: ${formatMoney(row.shift2Piastres)} ج.م',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
            ),
            if (row.configuredShiftCount == 3 || row.shift3Piastres > 0)
              Text(
                'ثالثة: ${formatMoney(row.shift3Piastres)} ج.م',
                style:
                    const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
              ),
            Text(
              'النسبة: ${(share * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 6,
            backgroundColor: const Color(0xFFE2E8F0),
            color: AppTheme.brandSecondary,
          ),
        ),
      ],
    );
  }
}
