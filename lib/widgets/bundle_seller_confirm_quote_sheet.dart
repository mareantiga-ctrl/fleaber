import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/bundle_quote_flow.dart';
import '/utils/dpd_shipping_rates.dart';
import '/widgets/fleaber_primary_button.dart';

/// Vendedora confirma peso/portes → RPC `batata_bundle_seller_confirm_quote`.
Future<bool> showBundleSellerConfirmQuoteSheet({
  required BuildContext context,
  required String bundleId,
  Map<String, dynamic>? bundleMeta,
}) async {
  FleaberDpdWeightBand selected = FleaberDpdWeightBand.upTo3;
  var modality = FleaberDpdModality.shopToShop;
  var busy = false;
  String? error;

  final until = formatBundleDeadlinePt(bundleMeta?['seller_confirm_expires_at']);
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setSt) {
          Future<void> confirm() async {
            setSt(() {
              busy = true;
              error = null;
            });
            try {
              final res = await batataBundleSellerConfirmQuote(
                bundleId: bundleId,
                weightKg: selected.maxKg,
                weightBand: selected.code,
                shippingModality: modality == FleaberDpdModality.shopToShop
                    ? 'shop_to_shop'
                    : 'shop_to_home',
              );
              if (res['ok'] != true) {
                setSt(() {
                  error = humanizeBundleQuoteError(res);
                  busy = false;
                });
                return;
              }
              if (context.mounted) Navigator.of(ctx).pop(true);
            } catch (e) {
              setSt(() {
                error = e.toString();
                busy = false;
              });
            }
          }

          final shipEur = fleaberDpdTablePriceEur(
            modality: modality,
            band: selected,
          );

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Confirmar peso e portes',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  until == null
                      ? 'Tens 48 horas para confirmar. Os artigos continuam disponíveis para venda.'
                      : 'Confirma até $until. Os artigos continuam disponíveis para venda.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                Text(
                  'Escalão de peso',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final b in FleaberDpdWeightBand.values)
                      ChoiceChip(
                        label: Text(b.labelPt),
                        selected: selected == b,
                        onSelected: busy
                            ? null
                            : (_) => setSt(() => selected = b),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Modalidade de envio',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Loja → Loja'),
                      selected: modality == FleaberDpdModality.shopToShop,
                      onSelected: busy
                          ? null
                          : (_) => setSt(
                                () => modality = FleaberDpdModality.shopToShop,
                              ),
                    ),
                    ChoiceChip(
                      label: const Text('Loja → Casa'),
                      selected: modality == FleaberDpdModality.shopToHome,
                      onSelected: busy
                          ? null
                          : (_) => setSt(
                                () => modality = FleaberDpdModality.shopToHome,
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Portes estimados: ${formatBundleEur(shipEur)} '
                  '(a compradora verá artigos + portes + Proteção Fleaber).',
                  style: GoogleFonts.inter(fontSize: 12.5, color: Colors.black54),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: const Color(0xFFB00020),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FleaberPrimaryButton(
                  width: double.infinity,
                  label: busy ? 'A confirmar…' : 'Confirmar cotação',
                  onPressed: busy ? null : confirm,
                ),
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  return result == true;
}
