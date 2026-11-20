import 'package:flutter_test/flutter_test.dart';
import 'package:ragaa/core/formatters.dart';
import 'package:ragaa/data/app_database.dart';
import 'package:ragaa/data/ragaa_repository.dart';
import 'package:ragaa/models/collection_amounts.dart';
import 'package:ragaa/models/collection_record.dart';
import 'package:ragaa/models/daily_journal.dart';
import 'package:ragaa/models/outlet.dart';
import 'package:ragaa/models/outlet_shift.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/journal_demo_data.dart';

Outlet fakeOutlet({
  required String id,
  required String name,
  int shiftCount = 2,
  bool isActive = true,
  int sortOrder = 0,
}) =>
    Outlet(
      id: id,
      name: name,
      shiftCount: shiftCount,
      isActive: isActive,
      notes: '',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
      sortOrder: sortOrder,
      shifts: <OutletShift>[
        for (var number = 1; number <= 3; number++)
          OutletShift(
            id: number,
            outletId: id,
            shiftNumber: number,
            label: defaultShiftLabel(number),
            startTime: defaultShiftTimes(number, shiftCount).start,
            endTime: defaultShiftTimes(number, shiftCount).end,
            isEnabled: number <= shiftCount,
            updatedAt: '2026-01-01T00:00:00.000Z',
          ),
      ],
    );

CollectionRecord fakeRecord({
  required String outletId,
  required String outletName,
  int shiftNumber = 1,
  String operationalDate = '2026-11-19',
  int manual = 0,
  int automatic = 0,
  int totalFees = 0,
  int general = 0,
  int nfc = 0,
  int visa = 0,
  int id = 1,
}) =>
    CollectionRecord(
      id: id,
      outletId: outletId,
      outletName: outletName,
      operationalDate: operationalDate,
      shiftNumber: shiftNumber,
      amountPiastres: general,
      amounts: CollectionAmounts(
        manualFeesPiastres: manual,
        automaticFeesPiastres: automatic,
        totalFeesPiastres: totalFees,
        generalTotalPiastres: general,
        nfcPiastres: nfc,
        visaPiastres: visa,
      ),
      shiftLabelSnapshot: defaultShiftLabel(shiftNumber),
      shiftStartSnapshot: '08:00',
      shiftEndSnapshot: '16:00',
      notes: '',
      revision: 1,
      createdAt: '2026-11-19T10:00:00.000Z',
      updatedAt: '2026-11-19T10:00:00.000Z',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('approved financial rules', () {
    test('scales total = general total − total fees (official example)', () {
      final journal = DailyJournal.build(
        operationalDate: '2026-11-19',
        outlets: [fakeOutlet(id: 'o1', name: 'نقل ١', shiftCount: 2)],
        records: [
          fakeRecord(
            outletId: 'o1',
            outletName: 'نقل ١',
            manual: 200000,
            automatic: 300000,
            totalFees: 550000,
            general: 1000000,
            nfc: 100000,
            visa: 50000,
          ),
        ],
      );

      final row = journal.sections.first.rows.single;
      expect(row.amounts.scalesTotalPiastres, 450000);
      expect(row.amounts.totalFeesPiastres, 550000);
      expect(row.amounts.generalTotalPiastres, 1000000);
      expect(formatMoney(row.amounts.scalesTotalPiastres), '4,500.00');
    });

    test('total fees stays independent of manual + automatic fees', () {
      final journal = DailyJournal.build(
        operationalDate: '2026-11-19',
        outlets: [fakeOutlet(id: 'o1', name: 'منفذ', shiftCount: 2)],
        records: [
          fakeRecord(
            outletId: 'o1',
            outletName: 'منفذ',
            manual: 200000,
            automatic: 300000,
            totalFees: 550000,
            general: 1000000,
          ),
        ],
      );
      final amounts = journal.sections.first.rows.single.amounts;
      // 2000 + 3000 must NOT be used anywhere.
      expect(amounts.manualFeesPiastres + amounts.automaticFeesPiastres, 500000);
      expect(amounts.totalFeesPiastres, 550000);
      expect(amounts.scalesTotalPiastres, 450000);
    });

    test('empty NFC/VISA are counted and stored as zero and never re-added', () {
      final journal = DailyJournal.build(
        operationalDate: '2026-11-19',
        outlets: [fakeOutlet(id: 'o1', name: 'منفذ', shiftCount: 2)],
        records: [
          fakeRecord(
            outletId: 'o1',
            outletName: 'منفذ',
            totalFees: 100000,
            general: 500000,
          ),
        ],
      );
      final amounts = journal.sections.first.rows.single.amounts;
      expect(amounts.nfcPiastres, 0);
      expect(amounts.visaPiastres, 0);
      expect(amounts.scalesTotalPiastres, 400000);

      // Adding electronic payments does not change the general total or scales:
      // they are already inside the general total entered by the user.
      final journalWithEpay = DailyJournal.build(
        operationalDate: '2026-11-19',
        outlets: [fakeOutlet(id: 'o1', name: 'منفذ', shiftCount: 2)],
        records: [
          fakeRecord(
            outletId: 'o1',
            outletName: 'منفذ',
            totalFees: 100000,
            general: 500000,
            nfc: 150000,
            visa: 200000,
          ),
        ],
      );
      final withEpay = journalWithEpay.sections.single.rows.single.amounts;
      expect(withEpay.generalTotalPiastres, 500000);
      expect(withEpay.scalesTotalPiastres, 400000);
      expect(journal.dayTotals.generalTotalPiastres,
          journalWithEpay.dayTotals.generalTotalPiastres);
    });
  });

  group('journal structure', () {
    late AppDatabase appDb;
    late RagaaRepository repo;

    setUp(() async {
      appDb = AppDatabase.atPath(inMemoryDatabasePath);
      await appDb.open();
      repo = RagaaRepository(appDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('builds per-shift sections, shift totals, per-outlet day totals and '
        'a non-duplicated grand total', () async {
      await JournalDemoDataset.seed(repo);
      final journal = await repo.buildDailyJournal(
        JournalDemoDataset.operationalDate,
      );

      expect(journal.hasData, isTrue);
      expect(journal.sections.length, 3);
      expect(journal.sections.map((s) => s.shiftNumber), [1, 2, 3]);
      expect(journal.outletDayTotals.length, 8);

      // Outlet printed order must follow the configured outlet order.
      expect(
        journal.outletDayTotals.map((row) => row.outletName).toList(),
        JournalDemoDataset.outlets.map((spec) => spec.$1).toList(),
      );

      // Shift 1 has 8 outlets (all configured for a first shift).
      expect(journal.sections.first.rows.length, 8);

      // Shift totals equal the sum of their own rows.
      for (final section in journal.sections) {
        final manualSum = section.rows.fold<int>(
          0,
          (sum, row) => sum + row.amounts.manualFeesPiastres,
        );
        final generalSum = section.rows.fold<int>(
          0,
          (sum, row) => sum + row.amounts.generalTotalPiastres,
        );
        expect(section.totals.manualFeesPiastres, manualSum);
        expect(section.totals.generalTotalPiastres, generalSum);
        expect(
          section.totals.scalesTotalPiastres,
          section.totals.generalTotalPiastres -
              section.totals.totalFeesPiastres,
        );
      }

      // Grand total = sum of the independent per-outlet day totals (no shift is
      // counted twice).
      final sumOfOutletTotals = journal.outletDayTotals.fold<int>(
        0,
        (sum, row) => sum + row.amounts.generalTotalPiastres,
      );
      expect(journal.dayTotals.generalTotalPiastres, sumOfOutletTotals);
      expect(
        journal.dayTotals.scalesTotalPiastres,
        journal.dayTotals.generalTotalPiastres -
            journal.dayTotals.totalFeesPiastres,
      );

      // «نقل ١» works 3 shifts: its day total = sum of its three shifts.
      final naql1 = journal.outletDayTotals
          .firstWhere((row) => row.outletName == 'نقل ١');
      expect(naql1.recordedShifts, 3);
      expect(naql1.amounts.generalTotalPiastres, 1000000 + 900000 + 700000);
      expect(naql1.amounts.scalesTotalPiastres, 450000 + 500000 + 380000);
      expect(naql1.amounts.nfcPiastres, 100000);
      expect(naql1.amounts.visaPiastres, 75000);

      // «رقابة» works 2 shifts only.
      final raqaba =
          journal.outletDayTotals.firstWhere((row) => row.outletName == 'رقابة');
      expect(raqaba.recordedShifts, 2);
      expect(raqaba.amounts.generalTotalPiastres, 650000);

      // Unrecorded shifts are printed as blank rows, never as invented money.
      final malaqiShift3 = journal.sections
          .firstWhere((section) => section.shiftNumber == 3)
          .rows
          .firstWhere((row) => row.outletName == 'ملاكي');
      expect(malaqiShift3.hasRecord, isFalse);
      expect(malaqiShift3.amounts.isZero, isTrue);
      expect(
        journal.sections
            .firstWhere((section) => section.shiftNumber == 3)
            .recordedCount,
        3,
      );
    });

    test('journal for a day without data keeps the empty paper form', () async {
      await JournalDemoDataset.seed(repo);
      final journal = await repo.buildDailyJournal('2026-11-20');
      expect(journal.hasData, isFalse);
      expect(journal.dayTotals.isZero, isTrue);
      expect(journal.recordedShiftsCount, 0);
      // Every configured outlet is still printed with blank (zero) cells, exactly
      // like the paper form, and nothing is invented.
      expect(journal.outletDayTotals.length, JournalDemoDataset.outlets.length);
      expect(journal.outletDayTotals.every((row) => row.amounts.isZero), isTrue);
    });

    test('rejects invalid operational dates', () async {
      expect(
        () => repo.buildDailyJournal('2026-02-31'),
        throwsA(isA<Exception>()),
      );
    });

    test('outlet order can be changed without losing any data', () async {
      final ids = await JournalDemoDataset.seed(repo);
      final before = await repo.buildDailyJournal(
        JournalDemoDataset.operationalDate,
      );
      expect(before.outletDayTotals.first.outletName, 'نقل ١');

      // Move «الدهسا» to the top of the printed order.
      await repo.reorderOutlets(<String>[
        ids['الدهسا']!,
        ...ids.entries
            .where((entry) => entry.key != 'الدهسا')
            .map((entry) => entry.value),
      ]);

      final after = await repo.buildDailyJournal(
        JournalDemoDataset.operationalDate,
      );
      expect(after.outletDayTotals.first.outletName, 'الدهسا');
      // Values are untouched, only the printed order changed.
      expect(
        after.dayTotals.generalTotalPiastres,
        before.dayTotals.generalTotalPiastres,
      );

      // The reorder is audited.
      final audits = await repo.queryAuditLogs(limit: 5);
      expect(
        audits.any((entry) => entry.summary.contains('إعادة ترتيب المنافذ')),
        isTrue,
      );
    });

    test('moveOutlet moves a single outlet up and down', () async {
      await repo.createOutlet(name: 'أ', shiftCount: 2);
      await repo.createOutlet(name: 'ب', shiftCount: 2);
      await repo.createOutlet(name: 'ج', shiftCount: 2);

      var outlets = await repo.listOutlets();
      expect(outlets.map((outlet) => outlet.name), ['أ', 'ب', 'ج']);

      await repo.moveOutlet(outlets[2].id, -1);
      outlets = await repo.listOutlets();
      expect(outlets.map((outlet) => outlet.name), ['أ', 'ج', 'ب']);

      await repo.moveOutlet(outlets.first.id, -1); // already first -> no-op
      outlets = await repo.listOutlets();
      expect(outlets.map((outlet) => outlet.name), ['أ', 'ج', 'ب']);
    });
  });
}
