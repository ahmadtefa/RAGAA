// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/exceptions.dart';
import '../../core/formatters.dart';
import '../../models/backup_info.dart';
import '../../models/backup_info.dart' as bi;
import '../../state/ragaa_controller.dart';
import '../widgets/common_widgets.dart';

/// Page for creating verified SQLite backups (local or external folder/USB),
/// verifying integrity (SHA-256 + PRAGMA integrity_check), and restoring safely.
class BackupPage extends StatefulWidget {
  final RagaaController controller;

  const BackupPage({super.key, required this.controller});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  String? _bannerPath;
  String? _bannerLabel;

  Future<void> _createQuickBackup() async {
    try {
      final info = await widget.controller.createManagedBackup();
      if (mounted) {
        setState(() {
          _bannerPath = info.filePath;
          _bannerLabel = 'تم إنشاء النسخة الاحتياطية والتحقق من سلامتها:';
        });
      }
    } on RagaaException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _exportExternalBackup() async {
    try {
      final info = await widget.controller.exportBackupToCustomPath();
      if (info != null && mounted) {
        setState(() {
          _bannerPath = info.filePath;
          _bannerLabel = 'تم تصدير النسخة الاحتياطية إلى المسار المحدد:';
        });
      }
    } on RagaaException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _pickAndRestoreExternal() async {
    try {
      final path = await widget.controller.pickExternalBackupFile();
      if (path == null || !mounted) return;
      await _confirmAndRestore(path);
    } on RagaaException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _confirmAndRestore(String filePath) async {
    bi.DatabaseStats preview;
    try {
      preview = await widget.controller.inspectBackupFile(filePath);
    } on RagaaException catch (e) {
      _showError(e.message);
      return;
    } catch (e) {
      _showError(e.toString());
      return;
    }

    if (!mounted) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RestoreConfirmDialog(stats: preview),
    );
    if (reason == null || !mounted) return;

    try {
      final outcome = await widget.controller.restoreBackup(
        filePath,
        reason: reason,
      );
      if (mounted) {
        setState(() {
          _bannerPath = outcome.safetyBackupPath;
          _bannerLabel =
              'تمت استعادة البيانات بنجاح! وحُفظت نسخة أمان تلقائية لبياناتك السابقة في:';
        });
      }
    } on RagaaException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _deleteBackup(BackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف النسخة الاحتياطية'),
        content: Text('هل تريد حذف الملف "${backup.fileName}" نهائيًا؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.deleteManagedBackup(backup.filePath);
    } on RagaaException catch (e) {
      _showError(e.message);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.controller.databaseStats;
    final backups = widget.controller.managedBackups;
    final busy = widget.controller.isBusy;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'النسخ الاحتياطي واستعادة البيانات',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            Text(
              'نسخ احتياطية متكاملة لقاعدة بيانات SQLite مع فحص السلامة (SHA-256) ونسخة أمان تلقائية قبل أي استعادة',
              style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
        if (_bannerPath != null) ...[
          const SizedBox(height: 14),
          SavedFileBanner(
            label: _bannerLabel ?? 'المسار:',
            filePath: _bannerPath!,
            onDismiss: () => setState(() => _bannerPath = null),
          ),
        ],
        const SizedBox(height: 16),

        // Actions Card
        SectionCard(
          title: 'إجراءات النسخ والاستعادة',
          subtitle:
              'يُنصح بحفظ نسخة يومية على وحدة تخزين خارجية (فلاشة USB أو قرص منفصل)',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const Key('quick_backup_btn'),
                onPressed: busy ? null : _createQuickBackup,
                icon: const Icon(Icons.backup_outlined, size: 18),
                label: const Text('إنشاء نسخة احتياطية الآن'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : _exportExternalBackup,
                icon: const Icon(Icons.save_alt, size: 18),
                label: const Text('حفظ نسخة في مسار خارجي'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : _pickAndRestoreExternal,
                icon: const Icon(Icons.restore_page_outlined, size: 18),
                label: const Text('استعادة من ملف خارجي'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Current DB Status Card
        if (stats != null)
          SectionCard(
            title: 'حالة قاعدة البيانات المحلية (SQLite)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    Text('المنافذ: ${stats.outletsCount}'),
                    Text('سجلات التحصيل: ${stats.collectionsCount}'),
                    Text('سجلات المراجعة: ${stats.auditLogsCount}'),
                    Text(
                      'إجمالي التحصيل المخزن: ${formatMoney(stats.totalPiastres, withCurrency: true)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text('الحجم: ${formatFileSize(stats.fileSizeBytes)}'),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'مسار قاعدة البيانات: ${stats.filePath}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // Managed Backups List
        SectionCard(
          title: 'النسخ الاحتياطية المحفوظة محليًا (${backups.length})',
          subtitle: widget.controller.backupService.managedBackupsDir,
          child: backups.isEmpty
              ? const EmptyStateBox(
                  icon: Icons.cloud_off_outlined,
                  title: 'لا توجد نسخ احتياطية محفوظة بعد',
                  subtitle:
                      'اضغط "إنشاء نسخة احتياطية الآن" لحفظ أول نسخة مؤمّنة من قاعدة البيانات',
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: backups.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final b = backups[index];
                    return Row(
                      children: [
                        Icon(
                          b.isPreRestoreSafety
                              ? Icons.shield_outlined
                              : Icons.storage_outlined,
                          color: b.isPreRestoreSafety
                              ? AppTheme.warningAmber
                              : AppTheme.brandPrimary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    b.fileName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  if (b.isPreRestoreSafety)
                                    const StatusBadge(
                                      text: 'نسخة أمان تلقائية',
                                      color: AppTheme.warningAmber,
                                    ),
                                  if (b.sha256.isNotEmpty)
                                    const StatusBadge(
                                      text: 'SHA-256 موثّق',
                                      color: AppTheme.positiveGreen,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${formatTimestamp(b.createdAt.toIso8601String())} | '
                                'الحجم: ${formatFileSize(b.fileSizeBytes)}'
                                '${b.outletsCount != null ? " | ${b.outletsCount} منفذ، ${b.collectionsCount} تحصيل" : ""}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => _confirmAndRestore(b.filePath),
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text('استعادة'),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'حذف النسخة',
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: AppTheme.dangerRed,
                          ),
                          onPressed: busy ? null : () => _deleteBackup(b),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RestoreConfirmDialog extends StatefulWidget {
  final DatabaseStats stats;

  const _RestoreConfirmDialog({required this.stats});

  @override
  State<_RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<_RestoreConfirmDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    return AlertDialog(
      title: const Text('تأكيد استعادة النسخة الاحتياطية'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تم فحص سلامة النسخة الاحتياطية بنجاح (SQLite OK). سيقوم البرنامج تلقائيًا بحفظ نسخة أمان من البيانات الحالية قبل الاستبدال.',
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('المنافذ في النسخة: ${s.outletsCount}'),
                  Text('سجلات التحصيل: ${s.collectionsCount}'),
                  Text(
                    'إجمالي التحصيل: ${formatMoney(s.totalPiastres, withCurrency: true)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'سبب الاستعادة (يُسجّل في سجل المراجعة)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('confirm_restore_btn'),
          onPressed: () => Navigator.pop(
            context,
            _reasonCtrl.text.trim().isEmpty
                ? 'استعادة يدوية بمعرفة المستخدم'
                : _reasonCtrl.text.trim(),
          ),
          child: const Text('استعادة الآن'),
        ),
      ],
    );
  }
}
