// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import 'responsive_layout.dart';
import '../../services/file_dialog_helper.dart';

/// Clean KPI metric card for Dashboard and Report headers.
class KpiMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color? accentColor;
  final bool highlighted;

  const KpiMetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    this.accentColor,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppTheme.brandPrimary;
    final bg = highlighted ? AppTheme.brandPrimary : Colors.white;
    final titleColor =
        highlighted ? Colors.white.withValues(alpha: 0.88) : const Color(0xFF475569);
    final valueColor = highlighted ? Colors.white : const Color(0xFF0F172A);
    final subColor =
        highlighted ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? AppTheme.brandPrimary : AppTheme.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: highlighted
                      ? Colors.white.withValues(alpha: 0.16)
                      : accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: highlighted ? Colors.white : accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AmountText(
            value,
            fontSize: 21,
            color: valueColor,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12, color: subColor),
            ),
          ],
        ],
      ),
    );
  }
}

/// Titled card container used to structure screen sections cleanly.
class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResponsiveHeader(
              breakpoint: 560,
              spacing: 10,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
              actions: trailing ?? const SizedBox.shrink(),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// Friendly placeholder displayed when a list or report section has no rows.
class EmptyStateBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyStateBox({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Banner displaying a recently saved file path with copy and open-folder buttons.
class SavedFileBanner extends StatelessWidget {
  final String label;
  final String filePath;
  final VoidCallback onDismiss;

  /// Shares the saved copy through the system share sheet; hidden when `null`.
  final Future<bool> Function()? onShare;

  /// Opens the saved file with the program the system uses for it; hidden when
  /// `null`. On a phone this is the "open after saving" the operator expects.
  final Future<bool> Function()? onOpen;

  const SavedFileBanner({
    super.key,
    required this.label,
    required this.filePath,
    required this.onDismiss,
    this.onShare,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A phone cannot fit four buttons beside the text: the actions wrap onto
    // their own line instead of squeezing the file name to nothing.
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final actions = <Widget>[
      if (onOpen != null)
        FilledButton.tonalIcon(
          key: const Key('open_saved_file'),
          onPressed: () async {
            final opened = await onOpen!();
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('لا يوجد تطبيق على هذا الجهاز يفتح هذا الملف'),
                ),
              );
            }
          },
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('فتح الملف'),
        ),
      if (onShare != null)
        TextButton.icon(
          onPressed: () => onShare!(),
          icon: const Icon(Icons.share, size: 16),
          label: const Text('مشاركة'),
        ),
      TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: filePath));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم نسخ مسار الملف')),
            );
          }
        },
        icon: const Icon(Icons.copy, size: 16),
        label: const Text('نسخ المسار'),
      ),
      if (FileDialogHelper.hasNativeSaveDialog)
        TextButton.icon(
          onPressed: () => FileDialogHelper.revealContainingFolder(filePath),
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('فتح المجلد'),
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.positiveGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.positiveGreen.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, color: AppTheme.positiveGreen, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.positiveGreen,
                      ),
                    ),
                    SelectableText(
                      filePath,
                      maxLines: 2,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'إغلاق',
              ),
            ],
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 30),
              child: wide
                  ? Row(children: actions.expand((a) => [a, const SizedBox(width: 4)]).toList())
                  : Wrap(spacing: 4, runSpacing: 0, children: actions),
            ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
