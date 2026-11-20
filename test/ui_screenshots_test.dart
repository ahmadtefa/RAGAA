import 'dart:io';
import 'dart:ui' as ui;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ragaa/data/app_database.dart';
import 'package:ragaa/data/backup_service.dart';
import 'package:ragaa/data/ragaa_repository.dart';
import 'package:ragaa/main.dart';
import 'package:ragaa/services/file_dialog_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/journal_demo_data.dart';

/// Captures real screenshots of the implemented Flutter UI (the exact widget
/// tree that ships in the APK and the Windows build) at real phone, tablet and
/// desktop sizes, including 100 / 150 / 200 % text scale.
///
/// The PNG files are written to `review/ui/screenshots/`; CI publishes them
/// with the other review artifacts so the client can inspect the real UI
/// instead of hand-drawn mockups.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final shotKey = GlobalKey();
  late Directory tempDir;
  late AppDatabase appDb;
  late RagaaController controller;
  var fontsLoaded = false;

  setUpAll(() async {
    // Load the real shipped Arabic font so the screenshots show genuine
    // Tajawal glyph shaping instead of the test placeholder font.
    for (final entry in <String, List<String>>{
      'Tajawal': <String>[
        'assets/fonts/Tajawal-Regular.ttf',
        'assets/fonts/Tajawal-Bold.ttf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      var loadedAny = false;
      for (final asset in entry.value) {
        try {
          loader.addFont(rootBundle.load(asset));
          loadedAny = true;
        } catch (error) {
          // ignore: avoid_print
          print('Could not queue font $asset: $error');
        }
      }
      if (loadedAny) {
        await loader.load();
        fontsLoaded = true;
      }
    }

    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('ragaa_shots_');
    final dbPath = p.join(tempDir.path, 'data', 'shots.db');
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
    await JournalDemoDataset.seed(repo);
    await controller.refreshAll();
  });

  tearDownAll(() async {
    controller.dispose();
    await appDb.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    required double width,
    required double height,
    required double textScale,
    double devicePixelRatio = 2.0,
  }) async {
    tester.view.physicalSize = Size(width * devicePixelRatio, height * devicePixelRatio);
    tester.view.devicePixelRatio = devicePixelRatio;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    // Rebuild from scratch so no drawer/route from the previous shot survives.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      RepaintBoundary(key: shotKey, child: RagaaApp(controller: controller)),
    );
    await settle(tester);
  }

  Future<void> openBarTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary =
        shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File(p.join('review', 'ui', 'screenshots', name));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('Screenshot written: ${file.path}');
    });
  }

  testWidgets('captures the real UI at phone, tablet and desktop sizes',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    expect(
      fontsLoaded,
      isTrue,
      reason: 'the real Tajawal Arabic font must load for the screenshots',
    );

    // 1 — dashboard, default phone (412 dp) at normal text size.
    await pumpApp(tester, width: 412, height: 915, textScale: 1.0);
    await capture(tester, '01_phone_dashboard_412.png');

    // 2 — dashboard on a 360 dp phone with 150 % text.
    await pumpApp(tester, width: 360, height: 800, textScale: 1.5);
    await capture(tester, '02_phone_dashboard_360_text150.png');

    // 3 — collections list, phone.
    await pumpApp(tester, width: 412, height: 915, textScale: 1.0);
    await openBarTab(tester, 'التحصيل');
    await capture(tester, '03_phone_collections_412.png');

    // 4 — outlets at the narrowest phone with 200 % text: the placement that
    // used to squeeze the outlet name into vertical letters.
    await pumpApp(tester, width: 320, height: 800, textScale: 2.0);
    await openBarTab(tester, 'المنافذ');
    await capture(tester, '04_phone_outlets_320_text200.png');

    // 5 — outlets at normal phone size.
    await pumpApp(tester, width: 412, height: 915, textScale: 1.0);
    await openBarTab(tester, 'المنافذ');
    await capture(tester, '05_phone_outlets_412.png');

    // 6 — reports screen on a phone.
    await pumpApp(tester, width: 412, height: 915, textScale: 1.0);
    await openBarTab(tester, 'التقارير');
    await capture(tester, '06_phone_reports_412.png');

    // 7 — the "more" drawer, which keeps every module reachable.
    await pumpApp(tester, width: 412, height: 915, textScale: 1.0);
    await openBarTab(tester, 'المزيد');
    await capture(tester, '07_phone_drawer_412.png');

    // 8 — the full-screen collection entry form.
    await pumpApp(tester, width: 412, height: 915, textScale: 1.0);
    await openBarTab(tester, 'التحصيل');
    await tester.tap(find.byKey(const Key('shell_new_collection')));
    await settle(tester);
    await capture(tester, '08_phone_entry_form_412.png');

    // 9 — tablet.
    await pumpApp(tester, width: 834, height: 1112, textScale: 1.0);
    await capture(tester, '09_tablet_dashboard_834.png');

    // 10 — desktop (the Windows build layout).
    await pumpApp(
      tester,
      width: 1440,
      height: 900,
      textScale: 1.0,
      devicePixelRatio: 1.0,
    );
    await capture(tester, '10_desktop_dashboard_1440.png');

    // 11 — desktop at 150 % text scale.
    await pumpApp(
      tester,
      width: 1440,
      height: 900,
      textScale: 1.5,
      devicePixelRatio: 1.0,
    );
    await capture(tester, '11_desktop_dashboard_1440_text150.png');
  });
}
