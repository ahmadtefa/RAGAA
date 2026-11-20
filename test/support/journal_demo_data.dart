import 'package:ragaa/data/ragaa_repository.dart';
import 'package:ragaa/models/collection_amounts.dart';

/// One demo collection entry: (manual, automatic, totalFees, general, nfc, visa)
/// expressed in piastres, exactly as the office would enter them.
typedef DemoEntry = (int, int, int, int, int, int);

/// Deterministic demo dataset used by the unit tests and by the review sample
/// generator, modelled on the real paper daily journal (8 outlets, mixed 2 and 3
/// shift configurations, one deliberately unrecorded shift).
class JournalDemoDataset {
  static const String operationalDate = '2026-11-19';

  /// Outlet name -> configured shift count, in the printed order.
  static const List<(String, int)> outlets = <(String, int)>[
    ('نقل ١', 3),
    ('نقل ٢', 3),
    ('ملاكي', 3),
    ('خروج ١', 3),
    ('رقابة', 2),
    ('المنيا ٢', 2),
    ('المنيا ٣', 2),
    ('الدهسا', 2),
  ];

  /// Outlet name -> shift number -> amounts. Shift 1 of «نقل ١» is the official
  /// validation example: 2000 + 3000 fees, 5500 total fees, 10000 general total,
  /// 1000 NFC, 500 VISA -> scales total 4500.
  static const Map<String, Map<int, DemoEntry>> entries =
      <String, Map<int, DemoEntry>>{
    'نقل ١': <int, DemoEntry>{
      1: (200000, 300000, 550000, 1000000, 100000, 50000),
      2: (150000, 250000, 400000, 900000, 0, 0),
      3: (120000, 200000, 320000, 700000, 0, 25000),
    },
    'نقل ٢': <int, DemoEntry>{
      1: (100000, 150000, 260000, 600000, 50000, 0),
      2: (90000, 120000, 210000, 500000, 0, 0),
      3: (80000, 100000, 180000, 450000, 0, 0),
    },
    'ملاكي': <int, DemoEntry>{
      1: (60000, 90000, 150000, 400000, 0, 0),
      2: (50000, 70000, 120000, 350000, 0, 0),
      // Shift 3 intentionally not recorded.
    },
    'خروج ١': <int, DemoEntry>{
      1: (20000, 30000, 50000, 150000, 0, 0),
      2: (15000, 25000, 40000, 120000, 0, 0),
      3: (10000, 15000, 25000, 90000, 0, 0),
    },
    'رقابة': <int, DemoEntry>{
      1: (50000, 80000, 130000, 350000, 0, 0),
      2: (45000, 70000, 115000, 300000, 0, 0),
    },
    'المنيا ٢': <int, DemoEntry>{
      1: (30000, 40000, 70000, 200000, 0, 0),
      // Shift 2 intentionally not recorded.
    },
    'المنيا ٣': <int, DemoEntry>{
      1: (25000, 35000, 60000, 180000, 0, 0),
      2: (20000, 30000, 50000, 150000, 0, 0),
    },
    'الدهسا': <int, DemoEntry>{
      1: (120000, 180000, 300000, 900000, 0, 0),
      2: (110000, 160000, 270000, 850000, 0, 0),
    },
  };

  /// Creates the demo outlets (in printed order) and their collections.
  /// Returns `outlet name -> outlet id`.
  static Future<Map<String, String>> seed(RagaaRepository repo) async {
    final ids = <String, String>{};
    for (final spec in outlets) {
      final created = await repo.createOutlet(name: spec.$1, shiftCount: spec.$2);
      ids[spec.$1] = created.id;
    }

    for (final outletEntry in entries.entries) {
      final outletId = ids[outletEntry.key]!;
      for (final shiftEntry in outletEntry.value.entries) {
        final values = shiftEntry.value;
        await repo.createCollection(
          outletId: outletId,
          operationalDate: operationalDate,
          shiftNumber: shiftEntry.key,
          amounts: CollectionAmounts(
            manualFeesPiastres: values.$1,
            automaticFeesPiastres: values.$2,
            totalFeesPiastres: values.$3,
            generalTotalPiastres: values.$4,
            nfcPiastres: values.$5,
            visaPiastres: values.$6,
          ),
        );
      }
    }
    return ids;
  }
}
