// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../state/ragaa_controller.dart';
import 'pages/audit_log_page.dart';
import 'pages/backup_page.dart';
import 'pages/collections_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/outlets_page.dart';
import 'widgets/collection_form_dialog.dart';
import 'pages/reports_page.dart';

class _NavItem {
  final String label;

  /// Shorter label used on the phone bottom bar where every destination only
  /// gets a narrow slot (the full label stays in the app bar and the drawer).
  final String? shortLabel;
  final IconData icon;
  final IconData selectedIcon;

  const _NavItem(this.label, this.icon, this.selectedIcon,
      {this.shortLabel});

  /// Always fits a bottom navigation slot without being cut.
  String get barLabel => shortLabel ?? label;
}

const List<_NavItem> _kNavItems = [
  _NavItem(
    'لوحة التحكم',
    Icons.dashboard_outlined,
    Icons.dashboard,
    shortLabel: 'الرئيسية',
  ),
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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

  /// One tap from anywhere to the form that matters most: recording today's
  /// collection. The operator never has to find the right tab first.
  Future<void> _openNewCollection() async {
    final saved = await CollectionFormDialog.show(
      context,
      controller: widget.controller,
    );
    if (saved != null && mounted) {
      setState(() => _selectedIndex = 1);
    }
  }

  /// Desktop only: the window is wide enough for a floating button that sits
  /// beside the content. On phones the same action lives in the app bar so it
  /// can never cover a row of data or a button.
  Widget _newCollectionFab() {
    return FloatingActionButton.extended(
      key: const Key('shell_new_collection'),
      onPressed: _openNewCollection,
      icon: const Icon(Icons.add_card),
      label: const Text('تحصيل جديد'),
    );
  }

  /// Phone replacement for the floating button: an always-reachable app-bar
  /// action with its own slot above the content.
  Widget _newCollectionAppBarAction() {
    return IconButton(
      key: const Key('shell_new_collection'),
      tooltip: 'تحصيل جديد',
      icon: const Icon(Icons.add_card),
      onPressed: _openNewCollection,
    );
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
            floatingActionButton:
                _selectedIndex == 0 ? null : _newCollectionFab(),
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
                                label: Text(
                                  isExtended ? item.label : item.barLabel,
                                ),
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
          key: _scaffoldKey,
          // No floating button on phones: it used to cover the last row of
          // data. The same action sits in the app bar instead (except on the
          // dashboard, which already has its own «تسجيل تحصيل» button).
          appBar: AppBar(
            title: Text('RAGAA | ${_kNavItems[_selectedIndex].label}'),
            actions: [
              if (_selectedIndex != 0) _newCollectionAppBarAction(),
            ],
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
          // The five bar labels keep their full Arabic text: the bar is chrome,
          // so its text scale is clamped instead of being cut with an ellipsis
          // when the system font is set to 200%. Screen content is unaffected.
          bottomNavigationBar: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: NavigationBar(
              // Four daily screens on the bar and one door to the rest: an
              // operator on the backup or audit screen sees that module lit in
              // "المزيد" instead of the bar silently pointing at the dashboard.
              selectedIndex: _selectedIndex < 4 ? _selectedIndex : 4,
              onDestinationSelected: (i) {
                if (i == 4) {
                  _scaffoldKey.currentState?.openDrawer();
                  return;
                }
                setState(() => _selectedIndex = i);
              },
              destinations: [
                for (var i = 0; i < 4; i++)
                  NavigationDestination(
                    icon: Icon(_kNavItems[i].icon),
                    selectedIcon: Icon(_kNavItems[i].selectedIcon),
                    label: _kNavItems[i].barLabel,
                  ),
                const NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  selectedIcon: Icon(Icons.more),
                  label: 'المزيد',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
