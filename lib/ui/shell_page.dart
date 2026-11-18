// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../state/ragaa_controller.dart';
import 'pages/audit_log_page.dart';
import 'pages/backup_page.dart';
import 'pages/collections_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/outlets_page.dart';
import 'pages/reports_page.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _NavItem(this.label, this.icon, this.selectedIcon);
}

const List<_NavItem> _kNavItems = [
  _NavItem('لوحة التحكم', Icons.dashboard_outlined, Icons.dashboard),
  _NavItem('التحصيل', Icons.payments_outlined, Icons.payments),
  _NavItem('المنافذ', Icons.storefront_outlined, Icons.storefront),
  _NavItem('التقارير', Icons.assessment_outlined, Icons.assessment),
  _NavItem('سجل المراجعة', Icons.fact_check_outlined, Icons.fact_check),
  _NavItem('النسخ الاحتياطي', Icons.backup_outlined, Icons.backup),
];

/// Adaptive Arabic RTL application shell:
/// - Desktop (Windows / Linux, width >= 860): permanent right-side `NavigationRail`.
/// - Mobile / Compact (Android / narrow windows): `AppBar` + bottom `NavigationBar`
///   / `Drawer` so all 6 modules remain effortlessly reachable.
class RagaaShellPage extends StatefulWidget {
  final RagaaController controller;

  const RagaaShellPage({super.key, required this.controller});

  @override
  State<RagaaShellPage> createState() => _RagaaShellPageState();
}

class _RagaaShellPageState extends State<RagaaShellPage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Widget _buildActivePage() {
    switch (_selectedIndex) {
      case 0:
        return DashboardPage(
          controller: widget.controller,
          onNavigateToReports: () => setState(() => _selectedIndex = 3),
        );
      case 1:
        return CollectionsPage(controller: widget.controller);
      case 2:
        return OutletsPage(controller: widget.controller);
      case 3:
        return ReportsPage(controller: widget.controller);
      case 4:
        return AuditLogPage(controller: widget.controller);
      case 5:
        return BackupPage(controller: widget.controller);
      default:
        return DashboardPage(
          controller: widget.controller,
          onNavigateToReports: () => setState(() => _selectedIndex = 3),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    if (!ctrl.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (ctrl.startupError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppTheme.dangerRed,
                ),
                const SizedBox(height: 12),
                const Text(
                  'تعذر تهيئة قاعدة البيانات المحلية',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SelectableText(ctrl.startupError!),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: ctrl.initialize,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 860;
        final isExtended = constraints.maxWidth >= 1120;

        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      left: BorderSide(color: AppTheme.borderSubtle),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.brandPrimary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.account_balance,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            if (isExtended) ...[
                              const SizedBox(width: 10),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'RAGAA | رجاء',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.brandPrimary,
                                    ),
                                  ),
                                  Text(
                                    'إدارة تحصيل المنافذ',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Divider(),
                      Expanded(
                        child: NavigationRail(
                          backgroundColor: Colors.white,
                          extended: isExtended,
                          minExtendedWidth: 210,
                          labelType: isExtended
                              ? NavigationRailLabelType.none
                              : NavigationRailLabelType.all,
                          selectedIndex: _selectedIndex,
                          onDestinationSelected: (i) =>
                              setState(() => _selectedIndex = i),
                          destinations: [
                            for (final item in _kNavItems)
                              NavigationRailDestination(
                                icon: Icon(item.icon),
                                selectedIcon: Icon(item.selectedIcon),
                                label: Text(item.label),
                              ),
                          ],
                        ),
                      ),
                      if (ctrl.isBusy)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(child: _buildActivePage()),
              ],
            ),
          );
        }

        // Compact / Android layout
        return Scaffold(
          appBar: AppBar(
            title: Text('RAGAA | ${_kNavItems[_selectedIndex].label}'),
          ),
          drawer: Drawer(
            child: SafeArea(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RAGAA | رجاء',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandPrimary,
                          ),
                        ),
                        Text(
                          'نظام إدارة تحصيل المنافذ',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  for (var i = 0; i < _kNavItems.length; i++)
                    ListTile(
                      leading: Icon(
                        _selectedIndex == i
                            ? _kNavItems[i].selectedIcon
                            : _kNavItems[i].icon,
                        color: _selectedIndex == i
                            ? AppTheme.brandPrimary
                            : null,
                      ),
                      title: Text(_kNavItems[i].label),
                      selected: _selectedIndex == i,
                      onTap: () {
                        setState(() => _selectedIndex = i);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
          ),
          body: _buildActivePage(),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex < 4 ? _selectedIndex : 0,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            destinations: [
              for (var i = 0; i < 4; i++)
                NavigationDestination(
                  icon: Icon(_kNavItems[i].icon),
                  selectedIcon: Icon(_kNavItems[i].selectedIcon),
                  label: _kNavItems[i].label,
                ),
            ],
          ),
        );
      },
    );
  }
}
