import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ragaa/core/app_theme.dart';
import 'package:ragaa/data/app_database.dart';
import 'package:ragaa/data/backup_service.dart';
import 'package:ragaa/data/ragaa_repository.dart';
import 'package:ragaa/main.dart';
import 'package:ragaa/services/file_dialog_helper.dart';
import 'package:ragaa/ui/pages/audit_log_page.dart';
import 'package:ragaa/ui/pages/backup_page.dart';
import 'package:ragaa/ui/pages/collections_page.dart';
import 'package:ragaa/ui/pages/dashboard_page.dart';
import 'package:ragaa/ui/pages/outlets_page.dart';
import 'package:ragaa/ui/pages/reports_page.dart';
import 'package:ragaa/ui/widgets/collection_form_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/journal_demo_data.dart';

/// Real responsive-layout verification, run against the implemented Flutter UI.
///
/// Every screen is rendered at the exact phone widths the client tests on
/// (320 / 360 / 375 / 390 / 412 dp), a tablet width and a desktop width, at
/// 100 / 125 / 150 / 200 % system text scale, and the test fails if Flutter
/// reports *any* RenderFlex overflow, clipped row or exception.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late AppDatabase appDb;
  late RagaaController controller;

  setUpAll(() async {
    // Measure real Arabic metrics: without the shipped font every glyph is a
    // full square (the test placeholder font), which would report false
    // clipping on text that fits perfectly on a device.
    final fontLoader = FontLoader('Tajawal')
      ..addFont(rootBundle.load('assets/fonts/Tajawal-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));
    await fontLoader.load();

    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ragaa_responsive_');
    final dbPath = p.join(tempDir.path, 'data', 'responsive.db');
    final backupsDir = p.join(tempDir.path, 'backups');
    final exportsDir = p.join(tempDir.path, 'exports');

    appDb = AppDatabase.atPath(dbPath, factory: databaseFactoryFfiNoIsolate);
    final repo = RagaaRepository(appDb);
    final backup = BackupService(
      appDatabase: appDb,
      repository: repo,
      managedBackupsDir: backupsDir,
      factory: databaseFactoryFfiNoIsolate,
    );
    controller = RagaaController(
      appDatabase: appDb,
      repository: repo,
      backupService: backup,
      fileDialogHelper: FileDialogHelper(
        defaultExportsDir: exportsDir,
        defaultBackupsDir: backupsDir,
      ),
    );
    await controller.initialize();
    // Seed the real demo dataset so the screens are laid out with realistic
    // Arabic outlet names and amounts instead of empty placeholders — for both
    // the fixed review date and today, so every list is populated.
    final outletIds = await JournalDemoDataset.seed(repo);
    await JournalDemoDataset.seedCollections(
      repo,
      outletIds,
      date: dateKey(DateTime.now()),
    );
    await controller.refreshAll();
  });

  tearDownAll(() async {
    controller.dispose();
    await appDb.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Widths every layout must survive: five real Android phone widths, a large
  /// phone, a tablet and a desktop window.
  const widths = <double>[320, 360, 375, 390, 412, 480, 600, 768, 1024, 1440];
  const textScales = <double>[1.0, 1.25, 1.5, 2.0];

  /// Lets async SQLite/controller work settle under the fake clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
  }

  Future<void> setViewport(
    WidgetTester tester, {
    required double width,
    double height = 2200,
    required double textScale,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
  }

  /// Full Flutter diagnostics for every reported error, so a failure names the
  /// exact widget and source line that overflowed.
  final layoutDiagnostics = <String>[];

  /// Re-installed for every test: the test binding resets `FlutterError.onError`
  /// between tests, which would otherwise drop the diagnostics.
  void installErrorCapture() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      layoutDiagnostics.add(details.toString());
      previous?.call(details);
    };
  }

  /// Fails the test if Flutter reported any layout error for this screen, and
  /// prints the full Flutter diagnostic so the offending widget is named.
  void expectNoLayoutError(WidgetTester tester, String label) {
    final error = tester.takeException();
    if (error == null) return;
    final buffer = StringBuffer('[$label] layout error:\n$error\n');
    if (error is FlutterError) {
      for (final node in error.diagnostics) {
        buffer.writeln(node.toStringDeep());
      }
    }
    if (layoutDiagnostics.isNotEmpty) {
      buffer.writeln('--- first reported diagnostic ---');
      final lines = layoutDiagnostics.first.split('\n');
      buffer.writeln(lines.take(30).join('\n'));
    }
    layoutDiagnostics.clear();
    fail(buffer.toString());
  }

  Widget harness(Widget page) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          // ignore: deprecated_member_use
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          // ignore: deprecated_member_use
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(body: page),
      );

  const screenNames = <String>[
    'dashboard',
    'collections',
    'outlets',
    'reports',
    'audit',
    'backup',
  ];

  Widget buildScreen(String name) {
    switch (name) {
      case 'dashboard':
        return DashboardPage(
          controller: controller,
          onNavigateToReports: () {},
        );
      case 'collections':
        return CollectionsPage(controller: controller);
      case 'outlets':
        return OutletsPage(controller: controller);
      case 'reports':
        return ReportsPage(controller: controller);
      case 'audit':
        return AuditLogPage(controller: controller);
      case 'backup':
        return BackupPage(controller: controller);
      default:
        return const SizedBox.shrink();
    }
  }

  Map<String, String> markers() => const <String, String>{
        'dashboard': 'لوحة التحكم المركزية',
        'collections': 'تسجيل وإدارة التحصيل',
        'outlets': 'المنافذ وإعدادات الورديات',
        'reports': 'التقارير وتصدير PDF وExcel',
        'audit': 'سجل المراجعة والتعديلات',
        'backup': 'النسخ الاحتياطي واستعادة البيانات',
      };

  /// The full matrix: every screen × every width × every text scale.
  for (final screen in screenNames) {
    testWidgets('$screen survives every phone/tablet/desktop width and scale',
        (tester) async {
      installErrorCapture();
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      for (final scale in textScales) {
        for (final width in widths) {
          await setViewport(tester, width: width, textScale: scale);
          await tester.pumpWidget(harness(buildScreen(screen)));
          await settle(tester);

          final label = '$screen @ ${width.toInt()}dp / ${(scale * 100).toInt()}%';
          expectNoLayoutError(tester, label);
          expect(
            find.text(markers()[screen]!),
            findsWidgets,
            reason: '$label: the screen title must stay readable and visible',
          );
        }
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  }

  testWidgets('phone shell keeps every navigation label readable and never '
      'duplicates the record-collection button', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    for (final scale in const [1.0, 1.5, 2.0]) {
      for (final width in const [320.0, 360.0, 390.0, 412.0, 480.0]) {
        await setViewport(tester, width: width, height: 800, textScale: scale);
        await tester.pumpWidget(RagaaApp(controller: controller));
        await settle(tester);
        // The shell keeps its state between pumps, so always start on home.
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('الرئيسية'),
          ),
        );
        await settle(tester);
        final label = 'shell @ ${width.toInt()}dp / ${(scale * 100).toInt()}%';
        expectNoLayoutError(tester, label);

        // The home destination is short enough to never be cut in a 5-slot bar.
        expect(find.text('الرئيسية'), findsOneWidget, reason: label);
        final slotWidth = width / 5;
        for (final navLabel in const [
          'الرئيسية',
          'التحصيل',
          'المنافذ',
          'التقارير',
          'المزيد',
        ]) {
          final navText = find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(navLabel),
          );
          expect(
            navText,
            findsOneWidget,
            reason: '$label: «$navLabel» must stay visible in the bottom bar',
          );
          // A label drawn with an ellipsis is narrower than the width its own
          // text needs: that is exactly the "cut label" the client reported.
          final paragraph = tester.renderObject<RenderParagraph>(navText);
          final naturalWidth = paragraph.getMaxIntrinsicWidth(double.infinity);
          expect(
            paragraph.size.width,
            greaterThanOrEqualTo(naturalWidth - 1),
            reason: '$label: «$navLabel» needs '
                '${naturalWidth.toStringAsFixed(1)}dp but is clipped to '
                '${paragraph.size.width.toStringAsFixed(1)}dp inside its '
                '${slotWidth.toStringAsFixed(0)}dp slot',
          );
        }

        // On the dashboard the FAB is redundant (the screen has its own
        // button), so it must be gone; on the other tabs it comes back.
        expect(
          find.byKey(const Key('shell_new_collection')),
          findsNothing,
          reason: '$label: no duplicate collection button on the dashboard',
        );
        expect(
          find.byKey(const Key('dashboard_add_collection_btn')),
          findsOneWidget,
        );

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('التحصيل'),
          ),
        );
        await settle(tester);
        expectNoLayoutError(tester, '$label / collections tab');
        // The action lives in the app bar on phones, so nothing floats over
        // the data any more, and the button is still one tap away.
        expect(find.byKey(const Key('shell_new_collection')), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.byKey(const Key('collections_new_btn')), findsOneWidget);
      }
    }
  });

  testWidgets('period selector degrades to a dropdown on phones and keeps all '
      'four options reachable', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final width in const [320.0, 360.0, 412.0]) {
      await setViewport(tester, width: width, height: 900, textScale: 1.0);
      await tester.pumpWidget(
        harness(
          DashboardPage(controller: controller, onNavigateToReports: () {}),
        ),
      );
      await settle(tester);
      expectNoLayoutError(tester, 'period selector @ ${width.toInt()}dp');

      expect(find.byKey(const Key('dashboard_period_selector')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dashboard_period_selector')));
      await settle(tester);
      for (final option in const ['اليوم', 'الأسبوع', 'الشهر', 'فترة مخصصة']) {
        expect(
          find.text(option),
          findsWidgets,
          reason: '«$option» must stay selectable at ${width.toInt()}dp',
        );
      }
      await tester.tap(find.text('الشهر').last);
      await settle(tester);
      expectNoLayoutError(
        tester,
        'period selector reopened @ ${width.toInt()}dp',
      );
    }
  });

  testWidgets('Arabic outlet names are laid out horizontally, never letter by '
      'letter', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    for (final scale in const [1.0, 1.5, 2.0]) {
      for (final width in const [320.0, 360.0, 412.0]) {
        await setViewport(tester, width: width, textScale: scale);
        await tester.pumpWidget(harness(OutletsPage(controller: controller)));
        await settle(tester);
        expectNoLayoutError(tester, 'outlets names @ ${width.toInt()}dp');

        for (final outlet in controller.outlets) {
          final finder = find.text(outlet.name);
          if (finder.evaluate().isEmpty) continue;
          final size = tester.getSize(finder.first);
          // A word broken into a vertical letter stack is taller than it is
          // wide; a readable Arabic word is always clearly wider.
          expect(
            size.width / size.height,
            greaterThan(0.9),
            reason: '«${outlet.name}» is being split vertically at '
                '${width.toInt()}dp / ${(scale * 100).toInt()}% '
                '(size: ${size.width.toStringAsFixed(1)}×'
                '${size.height.toStringAsFixed(1)})',
          );
        }
      }
    }
  });

  testWidgets('collection amounts and totals stay fully visible inside their '
      'cards on the narrowest phone', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    for (final scale in const [1.0, 1.5, 2.0]) {
      await setViewport(tester, width: 320, height: 2200, textScale: scale);
      await tester.pumpWidget(harness(CollectionsPage(controller: controller)));
      await settle(tester);
      final label = 'collections @ 320dp / ${(scale * 100).toInt()}%';
      expectNoLayoutError(tester, label);

      expect(
        find.textContaining('عدد السجلات المعروضة'),
        findsOneWidget,
        reason: label,
      );
      expect(find.textContaining('الإجمالي:'), findsWidgets, reason: label);

      // The card content must stay inside the screen width (no horizontal
      // overflow pushed off screen).
      final screenWidth = tester.view.physicalSize.width /
          tester.view.devicePixelRatio;
      for (final element in find
          .descendant(
            of: find.byType(Card),
            matching: find.byType(Text),
          )
          .evaluate()) {
        // Amounts are wrapped in a FittedBox that scales them to fit, so their
        // paragraph keeps its natural size while the painted text shrinks.
        if (find
            .ancestor(
              of: find.byWidget(element.widget),
              matching: find.byType(FittedBox),
            )
            .evaluate()
            .isNotEmpty) {
          continue;
        }
        final box = element.renderObject! as RenderBox;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        expect(
          rect.right,
          lessThanOrEqualTo(screenWidth + 2),
          reason: '$label: "${(element.widget as Text).data}" escapes the '
              'screen (right edge ${rect.right.toStringAsFixed(1)} > '
              '$screenWidth)',
        );
      }
    }
  });

  testWidgets('the on-screen keyboard never covers the entry save bar',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.viewInsets = const FakeViewPadding();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await setViewport(tester, width: 360, height: 740, textScale: 1.0);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          // ignore: deprecated_member_use
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          // ignore: deprecated_member_use
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => CollectionFormDialog.show(
                  context,
                  controller: controller,
                ),
                child: const Text('فتح النموذج'),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('فتح النموذج'));
    await settle(tester);

    expectNoLayoutError(tester, 'entry form with open keyboard @ 360dp');
    final saveButton = find.byKey(const Key('collection_save_button'));
    expect(saveButton, findsOneWidget);
    final rect = tester.getRect(saveButton);
    final keyboardTop = 740 - 320;
    expect(
      rect.bottom,
      lessThanOrEqualTo(keyboardTop + 0.5),
      reason: 'the save bar must sit above the keyboard, not under it '
          '(bottom ${rect.bottom.toStringAsFixed(1)} vs keyboard top '
          '$keyboardTop)',
    );
  });
}
