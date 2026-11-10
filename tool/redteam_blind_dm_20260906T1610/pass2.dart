/// RED TEAM CEGO DM pass2 — restore S1 + re-oráculos B2/C1/D3.
/// Staging only. NÃO corrigir.
import 'dart:io';
import '_rtdm.dart';

Future<void> main() async {
  final c = Rtdm.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final s1 = c.sellerId!;
  final b2 = c.buyer2Id!;

  final before = await c.profile(s1);
  final rpc = await c.rpc('batata_publish_hub', {'p_publish': true}, jwt: c.sellerJwt);
  await c.restoreSeller1Published();
  var after = await c.profile(s1);
  if (after?['hub_published'] != true) {
    final rpc2 = await c.rpc('batata_publish_hub', {'p_publish': true}, jwt: c.sellerJwt);
    c.note('restore.rpc2', 'second RPC publish', rpc2.brief, lens: 'DM1');
    after = await c.profile(s1);
  }
  c.note('restore.before', 'S1 before', before, lens: 'DM1');
  c.note('restore.rpc', 'batata_publish_hub true', rpc.brief, lens: 'DM1');
  c.note('restore.after', 'S1 after', after, lens: 'DM1');

  if (after?['hub_published'] != true) {
    c.hold(
      id: 'P2-RESTORE-S1',
      lens: 'DM1',
      severity: 'P2',
      title: 'S1 hub_published ficou false após probes (restore RPC+PATCH falhou)',
      actor: 'S1 RPC + service PATCH',
      pre: 'loja demo obrigatória published',
      repro: 'batata_publish_hub(true) + PATCH',
      expected: 'hub_published=true',
      obtained: after,
    );
  }

  // Confirm lives ended
  final lives = [
    '7cb5699c-a4c3-4e0b-a0fd-f74a78a1bbf2',
    '7ed37fa8-142f-48c0-ad98-43e38109ae01',
    'e5e182e8-501f-4811-830b-087096440164',
    'a0a83d33-cb9a-415a-b98c-83e897e66c2c',
    'e5db4cd9-0089-4d3a-a9d7-cdea440c3ac8',
    '604fd231-b297-4a39-b63d-0cc513cf4db9',
  ];
  for (final id in lives) {
    await c.endLive(id);
  }
  final liveRows = await c.rest(
    'GET',
    'lives?id=in.(${lives.join(',')})&select=id,status,is_active',
    service: true,
  );
  c.note('lives.ended', 'fixture lives', liveRows.brief, lens: 'DM4');

  // ----- B2 re-oracle: qty=0 listed not sold vs Hub (S1 published) -----
  const skuB2 = '1d97f585-8a18-4c17-be7b-10a22abb434e';
  final prodB2 = await c.productRow(skuB2);
  final hubB2j = await c.hubSku(skuB2, jwt: c.buyerJwt);
  final hubB2a = await c.hubSku(skuB2, anon: true);
  final oidTry = await c.insertOrder(
    productId: skuB2,
    jwt: c.buyerJwt,
    price: 12.0,
  );
  HttpHit? cpiB2;
  if (oidTry != null) {
    cpiB2 = await c.checkout(orderId: oidTry, productId: skuB2, jwt: c.buyerJwt);
  }
  final hubShows = hubB2j.list.isNotEmpty || hubB2a.list.isNotEmpty;
  final cpiCs = (cpiB2?.ok ?? false) && (cpiB2?.sessionId ?? '').startsWith('cs_');

  String b2r;
  if (after?['hub_published'] != true) {
    b2r = 'SKIP';
    c.skip('B2r', 'DM2', 'S1 ainda unpublished', after);
  } else if (hubShows || cpiCs) {
    b2r = 'HOLD';
    c.hold(
      id: 'P1-B2-QTY0-HUB',
      lens: 'DM2',
      severity: 'P1',
      title: 'qty=0 is_sold=false: Hub e/ou CPI ainda vendem',
      actor: 'anon+B1',
      pre: 'S1 published; products.quantity=0 listed',
      repro: 'GET hub_products_public + insertOrder/CPI',
      expected: 'Hub 0 e CPI/insert deny',
      obtained: {
        'prod': prodB2,
        'hubJwt_n': hubB2j.list.length,
        'hubAnon_n': hubB2a.list.length,
        'insert': oidTry,
        'cpi': cpiB2?.brief,
      },
    );
  } else {
    b2r = 'FAIL';
    c.block('B2r', 'DM2', 'qty0 published: Hub vazio + insert/CPI deny', {
      'prod': prodB2,
      'hubJwt': hubB2j.brief,
      'hubAnon': hubB2a.brief,
      'oid': oidTry,
      'cpi': cpiB2?.brief,
    });
  }
  c.probe(
    id: 'B2r',
    surfaces: 'Hub + products + CPI',
    action: 're-oracle qty=0 listed com S1 published',
    http: {'hubJwt': hubB2j.brief, 'hubAnon': hubB2a.brief, 'cpi': cpiB2?.brief},
    oracles: {
      'prod': prodB2,
      'hubShows': hubShows,
      'cpiCs': cpiCs,
      's1_pub': after?['hub_published'],
    },
    result: b2r,
    lens: 'DM2',
    countFinding: b2r == 'HOLD',
  );

  // ----- C1 re-oracle: leftover qty=1 after pago -----
  const skuC1 = 'e8f0b8f8-b50e-4d38-bdba-528c8a293a7d';
  const oidC1 = '8b711264-24bb-4231-acb1-0f6a1ad70f1f';
  final prodC1 = await c.productRow(skuC1);
  final orderC1 = await c.orderRow(oidC1);
  final hubC1j = await c.hubSku(skuC1, jwt: c.buyerJwt);
  final hubC1a = await c.hubSku(skuC1, anon: true);
  final chats = await c.chatsForProduct(skuC1);
  final msgs = await c.chatMsgsForOrder(oidC1);
  final qtyC1 = numOf(prodC1?['quantity']) ?? -1;
  final hubC1n = hubC1j.list.length;
  final shouldShow = qtyC1 > 0 && prodC1?['is_sold'] != true && prodC1?['list_on_marketplace'] == true;

  String c1r;
  if (after?['hub_published'] != true) {
    c1r = 'SKIP';
    c.skip('C1r', 'DM5', 'S1 unpublished', after);
  } else if (shouldShow && hubC1n == 0) {
    c1r = 'HOLD';
    c.hold(
      id: 'P1-C1-HUB-MISS',
      lens: 'DM1',
      severity: 'P1',
      title: 'Pago leftover qty=1 listado não aparece no Hub',
      actor: 'anon+B1',
      pre: 'order pago; product qty=1 listed not sold; S1 published',
      repro: 'GET hub_products_public id=SKU',
      expected: '1 linha Hub',
      obtained: {
        'prod': prodC1,
        'order': orderC1?['status'],
        'hubJwt': hubC1j.brief,
        'hubAnon': hubC1a.brief,
      },
    );
  } else {
    c1r = 'FAIL';
    c.block('C1r', 'DM5', 'pago leftover vs Hub coerente (ou qty0/sold)', {
      'qty': qtyC1,
      'hub_n': hubC1n,
      'shouldShow': shouldShow,
      'status': orderC1?['status'],
      'chats': chats.length,
      'msgs': msgs.length,
    });
  }
  c.probe(
    id: 'C1r',
    surfaces: 'orders + Hub + products + chat',
    action: 're-oracle pago leftover no Hub com S1 published',
    http: {'hubJwt': hubC1j.brief, 'hubAnon': hubC1a.brief},
    oracles: {
      'prod': prodC1,
      'status': orderC1?['status'],
      'hub_n': hubC1n,
      'shouldShow': shouldShow,
      'chats_n': chats.length,
      'msgs_n': msgs.length,
    },
    result: c1r,
    lens: 'DM5',
    countFinding: c1r == 'HOLD',
  );

  // ----- B1 hitch hold vs Hub (res accepted, lives ended) -----
  const skuB1 = 'a89de08c-05d8-483d-a6e5-638e0c915c0b';
  const ridB1 = '48230d14-b663-400f-86c6-2074cb70035e';
  final prodB1 = await c.productRow(skuB1);
  final resB1 = await c.resRow(ridB1);
  final hubB1 = await c.hubSku(skuB1, jwt: c.buyerJwt);
  final oidB1b = await c.insertOrder(
    productId: skuB1,
    jwt: c.buyerJwt,
    price: 12.0,
  );
  HttpHit? cpiB1;
  if (oidB1b != null) {
    cpiB1 = await c.checkout(orderId: oidB1b, productId: skuB1, jwt: c.buyerJwt);
  }
  final hubB1show = hubB1.list.isNotEmpty;
  final liveHeld = resB1?['status'] == 'accepted';
  final cpiDeny = oidB1b == null || cpiB1 == null || denied(cpiB1!);
  String b1r;
  if (liveHeld && hubB1show && cpiDeny) {
    b1r = 'HOLD';
    c.hold(
      id: 'P2-B1-HUB-HOLD',
      lens: 'DM2',
      severity: 'P2',
      title: 'Reserva live accepted: Hub ainda lista SKU; CPI recusa',
      actor: 'B1 Hub vs CPI vs live',
      pre: 'qty produto=1; reservation accepted',
      repro: 'GET hub + insertOrder/CPI vs live_reservation accepted',
      expected: 'Hub esconde OU CPI alinha com vitrine',
      obtained: {
        'prod': prodB1,
        'res': resB1,
        'hub_n': hubB1.list.length,
        'insert': oidB1b,
        'cpi': cpiB1?.brief,
      },
    );
  } else {
    b1r = 'FAIL';
    c.block('B1r', 'DM2', 'hitch hold vs Hub (estado)', {
      'liveHeld': liveHeld,
      'hubB1show': hubB1show,
      'cpiDeny': cpiDeny,
      'prod': prodB1,
      'res': resB1,
      'cpi': cpiB1?.brief,
    });
  }
  c.probe(
    id: 'B1r',
    surfaces: 'Hub + live_reservation + CPI + products',
    action: 're-oracle hitch accepted vs Hub vs CPI',
    http: {'hub': hubB1.brief, 'cpi': cpiB1?.brief},
    oracles: {
      'prod': prodB1,
      'res': resB1,
      'hubShow': hubB1show,
      'cpiDeny': cpiDeny,
    },
    result: b1r,
    lens: 'DM2',
    countFinding: b1r == 'HOLD',
  );

  // ----- D3 proper: initial_qty=2 leftover; refund ∥ B2 CPI -----
  final paid = await c.payToPago(lens: 'DM4', initialQty: 2);
  HttpHit? rf;
  HttpHit? cpiNew;
  Map<String, dynamic>? prodMid;
  Map<String, dynamic>? prodEnd;
  Map<String, dynamic>? orderOld;
  Map<String, dynamic>? orderNew;
  String? oidNew;
  if (paid != null) {
    prodMid = await c.productRow(paid.pid);
    oidNew = await c.insertOrder(
      productId: paid.pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 5.9,
    );
    if (oidNew != null) {
      final raced = await Future.wait([
        c.refund(paid.oid),
        c.checkout(
          orderId: oidNew,
          productId: paid.pid,
          jwt: c.buyer2Jwt,
          buyer: b2,
        ),
      ]);
      rf = raced[0];
      cpiNew = raced[1];
      orderOld = await c.orderRow(paid.oid);
      orderNew = await c.orderRow(oidNew);
      prodEnd = await c.productRow(paid.pid);
    }
  }
  final qtyMid = numOf(prodMid?['quantity']) ?? -1;
  final qtyEnd = numOf(prodEnd?['quantity']) ?? -1;
  final newCs = (cpiNew?.ok ?? false) && (cpiNew?.sessionId ?? '').startsWith('cs_');
  final refunded = rf != null && (rf.ok || rf.body.contains('already_refunded'));
  // After pay qty 2→1; B2 hold 1; refund restores +1 → expect 1 (if B2 hold) or 2.
  // Bug: qtyEnd > 2 or qtyEnd < 0 or (newCs && qtyEnd > 1 && refund restored without consuming hold)
  final over = qtyEnd > 2 || qtyEnd < 0;

  String d3r;
  if (paid == null) {
    d3r = 'SKIP';
    c.skip('D3r', 'DM4', 'paid fail', 'null');
  } else if (oidNew == null) {
    d3r = 'FAIL';
    c.block('D3r', 'DM4', 'B2 não inseriu leftover (stock hold) — pass1 D3 retract', {
      'qtyMid': qtyMid,
      'pid': paid.pid,
    });
  } else if (over) {
    d3r = 'HOLD';
    c.hold(
      id: 'P1-D3-REFUND-RACE',
      lens: 'DM4',
      severity: 'P1',
      title: 'Refund ∥ CPI leftover: stock incoerente',
      actor: 'S1 ∥ B2',
      pre: 'pago qty 2→1; B2 hold leftover',
      repro: 'Future.wait refund ∥ CPI',
      expected: 'qty 0..2 coerente',
      obtained: {
        'qtyMid': qtyMid,
        'qtyEnd': qtyEnd,
        'rf': rf?.brief,
        'cpi': cpiNew?.brief,
        'old': orderOld?['status'],
        'new': orderNew?['status'],
        'newCs': newCs,
      },
    );
  } else {
    d3r = 'FAIL';
    c.block('D3r', 'DM4', 'refund∥CPI leftover stock coerente — retract pass1 D3', {
      'qtyMid': qtyMid,
      'qtyEnd': qtyEnd,
      'refunded': refunded,
      'newCs': newCs,
      'old': orderOld?['status'],
      'new': orderNew?['status'],
    });
  }
  c.probe(
    id: 'D3r',
    surfaces: 'refund-order + CPI + products + orders',
    action: 'Future.wait refund pago ∥ CPI leftover qty=1',
    http: {'rf': rf?.brief, 'cpi': cpiNew?.brief},
    oracles: {
      'qtyMid': qtyMid,
      'qtyEnd': qtyEnd,
      'old': orderOld?['status'],
      'new': orderNew?['status'],
      'newCs': newCs,
      'refunded': refunded,
      'pass1_d3': 'retract — race não correu (qty0 insert deny)',
    },
    result: d3r,
    lens: 'DM4',
    countFinding: d3r == 'HOLD',
  );

  final finalProf = await c.profile(s1);
  c.note('final.s1', 'S1 hub_published exit', finalProf?['hub_published'], lens: 'DM1');
  if (finalProf?['hub_published'] != true) {
    await c.rpc('batata_publish_hub', {'p_publish': true}, jwt: c.sellerJwt);
    await c.restoreSeller1Published();
  }

  await dumpJson('${outDir()}/pass2.json', {
    'auditor': 'REDTEAM_BLIND_DM_CROSS_SURFACE_POS_DBDG_v1',
    'pass': 2,
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
    's1_before': before,
    's1_after': after,
    's1_exit': finalProf,
  });
  stdout.writeln('WROTE pass2.json probes=${c.probes.length} findings=${c.findings.length} '
      's1=${finalProf?['hub_published']}');
}
