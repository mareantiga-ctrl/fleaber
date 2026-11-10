import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/batata_bundle_discounts.dart';
import '/utils/fee_calculator.dart';
import '/widgets/fleaber_primary_button.dart';

/// Sheet de proposta/contraproposta para **conjunto** (subtotal, desconto, total artigos).
Future<double?> showBundleOfferAmountSheet({
  required BuildContext context,
  required List<ProductsRow> products,
  required BundleProductQuantities quantities,
  required BundleDiscountTiers tiers,
  String title = 'Proposta pelo conjunto',
  String? subtitle,
  double? initialOfferEur,
}) async {
  if (products.length < 2) return null;
  final totals = calculateBundleTotals(
    products: products,
    tiers: tiers,
    quantitiesByProductId: quantities,
  );
  final suggested = initialOfferEur != null && initialOfferEur > 0
      ? initialOfferEur
      : totals.total;
  final itemCount = bundleTotalItemCount(products, quantities);
  final ctrl = TextEditingController(
    text: suggested > 0 ? suggested.toStringAsFixed(2).replaceAll('.', ',') : '',
  );

  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      String? errorText;
      return StatefulBuilder(
        builder: (context, setModalState) {
          final bottom = MediaQuery.viewInsetsOf(context).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.35,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '$itemCount artigos',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                _line('Subtotal artigos', formatEuros(totals.subtotal)),
                if (totals.discountEur > 0.009) ...[
                  _line(
                    'Desconto de conjunto (${totals.discountPct.toStringAsFixed(0)}%)',
                    '− ${formatEuros(totals.discountEur)}',
                    valueColor: const Color(0xFF2E7D32),
                  ),
                  _line(
                    'Artigos (após desconto)',
                    formatEuros(totals.total),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'O teu valor',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\s]')),
                  ],
                  decoration: InputDecoration(
                    prefixText: '€ ',
                    hintText: totals.total.toStringAsFixed(2),
                    errorText: errorText,
                  ),
                ),
                const SizedBox(height: 14),
                FleaberPrimaryButton(
                  width: double.infinity,
                  label: 'Enviar proposta',
                  onPressed: () {
                    final raw = ctrl.text.trim().replaceAll(',', '.');
                    final parsed = double.tryParse(raw);
                    if (parsed == null || parsed <= 0) {
                      setModalState(
                        () => errorText = 'Indica um valor válido.',
                      );
                      return;
                    }
                    Navigator.of(ctx).pop(parsed);
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _line(String label, String value, {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF57636C),
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? const Color(0xFF101518),
          ),
        ),
      ],
    ),
  );
}
