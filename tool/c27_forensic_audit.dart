// ignore_for_file: avoid_print
/// C27 — auditoria forense independente (ligação reserva↔encomenda + dinheiro).
library;

import 'dart:convert';
import 'dart:io';

import 'package:fleaber/utils/fee_calculator.dart';

import 'live_ops_staging_client.dart';

const _orderId = '0f632c04-b3c5-4074-8957-892e258f7f92';
const _reqId = '2eafca8c-c9d9-46f4-8059-7fc87f7365dd';
const _liveId = '4901d8c0-49db-4471-a2f8-c7154e6d5e26';
const _out = 'tool/reports/battery_c27_2026-08-23/bd/c27_forensic_independent.json';

Future<List<Map<String, dynamic>>> _trySelect(
  LiveOpsStagingClient c,
  String table, {
  required String filter,
}) async {
  try {
    return await c.select(table, filter: filter, limit: 50);
  } catch (e) {
    return [
      {'_error': e.toString(), '_table': table},
    ];
  }
}

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final order =
      (await client.select('orders', filter: 'id=eq.$_orderId', limit: 1)).first;
  final req = (await client.select(
    'live_reservation_requests',
    filter: 'id=eq.$_reqId',
    limit: 1,
  )).first;

  final notes = req['notes']?.toString() ?? '';
  final stripePaidTag = 'stripe_paid:$_orderId';
  final stripeCheckoutTag = 'stripe_checkout:$_orderId';

  final unit = 11.0;
  const qty = 1;
  const shipping = kFleaberCarrierShippingEur;

  final uiProtection =
      calculateFleaberProtectionFee(unit * qty, shippingEur: shipping);
  final uiTotal = calculateFleaberBuyerTotal(
    itemPriceEur: unit * qty,
    shippingEur: shipping,
    includeProtectionFee: true,
  );

  final bagLineProtection =
      calculateFleaberProtectionFee(unit * qty, shippingEur: 0);
  final bagLineTotal = calculateFleaberBuyerTotal(
    itemPriceEur: unit * qty,
    shippingEur: 0,
    includeProtectionFee: true,
  );
  final bagStripeTotal = bagLineTotal + shipping;

  final stored = (order['price_total'] as num?)?.toDouble() ?? 0;

  final stripeEvents = await _trySelect(
    client,
    'stripe_checkout_events',
    filter: 'order_id=eq.$_orderId&order=created_at.desc',
  );
  final walletTx = await _trySelect(
    client,
    'wallet_transactions',
    filter: 'order_id=eq.$_orderId&order=created_at.desc',
  );

  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'app254_link': {
      'reservation_id': _reqId,
      'order_id': _orderId,
      'reservation_status': req['status'],
      'reservation_notes': notes,
      'reservation_order_id_column': req['order_id'],
      'order_live_reservation_request_id': order['live_reservation_request_id'],
      'proof_stripe_paid_in_notes': notes.contains(stripePaidTag),
      'proof_stripe_checkout_in_notes': notes.contains(stripeCheckoutTag),
      'mechanism':
          'batata_live_reservation_stripe_convert grava stripe_paid:{order_id} em notes; '
          'batata_live_reconcile_stripe_order faz match por notes/live_id/buyer_id/live_item_id',
    },
    'app214_finance': {
      'order_row': order,
      'formulas': {
        'ui_checkout_total_eur': uiTotal,
        'ui_breakdown': {
          'items_eur': unit * qty,
          'shipping_eur': shipping,
          'protection_eur': uiProtection,
        },
        'bag_persist_line_total_eur': bagLineTotal,
        'bag_persist_breakdown': {
          'items_eur': unit * qty,
          'protection_on_items_only_eur': bagLineProtection,
        },
        'bag_stripe_expected_eur': bagStripeTotal,
        'stored_price_total_bd': stored,
        'delta_ui_minus_bd': (uiTotal - stored).toStringAsFixed(2),
        'delta_ui_minus_stripe_expected':
            (uiTotal - bagStripeTotal).toStringAsFixed(2),
        'delta_stripe_expected_minus_bd':
            (bagStripeTotal - stored).toStringAsFixed(2),
      },
    },
    'stripe_checkout_events': stripeEvents,
    'wallet_transactions': walletTx,
    'live_id': _liveId,
  };

  File(_out)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
}
