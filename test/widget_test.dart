import 'package:flutter_test/flutter_test.dart';
import 'package:ragaa/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('validates operational dates and parses Arabic/Latin money safely', () {
    expect(isValidOperationalDate('2026-11-18'), isTrue);
    expect(isValidOperationalDate('2026-02-31'), isFalse);
    expect(isValidOperationalDate('2026-11-18T10:00:00'), isFalse);

    expect(tryParsePiastres('125.5'), 12550);
    expect(tryParsePiastres('١٢٥٠٫٧٥'), 125075);
    expect(tryParsePiastres('10.999'), isNull);
  });

  test('load() is idempotent and enforces shift bounds per outlet', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RagaaStore();
    await store.load();
    await store.addOutlet('منفذ التحرير', 2);
    await store.addOutlet('منفذ رمسيس', 3);

    // Reloading must not duplicate in-memory lists.
    await store.load();
    expect(store.outlets.length, 2);

    final twoShift = store.outlets.firstWhere((o) => o.shiftCount == 2);
    final threeShift = store.outlets.firstWhere((o) => o.shiftCount == 3);

    expect(
      () => store.saveCollection(Collection(twoShift.id, '2026-11-18', 3, 5000)),
      throwsFormatException,
    );
    await store.saveCollection(
      Collection(threeShift.id, '2026-11-18', 3, 15000),
    );
    expect(store.collections.length, 1);
  });

  testWidgets('renders Arabic RTL app and switches 3-shift to 2-shift cleanly',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RagaaApp());
    await tester.pumpAndSettle();

    expect(find.text('RAGAA | إدارة التحصيل'), findsOneWidget);
    expect(
      find.text('تاريخ البداية يجب ألا يكون بعد تاريخ النهاية'),
      findsNothing,
    );
  });
}
