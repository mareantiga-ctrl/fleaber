/// RED TEAM CEGO DE pass2 — DE-B tip (≥3). Restore S1 obrigatório.
import 'dart:convert';
import 'dart:io';
import '_rtde.dart';

Future<void> main() async {
  final c = Rtde.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final s1 = ids['s1'] as String;
  final s2 = ids['s2'] as String;
  final airPub = ids['airPub'] as String;

  Future<HttpHit> publish(bool on) {
    return c.rpc('batata_publish_hub', {'p_publish': on}, jwt: c.sellerJwt);
  }

  await c.restoreSeller1Published();
  await c.setHub(s2, false);
  await c.rest('PATCH', 'lives?id=eq.$airPub', service: true, body: {
    'status': 'live',
    'is_active': true,
  }, prefer: 'return=minimal');

  try {
    // ----- B1 tip mid-unpublish unpaid (S1 RPC, sem sk_test) -----
    final before = await c.profile(s1);
    c.note('b1.s1.before', 'S1 hub before', before?['hub_published'], lens: 'DE3');
    final balBefore = await c.walletBal(s1);
    final create = await c.edge(
      'create-live-tip-checkout',
      jwt: c.buyer2Jwt,
      body: {
        'live_id': airPub,
        'seller_id': s1,
        'amount_eur': 2,
      },
    );
    c.note('b1.create', 'tip Session S1 published', create, lens: 'DE3');
    String? tipId = create.map?['tipId']?.toString() ??
        create.map?['tip_id']?.toString();
    String? sessionId = create.map?['checkoutSessionId']?.toString() ??
        create.map?['sessionId']?.toString() ??
        create.map?['checkout_session_id']?.toString();
    if (tipId != null) c.createdTipIds.add(tipId);

    final unpub = await publish(false);
    c.note('b1.unpub', 'batata_publish_hub false', unpub, lens: 'DE3');
    final mid = await c.profile(s1);

    HttpHit? getUnpaid;
    if (sessionId != null && sessionId.isNotEmpty) {
      getUnpaid = await c.edge(
        'create-live-tip-checkout',
        method: 'GET',
        jwt: c.buyer2Jwt,
        qs: 'checkout_return=success&session_id=$sessionId',
      );
    }

    var tipStatus = '';
    var credited = false;
    if (tipId != null) {
      final row = await c.rest(
        'GET',
        'live_tips?id=eq.$tipId&select=id,status,amount',
        service: true,
      );
      tipStatus = '${row.map?['status'] ?? ''}';
      final balAfter = await c.walletBal(s1);
      credited = tipStatus == 'paid' ||
          tipStatus == 'settled' ||
          (balAfter - balBefore) > 0;
    }
    final paidCopy =
        getUnpaid?.body.toLowerCase().contains('pagamento recebido') ?? false;

    final restPub = await publish(true);
    c.note('b1.restore', 'batata_publish_hub true', restPub, lens: 'DE3');
    var after = await c.profile(s1);
    if (after?['hub_published'] != true) {
      await c.restoreSeller1Published();
      after = await c.profile(s1);
    }

    final sessionOk = create.ok && sessionId != null;
    final unpubWorked = mid?['hub_published'] == false;
    final restored = after?['hub_published'] == true;
    final unpaidCredit = credited || paidCopy;

    String b1result;
    if (!sessionOk) {
      b1result = 'SKIP';
      c.skip('B1', 'DE3', 'não criou Session', create);
    } else if (!unpubWorked) {
      b1result = 'SKIP';
      c.skip('B1', 'DE3', 'RPC unpublish S1 não pegou', {
        'unpub': unpub.brief,
        'mid': mid?['hub_published'],
      });
    } else if (unpaidCredit) {
      b1result = 'FAIL';
    } else {
      b1result = 'HOLD';
    }

    c.probe(
      id: 'B1',
      poco: 'DE-B',
      payload:
          'tip Session S1 published → RPC unpublish → GET unpaid → RPC republish',
      http: {
        'create': create.brief,
        'unpub': unpub.brief,
        'getUnpaid': getUnpaid?.brief,
        'restore': restPub.brief,
      },
      bd: {
        'hub_before': before?['hub_published'],
        'hub_mid': mid?['hub_published'],
        'hub_after': after?['hub_published'],
        'tipStatus': tipStatus,
        'credited': credited,
        'restored': restored,
        'has_sk_test': c.stripeTestKey != null,
      },
      result: b1result,
      lens: 'DE3',
      countFinding: b1result == 'FAIL',
    );
    if (unpaidCredit && sessionOk && unpubWorked) {
      c.hold(
        id: 'DE-B1-TIP-UNPAID-CREDIT-MIDUNPUB',
        lens: 'DE3',
        severity: 'P0',
        title: 'GET settle após unpublish creditou gorjeta não paga',
        actor: 'B2',
        pre: 'Session S1 published; RPC hub_published=false',
        repro: 'GET create-live-tip-checkout?checkout_return=success',
        expected: 'pending; Δwallet=0',
        obtained: {'status': tipStatus, 'get': getUnpaid?.brief},
      );
    }
    if (!restored) {
      c.hold(
        id: 'DE-B1-S1-RESTORE-FAILED',
        lens: 'DE3',
        severity: 'P2',
        title: 'S1 não voltou a hub_published=true após o probe',
        actor: 'S1 RPC',
        pre: 'obrigatório restaurar loja demo',
        repro: 'batata_publish_hub(true)',
        expected: 'hub_published=true',
        obtained: after,
      );
    }

    // ----- B2 amount / tip_id hostil -----
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
      poco: 'DE-B',
      payload: 'amount 0/0.01/-1/0.5/501 + tip_id cliente + seller≠owner live',
      http: {
        'amounts': amtHits,
        'tip_id': tipIdBody.brief,
        'wrongSeller': wrongSeller.brief,
      },
      result: b2fail ? 'FAIL' : 'HOLD',
      lens: 'DE3',
      countFinding: b2fail,
    );
    if (amtAccepted.isNotEmpty) {
      c.hold(
        id: 'DE-B2-TIP-AMOUNT',
        lens: 'DE3',
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
        id: 'DE-B2-TIP-ID-CLIENT',
        lens: 'DE3',
        severity: 'P1',
        title: 'tip_id do cliente aceite',
        actor: 'B2',
        pre: 'body.tip_id UUID',
        repro: 'POST create-live-tip-checkout tip_id=',
        expected: '400 Client tip_id is not allowed',
        obtained: tipIdBody.brief,
      );
    }

    // ----- B3 settle unpaid GET + RPC -----
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
    final paidCopy3 =
        (b3b2?.body.toLowerCase().contains('pagamento recebido') ?? false) ||
            (b3anon?.body.toLowerCase().contains('pagamento recebido') ?? false);
    final rpcSettled = b3rpc != null &&
        (b3rpc.ok &&
            (b3rpc.map?['ok'] == true ||
                '${b3rpc.body}'.toLowerCase().contains('"ok":true')));
    final b3fail =
        paidCopy3 || st3 == 'paid' || st3 == 'settled' || delta3 > 0 || rpcSettled;
    c.probe(
      id: 'B3',
      poco: 'DE-B',
      payload: 'GET settle unpaid B2/anon + RPC settle JWT (Session não paga)',
      http: {
        'create': b3create.brief,
        'getB2': b3b2?.brief,
        'getAnon': b3anon?.brief,
        'rpc': b3rpc?.brief,
      },
      bd: {'status': st3, 'deltaWallet': delta3},
      result: !b3create.ok ? 'SKIP' : (b3fail ? 'FAIL' : 'HOLD'),
      lens: 'DE3',
      countFinding: b3fail,
    );
    if (b3fail) {
      c.hold(
        id: 'DE-B3-SETTLE-UNPAID',
        lens: 'DE3',
        severity: 'P0',
        title: 'settle unpaid GET/RPC creditou gorjeta',
        actor: 'B2',
        pre: 'Session pending não paga',
        repro:
            'GET checkout_return=success e/ou RPC batata_settle_live_tip_from_stripe',
        expected: 'pending; Δ=0',
        obtained: {
          'status': st3,
          'delta': delta3,
          'get': b3b2?.brief,
          'rpc': b3rpc?.brief,
        },
      );
    }
  } finally {
    await publish(true);
    await c.restoreSeller1Published();
    await c.setHub(s2, false);
  }

  final s1final = await c.profile(s1);
  await dumpJson('${outDir()}/pass2.json', {
    'probes': c.probes,
    'findings': c.findings,
    'notes': c.notes,
    'skipped': c.skipped,
    'lenses': c.lensesHit.toList()..sort(),
    's1_hub_final': s1final?['hub_published'],
  });
  stdout.writeln(
    'PASS2 done probes=${c.probes.length} findings=${c.findings.length} s1=${s1final?['hub_published']}',
  );
}
