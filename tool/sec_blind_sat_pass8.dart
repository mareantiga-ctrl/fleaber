// Pass 8 — variants on review duplicate + reservation qty + raffle RPCs + cleanup
import 'dart:convert';
import 'dart:io';

const project = 'fxdknzrqjenzqcvnwqqq';
const base = 'https://$project.supabase.co';
const tag = 'SATB8_20260827';

late String anonKey, serviceKey, buyerJwt, sellerJwt, buyerId, sellerId;
String? e2eSecret;
final http = HttpClient();
final findings = <Map<String, dynamic>>[];
final notes = <String>[];

Future<Map<String, dynamic>> req(String method, String url, {String? token, Object? body}) async {
  final r = await http.openUrl(method, Uri.parse(url));
  final tok = token ?? anonKey;
  r.headers.set('apikey', tok == serviceKey ? serviceKey : anonKey);
  r.headers.set('Authorization', 'Bearer $tok');
  r.headers.set('Content-Type', 'application/json');
  if (method != 'GET' && method != 'DELETE') r.headers.set('Prefer', 'return=representation');
  if (body != null) r.add(utf8.encode(jsonEncode(body)));
  final res = await r.close().timeout(const Duration(seconds: 45));
  final raw = await res.transform(utf8.decoder).join();
  Object? parsed;
  try {
    parsed = raw.isEmpty ? null : jsonDecode(raw);
  } catch (_) {
    parsed = raw;
  }
  return {'status': res.statusCode, 'body': parsed, 'raw': raw.length > 2000 ? raw.substring(0, 2000) : raw};
}

Future<Map<String, dynamic>> rest(String t, {String method = 'GET', String? token, String qs = 'select=*&limit=8', Object? body}) =>
    req(method, '$base/rest/v1/$t${qs.isEmpty ? '' : '?$qs'}', token: token, body: body);

Future<Map<String, dynamic>> rpc(String n, {String? token, Object? body}) =>
    req('POST', '$base/rest/v1/rpc/$n', token: token, body: body ?? {});

Future<Map<String, dynamic>> edge(String n, {String? token, Object? body, Map<String, String>? extra}) async {
  final r = await http.openUrl('POST', Uri.parse('$base/functions/v1/$n'));
  final tok = token ?? anonKey;
  r.headers.set('apikey', anonKey);
  r.headers.set('Authorization', 'Bearer $tok');
  r.headers.set('Content-Type', 'application/json');
  extra?.forEach(r.headers.set);
  if (body != null) r.add(utf8.encode(jsonEncode(body)));
  final res = await r.close().timeout(const Duration(seconds: 60));
  final raw = await res.transform(utf8.decoder).join();
  Object? parsed;
  try {
    parsed = raw.isEmpty ? null : jsonDecode(raw);
  } catch (_) {
    parsed = raw;
  }
  return {'status': res.statusCode, 'body': parsed, 'raw': raw};
}

void find(String id, String sev, String surface, String impact, Object resp, {String variant = '', String fp = ''}) {
  findings.add({'id': id, 'sev': sev, 'surface': surface, 'impact': impact, 'response': resp, 'variant': variant, 'fp': fp});
  stderr.writeln('FINDING $sev $id $impact');
}

Future<void> main() async {
  final map = <String, String>{};
  for (final line in File('tool/live_ops_staging.env').readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#') || !t.contains('=')) continue;
    final i = t.indexOf('=');
    map[t.substring(0, i)] = t.substring(i + 1);
  }
  anonKey = map['SUPABASE_ANON_KEY']!;
  serviceKey = map['SUPABASE_SERVICE_ROLE_KEY']!;
  e2eSecret = map['FLEABER_STAGING_CRASH_INJECT_SECRET'];
  Future<Map> login(String e, String p) async {
    final r = await req('POST', '$base/auth/v1/token?grant_type=password', body: {'email': e, 'password': p});
    final b = r['body'] as Map;
    return {'jwt': b['access_token'], 'id': (b['user'] as Map)['id']};
  }
  final b = await login(map['LIVE_OPS_TEST_BUYER_EMAIL']!, map['LIVE_OPS_TEST_BUYER_PASSWORD']!);
  buyerJwt = b['jwt'] as String; buyerId = b['id'] as String;
  final s = await login(map['LIVE_OPS_TEST_SELLER_EMAIL']!, map['LIVE_OPS_TEST_SELLER_PASSWORD']!);
  sellerJwt = s['jwt'] as String; sellerId = s['id'] as String;

  try {
    await reviewVariants();
    await reservationVariants();
    await raffleRpcs();
    await oversellWithCategory();
    await cleanupArtifacts();
  } finally {
    http.close(force: true);
  }
  File('tool/reports/SATB_20260827_PASS8.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
    'findings': findings,
    'notes': notes,
    'p0': findings.where((f) => f['sev'] == 'P0').map((f) => f['id']).toList(),
    'p1': findings.where((f) => f['sev'] == 'P1').map((f) => f['id']).toList(),
  }));
  stdout.writeln(jsonEncode({'n': findings.length, 'p0': findings.where((f) => f['sev'] == 'P0').map((f) => f['id']).toList(), 'p1': findings.where((f) => f['sev'] == 'P1').map((f) => f['id']).toList()}));
}

Future<Map<String, dynamic>?> e2e(String probe) async {
  final r = await edge('sec-fase2-e2e-oversell', token: anonKey, extra: {
    'x-fleaber-e2e-secret': e2eSecret ?? '',
  }, body: {'probe': probe, 'buyer_id': buyerId, 'seller_id': sellerId, 'initial_qty': 1});
  final b = r['body'];
  return b is Map ? Map<String, dynamic>.from(b) : null;
}

Future<void> reviewVariants() async {
  final paid = await e2e('setup_paid_order');
  final oid = paid?['order_id']?.toString();
  notes.add('review fixture $oid');
  if (oid == null) return;
  await rest('orders', method: 'PATCH', token: buyerJwt, qs: 'id=eq.$oid', body: {'status': 'concluido'});

  final r1 = await rest('reviews', method: 'POST', token: buyerJwt, body: {
    'order_id': oid, 'buyer_id': buyerId, 'target_id': sellerId, 'stars': 5, 'comment': '$tag a', 'author_role': 'buyer',
  });
  notes.add('rev author_role=buyer ${r1['status']} ${r1['raw']}');
  final r2 = await rest('reviews', method: 'POST', token: buyerJwt, body: {
    'order_id': oid, 'buyer_id': buyerId, 'target_id': sellerId, 'stars': 1, 'comment': '$tag b',
  });
  notes.add('rev default comprador ${r2['status']} ${r2['raw']}');
  final r3 = await rest('reviews', method: 'POST', token: buyerJwt, body: {
    'order_id': oid, 'buyer_id': buyerId, 'target_id': sellerId, 'stars': 2, 'comment': '$tag c', 'author_role': 'vendedor',
  });
  notes.add('rev author_role=vendedor ${r3['status']} ${r3['raw']}');
  final r4 = await rest('reviews', method: 'POST', token: sellerJwt, body: {
    'order_id': oid, 'buyer_id': sellerId, 'target_id': buyerId, 'stars': 5, 'comment': '$tag seller',
  });
  notes.add('rev seller insert ${r4['status']} ${r4['raw']}');

  var count = 0;
  if (r1['status'] >= 200 && r1['status'] < 300) count++;
  if (r2['status'] >= 200 && r2['status'] < 300) count++;
  if (r3['status'] >= 200 && r3['status'] < 300) count++;
  if (count >= 2) {
    find('SATB-REV-DUP', 'P1', 'REVIEWS',
        'Duas (ou mais) reviews na mesma order: unique só conta author_role=comprador; author_role=buyer fura o duplicado.',
        {'n': count, 'r1': r1['raw'], 'r2': r2['raw'], 'r3': r3['raw']},
        variant: 'author_role buyer vs comprador vs vendedor',
        fp: 'primeira linha legacy sem unique');
  }

  // update/delete
  if (r1['body'] is List && (r1['body'] as List).isNotEmpty) {
    final id = ((r1['body'] as List).first as Map)['id'];
    final up = await rest('reviews', method: 'PATCH', token: buyerJwt, qs: 'id=eq.$id', body: {'stars': 1, 'comment': 'hack'});
    notes.add('review update own ${up['status']} ${up['raw']}');
    final del = await rest('reviews', method: 'DELETE', token: sellerJwt, qs: 'id=eq.$id');
    notes.add('review delete by seller ${del['status']} ${del['raw']}');
  }

  await rest('orders', method: 'DELETE', token: serviceKey, qs: 'id=eq.$oid');
  if (paid?['product_id'] != null) {
    await rest('products', method: 'DELETE', token: serviceKey, qs: 'id=eq.${paid!['product_id']}');
  }
}

Future<void> reservationVariants() async {
  const liveItem = 'ffb7b7e5-3007-44c7-b59d-44f99f36cb7f';
  const liveId = 'd43f048f-fd95-4fec-ac7a-4bea85cadeec';
  final ins99 = await rest('live_reservation_requests', method: 'POST', token: buyerJwt, body: {
    'live_id': liveId, 'live_item_id': liveItem, 'seller_id': sellerId, 'buyer_id': buyerId,
    'requested_qty': 99, 'status': 'accepted', 'source': 'fleaber_live',
  });
  notes.add('res qty99 ${ins99['status']} ${ins99['raw']}');
  String? rid;
  if (ins99['body'] is List && (ins99['body'] as List).isNotEmpty) {
    final row = (ins99['body'] as List).first as Map;
    rid = row['id']?.toString();
    notes.add('res qty99 persisted qty=${row['requested_qty']} status=${row['status']}');
    if (row['status'] == 'accepted') {
      find('SATB-RES-ACC', 'P1', 'RESERVATIONS', 'Buyer INSERT ficou accepted.', ins99['raw']);
    }
    if ((row['requested_qty'] as num?) == 99) {
      find('SATB-RES-QTY', 'P2', 'RESERVATIONS',
          'Buyer INSERT requested_qty=99 (acima do stock típico); status pending — seller accept poderia oversell.',
          ins99['raw'],
          variant: 'qty=99',
          fp: 'pending não consome stock até accept');
    }
  }
  if (rid != null) {
    final acc = await rest('live_reservation_requests', method: 'PATCH', token: buyerJwt, qs: 'id=eq.$rid', body: {'status': 'accepted'});
    notes.add('buyer PATCH accepted ${acc['status']} ${acc['raw']}');
    final accS = await rest('live_reservation_requests', method: 'PATCH', token: sellerJwt, qs: 'id=eq.$rid', body: {'status': 'accepted'});
    notes.add('seller PATCH accepted ${accS['status']} ${accS['raw']}');
    final conv = await rpc('batata_live_reservation_stripe_convert', token: buyerJwt, body: {
      'p_request_id': rid, 'p_order_id': '00000000-0000-0000-0000-000000000001',
    });
    notes.add('convert rpc buyer ${conv['status']} ${conv['raw']}');
    final act = await rpc('batata_process_live_reservation_request', token: buyerJwt, body: {
      'p_request_id': rid, 'p_action': 'accept', 'p_notes': tag, 'p_processed_by': buyerId,
    });
    notes.add('process accept as buyer ${act['status']} ${act['raw']}');
    await rest('live_reservation_requests', method: 'DELETE', token: serviceKey, qs: 'id=eq.$rid');
  }
  await rest('live_reservation_requests', method: 'DELETE', token: serviceKey, qs: 'id=eq.63d3e81c-4dea-4c18-b6f0-157e4b97f26c');
}

Future<void> raffleRpcs() async {
  final raffles = await rest('live_raffles', token: buyerJwt, qs: 'select=id,status,seller_id&limit=5');
  notes.add('raffles ${raffles['raw']}');
  final b = raffles['body'];
  if (b is List && b.isNotEmpty) {
    final rf = b.first as Map;
    final id = rf['id'];
    for (final call in [
      ['batata_join_live_raffle', {'p_raffle_id': id}],
      ['batata_close_live_raffle', {'p_raffle_id': id}],
      ['batata_cancel_live_raffle', {'p_raffle_id': id}],
    ]) {
      final r = await rpc(call[0] as String, token: buyerJwt, body: call[1] as Map);
      notes.add('raffle ${call[0]} ${r['status']} ${r['raw']}');
      if (r['status'] == 200 && (call[0] as String).contains('close')) {
        find('SATB-RAF-CLOSE', 'P1', 'RAFFLE', 'Buyer fechou rifa alheia.', r['raw']);
      }
    }
  }
  final w = await rest('live_raffle_winners', token: buyerJwt, qs: 'select=id,user_id,draw_proof,tickets_at_draw&limit=3');
  notes.add('winners sample ${w['raw']}');
}

Future<void> oversellWithCategory() async {
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final p = await rest('products', method: 'POST', token: sellerJwt, body: {
    'seller_id': sellerId, 'title': '$tag os $stamp', 'price': 5.0, 'quantity': 1,
    'ref_code': 'OS8-$stamp', 'list_on_marketplace': true, 'is_sold': false,
    'image_urls': [], 'category': 'Outros', 'state': 'Bom', 'description': tag,
  });
  notes.add('oversell product ${p['status']} ${p['raw']}');
  String? pid;
  if (p['body'] is List && (p['body'] as List).isNotEmpty) pid = ((p['body'] as List).first as Map)['id']?.toString();
  if (pid == null) return;
  final oids = <String>[];
  for (var i = 0; i < 3; i++) {
    final o = await rest('orders', method: 'POST', token: buyerJwt, body: {
      'buyer_id': buyerId, 'seller_id': sellerId, 'product_id': pid, 'quantity': 1,
      'status': 'reserva_pendente', 'payment_method': 'Pagamento na app', 'shipping_method': 'hand',
    });
    notes.add('oversell order $i ${o['status']} ${o['raw']}');
    if (o['body'] is List && (o['body'] as List).isNotEmpty) {
      oids.add(((o['body'] as List).first as Map)['id'].toString());
    }
  }
  var n = 0;
  for (final oid in oids) {
    final c = await req('POST', '$base/functions/v1/create-payment-intent', token: buyerJwt, body: {
      'buyer_id': buyerId, 'order_id': oid, 'shipping_method': 'hand',
    });
    notes.add('oversell session $oid ${c['status']}');
    if (c['status'] == 200) n++;
  }
  notes.add('oversell sessions=$n of ${oids.length}');
  if (n >= 2) {
    find('SATB-STK-04c', 'P1', 'STOCK', 'Variante 3 vias: $n Sessions em stock=1.', {'n': n, 'oids': oids});
  }
  for (final oid in oids) {
    await rest('orders', method: 'DELETE', token: serviceKey, qs: 'id=eq.$oid');
  }
  await rest('products', method: 'DELETE', token: serviceKey, qs: 'id=eq.$pid');
}

Future<void> cleanupArtifacts() async {
  await rest('reviews', method: 'DELETE', token: serviceKey, qs: 'comment=like.*SATB7*');
  await rest('reviews', method: 'DELETE', token: serviceKey, qs: 'comment=like.*SATB8*');
  await rest('live_reservation_requests', method: 'DELETE', token: serviceKey, qs: 'notes=eq.$tag');
  notes.add('cleanup done');
}
