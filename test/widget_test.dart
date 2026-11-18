import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ragaa/data/app_database.dart';
import 'package:ragaa/data/backup_service.dart';
import 'package:ragaa/data/ragaa_repository.dart';
import 'package:ragaa/main.dart';
import 'package:ragaa/models/report_models.dart';
import 'package:ragaa/services/file_dialog_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Allows background SQLite futures to settle and pumps widget frames cleanly.
Future<void> pumpWithDb(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();
  late Directory tempDir;
  late AppDatabase appDb;
  late RagaaController controller;

  Future<void> initTestController() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ragaa_ui_test_');
    final dbPath = p.join(tempDir.path, 'data', 'ui.db');
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
  }

  Future<void> disposeTestController() async {
    controller.dispose();
    await appDb.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }

  test('validates operational dates, shift times, and Arabic/Latin money', () {
    expect(isValidOperationalDate('2026-11-18'), isTrue);
    expect(isValidOperationalDate('2024-02-29'), isTrue);
    expect(isValidOperationalDate('2026-02-29'), isFalse);
    expect(isValidOperationalDate('2026-02-31'), isFalse);
    expect(isValidOperationalDate('2026-11-18T10:00:00'), isFalse);

    expect(isValidTime24('08:00'), isTrue);
    expect(isValidTime24('23:59'), isTrue);
    expect(isValidTime24('24:00'), isFalse);
    expect(isOvernightShift('22:00', '06:00'), isTrue);
    expect(isOvernightShift('08:00', '16:00'), isFalse);

    expect(tryParsePiastres('125.5'), 12550);
    expect(tryParsePiastres('١٢٥٠٫٧٥'), 125075);
    expect(tryParsePiastres('0'), 0);
    expect(tryParsePiastres('-5'), isNull);
    expect(tryParsePiastres('10.999'), isNull);
    expect(formatMoney(125075, withCurrency: true), '1,250.75 ج.م');
    expect(formatMoneyDelta(-5025), '-50.25 ج.م');
    expect(formatMoneyDelta(5025), '+50.25 ج.م');
  });

  testWidgets(
      'full desktop workflow: outlets, collections, duplicate guard, reports, audit, and backup',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1.0;
    await tester.runAsync(initTestController);
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.runAsync(disposeTestController);
    });

    await tester.pumpWidget(RagaaApp(controller: controller));
    await pumpWithDb(tester);

    // Verify RTL directionality and dashboard header.
    expect(find.text('لوحة التحكم المركزية'), findsOneWidget);
    final dirWidget = tester.widget<Directionality>(
      find.byType(Directionality).first,
    );
    expect(dirWidget.textDirection, TextDirection.rtl);

    // 1. Add an outlet with 3 shifts from the Dashboard.
    await tester.tap(find.byKey(const Key('dashboard_add_outlet_btn')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('outlet_name_field')),
      'منفذ التحرير',
    );
    await tester.tap(find.text('3 ورديات'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('outlet_save_button')));
    await pumpWithDb(tester);

    expect(controller.outlets.length, 1);
    expect(controller.outlets.single.shiftCount, 3);

    // 2. Record a collection entry (1,500.50 EGP).
    await tester.tap(find.byKey(const Key('dashboard_add_collection_btn')));
    await pumpWithDb(tester);
    await tester.enterText(
      find.byKey(const Key('collection_amount_field')),
      '1500.50',
    );
    await tester.tap(find.byKey(const Key('collection_save_button')));
    await pumpWithDb(tester);

    expect(find.text('1,500.50 ج.م'), findsWidgets);

    // 3. Attempt duplicate recording on same outlet/day/shift -> triggers audit confirm dialog.
    await tester.tap(find.byKey(const Key('dashboard_add_collection_btn')));
    await pumpWithDb(tester);
    await tester.enterText(
      find.byKey(const Key('collection_amount_field')),
      '1750.00',
    );
    await tester.tap(find.byKey(const Key('collection_save_button')));
    await pumpWithDb(tester);

    expect(find.text('منع تكرار التحصيل — تأكيد التعديل'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('duplicate_reason_field')),
      'مراجعة الخزينة المسائية',
    );
    await tester.tap(find.byKey(const Key('duplicate_confirm_button')));
    await pumpWithDb(tester);

    expect(find.text('1,750.00 ج.م'), findsWidgets);

    // 4. Navigate to Reports tab and verify PDF & Excel buttons + quick export.
    await tester.tap(find.text('التقارير'));
    await pumpWithDb(tester);
    expect(find.byKey(const Key('export_pdf_button')), findsOneWidget);
    expect(find.byKey(const Key('export_excel_button')), findsOneWidget);

    late String pdfSaved;
    late String xlsxSaved;
    await tester.runAsync(() async {
      final report = await controller.buildReport(
        ReportFilter(range: OperationalDateRange.daily(DateTime.now())),
      );
      pdfSaved = await controller.quickExportReport(report, asPdf: true);
      xlsxSaved = await controller.quickExportReport(report, asPdf: false);
      expect(await File(pdfSaved).exists(), isTrue);
      expect(await File(xlsxSaved).exists(), isTrue);
    });
    await pumpWithDb(tester);

    // 5. Navigate to Audit Log tab and verify edit reason is displayed.
    await tester.tap(find.text('سجل المراجعة'));
    await pumpWithDb(tester);
    expect(
      find.text('سبب التعديل: مراجعة الخزينة المسائية'),
      findsOneWidget,
    );

    // 6. Navigate to Backup tab and create a verified backup snapshot.
    await tester.tap(find.text('النسخ الاحتياطي'));
    await pumpWithDb(tester);
    expect(find.byKey(const Key('quick_backup_btn')), findsOneWidget);
    await tester.runAsync(() => controller.createManagedBackup());
    await pumpWithDb(tester);
    expect(controller.managedBackups.length, 1);
    expect(find.text('SHA-256 موثّق'), findsOneWidget);
  });

  testWidgets('renders cleanly on compact Android screen size', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    await tester.runAsync(initTestController);
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.runAsync(disposeTestController);
    });

    await tester.pumpWidget(RagaaApp(controller: controller));
    await pumpWithDb(tester);

    expect(find.text('RAGAA | لوحة التحكم'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
