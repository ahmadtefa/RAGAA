// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../models/audit_log_entry.dart';
import '../../state/ragaa_controller.dart';
import '../widgets/common_widgets.dart';

/// Displays the immutable audit trail of all creations, modifications,
/// shift schedule updates, legacy migrations, and database restorations.
class AuditLogPage extends StatefulWidget {
  final RagaaController controller;

  const AuditLogPage({super.key, required this.controller});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  String? _outletId;
  AuditEntityType? _entityType;
  AuditAction? _action;
  List<AuditLogEntry> _logs = const [];
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
    setState(() => _loading = true);
    final entries = await widget.controller.queryAuditLogs(
      outletId: _outletId,
      entityType: _entityType,
      action: _action,
    );
    if (mounted) {
      setState(() {
        _logs = entries;
        _loading = false;
      });
    }
  }

  Color _actionColor(AuditAction action) {
    switch (action) {
      case AuditAction.create:
        return AppTheme.positiveGreen;
      case AuditAction.update:
        return AppTheme.warningAmber;
      case AuditAction.restore:
        return const Color(0xFF1D4ED8);
      case AuditAction.migrate:
        return const Color(0xFF6D28D9);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outlets = widget.controller.outlets;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سجل المراجعة والتعديلات',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            Text(
              'سجل محاسبي غير قابل للحذف يوثق جميع الإضافات والتعديلات وتغييرات الورديات وعمليات الاستعادة',
              style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('audit_outlet_$_outletId'),
                    isExpanded: true,
                    initialValue: _outletId,
                    decoration: const InputDecoration(
                      labelText: 'المنفذ',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('كل المنافذ'),
                      ),
                      ...outlets.map(
                        (o) => DropdownMenuItem(
                          value: o.id,
                          child: Text(o.name),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _outletId = v);
                      _reload();
                    },
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<AuditEntityType?>(
                    key: ValueKey('audit_entity_$_entityType'),
                    isExpanded: true,
                    initialValue: _entityType,
                    decoration: const InputDecoration(
                      labelText: 'النوع',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('كل السجلات'),
                      ),
                      ...AuditEntityType.values.map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.arabicLabel),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _entityType = v);
                      _reload();
                    },
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<AuditAction?>(
                    key: ValueKey('audit_action_$_action'),
                    isExpanded: true,
                    initialValue: _action,
                    decoration: const InputDecoration(
                      labelText: 'العملية',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('كل العمليات'),
                      ),
                      ...AuditAction.values.map(
                        (a) => DropdownMenuItem(
                          value: a,
                          child: Text(a.arabicLabel),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _action = v);
                      _reload();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_logs.isEmpty)
          const EmptyStateBox(
            icon: Icons.fact_check_outlined,
            title: 'لا توجد سجلات مراجعة مطابقة للفلتر',
          )
        else
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _logs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = _logs[index];
                final delta = entry.amountDeltaPiastres;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusBadge(
                                text: entry.action.arabicLabel,
                                color: _actionColor(entry.action),
                              ),
                              StatusBadge(
                                text: entry.entityType.arabicLabel,
                                color: const Color(0xFF475569),
                              ),
                              if (delta != null && delta != 0)
                                StatusBadge(
                                  text: 'الفرق: ${formatMoneyDelta(delta)}',
                                  color: delta > 0
                                      ? AppTheme.positiveGreen
                                      : AppTheme.dangerRed,
                                ),
                            ],
                          ),
                          Text(
                            formatTimestamp(entry.createdAt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.summary,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (entry.reason.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'سبب التعديل: ${entry.reason}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
