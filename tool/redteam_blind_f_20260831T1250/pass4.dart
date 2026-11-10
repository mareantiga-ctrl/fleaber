/// Pass 4 — estado final OCR convert, stock, live_item; cleanup holds; lentes saturadas.
import 'dart:io';
import '_rtf.dart';

void main() async {
  final env = loadEnv();
  final c = Rtf.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();

  final map = <String, dynamic>{
    'auditor': 'REDTEAM_BLIND_F_POLITICAS_FINAS_v1',
    'stamp': stamp,
    'pass': 4,
  };
  final findings = <Map<String, dynamic>>[];
  var n = 400;
  String nid(String s) => 'RTF1250-${s.toUpperCase()}-${++n}';

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
  const ocrResv = 'd5198f20-1974-4074-bff6-a4ed93428e9f';
  const draftItem = '6b9accc4-755c-49ac-9b57-fc88a941e72b';
  const pausedItem = '38c59bba-4213-4249-a927-eae0aaa908df';
  const draftLive = '1332ba7e-91fb-4d4d-ab78-7052649d2363';
  const endedLive = '4bf308fe-51e8-45d6-ac21-d539e7a94da6';
  const muxHostile = '72115a99-967e-40d7-8268-e6fd372b56d3';
  const helperId = 'c7c1cec2-bf55-41ea-984f-76a1799b79fa';
  const resvPaused = '540a8260-eab8-41dd-bf28-aadc1056f4cb';

  await note(
    'OBS-ocr-final',
    c.rest(
      'GET',
      'live_reservation_requests?id=eq.$ocrResv&select=id,status,source,buyer_id,converted_order_id,requested_qty,notes',
      service: true,
    ),
    idn: 'svc',
  );
  await note(
    'OBS-orders-draft-item',
    c.rest(
      'GET',
      'orders?live_item_id=eq.$draftItem&select=id,status,buyer_id,product_id,price_total,amount_paid_cents,stripe_checkout_session_id,live_id,quantity',
      service: true,
    ),
    idn: 'svc',
  );
  await note(
    'OBS-live-item-draft',
    c.rest(
      'GET',
      'live_items?id=eq.$draftItem&select=id,status,is_active,quantity,product_id,price,title',
      service: true,
    ),
    idn: 'svc',
  );
  await note(
    'OBS-unlist',
    c.rest(
      'GET',
      'products?id=eq.$unlisted&select=id,quantity,is_sold,list_on_marketplace,title,price',
      service: true,
    ),
    idn: 'svc',
  );
  await note(
    'OBS-wallets-seller',
    c.rest(
      'GET',
      'wallets?id=eq.${c.sellerId}&select=id,balance',
      service: true,
    ),
    idn: 'svc',
  );
  await note(
    'OBS-wallets-buyer',
    c.rest(
      'GET',
      'wallets?id=eq.${c.buyerId}&select=id,balance',
      service: true,
    ),
    idn: 'svc',
  );

  // Hub still shows paused after restore?
  await note(
    'F2-hub-paused-still',
    c.rest(
      'GET',
      'hub_live_items_public?id=eq.$pausedItem&select=id,title,price,status,is_active',
    ),
    idn: 'anon',
  );

  // Buyer2 live_items of draft live (not in Hub)
  await note(
    'F2-b2-draft-item',
    c.rest(
      'GET',
      'live_items?id=eq.$draftItem&select=id,title,price,product_id,status,live_id',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );

  // Reviews UUID residual map
  await note(
    'F2-reviews-other-buyer',
    c.rest(
      'GET',
      'reviews_gerais?select=id,buyer_id,target_id,stars&limit=2',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );

  // Cancel lab holds
  for (final id in [
    'ef4f3318-37fd-4fab-8608-20a3e63b1792',
    'a80c3e0d-da01-4bf9-b7c3-ebe2a4585c60',
    '416f1351-fbc6-461c-a7a8-c0c68cc4b7cb',
  ]) {
    await c.rest('PATCH', 'orders?id=eq.$id', service: true, body: {
      'status': 'cancelado',
    }, prefer: 'return=minimal');
  }

  // Expire pairing leftover, reject helper, unlist products, end lives
  await c.rest(
    'PATCH',
    'seller_helpers?id=eq.$helperId',
    service: true,
    body: {'active': false, 'invitation_status': 'rejected'},
    prefer: 'return=minimal',
  );
  await c.rest(
    'PATCH',
    'live_reservation_requests?id=eq.$ocrResv',
    service: true,
    body: {'status': 'rejected'},
    prefer: 'return=minimal',
  );
  await c.rest(
    'PATCH',
    'live_reservation_requests?id=eq.$resvPaused',
    service: true,
    body: {'status': 'rejected'},
    prefer: 'return=minimal',
  );
  for (final live in [draftLive, endedLive, muxHostile]) {
    await c.rest('PATCH', 'lives?id=eq.$live', service: true, body: {
      'is_active': false,
      'status': live == draftLive ? 'draft' : 'ended',
    }, prefer: 'return=minimal');
  }
  await c.rest(
    'PATCH',
    'profiles?id=eq.${c.sellerId}',
    service: true,
    body: {'is_live': false},
    prefer: 'return=minimal',
  );

  map['findings'] = findings;
  final out = '${repoRoot()}/tool/redteam_blind_f_20260831T1250/out/pass4.json';
  await dumpJson(out, map);
  stderr.writeln('WROTE $out');
}
