// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../models/outlet.dart';
import '../../state/ragaa_controller.dart';
import '../widgets/common_widgets.dart';
import '../widgets/outlet_form_dialog.dart';

/// Page for creating outlets and configuring each outlet's independent shift count
/// (2 or 3 shifts) and shift schedules safely without data loss.
class OutletsPage extends StatelessWidget {
  final RagaaController controller;

  const OutletsPage({super.key, required this.controller});

  Future<void> _addOutlet(BuildContext context) async {
    final created = await OutletFormDialog.show(
      context,
      controller: controller,
    );
    if (created != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تمت إضافة المنفذ "${created.name}" (${created.shiftCountArabic})',
          ),
        ),
      );
    }
  }

  Future<void> _editOutlet(BuildContext context, Outlet outlet) async {
    final updated = await OutletFormDialog.show(
      context,
      controller: controller,
      existing: outlet,
    );
    if (updated != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تحديث إعدادات المنفذ "${updated.name}" دون المساس بالبيانات السابقة',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final outlets = controller.outlets;

    return ListView(
      padding: const EdgeInsets.all(20),
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
                  'المنافذ وإعدادات الورديات',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                Text(
                  'حدد لكل منفذ ورديتين أو 3 ورديات ومواعيدها بشكل مستقل، مع إمكانية التعديل لاحقًا دون فقد البيانات',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
            FilledButton.icon(
              key: const Key('outlets_add_btn'),
              onPressed: () => _addOutlet(context),
              icon: const Icon(Icons.add_business, size: 18),
              label: const Text('إضافة منفذ جديد'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (outlets.isEmpty)
          EmptyStateBox(
            icon: Icons.store_mall_directory_outlined,
            title: 'لا توجد منافذ مسجلة حاليًا',
            subtitle:
                'أضف منافذ التحصيل وحدد نظام الورديات لكل منفذ (ورديتان أو 3 ورديات)',
            action: FilledButton.icon(
              onPressed: () => _addOutlet(context),
              icon: const Icon(Icons.add),
              label: const Text('إضافة منفذ'),
            ),
          )
        else
          ...outlets.asMap().entries.map(
            (entry) {
              final index = entry.key;
              final outlet = entry.value;
              return Padding(
              key: ValueKey('outlet_card_${outlet.id}'),
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.brandPrimary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.storefront,
                              color: AppTheme.brandPrimary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      outlet.name,
                                      style: const TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    StatusBadge(
                                      text: outlet.shiftCountArabic,
                                      color: AppTheme.brandPrimary,
                                    ),
                                    StatusBadge(
                                      text: outlet.isActive ? 'نشط' : 'متوقف',
                                      color: outlet.isActive
                                          ? AppTheme.positiveGreen
                                          : AppTheme.warningAmber,
                                    ),
                                  ],
                                ),
                                if (outlet.notes.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    outlet.notes,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('outlet_move_up_${outlet.id}'),
                                tooltip: 'تحريك المنفذ لأعلى (ترتيب الطباعة)',
                                onPressed: index == 0
                                    ? null
                                    : () => controller.moveOutlet(outlet.id, -1),
                                icon: const Icon(Icons.arrow_upward, size: 18),
                              ),
                              IconButton(
                                key: Key('outlet_move_down_${outlet.id}'),
                                tooltip: 'تحريك المنفذ لأسفل (ترتيب الطباعة)',
                                onPressed: index == outlets.length - 1
                                    ? null
                                    : () => controller.moveOutlet(outlet.id, 1),
                                icon:
                                    const Icon(Icons.arrow_downward, size: 18),
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            key: Key('edit_outlet_${outlet.id}'),
                            onPressed: () => _editOutlet(context, outlet),
                            icon: const Icon(Icons.tune, size: 17),
                            label: const Text('تعديل الورديات'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          for (final s in outlet.activeShifts)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: AppTheme.borderSubtle),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.schedule,
                                    size: 16,
                                    color: Color(0xFF475569),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${s.label}: ',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    s.timeRange,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF334155),
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  if (s.isOvernight && s.endTime != '00:00') ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.nights_stay_outlined,
                                      size: 14,
                                      color: AppTheme.warningAmber,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
            },
          ),
      ],
    );
  }
}
