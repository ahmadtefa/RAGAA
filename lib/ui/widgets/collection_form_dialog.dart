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
    // A collection is entered one-handed, standing at the counter: the form
    // takes the whole screen instead of a dialog that a phone keyboard would
    // swallow, and it slides up like every other full-screen task.
    return Navigator.of(context).push<CollectionRecord>(
      MaterialPageRoute<CollectionRecord>(
        fullscreenDialog: true,
        builder: (_) => CollectionFormDialog(
          controller: controller,
          editingRecord: editingRecord,
          initialOutletId: initialOutletId,
          initialShiftNumber: initialShiftNumber,
          initialDate: initialDate,
        ),
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
  bool _dirty = false;
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
        if (mounted) _finish(updated);
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
      if (mounted) _finish(created);
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
        if (mounted) _finish(updated);
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

  void _markDirty() {
    _dirty = true;
  }

  /// Leaves the screen with a result, once the widget tree agrees that it may
  /// close: the unsaved-data guard reads `_dirty` during the next build, so the
  /// pop is queued behind that build instead of fighting the guard.
  void _finish(CollectionRecord? result) {
    setState(() {
      _dirty = false;
      _saving = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('خروج دون حفظ؟'),
        content: const Text(
          'الأرقام التي أدخلتها لم تُحفظ بعد. إن خرجت الآن ستُفقد هذه البيانات.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('متابعة الإدخال'),
          ),
          FilledButton(
            key: const Key('discard_entry_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('خروج دون حفظ'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.editingRecord;
    final today = dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final general = tryParsePiastres(_amountCtrl.text) ?? 0;
    final fees = tryParsePiastres(_totalFeesCtrl.text) ?? 0;
    final scales = general - fees;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmDiscard();
        if (!mounted || !leave) return;
        setState(() => _dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'تعديل تحصيل وردية' : 'تسجيل تحصيل وردية'),
          centerTitle: false,
        ),
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final horizontal = wide ? 28.0 : 14.0;
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _shiftSection(theme, editing, today, yesterday),
                        const SizedBox(height: 14),
                        _amountsSection(theme, wide),
                        const SizedBox(height: 14),
                        _notesSection(theme),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // The save bar is the scaffold's own bottom bar, not a row inside the
        // body: a snackbar ("تم نسخ المسار", a validation note) then floats
        // above it instead of covering the button, and the keyboard inset lifts
        // it clear of the keys rather than hiding it behind them.
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: _saveBar(theme, scales: scales, wide: _wideFor(context)),
        ),
      ),
    );
  }

  Widget _sectionCard(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _shiftSection(
    ThemeData theme,
    CollectionRecord? editing,
    DateTime today,
    DateTime yesterday,
  ) {
    return _sectionCard(
      theme,
      title: 'الوردية والمنفذ',
      icon: Icons.storefront_outlined,
      children: [
        if (editing != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editing.outletName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'التاريخ التشغيلي: ${editing.operationalDate} — ${editing.shiftTitle}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'المبلغ الحالي: ${formatMoney(editing.amountPiastres, withCurrency: true)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          )
        else ...[
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
              _markDirty();
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
                  _markDirty();
                  _checkDuplicate();
                },
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            'التاريخ التشغيلي للوردية',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
                  _markDirty();
                  _checkDuplicate();
                },
              ),
              ChoiceChip(
                label: const Text('أمس'),
                selected: dateKey(_operationalDate) == dateKey(yesterday),
                onSelected: (_) {
                  setState(() => _operationalDate = yesterday);
                  _markDirty();
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
                color: AppTheme.turquoiseWash,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.warningAmber),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF92400E),
                      ),
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

  Widget _amountsSection(ThemeData theme, bool wide) {
    return _sectionCard(
      theme,
      title: 'المبالغ',
      icon: Icons.payments_outlined,
      children: [
        TextField(
          key: const Key('collection_amount_field'),
          controller: _amountCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          decoration: InputDecoration(
            labelText: 'إجمالي مبلغ التحصيل (ج.م)',
            hintText: '0.00',
            suffixText: 'ج.م',
            prefixIcon: const Icon(Icons.payments_outlined),
            errorText: _errorText,
            errorMaxLines: 3,
          ),
          onChanged: (_) {
            _markDirty();
            setState(() {});
          },
        ),
        const SizedBox(height: 14),
        if (wide)
          Row(
            children: [
              Expanded(child: _amountField(_manualFeesCtrl, 'الرسوم اليدوية')),
              const SizedBox(width: 12),
              Expanded(child: _amountField(_automaticFeesCtrl, 'الرسوم الآلية')),
            ],
          )
        else ...[
          _amountField(_manualFeesCtrl, 'الرسوم اليدوية'),
          const SizedBox(height: 10),
          _amountField(_automaticFeesCtrl, 'الرسوم الآلية'),
        ],
        const SizedBox(height: 10),
        _amountField(_totalFeesCtrl, 'إجمالي الرسوم (مستقل)'),
        const SizedBox(height: 14),
        _computedScales(theme),
        const SizedBox(height: 14),
        if (wide)
          Row(
            children: [
              Expanded(child: _amountField(_nfcCtrl, 'NFC (اختياري)')),
              const SizedBox(width: 12),
              Expanded(child: _amountField(_visaCtrl, 'VISA (اختياري)')),
            ],
          )
        else ...[
          _amountField(_nfcCtrl, 'NFC (اختياري)'),
          const SizedBox(height: 10),
          _amountField(_visaCtrl, 'VISA (اختياري)'),
        ],
      ],
    );
  }

  Widget _notesSection(ThemeData theme) {
    return _sectionCard(
      theme,
      title: 'ملاحظات وتوثيق',
      icon: Icons.edit_note_outlined,
      children: [
        TextField(
          key: const Key('collection_notes_field'),
          controller: _notesCtrl,
          textInputAction: TextInputAction.next,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'ملاحظات (اختياري)',
            prefixIcon: Icon(Icons.sticky_note_2_outlined),
          ),
          onChanged: (_) => _markDirty(),
        ),
        if (_isEditing) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('collection_reason_field'),
            controller: _reasonCtrl,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'سبب التعديل (يُحفظ في سجل المراجعة)',
              hintText: 'مثال: مراجعة إيصال خزينة',
              prefixIcon: Icon(Icons.history_edu),
            ),
            onChanged: (_) => _markDirty(),
          ),
        ],
      ],
    );
  }

  /// The number the operator looks at while typing: general total minus fees.
  /// It is a result, not an input, so it is drawn on its own tinted panel with
  /// the same figure repeated in the always-visible save bar.
  Widget _computedScales(ThemeData theme) {
    final general = tryParsePiastres(_amountCtrl.text) ?? 0;
    final fees = tryParsePiastres(_totalFeesCtrl.text) ?? 0;
    final scales = general - fees;
    final accent = theme.colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate_outlined, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'إجمالي الموازين (محسوب)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatEditableAmount(scales),
                  key: const Key('collection_scales_value'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'ج.م',
            style: theme.textTheme.labelLarge?.copyWith(color: accent),
          ),
        ],
      ),
    );
  }

  bool _wideFor(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 900;

  Widget _saveBar(ThemeData theme, {required int scales, required bool wide}) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('إجمالي الموازين', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    formatMoney(scales, withCurrency: true),
                    key: const Key('entry_scales_total'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              key: const Key('collection_save_button'),
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 20),
              label: Text(
                _saving
                    ? 'جارٍ الحفظ...'
                    : (_isEditing ? 'حفظ التعديل' : 'حفظ التحصيل'),
              ),
              style: FilledButton.styleFrom(
                minimumSize: Size(wide ? 200 : 150, 54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        textInputAction: TextInputAction.next,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) {
          _markDirty();
          setState(() {});
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: '0.00',
          suffixText: 'ج.م',
        ),
      );
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
