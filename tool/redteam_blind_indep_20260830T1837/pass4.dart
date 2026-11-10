/// PASS 4 — assinaturas RPC exactas + settle de tip fake + observação económica.
/// Auditoria cega 20260830T1837. Não corrige. Não produção.
import 'dart:io';

import '_rt.dart';

Future<void> main() async {
  final c = await boot();
  stdout.writeln('PASS4 boot');

  final w0 = await rest(
    c.url,
    'GET',
    'wallets?id=in.(${c.buyerId},${c.sellerId})&select=id,balance',
    headers: c.svcH,
  );
  rec(
    surface: 'WALLET',
    attack: 'balances before pass4',
    identity: 'svc_observe',
    result: briefBody(w0),
    evidence: decode(w0),
  );

  final tips = await rest(
    c.url,
    'GET',
    'live_tips?buyer_id=eq.${c.buyerId}&order=created_at.desc&select=id,live_id,seller_id,amount,status,stripe_session_id,payment_source,completed_at&limit=8',
    headers: c.svcH,
  );
  rec(
    surface: 'TIPS',
    attack: 'recent buyer tips',
    identity: 'svc_observe',
    result: briefBody(tips),
    evidence: decode(tips),
  );

  final tipRows = asMaps(decode(tips));
  final fake = tipRows.where((t) {
    final s = '${t['stripe_session_id'] ?? ''}';
    return s.contains('cs_fake') || s.contains(prefix);
  }).toList();
  final pending = tipRows.where((t) => '${t['status']}' == 'pending').toList();

  for (final t in [...fake, ...pending].take(4)) {
    final id = t['id'].toString();
    final settle = await rpc(
      c.url,
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': id,
        'p_stripe_session_id': t['stripe_session_id'] ?? 'cs_fake',
        'p_paid_amount_cents': 10000,
      },
      headers: c.buyerH,
    );
    rec(
      surface: 'TIPS',
      attack: 'JWT settle fake/pending tip $id amount 100€',
      identity: 'buyer',
      result: briefBody(settle),
    );
    if (settle.statusCode == 200 &&
        !settle.body.toLowerCase().contains('permission') &&
        !settle.body.contains('false') &&
        settle.body.trim() != 'null') {
      finding(
        id: 'RT1837-P0-TIP-SETTLE',
        severity: 'P0',
        title: 'JWT liquida gorjeta Stripe sem pagamento real',
        actor: 'buyer',
        pre: 'live_tip pending com session fake',
        repro: 'rpc batata_settle_live_tip_from_stripe',
        impact: 'crédito seller sem captura',
        evidence: {'tip': t, 'rpc': briefBody(settle)},
      );
    }
  }

  final debit = await rpc(
    c.url,
    'batata_debit_wallet_once',
    {
      'p_wallet_id': c.sellerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 1,
      'p_description': prefix,
    },
    headers: c.buyerH,
  );
  rec(
    surface: 'RPC',
    attack: 'debit_wallet_once correct args as buyer vs seller wallet',
    identity: 'buyer',
    result: briefBody(debit),
  );
  if (debit.statusCode == 200 && debit.body.toLowerCase().contains('true')) {
    finding(
      id: 'RT1837-P0-DEBIT-RPC',
      severity: 'P0',
      title: 'JWT debita carteira alheia',
      actor: 'buyer',
      pre: 'JWT',
      repro: 'rpc batata_debit_wallet_once',
      impact: 'roubo de saldo',
      evidence: briefBody(debit),
    );
  }

  final fin = await rpc(
    c.url,
    'batata_wallet_payout_finish',
    {
      'p_idempotency_key': '${prefix}-same',
      'p_stripe_transfer_id': 'tr_forged',
      'p_failed': false,
    },
    headers: c.buyerH,
  );
  rec(
    surface: 'PAYOUT',
    attack: 'payout_finish forged transfer as buyer',
    identity: 'buyer',
    result: briefBody(fin),
  );

  final award = await rpc(
    c.url,
    'batata_award_live_raffle_tickets',
    {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
      'p_user_id': c.buyerId,
      'p_source_id': 'x',
      'p_tickets_delta': 99,
      'p_action_type': 'share',
      'p_metadata': {},
    },
    headers: c.buyerH,
  );
  rec(
    surface: 'RAFFLE',
    attack: 'award 99 tickets self',
    identity: 'buyer',
    result: briefBody(award),
  );

  final ds = await rest(
    c.url,
    'GET',
    'order_disputes?select=id,order_id,status&limit=3',
    headers: c.buyerH,
  );
  final dlist = asMaps(decode(ds));
  if (dlist.isNotEmpty) {
    final oid = dlist.first['order_id'].toString();
    final pr = await rpc(
      c.url,
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid, 'p_refund_percent': 100},
      headers: c.buyerH,
    );
    rec(
      surface: 'REFUND',
      attack: 'partial refund 100% as buyer on own dispute order',
      identity: 'buyer',
      result: briefBody(pr),
    );
    final prs = await rpc(
      c.url,
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid, 'p_refund_percent': 100},
      headers: c.sellerH,
    );
    rec(
      surface: 'REFUND',
      attack: 'partial refund 100% as seller',
      identity: 'seller',
      result: briefBody(prs),
    );
  }

  final tok = await rpc(
    c.url,
    'batata_create_seller_device_token',
    {'p_device_id': 'rt1837-buyer', 'p_label': prefix},
    headers: c.buyerH,
  );
  rec(
    surface: 'PS',
    attack: 'buyer create seller device token',
    identity: 'buyer',
    result: briefBody(tok),
  );

  final tokS = await rpc(
    c.url,
    'batata_create_seller_device_token',
    {'p_device_id': 'rt1837-seller', 'p_label': prefix},
    headers: c.sellerH,
  );
  rec(
    surface: 'PS',
    attack: 'seller create device token',
    identity: 'seller',
    result: briefBody(tokS),
  );

  // Bag checkout two products
  try {
    final p1 = await c.admin.insert('products', {
      'seller_id': c.sellerId,
      'title': '$prefix bag1 ${tag()}',
      'price': 5.0,
      'quantity': 2,
      'list_on_marketplace': true,
      'is_sold': false,
    });
    final p2 = await c.admin.insert('products', {
      'seller_id': c.sellerId,
      'title': '$prefix bag2 ${tag()}',
      'price': 6.0,
      'quantity': 2,
      'list_on_marketplace': true,
      'is_sold': false,
    });
    final o1 = await rest(c.url, 'POST', 'orders', headers: c.buyerH, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': p1['id'],
      'quantity': 1,
      'price_total': 5,
      'status': 'reserva_pendente',
      'payment_method': 'Seguro Fleaber',
      'shipping_method': 'hand',
    });
    final o2 = await rest(c.url, 'POST', 'orders', headers: c.buyerH, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': p2['id'],
      'quantity': 1,
      'price_total': 6,
      'status': 'reserva_pendente',
      'payment_method': 'Seguro Fleaber',
      'shipping_method': 'hand',
    });
    final a = asMaps(decode(o1));
    final b = asMaps(decode(o2));
    if (a.isNotEmpty && b.isNotEmpty) {
      final bag = await edge(
        c.url,
        'create-payment-intent',
        {
          'buyer_id': c.buyerId,
          'bag_checkout': true,
          'shipping_method': 'hand',
          'amount': 50,
          'bag_lines': [
            {
              'order_id': a.first['id'],
              'line_total_cents': 1,
              'quantity': 9,
            },
            {
              'order_id': b.first['id'],
              'line_total_cents': 1,
              'quantity': 9,
            },
          ],
        },
        headers: c.buyerH,
      );
      rec(
        surface: 'BAG',
        attack: 'bag checkout underpay line_total 1c qty 9',
        identity: 'buyer',
        result: briefBody(bag),
      );
      final d = decode(bag);
      if (d is Map) {
        final amt = d['amount_total'] ?? d['server_amount_cents'];
        rec(
          surface: 'BAG',
          attack: 'bag server amount',
          identity: 'buyer',
          result: 'amount=$amt',
          evidence: {
            'server_amount_cents': d['server_amount_cents'],
            'amount_total': d['amount_total'],
          },
        );
        final n = amt is num ? amt.toInt() : int.tryParse('$amt') ?? 0;
        // 5+6=11€ + protection, should be >> 50c
        if (bag.statusCode == 200 && n > 0 && n < 1100) {
          finding(
            id: 'RT1837-P0-BAG-UNDERPAY',
            severity: 'P0',
            title: 'Bag checkout cobra abaixo da soma dos contratos',
            actor: 'buyer',
            pre: 'duas orders',
            repro: 'create-payment-intent bag_checkout amount=50',
            impact: 'pagar menos',
            evidence: d,
          );
        }
      }
    }
  } catch (e) {
    rec(surface: 'BAG', attack: 'bag fixture', identity: 'svc', result: '$e');
  }

  final w1 = await rest(
    c.url,
    'GET',
    'wallets?id=in.(${c.buyerId},${c.sellerId})&select=id,balance',
    headers: c.svcH,
  );
  rec(
    surface: 'WALLET',
    attack: 'balances after pass4',
    identity: 'svc_observe',
    result: briefBody(w1),
    evidence: decode(w1),
  );

  await dumpJson('pass4', {
    'pass': 4,
    'project': projectMust,
    'utc': DateTime.now().toUtc().toIso8601String(),
    'matrix': matrix,
    'findings': findings,
    'gaps': gaps,
    'invariants': invariants,
  });
  stdout.writeln(
    'PASS4 done matrix=${matrix.length} findings=${findings.length}',
  );
}
