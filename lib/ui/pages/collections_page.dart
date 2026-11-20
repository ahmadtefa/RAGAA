// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/date_ranges.dart';
import '../../core/formatters.dart';
import '../../models/audit_log_entry.dart';
import '../../models/collection_record.dart';
import '../../state/ragaa_controller.dart';
import '../widgets/collection_form_dialog.dart';
import '../widgets/common_widgets.dart';
import '../widgets/responsive_layout.dart';

/// Page for daily collection entry, filtering, audited modification, and
/// viewing per-record revision history.
class CollectionsPage extends StatefulWidget {
  final RagaaController controller;

  const CollectionsPage({super.key, required this.controller});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  DateTime _fromDate = dateOnly(DateTime.now());
  DateTime _toDate = dateOnly(DateTime.now());
  String? _selectedOutletId;
  int? _selectedShift;
  List<CollectionRecord> _records = const [];
  bool _loading = true;
  int _lastSeenRevision = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _reload();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (widget.controller.dataRevision != _lastSeenRevision) {
      _reload();
    }
  }

  Future<void> _reload() async {
    _lastSeenRevision = widget.controller.dataRevision;
    if (_fromDate.isAfter(_toDate)) {
      setState(() {
        _records = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final rows = await widget.controller.queryCollections(
      range: OperationalDateRange.custom(_fromDate, _toDate),
      outletIds: _selectedOutletId != null ? {_selectedOutletId!} : const {},
      shiftNumber: _selectedShift,
    );
    if (mounted) {
      setState(() {
        _records = rows;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: isStart ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      final d = dateOnly(chosen);
      if (isStart) {
        _fromDate = d;
        if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
      } else {
        _toDate = d;
        if (_fromDate.isAfter(_toDate)) _fromDate = _toDate;
      }
    });
    await _reload();
  }

  Future<void> _addCollection() async {
    if (widget.controller.activeOutlets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أضف منفذًا نشطًا أولًا من تبويب المنافذ والورديات'),
        ),
      );
      return;
    }
    final saved = await CollectionFormDialog.show(
      context,
      controller: widget.controller,
      initialOutletId: _selectedOutletId,
      initialDate: _toDate,
    );
    if (saved != null && mounted) {
      // Expand visible date filter if the saved entry falls outside it.
      final recDate = parseOperationalDate(saved.operationalDate);
      if (recDate != null &&
          (recDate.isBefore(_fromDate) || recDate.isAfter(_toDate))) {
        setState(() {
          if (recDate.isBefore(_fromDate)) _fromDate = recDate;
          if (recDate.isAfter(_toDate)) _toDate = recDate;
        });
        await _reload();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم حفظ تحصيل "${saved.outletName}" (${saved.shiftTitle}) بنجاح',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editCollection(CollectionRecord record) async {
    final updated = await CollectionFormDialog.show(
      context,
      controller: widget.controller,
      editingRecord: record,
    );
    if (updated != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تعديل المبلغ إلى ${formatMoney(updated.amountPiastres, withCurrency: true)} وتسجيل العملية في سجل المراجعة',
          ),
        ),
      );
    }
  }

  Future<void> _showRecordAuditHistory(CollectionRecord record) async {
    final logs = await widget.controller.queryAuditLogs(
      entityType: AuditEntityType.collection,
      entityId: record.id.toString(),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('سجل مراجعة: ${record.outletName} — ${record.shiftTitle}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
          child: logs.isEmpty
              ? const Text('لا توجد سجلات مراجعة.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (_, index) {
                    final log = logs[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            StatusBadge(
                              text: log.action.arabicLabel,
                              color: log.action == AuditAction.create
                                  ? AppTheme.positiveGreen
                                  : AppTheme.warningAmber,
                            ),
                            Text(
                              formatTimestamp(log.createdAt),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(log.summary, style: const TextStyle(fontSize: 13)),
                        if (log.reason.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            'السبب: ${log.reason}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outlets = widget.controller.outlets;
    final totalPiastres =
        _records.fold<int>(0, (sum, r) => sum + r.amountPiastres);

    return ListView(
      padding: responsivePagePadding(context, withFabInset: true),
      children: [
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
                  'تسجيل وإدارة التحصيل',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                Text(
                  'سجل واحد لكل (منفذ + تاريخ تشغيلي + وردية) مع توثيق كامل لأي تعديل',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
            FilledButton.icon(
              key: const Key('collections_new_btn'),
              onPressed: _addCollection,
              icon: const Icon(Icons.add_card, size: 18),
              label: const Text('تسجيل تحصيل وردية'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Filters Bar
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: true),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('من: ${dateKey(_fromDate)}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isStart: false),
                  icon: const Icon(Icons.event, size: 16),
                  label: Text('إلى: ${dateKey(_toDate)}'),
                ),
                ActionChip(
                  label: const Text('اليوم'),
                  onPressed: () {
                    final d = dateOnly(DateTime.now());
                    setState(() {
                      _fromDate = d;
                      _toDate = d;
                    });
                    _reload();
                  },
                ),
                ActionChip(
                  label: const Text('هذا الشهر'),
                  onPressed: () {
                    final now = DateTime.now();
                    final r = OperationalDateRange.monthly(now.year, now.month);
                    setState(() {
                      _fromDate = r.start;
                      _toDate = r.end;
                    });
                    _reload();
                  },
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('col_outlet_filter_$_selectedOutletId'),
                    isExpanded: true,
                    initialValue: _selectedOutletId,
                    decoration: const InputDecoration(
                      labelText: 'المنفذ',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('كل المنافذ'),
                      ),
                      ...outlets.map(
                        (o) => DropdownMenuItem<String?>(
                          value: o.id,
                          child: Text(
                            o.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedOutletId = v);
                      _reload();
                    },
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: DropdownButtonFormField<int?>(
                    key: ValueKey('col_shift_filter_$_selectedShift'),
                    isExpanded: true,
                    initialValue: _selectedShift,
                    decoration: const InputDecoration(
                      labelText: 'الوردية',
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Quick Total Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.brandPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.brandPrimary.withValues(alpha: 0.2),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 16,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'عدد السجلات المعروضة: ${_records.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                AmountText(
                  'الإجمالي: ${formatMoney(totalPiastres, withCurrency: true)}',
                  fontSize: 16,
                  color: AppTheme.brandPrimary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Records List
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(36),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_records.isEmpty)
          EmptyStateBox(
            icon: Icons.receipt_long_outlined,
            title: 'لا توجد سجلات تحصيل في النطاق المحدد',
            subtitle: 'اضغط "تسجيل تحصيل وردية" لإضافة سجل جديد أو وسّع فترة البحث',
            action: FilledButton.icon(
              onPressed: _addCollection,
              icon: const Icon(Icons.add),
              label: const Text('تسجيل تحصيل جديد'),
            ),
          )
        else
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _records.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final rec = _records[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // The record data keeps the full width; the amount and the
                      // two action buttons move to their own row on phones so the
                      // outlet name and shift are never squeezed.
                      final data = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                rec.outletName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              StatusBadge(
                                text: rec.shiftTitle,
                                color: AppTheme.brandPrimary,
                              ),
                              if (rec.wasModified)
                                StatusBadge(
                                  text: 'معدّل (${rec.revision})',
                                  color: AppTheme.warningAmber,
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'التاريخ التشغيلي: ${rec.operationalDate}'
                            '${rec.shiftScheduleDisplay.isNotEmpty ? " | الموعد: ${rec.shiftScheduleDisplay}" : ""}'
                            '${rec.notes.isNotEmpty ? " | ${rec.notes}" : ""}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _amountChip('يدوي', rec.manualFeesPiastres),
                              _amountChip('آلي', rec.automaticFeesPiastres),
                              _amountChip('إجمالي الرسوم', rec.totalFeesPiastres),
                              _amountChip(
                                'الموازين',
                                rec.scalesTotalPiastres,
                                emphasised: true,
                              ),
                              _amountChip('NFC', rec.nfcPiastres),
                              _amountChip('VISA', rec.visaPiastres),
                              _amountChip(
                                'الإجمالي',
                                rec.generalTotalPiastres,
                                emphasised: true,
                              ),
                            ],
                          ),
                        ],
                      );
                      final amount = AmountText(
                        formatMoney(rec.amountPiastres, withCurrency: true),
                        fontSize: 16.5,
                      );
                      final actions = <Widget>[
                        IconButton(
                          tooltip: 'تعديل المبلغ (مع سجل مراجعة)',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _editCollection(rec),
                        ),
                        IconButton(
                          tooltip: 'عرض سجل مراجعة الوردية',
                          icon: const Icon(Icons.history, size: 20),
                          onPressed: () => _showRecordAuditHistory(rec),
                        ),
                      ];
                      if (constraints.maxWidth < 640) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            data,
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(child: amount),
                                ...actions,
                              ],
                            ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: data),
                          const SizedBox(width: 12),
                          // Cap the amount so a large text scale can never push
                          // it past the card edge; it scales down only when the
                          // natural width does not fit.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.4,
                            ),
                            child: amount,
                          ),
                          const SizedBox(width: 8),
                          ...actions,
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Compact amount chip so every approved financial field stays visible on the
  /// collection list (desktop and phone).
  Widget _amountChip(String label, int value, {bool emphasised = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: emphasised
              ? AppTheme.brandPrimary.withValues(alpha: 0.08)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$label: ${formatMoney(value)}',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
            color: emphasised
                ? AppTheme.brandPrimary
                : const Color(0xFF334155),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
}
