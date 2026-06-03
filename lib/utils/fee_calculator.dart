import 'package:intl/intl.dart';

const double fleaberProtectionFixedFeeEur = 0.65;
const double fleaberProtectionPercentage = 0.05;

double _roundEuroCents(double value) => (value * 100).roundToDouble() / 100;

double calculateFleaberProtectionFee(
  double itemPriceEur, {
  double shippingEur = 0,
}) {
  final protectedAmount = itemPriceEur + shippingEur;
  if (protectedAmount <= 0 || protectedAmount.isNaN) return 0;
  return _roundEuroCents(
    fleaberProtectionFixedFeeEur +
        (protectedAmount * fleaberProtectionPercentage),
  );
}

double calculateFleaberBuyerTotal({
  required double itemPriceEur,
  double shippingEur = 0,
  bool includeProtectionFee = true,
}) {
  final fee = includeProtectionFee
      ? calculateFleaberProtectionFee(
          itemPriceEur,
          shippingEur: shippingEur,
        )
      : 0.0;
  return _roundEuroCents(itemPriceEur + shippingEur + fee);
}

String formatFleaberProtectionFee(
  double itemPriceEur, {
  double shippingEur = 0,
}) {
  return formatEuros(
    calculateFleaberProtectionFee(
      itemPriceEur,
      shippingEur: shippingEur,
    ),
  );
}

String formatFleaberBuyerTotal({
  required double itemPriceEur,
  double shippingEur = 0,
  bool includeProtectionFee = true,
}) {
  return formatEuros(
    calculateFleaberBuyerTotal(
      itemPriceEur: itemPriceEur,
      shippingEur: shippingEur,
      includeProtectionFee: includeProtectionFee,
    ),
  );
}

String formatEuros(double value) {
  final safeValue = value.isNaN ? 0.0 : value;
  return NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(safeValue);
}
