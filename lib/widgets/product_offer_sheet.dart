import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_colors.dart';
import '/utils/fleaber_radius.dart';
import '/utils/fee_calculator.dart';
import '/widgets/fleaber_primary_button.dart';

/// Bottom sheet estilo Vinted — introduzir valor da proposta.
Future<double?> showProductOfferAmountSheet({
  required BuildContext context,
  required ProductsRow product,
  String title = 'Fazer proposta',
  String? subtitle,
  double? initialAmountEur,
}) async {
  final listPrice = product.price ?? 0;
  final ctrl = TextEditingController(
    text: initialAmountEur != null && initialAmountEur > 0
        ? initialAmountEur.toStringAsFixed(2).replaceAll('.', ',')
        : '',
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
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E3E7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF101518),
                  ),
                ),
                if (listPrice > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Preço do anúncio: ${formatEuros(listPrice)}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: FleaberColors.teal,
                    ),
                  ),
                ],
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.35,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[\d,\.]'),
                    ),
                  ],
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'O teu preço (€)',
                    hintText: 'ex.: 12,50',
                    errorText: errorText,
                    border: OutlineInputBorder(
                      borderRadius: FleaberRadius.circularMd,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: FleaberRadius.circularMd,
                      borderSide: const BorderSide(
                        color: FleaberColors.teal,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'O vendedor pode aceitar, recusar ou enviar uma contra-proposta no chat.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.35,
                    color: const Color(0xFF57636C),
                  ),
                ),
                const SizedBox(height: 20),
                FleaberPrimaryButton(
                  label: 'Enviar proposta',
                  onPressed: () {
                          final raw = ctrl.text.trim().replaceAll(',', '.');
                          final v = double.tryParse(raw);
                          if (v == null || v <= 0) {
                            setModalState(() {
                              errorText = 'Introduz um valor válido.';
                            });
                            return;
                          }
                          if (listPrice > 0 && v >= listPrice) {
                            setModalState(() {
                              errorText =
                                  'Deve ser inferior a ${formatEuros(listPrice)}.';
                            });
                            return;
                          }
                          Navigator.of(ctx).pop(v);
                        },
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF57636C),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String formatOfferEuros(double value) =>
    NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(value);
