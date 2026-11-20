// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/exceptions.dart';
import '../../core/formatters.dart';
import '../../models/collection_record.dart';
import '../../models/collection_amounts.dart';
import '../../models/outlet.dart';
import '../../state/ragaa_controller.dart';

/// Dialog for recording a new shift collection or making an audited edit to an
/// existing collection entry.
///
/// Actively detects duplicate `(outlet, operationalDate, shiftNumber)` entries,
/// blocks silent overwrites, and requires explicit confirmation + optional reason
/// recorded in `audit_logs`.
class CollectionFormDialog extends StatefulWidget {
  final RagaaController controller;
  final CollectionRecord? editingRecord;
  final String? initialOutletId;
  final int? initialShiftNumber;
  final DateTime? initialDate;

  const CollectionFormDialog({
    super.key,
    required this.controller,
    this.editingRecord,
    this.initialOutletId,
    this.initialShiftNumber,
    this.initialDate,
  });

  static Future<CollectionRecord?> show(
    BuildContext context, {
    required RagaaController controller,
    CollectionRecord? editingRecord,
    String? initialOutletId,
    int? initialShiftNumber,
    DateTime? initialDate,
  }) {
    return showDialog<CollectionRecord>(
      context: context,
      builder: (_) => CollectionFormDialog(
        controller: controller,
        editingRecord: editingRecord,
        initialOutletId: initialOutletId,
        initialShiftNumber: initialShiftNumber,
        initialDate: initialDate,
      ),
    );
  }

  @override
  State<CollectionFormDialog> createState() => _CollectionFormDialogState();
}

class _CollectionFormDialogState extends State<CollectionFormDialog> {
  late String _outletId;
  late int _shiftNumber;
  late DateTime _operationalDate;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _manualFeesCtrl;
  late final TextEditingController _automaticFeesCtrl;
  late final TextEditingController _totalFeesCtrl;
  late final TextEditingController _nfcCtrl;
  late final TextEditingController _visaCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _reasonCtrl;

  CollectionRecord? _detectedDuplicate;
  bool _saving = false;
  String? _errorText;

  bool get _isEditing => widget.editingRecord != null;

  List<Outlet> get _selectableOutlets => widget.controller.activeOutlets;

  Outlet _currentOutlet() => _selectableOutlets.firstWhere(
        (o) => o.id == _outletId,
        orElse: () => _selectableOutlets.first,
      );

  @override
  void initState() {
    super.initState();
    final editing = widget.editingRecord;
    if (editing != null) {
      _outletId = editing.outletId;
      _shiftNumber = editing.shiftNumber;
      _operationalDate = parseOperationalDate(editing.operationalDate) ??
          dateOnly(DateTime.now());
      _amountCtrl = TextEditingController(
        text: formatEditableAmount(editing.generalTotalPiastres),
      );
      _manualFeesCtrl = TextEditingController(
          text: formatEditableAmount(editing.manualFeesPiastres));
      _automaticFeesCtrl = TextEditingController(
          text: formatEditableAmount(editing.automaticFeesPiastres));
      _totalFeesCtrl = TextEditingController(
          text: formatEditableAmount(editing.totalFeesPiastres));
      _nfcCtrl = TextEditingController(
          text: editing.nfcPiastres == 0
              ? ''
              : formatEditableAmount(editing.nfcPiastres));
      _visaCtrl = TextEditingController(
          text: editing.visaPiastres == 0
              ? ''
              : formatEditableAmount(editing.visaPiastres));
      _notesCtrl = TextEditingController(text: editing.notes);
      _reasonCtrl = TextEditingController();
    } else {
      final outlets = _selectableOutlets;
      final preferredId = widget.initialOutletId;
      _outletId =
          (preferredId != null && outlets.any((o) => o.id == preferredId))
              ? preferredId
              : outlets.first.id;
      final outlet = _currentOutlet();
      final preferredShift = widget.initialShiftNumber ?? 1;
      _shiftNumber =
          (preferredShift >= 1 && preferredShift <= outlet.shiftCount)
              ? preferredShift
              : 1;
      _operationalDate = dateOnly(widget.initialDate ?? DateTime.now());
      _amountCtrl = TextEditingController();
      _manualFeesCtrl = TextEditingController();
      _automaticFeesCtrl = TextEditingController();
      _totalFeesCtrl = TextEditingController();
      _nfcCtrl = TextEditingController();
      _visaCtrl = TextEditingController();
      _notesCtrl = TextEditingController();
      _reasonCtrl = TextEditingController();
      _checkDuplicate();
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _manualFeesCtrl.dispose();
    _automaticFeesCtrl.dispose();
    _totalFeesCtrl.dispose();
    _nfcCtrl.dispose();
    _visaCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkDuplicate() async {
    if (_isEditing) return;
    final found = await widget.controller.findExistingCollection(
      outletId: _outletId,
      operationalDate: dateKey(_operationalDate),
      shiftNumber: _shiftNumber,
    );
    if (mounted) {
      setState(() => _detectedDuplicate = found);
    }
  }

  Future<void> _pickOperationalDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _operationalDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (chosen != null && mounted) {
      setState(() => _operationalDate = dateOnly(chosen));
      await _checkDuplicate();
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    int? amountOrZero(TextEditingController field) =>
        field.text.trim().isEmpty ? 0 : tryParsePiastres(field.text);
    final piastres = tryParsePiastres(_amountCtrl.text);
    final manual = amountOrZero(_manualFeesCtrl);
    final automatic = amountOrZero(_automaticFeesCtrl);
    final totalFees = amountOrZero(_totalFeesCtrl);
    final nfc = amountOrZero(_nfcCtrl);
    final visa = amountOrZero(_visaCtrl);
    if (piastres == null || manual == null || automatic == null ||
        totalFees == null || nfc == null || visa == null) {
      setState(() => _errorText = 'أدخل مبالغ صحيحة بحد أقصى رقمين عشريين');
      return;
    }
    if (piastres < totalFees) {
      setState(() => _errorText = 'إجمالي الرسوم أكبر من الإجمالي العام');
      return;
    }
    final amounts = CollectionAmounts(
      manualFeesPiastres: manual,
      automaticFeesPiastres: automatic,
      totalFeesPiastres: totalFees,
      generalTotalPiastres: piastres,
      nfcPiastres: nfc,
      visaPiastres: visa,
    );

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      if (_isEditing) {
        final updated = await widget.controller.updateCollection(
          collectionId: widget.editingRecord!.id,
          newAmounts: amounts,
          notes: _notesCtrl.text,
          reason: _reasonCtrl.text.trim().isEmpty
              ? 'تعديل يدوي لسجل التحصيل'
              : _reasonCtrl.text.trim(),
        );
        if (mounted) Navigator.of(context).pop(updated);
        return;
      }

      // Attempt strict insert first.
      final created = await widget.controller.createCollection(
        outletId: _outletId,
        operationalDate: dateKey(_operationalDate),
        shiftNumber: _shiftNumber,
        amounts: amounts,
        notes: _notesCtrl.text,
      );
      if (mounted) Navigator.of(context).pop(created);
    } on DuplicateCollectionException catch (dup) {
      if (!mounted) return;
      setState(() {
        _detectedDuplicate = dup.existing;
        _saving = false;
      });
      final confirmReason = await _confirmAuditedReplacement(
        dup.existing,
        piastres,
      );
      if (confirmReason == null || !mounted) return;

      setState(() => _saving = true);
      try {
        final updated = await widget.controller.updateCollection(
          collectionId: dup.existing.id,
          newAmounts: amounts,
          notes: _notesCtrl.text.trim().isEmpty
              ? dup.existing.notes
              : _notesCtrl.text,
          reason: confirmReason,
        );
        if (mounted) Navigator.of(context).pop(updated);
      } on RagaaException catch (e) {
        if (mounted) {
          setState(() {
            _errorText = e.message;
            _saving = false;
          });
        }
      }
    } on RagaaException catch (e) {
      if (mounted) {
        setState(() {
          _errorText = e.message;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorText = e.toString();
          _saving = false;
        });
      }
    }
  }

  Future<String?> _confirmAuditedReplacement(
    CollectionRecord existing,
    int newPiastres,
  ) {
    return showDialog<String>(
      context: context,
      builder: (_) => _DuplicateConfirmDialog(
        existing: existing,
        newPiastres: newPiastres,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editingRecord;
    final today = dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);

    return AlertDialog(
      title: Text(
        _isEditing ? 'تعديل تحصيل وردية' : 'تسجيل تحصيل وردية',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 320),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (editing != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        editing.outletName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'التاريخ التشغيلي: ${editing.operationalDate} — ${editing.shiftTitle}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'المبلغ الحالي: ${formatMoney(editing.amountPiastres, withCurrency: true)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brandPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ] else ...[
                DropdownButtonFormField<String>(
                  key: const Key('collection_outlet_dropdown'),
                  isExpanded: true,
                  initialValue: _outletId,
                  decoration: const InputDecoration(
                    labelText: 'المنفذ',
                    prefixIcon: Icon(Icons.storefront),
                  ),
                  items: _selectableOutlets
                      .map(
                        (o) => DropdownMenuItem<String>(
                          value: o.id,
                          child: Text('${o.name} (${o.shiftCountArabic})'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _outletId = v;
                      final maxShifts = _currentOutlet().shiftCount;
                      if (_shiftNumber > maxShifts) {
                        _shiftNumber = 1;
                      }
                    });
                    _checkDuplicate();
                  },
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final outlet = _currentOutlet();
                    final shifts = outlet.activeShifts;
                    return DropdownButtonFormField<int>(
                      key: ValueKey(
                        'shift_${outlet.id}_${outlet.shiftCount}_$_shiftNumber',
                      ),
                      isExpanded: true,
                      initialValue: _shiftNumber,
                      decoration: const InputDecoration(
                        labelText: 'الوردية',
                        prefixIcon: Icon(Icons.access_time),
                      ),
                      items: shifts
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: s.shiftNumber,
                              child: Text(s.displayLabel),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _shiftNumber = v);
                        _checkDuplicate();
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'التاريخ التشغيلي للوردية',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickOperationalDate,
                      icon: const Icon(Icons.calendar_month, size: 18),
                      label: Text(
                        '${arabicWeekday(_operationalDate)} ${dateKey(_operationalDate)}',
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('اليوم'),
                      selected: dateKey(_operationalDate) == dateKey(today),
                      onSelected: (_) {
                        setState(() => _operationalDate = today);
                        _checkDuplicate();
                      },
                    ),
                    ChoiceChip(
                      label: const Text('أمس'),
                      selected: dateKey(_operationalDate) == dateKey(yesterday),
                      onSelected: (_) {
                        setState(() => _operationalDate = yesterday);
                        _checkDuplicate();
                      },
                    ),
                  ],
                ),
                if (_detectedDuplicate != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: AppTheme.warningAmber,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تنبيه: هذه الوردية مسجلة مسبقًا بمبلغ ${formatMoney(_detectedDuplicate!.amountPiastres, withCurrency: true)}. يمنع النظام التكرار، وعند الحفظ سيطلب تأكيد تعديل المبلغ مع توثيقه في سجل المراجعة.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
              ],
              TextField(
                key: const Key('collection_amount_field'),
                controller: _amountCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'إجمالي مبلغ التحصيل (ج.م)',
                  hintText: '0.00',
                  suffixText: 'ج.م',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  errorText: _errorText,
                ),
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _amountField(_manualFeesCtrl, 'الرسوم اليدوية')),
                const SizedBox(width: 8),
                Expanded(
                    child: _amountField(_automaticFeesCtrl, 'الرسوم الآلية')),
              ]),
              const SizedBox(height: 10),
              _amountField(_totalFeesCtrl, 'إجمالي الرسوم (مستقل)'),
              const SizedBox(height: 10),
              _calculatedScalesField(),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _amountField(_nfcCtrl, 'NFC (اختياري)')),
                const SizedBox(width: 8),
                Expanded(child: _amountField(_visaCtrl, 'VISA (اختياري)')),
              ]),
              const SizedBox(height: 12),
              TextField(
                key: const Key('collection_notes_field'),
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  prefixIcon: Icon(Icons.sticky_note_2_outlined),
                ),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('collection_reason_field'),
                  controller: _reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'سبب التعديل (يُحفظ في سجل المراجعة)',
                    hintText: 'مثال: مراجعة إيصال خزينة',
                    prefixIcon: Icon(Icons.history_edu),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          key: const Key('collection_save_button'),
          onPressed: _saving ? null : _submit,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: Text(
            _saving
                ? 'جارٍ الحفظ...'
                : (_isEditing ? 'حفظ التعديل' : 'حفظ التحصيل'),
          ),
        ),
      ],
    );
  }

  Widget _amountField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        textInputAction: TextInputAction.next,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
            labelText: label, hintText: '0.00', suffixText: 'ج.م'),
      );

  Widget _calculatedScalesField() {
    final general = tryParsePiastres(_amountCtrl.text) ?? 0;
    final fees = tryParsePiastres(_totalFeesCtrl.text) ?? 0;
    final scales = general - fees;
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'إجمالي الموازين (محسوب)',
        suffixText: 'ج.م',
        prefixIcon: Icon(Icons.calculate_outlined),
      ),
      child: Text(formatEditableAmount(scales)),
    );
  }
}

class _DuplicateConfirmDialog extends StatefulWidget {
  final CollectionRecord existing;
  final int newPiastres;

  const _DuplicateConfirmDialog({
    required this.existing,
    required this.newPiastres,
  });

  @override
  State<_DuplicateConfirmDialog> createState() =>
      _DuplicateConfirmDialogState();
}

class _DuplicateConfirmDialogState extends State<_DuplicateConfirmDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delta = widget.newPiastres - widget.existing.amountPiastres;
    return AlertDialog(
      title: const Text('منع تكرار التحصيل — تأكيد التعديل'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'يوجد سجل مسجل بالفعل لمنفذ "${widget.existing.outletName}" — ${widget.existing.shiftTitle} بتاريخ ${widget.existing.operationalDate}.',
            ),
            const SizedBox(height: 10),
            Text(
              'المبلغ السابق: ${formatMoney(widget.existing.amountPiastres, withCurrency: true)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              'المبلغ الجديد: ${formatMoney(widget.newPiastres, withCurrency: true)} (${formatMoneyDelta(delta)})',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.brandPrimary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('duplicate_reason_field'),
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'سبب التعديل لسجل المراجعة',
                hintText: 'مثال: تصحيح جرد الوردية',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('duplicate_confirm_button'),
          onPressed: () {
            final r = _reasonCtrl.text.trim().isEmpty
                ? 'استبدال مبلغ وردية مسجلة بعد التأكيد'
                : _reasonCtrl.text.trim();
            Navigator.of(context).pop(r);
          },
          child: const Text('تأكيد التعديل وتوثيقه'),
        ),
      ],
    );
  }
}
