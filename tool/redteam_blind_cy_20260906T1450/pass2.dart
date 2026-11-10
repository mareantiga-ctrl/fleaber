/// RED TEAM CEGO CY pass2 — CY-B tip residual (≥3).
import 'dart:convert';
import 'dart:io';
import '_rtcy.dart';

Future<void> main() async {
  final c = Rtcy.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final s1 = ids['s1'] as String;
  final s2 = ids['s2'] as String;
  final airPub = ids['airPub'] as String;
  var airUnpub = ids['airUnpub'] as String;

  await c.restoreSeller1Published();

  // S2 published + broadcasting for Session, then unpublish (não mexer S1).
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'hub_published': true,
    'is_live': true,
    'user_type': 'vendedor',
  }, prefer: 'return=minimal');
  await c.rest('PATCH', 'lives?id=eq.$airUnpub', service: true, body: {
    'status': 'live',
    'is_active': true,
  }, prefer: 'return=minimal');

  final balBefore = await c.walletBal(s2);

  // ----- B1 Session published → unpublish → GET return -----
  final b1create = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': airUnpub,
      'seller_id': s2,
      'amount_eur': 2,
    },
  );
  c.note('b1.create', 'tip session S2 published', b1create, lens: 'CY3');
  String? tipId = b1create.map?['tipId']?.toString() ??
      b1create.map?['tip_id']?.toString();
  String? sessionId = b1create.map?['checkoutSessionId']?.toString() ??
      b1create.map?['sessionId']?.toString() ??
      b1create.map?['checkout_session_id']?.toString();
  if (tipId != null) c.createdTipIds.add(tipId);

  await c.setHub(s2, false);
  final s2after = await c.profile(s2);

  HttpHit? getAfterUnpub;
  HttpHit? payHit;
  HttpHit? getAfterPay;
  var paid = false;
  var credited = false;
  var tipStatus = '';

  if (sessionId != null && sessionId.isNotEmpty) {
    getAfterUnpub = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: 'checkout_return=success&session_id=$sessionId',
    );

    if (c.stripeTestKey != null) {
      final sess = await c.stripe('GET', '/v1/checkout/sessions/$sessionId');
      c.note('b1.stripe.session', 'retrieve session', sess, lens: 'CY3');
      final pi = sess.map?['payment_intent']?.toString();
      if (pi != null && pi.startsWith('pi_')) {
        payHit = await c.stripe(
          'POST',
          '/v1/payment_intents/$pi/confirm',
          fields: {'payment_method': 'pm_card_visa'},
        );
        final st = '${payHit.map?['status'] ?? ''}';
        paid = st == 'succeeded' ||
            '${sess.map?['payment_status']}' == 'paid';
      }
    }

    getAfterPay = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: 'checkout_return=success&session_id=$sessionId',
    );

    final tipRow = await c.rest(
      'GET',
      'live_tips?id=eq.$tipId&select=id,status,amount,buyer_id,seller_id',
      service: true,
    );
    tipStatus = '${tipRow.map?['status'] ?? ''}';
    final balAfter = await c.walletBal(s2);
    credited = tipStatus == 'paid' ||
        tipStatus == 'settled' ||
        (balAfter - balBefore) > 0;
  }

  final sessionOk = b1create.ok && sessionId != null;
  final unpaidCredit = credited && !paid;
  final paidOnUnpub = paid && credited;
  final gotPaidCopy = (getAfterUnpub?.body.toLowerCase().contains('pagamento recebido') ??
          false) ||
      (getAfterPay?.body.toLowerCase().contains('pagamento recebido') ?? false);
  final b1result = !sessionOk
      ? 'SKIP'
      : (unpaidCredit || paidOnUnpub || (gotPaidCopy && !paid) ? 'FAIL' : 'HOLD');

  c.probe(
    id: 'B1',
    poco: 'CY-B',
    payload:
        'tip Session S2 published → unpublish → GET return' +
        (c.stripeTestKey != null ? ' + confirm PI TEST' : ' (sem sk_test local)'),
    http: {
      'create': b1create.brief,
      'getUnpaid': getAfterUnpub?.brief,
      'pay': payHit?.brief,
      'getAfterPay': getAfterPay?.brief,
    },
    bd: {
      'tipStatus': tipStatus,
      'credited': credited,
      'paidStripe': paid,
      'hub_after': s2after?['hub_published'],
      'has_sk_test': c.stripeTestKey != null,
    },
    result: b1result,
    lens: 'CY3',
    countFinding: b1result == 'FAIL',
  );
  if (unpaidCredit || (gotPaidCopy && !paid)) {
    c.hold(
      id: 'CY-B1-TIP-UNPAID-CREDIT-MIDUNPUB',
      lens: 'CY3',
      severity: 'P0',
      title: 'GET settle após unpublish creditou gorjeta não paga',
      actor: 'B2',
      pre: 'Session criada published; depois hub_published=false',
      repro: 'GET create-live-tip-checkout?checkout_return=success',
      expected: 'pending; Δwallet=0',
      obtained: {'status': tipStatus, 'get': getAfterUnpub?.brief},
    );
  } else if (paidOnUnpub) {
    c.hold(
      id: 'CY-B1-TIP-PAY-AFTER-UNPUB',
      lens: 'CY3',
      severity: 'P2',
      title: 'pago TEST após unpublish a meio ainda settle/credita',
      actor: 'B2',
      pre: 'Session open → unpublish → confirm PI',
      repro: 'Stripe confirm + GET return',
      expected: 'settle recusado (loja desligada)',
      obtained: {'pay': payHit?.brief, 'status': tipStatus},
    );
  } else if (!sessionOk) {
    c.skip('B1', 'CY3', 'não criou Session com S2 published', b1create);
  }

  // ----- B2 tip_id / amount hostil -----
  await c.restoreSeller1Published();
  await c.rest('PATCH', 'lives?id=eq.$airPub', service: true, body: {
    'status': 'live',
    'is_active': true,
  }, prefer: 'return=minimal');

  final amounts = <num>[0, 0.01, -1, 0.5, 501];
  final amtHits = <String, String>{};
  final amtAccepted = <num>[];
  for (final amt in amounts) {
    final t = await c.edge(
      'create-live-tip-checkout',
      jwt: c.buyer2Jwt,
      body: {
        'live_id': airPub,
        'seller_id': s1,
        'amount_eur': amt,
      },
    );
    amtHits['$amt'] = t.brief;
    if (t.ok) amtAccepted.add(amt);
  }
  final tipIdBody = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': airPub,
      'seller_id': s1,
      'amount_eur': 2,
      'tip_id': '00000000-0000-4000-a000-0000000000bb',
    },
  );
  final wrongSeller = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': airPub,
      'seller_id': s2,
      'amount_eur': 2,
    },
  );
  final b2fail = amtAccepted.isNotEmpty || tipIdBody.ok;
  c.probe(
    id: 'B2',
    poco: 'CY-B',
    payload: 'amount 0/0.01/-1/0.5/501 + tip_id cliente + seller≠owner live',
    http: {
      'amounts': amtHits,
      'tip_id': tipIdBody.brief,
      'wrongSeller': wrongSeller.brief,
    },
    result: b2fail ? 'FAIL' : 'HOLD',
    lens: 'CY3',
    countFinding: b2fail,
  );
  if (amtAccepted.isNotEmpty) {
    c.hold(
      id: 'CY-B2-TIP-AMOUNT',
      lens: 'CY3',
      severity: amtAccepted.any((a) => a >= 501) ? 'P2' : 'P1',
      title: 'tip aceita amount hostil $amtAccepted',
      actor: 'B2',
      pre: 'teto 1–500 EUR',
      repro: 'POST create-live-tip-checkout amount_eur hostil',
      expected: '400',
      obtained: amtHits,
    );
  }
  if (tipIdBody.ok) {
    c.hold(
      id: 'CY-B2-TIP-ID-CLIENT',
      lens: 'CY3',
      severity: 'P1',
      title: 'tip_id do cliente aceite',
      actor: 'B2',
      pre: 'body.tip_id UUID',
      repro: 'POST create-live-tip-checkout tip_id=',
      expected: '400 Client tip_id is not allowed',
      obtained: tipIdBody.brief,
    );
  }

  // ----- B3 settle unpaid GET -----
  final b3create = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': airPub,
      'seller_id': s1,
      'amount_eur': 2,
    },
  );
  String? tip3 = b3create.map?['tipId']?.toString() ??
      b3create.map?['tip_id']?.toString();
  String? sess3 = b3create.map?['checkoutSessionId']?.toString() ??
      b3create.map?['sessionId']?.toString();
  if (tip3 != null) c.createdTipIds.add(tip3);
  HttpHit? b3b2;
  HttpHit? b3anon;
  HttpHit? b3rpc;
  var st3 = '';
  var delta3 = 0.0;
  final balS1 = await c.walletBal(s1);
  if (sess3 != null && sess3.isNotEmpty) {
    b3b2 = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: 'checkout_return=success&session_id=$sess3',
    );
    b3anon = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: 'checkout_return=success&session_id=$sess3',
    );
    b3rpc = await c.rpc(
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tip3,
        'p_stripe_session_id': sess3,
        'p_paid_amount_cents': 200,
      },
      jwt: c.buyer2Jwt,
    );
    final row = await c.rest(
      'GET',
      'live_tips?id=eq.$tip3&select=id,status,amount',
      service: true,
    );
    st3 = '${row.map?['status'] ?? ''}';
    final balAfter = await c.walletBal(s1);
    delta3 = (balAfter - balS1).toDouble();
  }
  final paidCopy =
      (b3b2?.body.toLowerCase().contains('pagamento recebido') ?? false) ||
          (b3anon?.body.toLowerCase().contains('pagamento recebido') ?? false);
  final rpcSettled = b3rpc != null &&
      (b3rpc.ok &&
          (b3rpc.map?['ok'] == true ||
              '${b3rpc.body}'.toLowerCase().contains('true')));
  final b3fail = paidCopy || st3 == 'paid' || st3 == 'settled' || delta3 > 0 || rpcSettled;
  c.probe(
    id: 'B3',
    poco: 'CY-B',
    payload: 'GET settle unpaid B2/anon + RPC settle JWT (Session não paga)',
    http: {
      'create': b3create.brief,
      'getB2': b3b2?.brief,
      'getAnon': b3anon?.brief,
      'rpc': b3rpc?.brief,
    },
    bd: {'status': st3, 'deltaWallet': delta3},
    result: !b3create.ok
        ? 'SKIP'
        : (b3fail ? 'FAIL' : 'HOLD'),
    lens: 'CY3',
    countFinding: b3fail,
  );
  if (b3fail) {
    c.hold(
      id: 'CY-B3-SETTLE-UNPAID',
      lens: 'CY3',
      severity: 'P0',
      title: 'settle unpaid GET/RPC creditou gorjeta',
      actor: 'B2',
      pre: 'Session pending não paga',
      repro: 'GET checkout_return=success e/ou RPC batata_settle_live_tip_from_stripe',
      expected: 'pending; Δ=0',
      obtained: {
        'status': st3,
        'delta': delta3,
        'get': b3b2?.brief,
        'rpc': b3rpc?.brief,
      },
    );
  }

  await c.setHub(s2, false);
  await c.restoreSeller1Published();
  await dumpJson('${outDir()}/pass2.json', {
    'probes': c.probes,
    'findings': c.findings,
    'notes': c.notes,
    'skipped': c.skipped,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln('PASS2 done probes=${c.probes.length} findings=${c.findings.length}');
}
