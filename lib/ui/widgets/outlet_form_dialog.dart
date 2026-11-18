// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/exceptions.dart';
import '../../core/formatters.dart';
import '../../models/outlet.dart';
import '../../models/outlet_shift.dart';
import '../../state/ragaa_controller.dart';

/// Dialog for creating a new outlet or editing an existing outlet's name,
/// independent shift count (2 or 3), and per-shift start/end schedules without
/// losing any historical collection data.
class OutletFormDialog extends StatefulWidget {
  final RagaaController controller;
  final Outlet? existing;

  const OutletFormDialog({
    super.key,
    required this.controller,
    this.existing,
  });

  static Future<Outlet?> show(
    BuildContext context, {
    required RagaaController controller,
    Outlet? existing,
  }) {
    return showDialog<Outlet>(
      context: context,
      builder: (_) => OutletFormDialog(
        controller: controller,
        existing: existing,
      ),
    );
  }

  @override
  State<OutletFormDialog> createState() => _OutletFormDialogState();
}

class _OutletFormDialogState extends State<OutletFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _reasonCtrl;
  late final List<TextEditingController> _labelCtrls;
  late List<String> _startTimes;
  late List<String> _endTimes;
  late int _shiftCount;
  late bool _isActive;
  int _historicalShift3Count = 0;
  bool _saving = false;
  String? _errorMessage;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _nameCtrl = TextEditingController(text: ex?.name ?? '');
    _notesCtrl = TextEditingController(text: ex?.notes ?? '');
    _reasonCtrl = TextEditingController();
    _shiftCount = ex?.shiftCount ?? 2;
    _isActive = ex?.isActive ?? true;

    _labelCtrls = [];
    _startTimes = [];
    _endTimes = [];
    for (var s = 1; s <= 3; s++) {
      final saved = ex?.shiftByNumber(s);
      final def = defaultShiftTimes(s, _shiftCount);
      _labelCtrls.add(
        TextEditingController(text: saved?.label ?? defaultShiftLabel(s)),
      );
      _startTimes.add(saved?.startTime ?? def.start);
      _endTimes.add(saved?.endTime ?? def.end);
    }

    if (ex != null) {
      widget.controller.countCollectionsForOutletShift(ex.id, 3).then((cnt) {
        if (mounted) setState(() => _historicalShift3Count = cnt);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    for (final c in _labelCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _onShiftCountChanged(int value) {
    setState(() {
      _shiftCount = value;
      // When creating a fresh outlet, align default hours cleanly with 2 vs 3 shifts.
      if (!_isEditing) {
        for (var s = 1; s <= 3; s++) {
          final def = defaultShiftTimes(s, value);
          _startTimes[s - 1] = def.start;
          _endTimes[s - 1] = def.end;
        }
      }
    });
  }

  Future<void> _pickTime(int shiftIndex, {required bool isStart}) async {
    final current = parseTime24(
      isStart ? _startTimes[shiftIndex] : _endTimes[shiftIndex],
    );
    final initial = TimeOfDay(
      hour: current?.hour ?? 8,
      minute: current?.minute ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      final formatted = formatTime24(picked.hour, picked.minute);
      setState(() {
        if (isStart) {
          _startTimes[shiftIndex] = formatted;
        } else {
          _endTimes[shiftIndex] = formatted;
        }
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final schedules = <ShiftScheduleInput>[
      for (var s = 1; s <= 3; s++)
        ShiftScheduleInput(
          shiftNumber: s,
          label: _labelCtrls[s - 1].text.trim().isEmpty
              ? defaultShiftLabel(s)
              : _labelCtrls[s - 1].text.trim(),
          startTime: _startTimes[s - 1],
          endTime: _endTimes[s - 1],
        ),
    ];

    try {
      final Outlet saved;
      if (_isEditing) {
        saved = await widget.controller.updateOutlet(
          outletId: widget.existing!.id,
          name: _nameCtrl.text,
          shiftCount: _shiftCount,
          schedules: schedules,
          isActive: _isActive,
          notes: _notesCtrl.text,
          reason: _reasonCtrl.text,
        );
      } else {
        saved = await widget.controller.createOutlet(
          name: _nameCtrl.text,
          shiftCount: _shiftCount,
          schedules: schedules,
          notes: _notesCtrl.text,
        );
      }
      if (mounted) Navigator.of(context).pop(saved);
    } on RagaaException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducingFrom3To2 =
        _isEditing && widget.existing!.shiftCount == 3 && _shiftCount == 2;

    return AlertDialog(
      title: Text(_isEditing ? 'تعديل المنفذ والورديات' : 'إضافة منفذ جديد'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, minWidth: 340),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: AppTheme.dangerRed,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                key: const Key('outlet_name_field'),
                controller: _nameCtrl,
                autofocus: !_isEditing,
                decoration: const InputDecoration(
                  labelText: 'اسم المنفذ',
                  hintText: 'مثال: منفذ المعادي الرئيسي',
                  prefixIcon: Icon(Icons.storefront),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'عدد الورديات اليومية للمنفذ',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 2,
                    label: Text('ورديتان'),
                    icon: Icon(Icons.looks_two_outlined),
                  ),
                  ButtonSegment<int>(
                    value: 3,
                    label: Text('3 ورديات'),
                    icon: Icon(Icons.looks_3_outlined),
                  ),
                ],
                selected: {_shiftCount},
                onSelectionChanged: (sel) => _onShiftCountChanged(sel.first),
              ),
              if (reducingFrom3To2) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppTheme.warningAmber,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _historicalShift3Count > 0
                              ? 'سيتم الاحتفاظ بجميع سجلات الوردية الثالثة السابقة ($_historicalShift3Count سجل) ومواعيدها دون أي فقد في البيانات أو التقارير.'
                              : 'سيتم إيقاف الوردية الثالثة للتسجيل الجديد مع حفظ إعداداتها لإعادة تفعيلها متى شئت.',
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
              const SizedBox(height: 16),
              const Text(
                'مواعيد ومسميات الورديات',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _shiftCount; i++) ...[
                _buildShiftEditorCard(i),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 6),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'المنفذ نشط للتسجيل اليومي',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'إيقاف المنفذ يمنع التسجيل الجديد مع بقاء كامل بياناته في التقارير',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('outlet_reason_field'),
                  controller: _reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'سبب التعديل (يُسجّل في سجل المراجعة)',
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
          key: const Key('outlet_save_button'),
          onPressed: _saving ? null : _submit,
          icon: const Icon(Icons.check, size: 18),
          label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ],
    );
  }

  Widget _buildShiftEditorCard(int index) {
    final start = _startTimes[index];
    final end = _endTimes[index];
    final overnight = isOvernightShift(start, end) && end != '00:00';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _labelCtrls[index],
            decoration: InputDecoration(
              labelText: 'مسمى الوردية ${index + 1}',
              isDense: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickTime(index, isStart: true),
                icon: const Icon(Icons.schedule, size: 16),
                label: Text('من: $start'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickTime(index, isStart: false),
                icon: const Icon(Icons.schedule_send, size: 16),
                label: Text('إلى: $end'),
              ),
              if (overnight)
                const Text(
                  'تمتد بعد منتصف الليل (تتبع التاريخ التشغيلي)',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.warningAmber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
