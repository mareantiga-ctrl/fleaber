/// PASS 4 — I4 webhook Transfer replay · I2 GET sem JWT · I7 fecho livros.
import 'dart:io';
import '_rti.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rti.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{'pass': 4, 'prefix': prefix};
  final wStart = await c.wallets();
  out['wallets_start'] = wStart;

  // I4: webhook sem assinatura — transfer.created / payout.paid / charge.refunded
  final fakeEvents = <Map<String, Object?>>[
    {
      'id': 'evt_rti_transfer',
      'object': 'event',
      'type': 'transfer.created',
      'data': {
        'object': {
          'id': 'tr_rti_fake',
          'object': 'transfer',
          'amount': 50000,
          'currency': 'eur',
          'destination': 'acct_fake',
          'metadata': {'fleaber_user_id': c.buyerId, 'type': 'wallet_withdrawal'},
        },
      },
    },
    {
      'id': 'evt_rti_payout',
      'object': 'event',
      'type': 'payout.paid',
      'data': {
        'object': {
          'id': 'po_rti_fake',
          'amount': 50000,
          'currency': 'eur',
        },
      },
    },
    {
      'id': 'evt_rti_refund',
      'object': 'event',
      'type': 'charge.refunded',
      'data': {
        'object': {
          'id': 'ch_rti_fake',
          'refunded': true,
          'metadata': {'fleaber_order_id': '00000000-0000-0000-0000-000000000099'},
        },
      },
    },
  ];
  final hookHits = <String, Object?>{};
  for (final ev in fakeEvents) {
    final h = await c.req(
      'POST',
      '/functions/v1/stripe-webhook',
      body: ev,
      extra: {'stripe-signature': 't=1,v1=deadbeef'},
    );
    hookHits['${ev['type']}'] = h.brief;
    c.note('p4.i4.hook', 'webhook ${ev['type']}', h.brief, lens: 'I4');
  }
  out['webhooks'] = hookHits;
  final wAfterHook = await c.wallets();
  if ((wAfterHook['buyer']! - wStart['buyer']!).abs() > 0.05 ||
      (wAfterHook['seller']! - wStart['seller']!).abs() > 0.05) {
    c.hold(
      id: 'RTI-I4-003',
      lens: 'I4',
      severity: 'P0',
      title: 'Webhook Stripe forjado alterou carteiras',
      actor: 'unauth POST stripe-webhook',
      pre: 'signature morta',
      repro: 'POST transfer.created / payout.paid / charge.refunded',
      expected: '400 invalid_signature, Δwallet=0',
      obtained: {'start': wStart, 'after': wAfterHook, 'hits': hookHits},
    );
  }

  final hookNoSig = await c.req(
    'POST',
    '/functions/v1/stripe-webhook',
    body: fakeEvents.first,
  );
  c.note('p4.i4.nosig', 'webhook sem stripe-signature', hookNoSig.brief,
      lens: 'I4');

  // I2: GET Connect sem JWT
  final getAnon = await c.req(
    'GET',
    '/functions/v1/create-connect-account?web_return_origin=${Uri.encodeQueryComponent('https://evil.com')}',
  );
  c.note('p4.i2.get_anon_evil', 'GET Connect anon evil origin', {
    'status': getAnon.status,
    'location': getAnon.location,
    'body': clip(getAnon.body, 100),
  }, lens: 'I2');
  final loc = (getAnon.location ?? '').toLowerCase();
  if (getAnon.status >= 300 && loc.contains('evil')) {
    c.hold(
      id: 'RTI-I2-006',
      lens: 'I2',
      severity: 'P1',
      title: 'GET Connect anónimo redirecciona para evil.com',
      actor: 'anon',
      pre: 'sem JWT',
      repro: 'GET create-connect-account?web_return_origin=https://evil.com',
      expected: 'HTML wallet ou 303 só fleaber',
      obtained: getAnon.location,
    );
  }

  // I1: Edge payout com JWT do buyer contra conta Connect do seller (amount no body)
  final stealPay = await c.edge(
    'create-connect-account',
    {
      'user_id': c.sellerId,
      'amount': 100,
      'idempotency_key': '${prefix}_steal_pay',
    },
    jwt: c.buyerJwt,
  );
  c.note('p4.i1.steal_pay', 'buyer payout user_id seller', stealPay.brief,
      lens: 'I1');

  // I1: seller2 tenta payout (conta nova, amount do saldo de seller1 — não tem)
  final s2pay = await c.edge(
    'create-connect-account',
    {
      'amount': 100,
      'idempotency_key': '${prefix}_s2_pay',
    },
    jwt: c.seller2Jwt,
  );
  c.note('p4.i1.s2_payout', 'seller2 payout 100¢', s2pay.brief, lens: 'I1');
  if (s2pay.ok && s2pay.map?['success'] == true) {
    final s2w = await c.walletRow(c.seller2Id);
    c.hold(
      id: 'RTI-I1-008',
      lens: 'I1',
      severity: 'P1',
      title: 'seller2 levantou 100¢ sem saldo libertado neste ciclo',
      actor: 'seller2 JWT',
      pre: 'conta nova',
      repro: 'POST create-connect-account amount=100',
      expected: 'insufficient ou Connect not ready',
      obtained: {'edge': s2pay.brief, 'wallet': s2w},
    );
  }

  // I7: um fluxo pago curto só para fechar livros se pass3 não libertou
  final oid = await c.payAndComplete(lens: 'I7');
  Map<String, dynamic>? lastOrder;
  if (oid != null) {
    await c.tryRelease(oid, jwt: c.buyerJwt);
    await c.tryRelease(oid, service: true);
    lastOrder = await c.orderRow(oid);
    final tx = await c.walletTxns(orderId: oid);
    out['i7_order'] = lastOrder;
    out['i7_txns'] = tx;
    c.note('p4.i7.close', 'order+txns', {
      'status': lastOrder?['status'],
      'release': lastOrder?['wallet_release_processed_at'],
      'refund': lastOrder?['wallet_refund_processed_at'],
      'pi': lastOrder?['stripe_payment_intent_id'],
      'txn_n': tx.length,
    }, lens: 'I7');
  }

  // Finish JWT on a real ledger key if any
  final led = await c.payoutLedger(userId: c.sellerId, limit: 5);
  out['ledger_tail'] = led;
  if (led.isNotEmpty && led.first is Map) {
    final key = (led.first as Map)['idempotency_key'];
    final fin = await c.rpc(
      'batata_wallet_payout_finish',
      {
        'p_idempotency_key': key,
        'p_stripe_transfer_id': 'tr_rti_hostile_finish',
        'p_failed': true,
      },
      jwt: c.buyerJwt,
    );
    c.note('p4.i1.finish_existing', 'JWT finish failed em ledger real', fin.brief,
        lens: 'I1');
    if (fin.ok && fin.map?['ok'] == true) {
      c.hold(
        id: 'RTI-I1-009',
        lens: 'I1',
        severity: 'P0',
        title: 'JWT marcou payout_finish failed (poderia re-creditar)',
        actor: 'buyer JWT',
        pre: 'ledger existente $key',
        repro: 'rpc batata_wallet_payout_finish p_failed=true',
        expected: '403',
        obtained: fin.brief,
      );
    }
  }

  out['wallets_end'] = await c.wallets();
  out['findings'] = c.findings;
  out['notes'] = c.notes;
  await dumpJson('tool/redteam_blind_i_20260831T1706/pass4.json', out);
  stdout.writeln('PASS4 findings=${c.findings.length}');
  stdout.writeln('DONE prefix=$prefix production_touched=false');
}
