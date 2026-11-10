/// Pass 3 — encadear OCR draft → accept → caixa; stock; restos. Sem captura se Session negar.
import 'dart:io';
import '_rtf.dart';

void main() async {
  final env = loadEnv();
  final c = Rtf.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();

  final findings = <Map<String, dynamic>>[];
  final map = <String, dynamic>{
    'auditor': 'REDTEAM_BLIND_F_POLITICAS_FINAS_v1',
    'stamp': stamp,
    'pass': 3,
  };
  var n = 300;
  String nid(String s) => 'RTF1250-${s.toUpperCase()}-${++n}';
  void add(Map<String, dynamic> f) => findings.add(f);

  Future<HttpHit> note(String label, Future<HttpHit> fut, {String idn = ''}) async {
    final h = await fut;
    map[label] = {
      'http': h.status,
      'n': h.list.length,
      'id': h.firstId,
      'snip': h.snippet,
      'identity': idn,
    };
    stderr.writeln('${h.status} $label ${h.snippet}');
    return h;
  }

  const unlisted = 'f3f94bbf-07af-4891-9ba8-dc5e38406f5f';
  const listed = 'd70145a9-203a-4b2d-b05f-6439e8b369d7';
  const endedLive = '4bf308fe-51e8-45d6-ac21-d539e7a94da6';
  const draftLive = '1332ba7e-91fb-4d4d-ab78-7052649d2363';
  const ocrResv = 'd5198f20-1974-4074-bff6-a4ed93428e9f';
  const pausedItem = '38c59bba-4213-4249-a927-eae0aaa908df';
  const liveOnlyItem = '090868bc-fd9d-4b07-a54c-943ae0daa86c';
  const draftItem = '6b9accc4-755c-49ac-9b57-fc88a941e72b';
  const muxHostile = '72115a99-967e-40d7-8268-e6fd372b56d3';

  final before = await note(
    'OBS-unlist-before',
    c.rest(
      'GET',
      'products?id=eq.$unlisted&select=id,title,price,quantity,is_sold,list_on_marketplace',
      service: true,
    ),
    idn: 'svc',
  );

  final ocrRow = await note(
    'OBS-ocr-resv',
    c.rest(
      'GET',
      'live_reservation_requests?id=eq.$ocrResv&select=id,status,source,buyer_id,seller_id,live_id,live_item_id,requested_qty,notes',
      service: true,
    ),
    idn: 'svc',
  );

  // Seller accept OCR pending on DRAFT live
  final acc = await note(
    'F8-seller-accept-ocr-draft',
    c.rpc('batata_process_live_reservation_request', {
      'p_request_id': ocrResv,
      'p_action': 'accept',
    }, jwt: c.sellerJwt),
    idn: 'seller',
  );
  if (acc.ok && acc.body.contains('"ok":true')) {
    add(finding(
      id: nid('f8-accept-ocr-draft'),
      lens: 'F8',
      severity: 'P1',
      title: 'Seller accept reserva OCR em live DRAFT',
      pre: 'resv $ocrResv live draft',
      repro: 'rpc process_live_reservation_request accept',
      proven: true,
      evidence: {'snip': acc.snippet},
    ));
  }

  final afterAcc = await note(
    'OBS-ocr-after-accept',
    c.rest(
      'GET',
      'live_reservation_requests?id=eq.$ocrResv&select=id,status,requested_qty',
      service: true,
    ),
    idn: 'svc',
  );

  final afterProd = await note(
    'OBS-unlist-after-accept',
    c.rest(
      'GET',
      'products?id=eq.$unlisted&select=id,quantity,is_sold,list_on_marketplace',
      service: true,
    ),
    idn: 'svc',
  );

  // Convert
  final conv = await note(
    'F8-seller-convert-ocr',
    c.rpc('batata_process_live_reservation_request', {
      'p_request_id': ocrResv,
      'p_action': 'convert',
    }, jwt: c.sellerJwt),
    idn: 'seller',
  );

  // Hold after accept (stock consumed?)
  final hold = await note(
    'F8-hold-unlist-after-ocr-accept',
    c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': unlisted,
      'live_id': draftLive,
      'live_item_id': draftItem,
      'quantity': 1,
      'price_total': 77.7,
      'status': 'aguarda_pagamento',
      'payment_method': 'pagamento na app',
      'shipping_method': 'hand',
    }),
    idn: 'buyer',
  );
  if (hold.ok) {
    add(finding(
      id: nid('f8-hold-after-ocr'),
      lens: 'F8',
      severity: 'P1',
      title: 'Hold unlist após OCR+accept em live draft',
      pre: 'unlist $unlisted',
      repro: 'POST orders aguarda_pagamento live_item draft',
      proven: true,
      evidence: {'snip': hold.snippet, 'id': hold.firstId},
    ));
    final oid = hold.firstId;
    if (oid != null) {
      final pi = await note(
        'F8-pi-unlist-draft',
        c.edge('create-payment-intent', {
          'buyer_id': c.buyerId,
          'seller_id': c.sellerId,
          'product_id': unlisted,
          'order_id': oid,
          'quantity': 1,
          'amount': 1,
          'currency': 'eur',
          'shipping_method': 'hand',
          'live_id': draftLive,
          'live_item_id': draftItem,
        }, jwt: c.buyerJwt),
        idn: 'buyer',
      );
      if (pi.ok && pi.hasCheckout) {
        add(finding(
          id: nid('f8-session-unlist-draft'),
          lens: 'F8',
          severity: 'P1',
          title: 'Session Stripe TEST para unlist via live DRAFT',
          pre: 'order $oid',
          repro: 'create-payment-intent after OCR path',
          proven: true,
          evidence: {'snip': pi.snippet},
          note: 'SESSION ≠ captura',
        ));
      }
    }
  }

  // Reservation JWT on paused Hub-visible item (ended live)
  final resvP = await note(
    'F1-resv-paused-hub',
    c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
      'live_id': endedLive,
      'live_item_id': pausedItem,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
    }),
    idn: 'buyer',
  );
  if (resvP.ok) {
    add(finding(
      id: nid('f1-resv-paused'),
      lens: 'F1',
      severity: 'P2',
      title: 'Buyer reserva item paused visível no Hub (live ended)',
      pre: 'item $pausedItem',
      repro: 'POST live_reservation_requests',
      proven: true,
      evidence: {'snip': resvP.snippet},
    ));
    final seen = await note(
      'F1-unlist-via-paused-resv',
      c.rest(
        'GET',
        'products?id=eq.$unlisted&select=id,title,price,list_on_marketplace',
        jwt: c.buyerJwt,
      ),
      idn: 'buyer',
    );
    if (seen.ok && seen.list.isNotEmpty) {
      add(finding(
        id: nid('f1-shadow-paused'),
        lens: 'F1',
        severity: 'P2',
        title: 'Unlist lido via reserva em item paused/ended',
        pre: 'resv ${resvP.firstId}',
        repro: 'GET products unlist as buyer',
        proven: true,
        evidence: {'snip': seen.snippet},
      ));
    }
  }

  // Cancel leftover listed holds so stock recovers (svc observation cleanup)
  final leftover = await note(
    'OBS-listed-holds',
    c.rest(
      'GET',
      'orders?product_id=eq.$listed&buyer_id=eq.${c.buyerId}&status=neq.cancelado&select=id,status,quantity&limit=20',
      service: true,
    ),
    idn: 'svc',
  );
  if (leftover.list.isNotEmpty) {
    for (final row in leftover.list) {
      if (row is! Map) continue;
      final id = row['id']?.toString();
      final st = row['status']?.toString() ?? '';
      if (id == null) continue;
      if (st == 'reserva_pendente' || st == 'aguarda_pagamento') {
        await c.rest('PATCH', 'orders?id=eq.$id', service: true, body: {
          'status': 'cancelado',
        }, prefer: 'return=minimal');
      }
    }
  }

  // Storage without GET+body
  await note(
    'F2-storage-get',
    c.req('POST', '/storage/v1/object/list/chat-media', jwt: c.buyer2Jwt, body: {
      'prefix': '',
      'limit': 5,
    }),
    idn: 'buyer2',
  );
  await note(
    'F2-storage-private',
    c.req('POST', '/storage/v1/object/list/fleaber-private', jwt: c.buyer2Jwt, body: {
      'prefix': '',
      'limit': 5,
    }),
    idn: 'buyer2',
  );

  await note(
    'F7-expire-offers',
    c.rpc('batata_expire_product_offers', {}, jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note(
    'F7-raffle-assert',
    c.rpc('batata_live_raffle_assert_seller', {'p_live_id': endedLive}, jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note(
    'F2-helpers',
    c.rest(
      'GET',
      'seller_helpers?select=id,seller_id,permissions,invited_email&limit=8',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );
  await note(
    'F2-live-items-base-b2',
    c.rest(
      'GET',
      'live_items?id=eq.$pausedItem&select=id,title,price,quantity,status,product_id',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );
  await note(
    'F2-live-items-anon',
    c.rest(
      'GET',
      'live_items?id=eq.$pausedItem&select=id,title,price',
    ),
    idn: 'anon',
  );

  // Tip checkout on ended (anti-atrophy 1 repro)
  await note(
    'F4-tip-ended-1repro',
    c.edge('create-live-tip-checkout', {
      'live_id': endedLive,
      'amount': 100,
    }, jwt: c.buyerJwt),
    idn: 'buyer',
  );

  // Refund as buyer on random
  await note(
    'F4-refund-buyer',
    c.edge('refund-order', {
      'order_id': listed,
    }, jwt: c.buyerJwt),
    idn: 'buyer',
  );

  map['ocr_accept'] = acc.snippet;
  map['ocr_convert'] = conv.snippet;
  map['hold'] = hold.snippet;
  map['prod_before'] = before.snippet;
  map['prod_after'] = afterProd.snippet;
  map['ocr_status'] = afterAcc.snippet;
  map['ocr_row'] = ocrRow.snippet;

  // Ensure no live left active
  for (final id in [draftLive, endedLive, muxHostile]) {
    await c.rest('PATCH', 'lives?id=eq.$id', service: true, body: {
      'is_active': false,
    }, prefer: 'return=minimal');
  }

  map['findings'] = findings;
  map['finding_count'] = findings.length;
  final out = '${repoRoot()}/tool/redteam_blind_f_20260831T1250/out/pass3.json';
  await dumpJson(out, map);
  stderr.writeln('WROTE $out findings=${findings.length}');
}
