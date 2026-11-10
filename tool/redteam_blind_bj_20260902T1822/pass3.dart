/// PASS 3 — BJ4 webhook Transfer replay · BJ7 composição caixa · race NFC∥NFD.
import 'dart:convert';
import 'dart:io';
import '_rtbj.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtbj.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();

  final w0 = await c.wallets();
  c.note('p3.start', 'saldos', w0, lens: 'BJ7');

  // Unsigned Transfer webhook
  final fakeEvt = jsonEncode({
    'id': 'evt_bj_replay',
    'object': 'event',
    'type': 'transfer.created',
    'data': {
      'object': {
        'id': 'tr_bj_fake',
        'object': 'transfer',
        'amount': 5000,
        'currency': 'eur',
        'destination': 'acct_fake',
        'metadata': {
          'fleaber_user_id': c.sellerId,
          'type': 'wallet_withdrawal',
        },
      },
    },
  });
  final noSig = await c.req(
    'POST',
    '/functions/v1/stripe-webhook',
    body: fakeEvt,
    extra: {'Content-Type': 'application/json'},
  );
  c.note('p3.wh.nosig', 'transfer.created sem assinatura', noSig.brief,
      lens: 'BJ4');
  if (noSig.ok && noSig.map?['ok'] == true && noSig.map?['ignored'] == null) {
    c.hold(
      id: 'BJ4-05-webhook-nosig',
      lens: 'BJ4',
      severity: 'P0',
      title: 'Webhook Stripe aceitou transfer.created sem assinatura',
      actor: 'anon POST',
      pre: 'constructEventAsync exige stripe-signature',
      repro: 'POST stripe-webhook type=transfer.created sem signature',
      expected: '400 invalid_signature',
      obtained: noSig.brief,
    );
  } else {
    c.block('BJ4-05-webhook-nosig', 'BJ4', 'webhook sem signature', noSig);
  }

  final fakeSig = await c.req(
    'POST',
    '/functions/v1/stripe-webhook',
    body: fakeEvt,
    extra: {
      'Content-Type': 'application/json',
      'stripe-signature':
          't=1710000000,v1=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
    },
  );
  c.note('p3.wh.fakesig', 'transfer.created signature forjada', fakeSig.brief,
      lens: 'BJ4');
  if (fakeSig.ok && fakeSig.map?['ok'] == true) {
    c.hold(
      id: 'BJ4-06-webhook-fakesig',
      lens: 'BJ4',
      severity: 'P0',
      title: 'Webhook aceitou assinatura Stripe forjada',
      actor: 'anon',
      pre: 'HMAC whsec',
      repro: 'POST stripe-signature=v1=deadbeef',
      expected: '400',
      obtained: fakeSig.brief,
    );
  } else {
    c.block('BJ4-06-webhook-fakesig', 'BJ4', 'fake signature', fakeSig);
  }

  final getWh = await c.edge('stripe-webhook', method: 'GET');
  c.note('p3.wh.get', 'GET stripe-webhook', getWh.brief, lens: 'BJ4');
  if (getWh.ok && getWh.map?['ok'] == true) {
    c.hold(
      id: 'BJ4-07-webhook-get',
      lens: 'BJ4',
      severity: 'P2',
      title: 'GET stripe-webhook trata evento',
      actor: 'anon GET',
      pre: 'só POST',
      repro: 'GET /functions/v1/stripe-webhook',
      expected: '405',
      obtained: getWh.brief,
    );
  } else {
    c.block('BJ4-07-webhook-get', 'BJ4', 'GET webhook', getWh);
  }

  // Finalize refund JWT
  final finJwt = await c.rpc('batata_finalize_stripe_order_refund', {
    'p_order_id': '00000000-0000-0000-0000-000000000001',
    'p_refund_id': 're_bj_fake',
    'p_amount_cents': 99999,
  }, jwt: c.sellerJwt);
  await c.expectDenied(
    id: 'BJ3-06-jwt-finalize-refund',
    lens: 'BJ3',
    title: 'JWT finalize_stripe_order_refund',
    hit: finJwt,
    actor: 'seller JWT',
    pre: 'GRANT service_role',
    repro: 'rpc batata_finalize_stripe_order_refund amount=99999',
    severityIfOpen: 'P0',
    isSuccess: (h) => h.ok && h.map?['ok'] == true,
  );

  // INSERT wallet_transactions JWT
  final mintTx = await c.rest('POST', 'wallet_transactions', jwt: c.sellerJwt, body: {
    'wallet_id': c.sellerId,
    'amount': 50,
    'type': 'venda',
    'description': '$prefix mint',
  });
  await c.expectDenied(
    id: 'BJ7-01-jwt-insert-txn',
    lens: 'BJ7',
    title: 'Seller INSERT wallet_transactions mint',
    hit: mintTx,
    actor: 'seller JWT',
    pre: 'RLS sem INSERT authenticated',
    repro: 'POST wallet_transactions amount=50 type=venda',
    severityIfOpen: 'P0',
  );

  // Race NFC∥NFD em paralelo (se pass1 sequencial não duplicou por Connect down)
  const nfc = 'race-caf\u00e9-bj22yy';
  const nfd = 'race-cafe\u0301-bj22yy';
  if (nfc != nfd) {
    final bal = await c.walletBal(c.sellerId);
    if (bal < 3) await c.fixtureCreditSeller(5);
    final pair = await Future.wait([
      c.connect({'amount': 100, 'idempotency_key': nfc}),
      c.connect({'amount': 100, 'idempotency_key': nfd}),
    ]);
    c.note('p3.nfc.race.a', 'NFC∥', pair[0].brief, lens: 'BJ4');
    c.note('p3.nfc.race.b', 'NFD∥', pair[1].brief, lens: 'BJ4');
    final ts = pair
        .map((h) => h.transferId)
        .where((t) => t != null && t.startsWith('tr_'))
        .toSet();
    if (ts.length > 1) {
      c.hold(
        id: 'BJ4-08-nfc-nfd-race',
        lens: 'BJ4',
        severity: 'P0',
        title: 'Race NFC∥NFD criou duas Transfers',
        actor: 'seller JWT ×2',
        pre: 'keys visualmente iguais, hashes distintos',
        repro: 'Future.wait POST NFC e NFD amount=100',
        expected: '≤1 Transfer',
        obtained: pair.map((h) => h.brief).toList(),
      );
    } else {
      c.block('BJ4-08-nfc-nfd-race', 'BJ4', 'race NFC/NFD', ts);
    }
  }

  // refund-order crash_inject
  if (c.crashSecret.length >= 16) {
    final oid = await c.payOrder(lens: 'BJ3');
    if (oid != null) {
      final crashRef = await c.refundOrder(oid, extraBody: {
        'crash_inject': 'after_stripe_before_db',
      }, extra: {
        'x-fleaber-crash-inject-secret': c.crashSecret,
      });
      c.note('p3.refund.crash', 'refund crash after_stripe_before_db',
          crashRef.brief, lens: 'BJ3');
      final rowCrash = await c.orderRow(oid);
      c.note('p3.refund.crash.row', 'order após crash inject', rowCrash,
          lens: 'BJ3');
      final retry = await c.refundOrder(oid);
      c.note('p3.refund.retry', 'retry refund-order', retry.brief, lens: 'BJ3');
      final listed = await c.e2e('list_stripe_refunds', {
        'payment_intent_id': rowCrash?['stripe_payment_intent_id'],
      });
      c.note('p3.refund.list', 'list_stripe_refunds', listed.brief, lens: 'BJ3');
      final n = numOf(listed.map?['refund_count'])?.round() ??
          ((listed.map?['refunds'] is List)
              ? (listed.map!['refunds'] as List).length
              : 0);
      if (n > 1) {
        c.hold(
          id: 'BJ3-07-crash-refund-dup',
          lens: 'BJ3',
          severity: 'P0',
          title: 'crash refund + retry criou 2 refunds Stripe',
          actor: 'seller JWT + crash_inject',
          pre: 'idempotency fleaber_order_refund_{orderId}',
          repro: 'POST refund-order crash after_stripe_before_db; retry',
          expected: '1 refund Stripe',
          obtained: {
            'crash': crashRef.brief,
            'retry': retry.brief,
            'n': n,
            'list': listed.brief,
          },
        );
      } else {
        c.block('BJ3-07-crash-refund-dup', 'BJ3', 'refund crash retry', {
          'n': n,
          'retry': retry.brief,
        });
      }

      // Release após refund (não deve mint)
      final sellerB = await c.walletBal(c.sellerId);
      await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
        'status': 'enviado',
      });
      await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
        'status': 'concluido',
      });
      final rel = await c.tryRelease(oid, jwt: c.buyerJwt);
      final relSvc = rel.ok && rel.json == true
          ? rel
          : await c.tryRelease(oid, service: true);
      final sellerA = await c.walletBal(c.sellerId);
      c.note('p3.release.after_refund', 'release após refund', {
        'rel': rel.brief,
        'relSvc': relSvc.brief,
        'delta': sellerA - sellerB,
      }, lens: 'BJ3');
      if ((relSvc.ok && relSvc.json == true) && (sellerA - sellerB) > 0.05) {
        c.hold(
          id: 'BJ3-08-release-after-refund-mint',
          lens: 'BJ3',
          severity: 'P0',
          title: 'Release após refund creditou seller',
          actor: 'buyer/service release',
          pre: 'stripe_refund_id deve bloquear crédito',
          repro: 'refund-order → enviado → concluido → release',
          expected: 'release false / Δ=0',
          obtained: {
            'delta': sellerA - sellerB,
            'rel': relSvc.brief,
          },
        );
      } else {
        c.block('BJ3-08-release-after-refund-mint', 'BJ3',
            'release pós-refund', {
          'delta': sellerA - sellerB,
          'rel': relSvc.brief,
        });
      }
    }
  }

  final w1 = await c.wallets();
  c.note('p3.end', 'saldos', w1, lens: 'BJ7');
  await c.dumpAll('pass3.json');
  stdout.writeln('PASS3 findings=${c.findings.length} blocked=${c.blocked.length}');
}
