import '../core/formatters.dart';

/// The approved monetary fields for one outlet shift, represented as integer
/// piastres to keep all accounting arithmetic exact.
class CollectionAmounts {
  final int manualFeesPiastres;
  final int automaticFeesPiastres;
  final int totalFeesPiastres;
  final int generalTotalPiastres;
  final int nfcPiastres;
  final int visaPiastres;

  const CollectionAmounts({
    required this.manualFeesPiastres,
    required this.automaticFeesPiastres,
    required this.totalFeesPiastres,
    required this.generalTotalPiastres,
    this.nfcPiastres = 0,
    this.visaPiastres = 0,
  });

  /// The only approved formula for the scales column. NFC/VISA are already
  /// included in [generalTotalPiastres] and are deliberately not added here.
  int get scalesTotalPiastres => generalTotalPiastres - totalFeesPiastres;

  bool get isValid =>
      [
        manualFeesPiastres,
        automaticFeesPiastres,
        totalFeesPiastres,
        generalTotalPiastres,
        nfcPiastres,
        visaPiastres,
      ].every((value) => value >= 0 && value <= kMaxAmountPiastres) &&
      scalesTotalPiastres >= 0;

  Map<String, int> toDatabaseMap() => {
        'manual_fees_piastres': manualFeesPiastres,
        'automatic_fees_piastres': automaticFeesPiastres,
        'total_fees_piastres': totalFeesPiastres,
        'general_total_piastres': generalTotalPiastres,
        'nfc_piastres': nfcPiastres,
        'visa_piastres': visaPiastres,
      };
}
