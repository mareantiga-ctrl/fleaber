import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/dpd_shipping_rates.dart';
import '/utils/order_post_purchase_lifecycle.dart';
import '/utils/order_shipping_ops_service.dart';
import '/widgets/fleaber_primary_button.dart';

/// ZIP 140 — vendedor confirma peso (3 dias) / assume / solicita diferença.
Future<void> showOrderWeightConfirmSheet({
  required BuildContext context,
  required String orderId,
  String? chargedBand,
}) async {
  FleaberDpdWeightBand? selected =
      FleaberDpdWeightBand.fromCode(chargedBand) ?? FleaberDpdWeightBand.upTo3;
  var busy = false;
  String? error;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setSt) {
          Future<void> run(String action) async {
            if (selected == null) return;
            setSt(() {
              busy = true;
              error = null;
            });
            try {
              final res = await OrderShippingOpsService.sellerConfirmWeight(
                orderId: orderId,
                actualBand: selected,
                action: action,
              );
              if (res['ok'] != true) {
                setSt(() {
                  error = (res['message'] ?? res['error'] ?? 'Falha').toString();
                  busy = false;
                });
                return;
              }
              if (context.mounted) Navigator.of(ctx).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      action == 'request_delta'
                          ? 'Diferença pedida ao comprador (48 h).'
                          : action == 'assume'
                              ? 'Assumiste a diferença de portes.'
                              : 'Peso confirmado.',
                    ),
                  ),
                );
              }
            } catch (e) {
              setSt(() {
                error = e.toString();
                busy = false;
              });
            }
          }

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
                  'Confirmar peso do envio',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tens 3 dias após o pagamento. Escalão cobrado ao comprador: '
                  '${chargedBand ?? '—'}.',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final b in FleaberDpdWeightBand.values)
                      ChoiceChip(
                        label: Text(b.labelPt),
                        selected: selected == b,
                        onSelected: busy
                            ? null
                            : (v) => setSt(() => selected = v ? b : selected),
                      ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 14),
                FleaberPrimaryButton(
                  label: busy ? 'A processar…' : 'Confirmar (sem diferença)',
                  onPressed: busy || selected?.code != chargedBand
                      ? null
                      : () => run('confirm'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy || selected?.code == chargedBand
                      ? null
                      : () => run('assume'),
                  child: const Text('Assumir diferença de portes'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy || selected?.code == chargedBand
                      ? null
                      : () => run('request_delta'),
                  child: const Text('Pedir diferença ao comprador (48 h)'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Se pedires diferença, o prazo de envio fica pausado até o '
                  'comprador pagar. Etiqueta DPD bloqueada enquanto pendente.',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Comprador: pagar diferença pendente.
Future<void> showOrderShippingDeltaPaySheet({
  required BuildContext context,
  required String orderId,
}) async {
  final adj = await OrderShippingOpsService.fetchPendingAdjustment(orderId);
  if (!context.mounted) return;
  if (adj == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não há diferença de portes pendente.')),
    );
    return;
  }
  final delta = _num(adj['shipping_delta_cents']) / 100.0;
  final fee = _num(adj['stripe_fee_grossup_cents']) / 100.0;
  final total = _num(adj['amount_charge_cents']) / 100.0;
  final adjId = adj['id']?.toString() ?? '';
  final expiresRaw = adj['expires_at']?.toString() ?? '';
  final expires =
      formatOrderDeadlineIsoPt(expiresRaw) ?? expiresRaw;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      var busy = false;
      return StatefulBuilder(
        builder: (context, setSt) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Diferença de portes',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    'Portes extra: ${delta.toStringAsFixed(2)} €',
                    if (fee > 0)
                      'Processamento Stripe: ${fee.toStringAsFixed(2)} €'
                    else
                      'Sem taxa de processamento adicional neste pagamento '
                          '(política PSD2 — taxa Stripe absorvida).',
                    'Total a pagar: ${total.toStringAsFixed(2)} €',
                    'Sem Proteção Fleaber neste pagamento.',
                    if (expires.isNotEmpty) 'Prazo (48 h): $expires',
                  ].join('\n'),
                  style: GoogleFonts.inter(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),
                FleaberPrimaryButton(
                  label: busy ? 'A abrir…' : 'Pagar diferença',
                  onPressed: busy || adjId.isEmpty
                      ? null
                      : () async {
                          setSt(() => busy = true);
                          try {
                            await OrderShippingOpsService.buyerPayShippingDelta(
                              orderId: orderId,
                              adjustmentId: adjId,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                            setSt(() => busy = false);
                          }
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

num _num(dynamic v) {
  if (v is num) return v;
  return num.tryParse('$v') ?? 0;
}
