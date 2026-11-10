/// CY pass2b — B1 tip mid-unpublish via RPC real (S1). Restore obrigatório.
import 'dart:convert';
import 'dart:io';
import '_rtcy.dart';

Future<void> main() async {
  final c = Rtcy.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  final ids = jsonDecode(await File('${outDir()}/pass1_ids.json').readAsString())
      as Map<String, dynamic>;
  final s1 = ids['s1'] as String;
  final airPub = ids['airPub'] as String;

  Future<HttpHit> publish(bool on) {
    return c.rpc('batata_publish_hub', {'p_publish': on}, jwt: c.sellerJwt);
  }

  await c.rest('PATCH', 'lives?id=eq.$airPub', service: true, body: {
    'status': 'live',
    'is_active': true,
  }, prefer: 'return=minimal');

  final before = await c.profile(s1);
  c.note('b1b.s1.before', 'S1 hub before', before?['hub_published'], lens: 'CY3');

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
  c.note('b1b.create', 'tip Session S1 published', create, lens: 'CY3');
  String? tipId = create.map?['tipId']?.toString() ??
      create.map?['tip_id']?.toString();
  String? sessionId = create.map?['checkoutSessionId']?.toString() ??
      create.map?['sessionId']?.toString() ??
      create.map?['checkout_session_id']?.toString();

  final unpub = await publish(false);
  c.note('b1b.unpub', 'batata_publish_hub false', unpub, lens: 'CY3');
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

  // Restore S1 FIRST before classifying.
  final restPub = await publish(true);
  c.note('b1b.restore', 'batata_publish_hub true', restPub, lens: 'CY3');
  var after = await c.profile(s1);
  if (after?['hub_published'] != true) {
    final again = await publish(true);
    c.note('b1b.restore2', 'retry publish', again, lens: 'CY3');
    after = await c.profile(s1);
  }

  final sessionOk = create.ok && sessionId != null;
  final unpubWorked = mid?['hub_published'] == false;
  final restored = after?['hub_published'] == true;
  final b1fail = (credited && !false) && (paidCopy || credited);
  // unpaid credit only
  final unpaidCredit = credited || paidCopy;

  String result;
  if (!sessionOk) {
    result = 'SKIP';
  } else if (!unpubWorked) {
    result = 'SKIP';
    c.skip('B1', 'CY3', 'RPC unpublish S1 não pegou', {
      'unpub': unpub.brief,
      'mid': mid?['hub_published'],
    });
  } else if (unpaidCredit) {
    result = 'FAIL';
  } else {
    result = 'HOLD';
  }

  c.probe(
    id: 'B1',
    poco: 'CY-B',
    payload:
        'tip Session S1 published → RPC unpublish → GET unpaid → RPC republish (sem sk_test)',
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
    },
    result: result,
    lens: 'CY3',
    countFinding: result == 'FAIL',
  );
  if (unpaidCredit && sessionOk && unpubWorked) {
    c.hold(
      id: 'CY-B1-TIP-UNPAID-CREDIT-MIDUNPUB',
      lens: 'CY3',
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
      id: 'CY-B1-S1-RESTORE-FAILED',
      lens: 'CY3',
      severity: 'P2',
      title: 'S1 não voltou a hub_published=true após o probe',
      actor: 'S1 RPC',
      pre: 'obrigatório restaurar loja demo',
      repro: 'batata_publish_hub(true)',
      expected: 'hub_published=true',
      obtained: after,
    );
  }

  await dumpJson('${outDir()}/pass2b.json', {
    'probes': c.probes,
    'findings': c.findings,
    'notes': c.notes,
    'skipped': c.skipped,
    's1_final': after?['hub_published'],
  });
  stdout.writeln(
    'PASS2B done result=$result restored=$restored hub_mid=${mid?['hub_published']}',
  );
}
