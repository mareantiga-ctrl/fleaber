import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fee_calculator.dart';
import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_checkout_ui.dart';

/// Mostra MB WAY / IBAN e valor a transferir para conjunto em pagamento directo.
Future<void> showBundleDirectPaymentDetailsSheet(
  BuildContext context, {
  required Map<String, dynamic> details,
}) {
  final amount = (details['amount_eur'] as num?)?.toDouble() ?? 0.0;
  final itemsEur = (details['items_eur'] as num?)?.toDouble();
  final shippingEur = (details['shipping_eur'] as num?)?.toDouble();
  final mbWay = details['mb_way']?.toString().trim() ?? '';
  final iban = details['iban']?.toString().trim() ?? '';

  return FleaberCheckoutUi.showHost<void>(
    context: context,
    builder: (ctx) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FleaberCheckoutHandle(),
                    FleaberCheckoutTitleBar(
                      title: 'Dados de pagamento',
                      subtitle:
                          'Transfere o valor e confirma depois no chat ou no saco.',
                      onClose: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FleaberCheckoutBody(
                  primaryLabel: 'Fechar',
                  onPrimary: () => Navigator.of(ctx).pop(),
                  children: [
                    FleaberCheckoutTotalsCard(
                      lines: [
                        FleaberCheckoutPriceLine(
                          label: 'Valor a pagar',
                          value: formatEuros(amount),
                          isTotal: true,
                        ),
                        if (itemsEur != null)
                          FleaberCheckoutPriceLine(
                            label: 'Artigos',
                            value: formatEuros(itemsEur),
                          ),
                        if (shippingEur != null)
                          FleaberCheckoutPriceLine(
                            label: 'Envio',
                            value: formatEuros(shippingEur),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (mbWay.isNotEmpty) ...[
                      const FleaberCheckoutSectionLabel('MB WAY'),
                      const SizedBox(height: 6),
                      SelectableText(
                        mbWay,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: FleaberColors.teal,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (iban.isNotEmpty) ...[
                      const FleaberCheckoutSectionLabel('IBAN'),
                      const SizedBox(height: 6),
                      SelectableText(
                        iban,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: FleaberCheckoutUi.ink,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (mbWay.isEmpty && iban.isEmpty)
                      Text(
                        'O vendedor ainda não indicou MB WAY nem IBAN no perfil. '
                        'Pede os dados no chat.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.35,
                          color: FleaberCheckoutUi.muted,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Depois de pagares, usa «Confirmar pagamento» no saco ou no chat '
                      'para enviar a prova ao vendedor.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.35,
                        color: FleaberCheckoutUi.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
