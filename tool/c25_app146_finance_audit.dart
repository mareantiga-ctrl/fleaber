// ignore_for_file: avoid_print
/// Auditoria financeira APP-146 — todas as txs do buyer ligadas à encomenda C25
/// + saldo + tipos relacionados etiqueta/portes.
library;

import 'dart:convert';

import 'live_ops_staging_client.dart';

const _orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
const _buyerId = '7848848c-92df-4341-ad2a-7a5c24f1c250';
const _sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL')),
    anonKey: envRequire(e, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final order = (await c.select('orders', filter: 'id=eq.$_orderId', limit: 1))
      .first;
  final dispute = await c.select(
    'order_disputes',
    filter: 'order_id=eq.$_orderId',
    limit: 5,
  );
  final txsOrder = await c.select(
    'wallet_transactions',
    filter: 'order_id=eq.$_orderId',
    limit: 50,
  );
  // Qualquer tx buyer no dia do reembolso (para não perder débito sem order_id)
  final txsBuyerRecent = await c.select(
    'wallet_transactions',
    filter:
        'wallet_id=eq.$_buyerId&created_at=gte.2026-08-22T00:00:00Z&order=created_at.asc',
    limit: 100,
  );
  final buyerWallet =
      (await c.select('wallets', filter: 'id=eq.$_buyerId', limit: 1)).first;
  final sellerWallet =
      (await c.select('wallets', filter: 'id=eq.$_sellerId', limit: 1)).first;

  // Soma líquida por order_id no buyer
  var netBuyerOnOrder = 0.0;
  for (final t in txsOrder) {
    if (t['wallet_id']?.toString() == _buyerId) {
      netBuyerOnOrder += (t['amount'] as num?)?.toDouble() ?? 0;
    }
  }

  final feeUi = 3.5;
  final price = (order['price_total'] as num?)?.toDouble() ?? 0;
  final expectedNetIfFeeDeducted = price - feeUi;
  final sellerPaysShipping = dispute.isNotEmpty
      ? dispute.first['seller_pays_return_shipping'] == true
      : null;

  print(jsonEncode({
    'order': {
      'id': order['id'],
      'price_total': order['price_total'],
      'status': order['status'],
      'wallet_refund_processed_at': order['wallet_refund_processed_at'],
      'returned_at': order['returned_at'],
    },
    'dispute': dispute,
    'ui_rule_copy':
        'Custo da etiqueta: 3,50 € abatido ao reembolso se portes a cargo do comprador',
    'seller_pays_return_shipping': sellerPaysShipping,
    'expected_refund_gross': price,
    'expected_label_fee_if_buyer_pays': feeUi,
    'expected_net_if_fee_deducted': expectedNetIfFeeDeducted,
    'wallet_transactions_for_order': txsOrder,
    'buyer_wallet_txs_on_2026_08_22': txsBuyerRecent,
    'buyer_wallet': buyerWallet,
    'seller_wallet': sellerWallet,
    'net_buyer_amount_on_order_txs': netBuyerOnOrder,
    'has_label_fee_debit_tx': txsOrder.any((t) {
      final a = (t['amount'] as num?)?.toDouble() ?? 0;
      final typ = (t['type'] ?? '').toString().toLowerCase();
      final desc = (t['description'] ?? '').toString().toLowerCase();
      return a == -feeUi ||
          a == feeUi && typ.contains('etiqueta') ||
          desc.contains('etiqueta') ||
          desc.contains('portes') ||
          desc.contains('label');
    }),
    'verdict_hint': netBuyerOnOrder == price
        ? 'BUG: reembolso bruto = preço; sem débito 3,50 apesar UI e seller_pays_return_shipping=false'
        : (netBuyerOnOrder == expectedNetIfFeeDeducted
            ? 'OK líquido 1,50'
            : 'INVESTIGAR net=$netBuyerOnOrder'),
  }));
}
