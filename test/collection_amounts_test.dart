import 'package:flutter_test/flutter_test.dart';
import 'package:ragaa/models/collection_amounts.dart';

void main() {
  test('derives scales from independently entered general total and total fees',
      () {
    const amounts = CollectionAmounts(
      manualFeesPiastres: 200000,
      automaticFeesPiastres: 300000,
      totalFeesPiastres: 550000,
      generalTotalPiastres: 1000000,
      nfcPiastres: 100000,
      visaPiastres: 50000,
    );

    expect(amounts.scalesTotalPiastres, 450000);
    expect(amounts.generalTotalPiastres, 1000000);
    expect(amounts.totalFeesPiastres, 550000);
  });

  test('accepts omitted electronic payments as zero', () {
    const amounts = CollectionAmounts(
      manualFeesPiastres: 0,
      automaticFeesPiastres: 0,
      totalFeesPiastres: 0,
      generalTotalPiastres: 250000,
    );

    expect(amounts.nfcPiastres, 0);
    expect(amounts.visaPiastres, 0);
    expect(amounts.scalesTotalPiastres, 250000);
  });
}
