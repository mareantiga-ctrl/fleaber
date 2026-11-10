/// RED TEAM CEGO CM pass2 — CM-B tip mid-unpublish / settle (≥4).
import 'dart:convert';
import 'dart:io';
import '_rtcm.dart';

Future<void> main() async {
  final c = Rtcm.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final s1 = ids['s1'] as String;
  final s2 = ids['s2'] as String;
  var airUnpub = ids['airUnpub'] as String;
  final airPub = ids['airPub'] as String;

  // S2 starts unpublished from pass1. For B1 we need published → session → unpublish.
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'hub_published': true,
    'is_live': true,
  }, prefer: 'return=minimal');
  await c.rest('PATCH', 'lives?id=eq.$airUnpub', service: true, body: {
    'status': 'live',
    'is_active': true,
  }, prefer: 'return=minimal');

  final balBefore = await c.walletBal(s2);

  // ----- B1 Session tip published → unpublish → pay/return -----
  final b1create = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': airUnpub,
      'seller_id': s2,
      'amount_eur': 2,
    },
  );
  c.note('b1.create', 'tip session while S2 published', b1create, lens: 'CM3');
  String? tipId = b1create.map?['tipId']?.toString() ??
      b1create.map?['tip_id']?.toString();
  String? sessionId = b1create.map?['checkoutSessionId']?.toString() ??
      b1create.map?['sessionId']?.toString() ??
      b1create.map?['checkout_session_id']?.toString();
  if (tipId != null) c.createdTipIds.add(tipId);

  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'hub_published': false,
  }, prefer: 'return=minimal');
  final s2after = await c.profile(s2);

  HttpHit? getAfterUnpub;
  HttpHit? payHit;
  HttpHit? getAfterPay;
  var paid = false;
  var credited = false;
  String tipStatus = '';

  if (sessionId != null && sessionId.isNotEmpty) {
    getAfterUnpub = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: 'checkout_return=success&session_id=$sessionId',
    );

    if (c.stripeTestKey != null) {
      final sess = await c.stripe('GET', '/v1/checkout/sessions/$sessionId');
      c.note('b1.stripe.session', 'retrieve session', sess, lens: 'CM3');
      final pi = sess.map?['payment_intent']?.toString();
      if (pi != null && pi.startsWith('pi_')) {
        payHit = await c.stripe(
          'POST',
          '/v1/payment_intents/$pi/confirm',
          fields: {'payment_method': 'pm_card_visa'},
        );
        c.note('b1.stripe.confirm', 'confirm PI 4242', payHit, lens: 'CM3');
        final st = '${payHit.map?['status'] ?? ''}';
        paid = st == 'succeeded' ||
            '${sess.map?['payment_status']}' == 'paid' ||
            payHit.ok && st.contains('succeed');
        if (!paid && payHit.ok) {
          final again = await c.stripe('GET', '/v1/checkout/sessions/$sessionId');
          paid = '${again.map?['payment_status']}' == 'paid';
          c.note('b1.stripe.session2', 'session after confirm', again,
              lens: 'CM3');
        }
      } else {
        payHit = sess;
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
      'live_tips?id=eq.$tipId&select=id,status,amount,buyer_id,seller_id,stripe_session_id',
      service: true,
    );
    tipStatus = '${tipRow.map?['status'] ?? ''}';
    final balAfter = await c.walletBal(s2);
    credited = tipStatus == 'paid' ||
        tipStatus == 'settled' ||
        (balAfter - balBefore) > 0;
    c.note('b1.tip.row', 'tip after mid-unpub', {
      'status': tipStatus,
      'delta': balAfter - balBefore,
      'paidStripe': paid,
    }, lens: 'CM3');
  }

  final b1sessionOk = b1create.ok && sessionId != null;
  final b1fail = credited ||
      (paid && (getAfterPay?.body.toLowerCase().contains('pagamento recebido') ??
          false));
  // Session created while published then unpublish: unpaid GET should stay pending.
  // FAIL if credit without pay, OR credit after pay on unpublished (policy: mid-unpub should block settle).
  final unpaidCredit = credited && !paid;
  final paidOnUnpub = paid && credited;
  final b1result = !b1sessionOk
      ? 'SKIP'
      : (unpaidCredit || paidOnUnpub ? 'FAIL' : 'HOLD');

  c.probe(
    id: 'B1',
    poco: 'CM-B',
    payload:
        'tip Session S2 published → unpublish → GET return' +
        (c.stripeTestKey != null ? ' + confirm PI TEST' : ' (sem sk_test)'),
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
    },
    result: b1result,
    lens: 'CM3',
    countFinding: b1result == 'FAIL',
  );
  if (unpaidCredit) {
    c.hold(
      id: 'CM-B1-TIP-UNPAID-CREDIT-MIDUNPUB',
      lens: 'CM3',
      severity: 'P0',
      title: 'GET settle após unpublish creditou gorjeta não paga',
      actor: 'B2',
      pre: 'Session criada published; depois hub_published=false; Session não paga',
      repro: 'GET create-live-tip-checkout?checkout_return=success',
      expected: 'pending; Δwallet=0',
      obtained: {'status': tipStatus, 'get': getAfterUnpub?.brief},
    );
  } else if (paidOnUnpub) {
    c.hold(
      id: 'CM-B1-TIP-PAY-AFTER-UNPUB',
      lens: 'CM3',
      severity: 'P2',
      title: 'pago TEST após unpublish a meio ainda settle/credita',
      actor: 'B2',
      pre: 'Session open → unpublish → confirm PI',
      repro: 'Stripe confirm + GET return',
      expected: 'settle recusado (loja desligada) ou Session expirada',
      obtained: {
        'pay': payHit?.brief,
        'get': getAfterPay?.brief,
        'status': tipStatus,
      },
    );
  } else if (!b1sessionOk) {
    c.skip('B1', 'CM3', 'não criou Session com S2 published', b1create);
  }

  // ----- B2 tip bind live acaba unpublished -----
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'hub_published': true,
    'is_live': true,
  }, prefer: 'return=minimal');
  final liveB2 = await c.insertLive(
    seller: s2,
    active: true,
    status: 'live',
    muxPlayback: ids['pbAir']?.toString(),
    title: '$prefix b2-bind',
  );
  final b2create = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': liveB2,
      'seller_id': s2,
      'amount_eur': 2,
    },
  );
  String? tip2 = b2create.map?['tipId']?.toString() ??
      b2create.map?['tip_id']?.toString();
  String? sess2 = b2create.map?['checkoutSessionId']?.toString() ??
      b2create.map?['sessionId']?.toString();
  if (tip2 != null) c.createdTipIds.add(tip2);

  await c.rest('PATCH', 'lives?id=eq.$liveB2', service: true, body: {
    'status': 'ended',
    'is_active': false,
  }, prefer: 'return=minimal');
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'hub_published': false,
  }, prefer: 'return=minimal');

  HttpHit? b2get;
  if (sess2 != null && sess2.isNotEmpty) {
    b2get = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: 'checkout_return=success&session_id=$sess2',
    );
  }
  final tip2row = tip2 == null
      ? null
      : await c.rest(
          'GET',
          'live_tips?id=eq.$tip2&select=id,status,amount,live_id',
          service: true,
        );
  final st2 = '${tip2row?.map?['status'] ?? ''}';
  final b2credit = st2 == 'paid' || st2 == 'settled';
  c.probe(
    id: 'B2',
    poco: 'CM-B',
    payload: 'tip bind live published → end+unpublish → GET settle unpaid',
    http: {'create': b2create.brief, 'get': b2get?.brief},
    bd: {'status': st2, 'live': liveB2},
    result: !b2create.ok
        ? 'SKIP'
        : (b2credit ? 'FAIL' : 'HOLD'),
    lens: 'CM3',
  );
  if (b2credit) {
    c.hold(
      id: 'CM-B2-TIP-BIND-ENDED-UNPUB',
      lens: 'CM3',
      severity: 'P0',
      title: 'settle unpaid após live ended+unpublished creditou',
      actor: 'B2',
      pre: liveB2 ?? '',
      repro: 'GET return após end+unpublish',
      expected: 'pending',
      obtained: {'get': b2get?.brief, 'status': st2},
    );
  }

  // ----- B3 tip_id cliente / amount hostil -----
  await c.rest('PATCH', 'profiles?id=eq.$s1', service: true, body: {
    'hub_published': true,
  }, prefer: 'return=minimal');
  final amounts = <num>[0, 0.01, -1, 0.5, 501];
  final amtHits = <String, String>{};
  var amtAccepted = <num>[];
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
  final b3fail = amtAccepted.isNotEmpty || tipIdBody.ok;
  c.probe(
    id: 'B3',
    poco: 'CM-B',
    payload: 'amount 0/0.01/-1/0.5/501 + tip_id cliente + seller≠owner',
    http: {
      'amounts': amtHits,
      'tip_id': tipIdBody.brief,
      'wrongSeller': wrongSeller.brief,
    },
    result: b3fail ? 'FAIL' : 'HOLD',
    lens: 'CM3',
  );
  if (amtAccepted.isNotEmpty) {
    c.hold(
      id: 'CM-B3-TIP-AMOUNT',
      lens: 'CM3',
      severity: amtAccepted.any((a) => a >= 501) ? 'P2' : 'P1',
      title: 'tip aceita amount hostil $amtAccepted',
      actor: 'B2',
      pre: 'teto 1–500',
      repro: 'POST create-live-tip-checkout amount_eur hostil',
      expected: '400',
      obtained: amtHits,
    );
  }
  if (tipIdBody.ok) {
    c.hold(
      id: 'CM-B3-TIP-ID-CLIENT',
      lens: 'CM3',
      severity: 'P1',
      title: 'tip_id do cliente aceite',
      actor: 'B2',
      pre: 'body.tip_id UUID',
      repro: 'POST create-live-tip-checkout tip_id=',
      expected: '400 Client tip_id is not allowed',
      obtained: tipIdBody.brief,
    );
  }

  // ----- B4 settle unpaid GET -----
  final b4create = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': airPub,
      'seller_id': s1,
      'amount_eur': 2,
    },
  );
  String? tip4 = b4create.map?['tipId']?.toString() ??
      b4create.map?['tip_id']?.toString();
  String? sess4 = b4create.map?['checkoutSessionId']?.toString() ??
      b4create.map?['sessionId']?.toString();
  if (tip4 != null) c.createdTipIds.add(tip4);
  HttpHit? b4b2;
  HttpHit? b4anon;
  HttpHit? b4replay;
  HttpHit? b4rpc;
  var st4 = '';
  var delta4 = 0.0;
  final balS1 = await c.walletBal(s1);
  if (sess4 != null && sess4.isNotEmpty) {
    b4b2 = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: 'checkout_return=success&session_id=$sess4',
    );
    b4anon = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: 'checkout_return=success&session_id=$sess4',
    );
    b4replay = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: 'checkout_return=success&session_id=$sess4',
    );
    b4rpc = await c.rpc(
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tip4,
        'p_stripe_session_id': sess4,
        'p_paid_amount_cents': 200,
      },
      jwt: c.buyer2Jwt,
    );
    final row = await c.rest(
      'GET',
      'live_tips?id=eq.$tip4&select=id,status,amount',
      service: true,
    );
    st4 = '${row.map?['status'] ?? ''}';
    final balAfter = await c.walletBal(s1);
    delta4 = (balAfter - balS1).toDouble();
  }
  final b4paidCopy = (b4b2?.body.toLowerCase().contains('pagamento recebido') ??
          false) &&
      st4 != 'paid';
  final b4credit = st4 == 'paid' || st4 == 'settled' || delta4 > 0;
  final b4rpcOk = b4rpc?.ok == true && '${b4rpc?.body}' == 'true';
  c.probe(
    id: 'B4',
    poco: 'CM-B',
    payload: 'GET settle unpaid B2/anon/replay + RPC settle JWT',
    http: {
      'create': b4create.brief,
      'b2': b4b2?.brief,
      'anon': b4anon?.brief,
      'replay': b4replay?.brief,
      'rpc': b4rpc?.brief,
    },
    bd: {'status': st4, 'delta': delta4},
    result: !b4create.ok
        ? 'SKIP'
        : (b4credit || b4rpcOk || b4paidCopy ? 'FAIL' : 'HOLD'),
    lens: 'CM3',
  );
  if (b4credit || b4rpcOk) {
    c.hold(
      id: 'CM-B4-UNPAID-CREDIT',
      lens: 'CM3',
      severity: 'P0',
      title: 'settle unpaid creditou / RPC JWT settle',
      actor: 'B2',
      pre: sess4 ?? '',
      repro: 'GET return unpaid; RPC batata_settle_live_tip_from_stripe',
      expected: 'pending; RPC 403; «ainda não confirmado»',
      obtained: {
        'get': b4b2?.brief,
        'rpc': b4rpc?.brief,
        'status': st4,
        'delta': delta4,
      },
    );
  } else if (b4paidCopy) {
    c.hold(
      id: 'CM-B4-UNPAID-PAID-COPY',
      lens: 'CM3',
      severity: 'P2',
      title: 'GET return diz pago sem Stripe paid',
      actor: 'B2',
      pre: sess4 ?? '',
      repro: 'GET checkout_return=success unpaid',
      expected: '«Pagamento ainda não confirmado»',
      obtained: b4b2?.brief,
    );
  }

  // leave S2 unpublished (fixture)
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'hub_published': false,
    'is_live': false,
  }, prefer: 'return=minimal');

  await dumpJson('${outDir()}/pass2.json', {
    'lenses': c.lensesHit.toList()..sort(),
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
    'tipIdB1': tipId,
    'sessionIdB1': sessionId,
    'stripeKeyPresent': c.stripeTestKey != null,
  });
}
