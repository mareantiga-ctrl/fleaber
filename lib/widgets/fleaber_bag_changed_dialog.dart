import 'package:flutter/material.dart';

import '/utils/fee_calculator.dart';
import '/widgets/fleaber_primary_button.dart';
import '/widgets/live_vendor_ops_ui.dart';

/// Phase 4 — bag revalidation UX when some lines become unavailable.
class FleaberBagChangedDialog extends StatelessWidget {
  const FleaberBagChangedDialog({
    super.key,
    required this.unavailableCount,
    required this.totalCents,
  });

  final int unavailableCount;
  final int totalCents;

  static Future<bool?> show(
    BuildContext context, {
    required int unavailableCount,
    required int totalCents,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => FleaberBagChangedDialog(
        unavailableCount: unavailableCount,
        totalCents: totalCents,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalLabel = formatEuros(totalCents / 100.0);
    final unavailableLine =
        LiveVendorSellerCopy.artigosIndisponiveis(unavailableCount);
    final body =
        '$unavailableLine Queres pagar só o que resta?\n\nNovo total: $totalLabel';

    return AlertDialog(
      title: const Text('O saco mudou'),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        // Content-sized CTA — padding real ~24 px; altura 48; não oversized.
        FleaberPrimaryButton(
          onPressed: () => Navigator.pop(context, true),
          label: 'Continuar',
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Colors.white,
            height: 1.2,
          ),
        ),
      ],
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    );
  }
}
