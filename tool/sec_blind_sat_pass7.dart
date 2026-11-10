// Pass 7 — gaps from pass 1–6. Staging only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const project = 'fxdknzrqjenzqcvnwqqq';
const base = 'https://$project.supabase.co';
const tag = 'SATB7_20260827';

late String anonKey, serviceKey, buyerJwt, sellerJwt, buyerId, sellerId;
String? e2eSecret;
final http = HttpClient();
final findings = <Map<String, dynamic>>[];
final notes = <String>[];
final createdP = <String>[];
final createdO = <String>[];

Future<Map<String, dynamic>> req(String method, String url,
    {String? token, Object? body, Map<String, String>? extra, String? contentType}) async {
  final r = await http.openUrl(method, Uri.parse(url));
  final key = token ?? anonKey;
  r.headers.set('apikey', token == serviceKey ? serviceKey : anonKey);
  r.headers.set('Authorization', 'Bearer $key');
  r.headers.set('Content-Type', contentType ?? 'application/json');
  extra?.forEach(r.headers.set);
  if (method != 'GET' && method != 'DELETE') {
    r.headers.set('Prefer', 'return=representation');
  }
  if (body != null) {
    if (body is List<int>) {
      r.add(body);
    } else {
      r.add(utf8.encode(body is String ? body : jsonEncode(body)));
    }
  }
  final res = await r.close().timeout(const Duration(seconds: 60));
  final raw = await res.transform(utf8.decoder).join();
  Object? parsed;
  try {
    parsed = raw.isEmpty ? null : jsonDecode(raw);
  } catch (_) {
    parsed = raw;
  }
  return {'status': res.statusCode, 'body': parsed, 'raw': raw.length > 2500 ? raw.substring(0, 2500) : raw};
}

Future<Map<String, dynamic>> rest(String t,
    {String method = 'GET', String? token, String qs = 'select=*&limit=8', Object? body}) {
  final q = qs.isEmpty ? '' : '?$qs';
  return req(method, '$base/rest/v1/$t$q', token: token ?? anonKey, body: body);
}

Future<Map<String, dynamic>> rpc(String n, {String? token, Object? body}) =>
    req('POST', '$base/rest/v1/rpc/$n', token: token, body: body ?? {});

Future<Map<String, dynamic>> edge(String n,
    {String method = 'POST', String? token, Object? body, String qs = '', Map<String, String>? extra}) {
  final q = qs.isEmpty ? '' : '?$qs';
  return req(method, '$base/functions/v1/$n$q', token: token, body: body, extra: extra);
}

Future<Map<String, dynamic>?> adminRow(String t, String id) async {
  final r = await rest(t, token: serviceKey, qs: 'id=eq.$id&select=*&limit=1');
  final b = r['body'];
  if (b is List && b.isNotEmpty) return Map<String, dynamic>.from(b.first as Map);
  return null;
}

void find(String id, String sev, String surface, String impact, Object resp,
    {String identity = 'buyer', String variant = '', String fp = '', String pre = '', String after = ''}) {
  findings.add({
    'id': id,
    'sev': sev,
    'surface': surface,
    'impact': impact,
    'identity': identity,
    'response': resp,
    'variant': variant,
    'fp': fp,
    'pre': pre,
    'after': after,
  });
  stderr.writeln('FINDING $sev $id $impact');
}

Future<void> load() async {
  final map = <String, String>{};
  for (final line in File('tool/live_ops_staging.env').readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#') || !t.contains('=')) continue;
    final i = t.indexOf('=');
    map[t.substring(0, i)] = t.substring(i + 1);
  }
  if (!(map['SUPABASE_URL'] ?? '').contains(project)) throw StateError('not staging');
  anonKey = map['SUPABASE_ANON_KEY']!;
  serviceKey = map['SUPABASE_SERVICE_ROLE_KEY']!;
  e2eSecret = map['FLEABER_STAGING_CRASH_INJECT_SECRET'];
  Future<Map> login(String e, String p) async {
    final r = await req('POST', '$base/auth/v1/token?grant_type=password',
        body: {'email': e, 'password': p});
    final b = r['body'] as Map;
    return {'jwt': b['access_token'], 'id': (b['user'] as Map)['id']};
  }

  final b = await login(map['LIVE_OPS_TEST_BUYER_EMAIL']!, map['LIVE_OPS_TEST_BUYER_PASSWORD']!);
  buyerJwt = b['jwt'] as String;
  buyerId = b['id'] as String;
  final s = await login(map['LIVE_OPS_TEST_SELLER_EMAIL']!, map['LIVE_OPS_TEST_SELLER_PASSWORD']!);
  sellerJwt = s['jwt'] as String;
  sellerId = s['id'] as String;
}

Future<Map<String, dynamic>?> e2e(String probe, [Map<String, dynamic> extra = const {}]) async {
  final r = await edge('sec-fase2-e2e-oversell', token: anonKey, extra: {
    'x-fleaber-e2e-secret': e2eSecret ?? '',
  }, body: {'probe': probe, 'buyer_id': buyerId, 'seller_id': sellerId, ...extra});
  final b = r['body'];
  if (b is Map) return Map<String, dynamic>.from(b);
  return {'http': r['status'], 'raw': r['raw']};
}

num bal(Map? w) => num.tryParse('${w?['balance']}') ?? 0;

Future<void> cleanup() async {
  for (final id in createdO) {
    await rest('orders', method: 'DELETE', token: serviceKey, qs: 'id=eq.$id');
  }
  for (final id in createdP) {
    await rest('orders', method: 'DELETE', token: serviceKey, qs: 'product_id=eq.$id');
    await rest('products', method: 'DELETE', token: serviceKey, qs: 'id=eq.$id');
  }
}

Future<void> main() async {
  await load();
  try {
    await testCreditCorrectSig();
    await testReleaseThenRefundClawback();
    await testDoublePayStock1();
    await testStorageMimeAndList();
    await testCrossSelectLeaks();
    await testReviewsStars();
    await testReservationRpc();
    await testStreamKey();
    await testThreeWayOversell();
    await testOpenApiAndRpcs();
    await testWebReturn();
    await testChatForeign();
    await testPriceTotalInsert();
    await testBagSameSku();
    await testPaidSkipEnviado();
  } finally {
    await cleanup();
    http.close(force: true);
  }
  final out = {
    'when': DateTime.now().toUtc().toIso8601String(),
    'findings': findings,
    'notes': notes,
    'p0': findings.where((f) => f['sev'] == 'P0').map((f) => f['id']).toList(),
    'p1': findings.where((f) => f['sev'] == 'P1').map((f) => f['id']).toList(),
  };
  File('tool/reports/SATB_20260827_PASS7.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln(jsonEncode({'n': findings.length, 'p0': out['p0'], 'p1': out['p1']}));
}

Future<void> testCreditCorrectSig() async {
  final wBefore = await adminRow('wallets', buyerId);
  final r = await rpc('batata_credit_wallet_once', token: buyerJwt, body: {
    'p_wallet_id': buyerId,
    'p_order_id': '00000000-0000-0000-0000-000000000001',
    'p_amount': 50,
    'p_type': 'credito',
    'p_description': tag,
  });
  notes.add('credit p_wallet_id ${r['status']} ${r['raw']}');
  final r2 = await rpc('batata_credit_wallet_once', token: buyerJwt, body: {
    'p_wallet_id': sellerId,
    'p_order_id': '00000000-0000-0000-0000-000000000002',
    'p_amount': 50,
    'p_type': 'credito',
    'p_description': tag,
  });
  notes.add('credit seller wallet as buyer ${r2['status']} ${r2['raw']}');
  final debit = await rpc('batata_debit_wallet_once', token: buyerJwt, body: {
    'p_wallet_id': sellerId,
    'p_order_id': '00000000-0000-0000-0000-000000000002',
    'p_amount': 1,
    'p_description': tag,
  });
  notes.add('debit seller as buyer ${debit['status']} ${debit['raw']}');
  final wAfter = await adminRow('wallets', buyerId);
  final wS = await adminRow('wallets', sellerId);
  if (bal(wAfter) > bal(wBefore) + 1) {
    find('SATB-WAL-06', 'P0', 'WALLET', 'JWT credit_wallet_once mintou saldo.', r['raw'],
        after: '${bal(wBefore)}→${bal(wAfter)}');
  }
  if (r['status'] == 200 && r['body'] == true) {
    find('SATB-WAL-06b', 'P0', 'WALLET', 'credit_wallet_once EXECUTE authenticated devolveu true.',
        r['raw']);
  }
  notes.add('wallets after credit buyer=${bal(wAfter)} seller=${bal(wS)}');
}

Future<void> testReleaseThenRefundClawback() async {
  final paid = await e2e('setup_paid_order', {'initial_qty': 2});
  notes.add('clawback fixture $paid');
  final oid = paid?['order_id']?.toString();
  final pid = paid?['product_id']?.toString();
  if (pid != null) createdP.add(pid);
  if (oid == null) return;
  createdO.add(oid);
  final w0 = await adminRow('wallets', sellerId);
  await rest('orders', method: 'PATCH', token: buyerJwt, qs: 'id=eq.$oid', body: {'status': 'concluido'});
  final rel = await rpc('batata_release_seller_wallet_for_order', token: buyerJwt, body: {'p_order_id': oid});
  final w1 = await adminRow('wallets', sellerId);
  notes.add('after release buyer-rpc ${rel['status']} ${rel['raw']} bal ${bal(w0)}→${bal(w1)}');
  final rf = await edge('refund-order', token: sellerJwt, body: {'order_id': oid});
  final w2 = await adminRow('wallets', sellerId);
  notes.add('after refund ${rf['status']} ${rf['raw']} bal ${bal(w1)}→${bal(w2)}');
  final credited = bal(w1) - bal(w0);
  final clawed = bal(w1) - bal(w2);
  if (credited > 0.01 && clawed < credited - 0.05) {
    find(
      'SATB-WAL-CLAW',
      'P0',
      'WALLET',
      'Release + refund Stripe: clawback incompleto — vendedor fica com fundos e comprador reembolsado.',
      {
        'w0': bal(w0),
        'w1': bal(w1),
        'w2': bal(w2),
        'credited': credited,
        'clawed': clawed,
        'refund': rf['raw'],
      },
      identity: 'buyer+seller',
      variant: 'release then stripe refund',
      fp: 'commission retained on purpose / rounding',
      pre: 'paid then buyer concluido+release',
      after: 'seller kept ${bal(w2) - bal(w0)}',
    );
  }
}

Future<void> testDoublePayStock1() async {
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final p = await rest('products', method: 'POST', token: sellerJwt, body: {
    'seller_id': sellerId,
    'title': '$tag race $stamp',
    'price': 5.0,
    'quantity': 1,
    'ref_code': 'SATB7-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': [],
  });
  String? pid;
  final pb = p['body'];
  if (pb is List && pb.isNotEmpty) pid = (pb.first as Map)['id']?.toString();
  if (pid == null) {
    notes.add('doublepay product fail ${p['raw']}');
    return;
  }
  createdP.add(pid);
  Future<String?> order() async {
    final r = await rest('orders', method: 'POST', token: buyerJwt, body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    final b = r['body'];
    String? id;
    if (b is List && b.isNotEmpty) id = (b.first as Map)['id']?.toString();
    if (id != null) createdO.add(id);
    return id;
  }

  final o1 = await order();
  final o2 = await order();
  notes.add('doublepay orders $o1 $o2');
  if (o1 == null || o2 == null) return;

  // Pay both via e2e settle: create two PIs using setup is heavy; use oversell function if probe exists.
  // Direct: two paid fixtures can't share stock=1. Use stripe via e2e by settling two PIs.
  // We'll call setup isn't right. Use PaymentIntent through e2e list? 
  // Alternative: invoke create-payment-intent then fase2? We don't have PI until pay.
  // Use e2e oversell default path if any.
  final ov = await e2e('', {'product_id': pid, 'initial_qty': 1});
  notes.add('e2e default oversell $ov');

  // Service observe stock after attempting two paid orders via two setup_paid_order would create NEW products.
  // Instead POST two fake settles won't work without PI.
  // Variant: 3 checkout sessions
  final c3p = await rest('products', method: 'POST', token: sellerJwt, body: {
    'seller_id': sellerId,
    'title': '$tag 3way $stamp',
    'price': 5.0,
    'quantity': 1,
    'ref_code': 'SATB7-3-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': [],
  });
  String? p3;
  final p3b = c3p['body'];
  if (p3b is List && p3b.isNotEmpty) p3 = (p3b.first as Map)['id']?.toString();
  if (p3 != null) {
    createdP.add(p3);
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      final r = await rest('orders', method: 'POST', token: buyerJwt, body: {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p3,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
      });
      final b = r['body'];
      if (b is List && b.isNotEmpty) {
        ids.add((b.first as Map)['id'].toString());
        createdO.add(ids.last);
      }
    }
    var sessions = 0;
    for (final oid in ids) {
      final c = await edge('create-payment-intent', token: buyerJwt, body: {
        'buyer_id': buyerId,
        'order_id': oid,
        'shipping_method': 'hand',
      });
      notes.add('3way checkout $oid ${c['status']}');
      if (c['status'] == 200) sessions++;
    }
    if (sessions >= 2) {
      find('SATB-STK-04b', 'P1', 'STOCK',
          '3 orders stock=1: $sessions Checkout Sessions criadas (variante 3 vias).',
          {'sessions': sessions, 'orders': ids},
          variant: '3 orders', fp: 'settle refunds extras');
    }
  }
}

Future<void> testStorageMimeAndList() async {
  // 1x1 png
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
  final path = 'order_proofs/$sellerId/$tag-cross.png';
  final up = await req(
    'POST',
    '$base/storage/v1/object/fleaber_private/$path',
    token: buyerJwt,
    body: png,
    contentType: 'image/png',
    extra: {'x-upsert': 'true'},
  );
  notes.add('private png cross ${up['status']} ${up['raw']}');
  if (up['status'] >= 200 && up['status'] < 300) {
    find('SATB-STO-01', 'P1', 'STORAGE', 'Buyer carregou prova no prefixo do vendedor (fleaber_private).',
        up['raw'],
        variant: 'image/png seller prefix');
  }
  final own = 'order_proofs/$buyerId/$tag-own.png';
  final up2 = await req('POST', '$base/storage/v1/object/fleaber_private/$own',
      token: buyerJwt, body: png, contentType: 'image/png', extra: {'x-upsert': 'true'});
  notes.add('private png own ${up2['status']} ${up2['raw']}');

  final listAnon = await req('POST', '$base/storage/v1/object/list/fleaber_private',
      token: anonKey, body: {'prefix': 'order_proofs/', 'limit': 20});
  notes.add('private list anon ${listAnon['status']} ${listAnon['raw']}');
  if (listAnon['status'] == 200 && listAnon['body'] is List && (listAnon['body'] as List).isNotEmpty) {
    find('SATB-STO-02', 'P1', 'STORAGE', 'Anon lista objectos em fleaber_private.', listAnon['raw'],
        identity: 'anon', variant: 'list prefix');
  }

  final listChat = await req('POST', '$base/storage/v1/object/list/chat_media',
      token: anonKey, body: {'prefix': 'order_proofs/', 'limit': 10});
  notes.add('chat_media proofs anon list ${listChat['status']} ${listChat['raw']}');

  final trav = await req('POST', '$base/storage/v1/object/fleaber_private/order_proofs/$buyerId/../$sellerId/x.png',
      token: buyerJwt, body: png, contentType: 'image/png');
  notes.add('path traversal ${trav['status']} ${trav['raw']}');
}

Future<void> testCrossSelectLeaks() async {
  for (final t in [
    'stripe_checkout_events',
    'live_tips',
    'live_raffle_winners',
    'live_reservation_requests',
    'order_disputes',
    'live_raffles',
    'wallet_transactions',
    'product_offers',
  ]) {
    final r = await rest(t, token: buyerJwt, qs: 'select=*&limit=20');
    final b = r['body'];
    notes.add('cross $t ${r['status']} n=${b is List ? b.length : r['raw']}');
    if (b is List && b.isNotEmpty) {
      final sample = Map<String, dynamic>.from(b.first as Map);
      final foreign = b.where((e) {
        if (e is! Map) return false;
        final ids = [
          e['buyer_id'],
          e['user_id'],
          e['wallet_id'],
          e['user_a'],
        ].map((x) => x?.toString()).whereType<String>().toList();
        if (ids.isEmpty) return false;
        return ids.every((x) => x != buyerId);
      }).toList();
      notes.add('cross $t foreign_guess=${foreign.length} keys=${sample.keys.toList()}');
      if (t == 'stripe_checkout_events' && foreign.isNotEmpty) {
        find('SATB-EVT-01', 'P2', 'CHECKOUT', 'Buyer lê stripe_checkout_events de outros.',
            {'n': foreign.length, 'sample': foreign.first}, variant: t);
      }
      if (t == 'live_tips') {
        final others = b.where((e) => e is Map && e['buyer_id'] != buyerId && e['seller_id'] != buyerId).toList();
        if (others.isNotEmpty) {
          find('SATB-TIP-01', 'P2', 'TIPS', 'Buyer lê gorjetas alheias.', {'n': others.length, 'sample': others.first});
        }
      }
      if (t == 'order_disputes') {
        final others = b.where((e) => e is Map && e['buyer_id'] != buyerId).toList();
        if (others.isNotEmpty) {
          find('SATB-DSP-02', 'P1', 'DISPUTE', 'Buyer lê disputas de outros compradores.',
              {'n': others.length, 'sample': others.first});
        }
      }
    }
  }
}

Future<void> testReviewsStars() async {
  final paid = await e2e('setup_paid_order', {'initial_qty': 1});
  final oid = paid?['order_id']?.toString();
  final pid = paid?['product_id']?.toString();
  if (pid != null) createdP.add(pid);
  if (oid == null) return;
  createdO.add(oid);
  await rest('orders', method: 'PATCH', token: buyerJwt, qs: 'id=eq.$oid', body: {'status': 'concluido'});
  final ins = await rest('reviews', method: 'POST', token: buyerJwt, body: {
    'order_id': oid,
    'buyer_id': buyerId,
    'target_id': sellerId,
    'stars': 5,
    'comment': tag,
    'author_role': 'buyer',
    'target_type': 'seller',
  });
  notes.add('review paid concluido ${ins['status']} ${ins['raw']}');
  final spoof = await rest('reviews', method: 'POST', token: buyerJwt, body: {
    'order_id': oid,
    'buyer_id': sellerId,
    'target_id': buyerId,
    'stars': 1,
    'comment': '$tag spoof',
  });
  notes.add('review spoof buyer_id ${spoof['status']} ${spoof['raw']}');
  if (spoof['status'] >= 200 && spoof['status'] < 300) {
    find('SATB-REV-02', 'P1', 'REVIEWS', 'Buyer insere review com buyer_id=seller.', spoof['raw']);
  }
  // duplicate
  final dup = await rest('reviews', method: 'POST', token: buyerJwt, body: {
    'order_id': oid,
    'buyer_id': buyerId,
    'target_id': sellerId,
    'stars': 1,
    'comment': '$tag dup',
  });
  notes.add('review dup ${dup['status']} ${dup['raw']}');
  if (dup['status'] >= 200 && dup['status'] < 300 && ins['status'] >= 200 && ins['status'] < 300) {
    find('SATB-REV-03', 'P1', 'REVIEWS', 'Review duplicada na mesma order.', dup['raw']);
  }
}

Future<void> testReservationRpc() async {
  final items = await rest('live_items', token: sellerJwt, qs: 'select=id,live_id,status&limit=3');
  notes.add('live_items seller ${items['status']} ${items['raw']}');
  final b = items['body'];
  if (b is! List || b.isEmpty) {
    notes.add('no live items for reservation rpc');
    return;
  }
  final li = b.first as Map;
  for (final name in [
    'batata_process_live_reservation_request',
    'batata_live_reservation_queue_for_live',
    'batata_live_item_stock',
  ]) {
    final r = await rpc(name, token: buyerJwt, body: {
      'p_live_item_id': li['id'],
      'p_requested_qty': 9,
      'p_live_id': li['live_id'],
    });
    notes.add('res rpc $name ${r['status']} ${r['raw']}');
  }
  final ins = await rest('live_reservation_requests', method: 'POST', token: buyerJwt, body: {
    'live_id': li['live_id'],
    'live_item_id': li['id'],
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 9,
    'status': 'accepted',
    'source': 'fleaber_live',
  });
  notes.add('res insert real live ${ins['status']} ${ins['raw']}');
  if (ins['status'] >= 200 && ins['status'] < 300) {
    final row = (ins['body'] is List && (ins['body'] as List).isNotEmpty)
        ? (ins['body'] as List).first
        : ins['body'];
    final qty = row is Map ? row['requested_qty'] : null;
    final st = row is Map ? row['status'] : null;
    if (st == 'accepted' || (qty is num && qty >= 9)) {
      find('SATB-RES-01', 'P1', 'RESERVATIONS', 'INSERT directo accepted/qty alto em live real.',
          ins['raw'],
          variant: 'real live_item');
    }
  }
}

Future<void> testStreamKey() async {
  final own = await rest('lives', token: sellerJwt, qs: 'select=id,mux_stream_key,stream_key,status,seller_id&limit=5');
  notes.add('lives seller ${own['status']} ${own['raw']}');
  final buy = await rest('lives', token: buyerJwt, qs: 'select=id,mux_stream_key,stream_key,status&limit=5');
  notes.add('lives buyer ${buy['status']} ${buy['raw']}');
  if (own['body'] is List) {
    for (final row in own['body'] as List) {
      if (row is Map) {
        final k = (row['mux_stream_key'] ?? row['stream_key'] ?? '').toString();
        if (k.isNotEmpty) {
          notes.add('seller can read own stream_key len=${k.length} live=${row['id']}');
          // buyer get that id
          final x = await rest('lives', token: buyerJwt, qs: 'id=eq.${row['id']}&select=id,mux_stream_key,stream_key');
          notes.add('buyer get live by id ${x['status']} ${x['raw']}');
          if (x['body'] is List && (x['body'] as List).isNotEmpty) {
            final r2 = (x['body'] as List).first as Map;
            final k2 = (r2['mux_stream_key'] ?? r2['stream_key'] ?? '').toString();
            if (k2.isNotEmpty) {
              find('SATB-MUX-01', 'P0', 'MUX', 'Buyer lê stream_key de live alheia.', x['raw']);
            }
          }
          break;
        }
      }
    }
  }
  final svc = await rest('lives', token: serviceKey, qs: 'mux_stream_key=not.is.null&select=id,seller_id,status&limit=1');
  notes.add('svc live with key ${svc['raw']}');
}

Future<void> testThreeWayOversell() async {
  // already in double pay
}

Future<void> testOpenApiAndRpcs() async {
  final r = await req('GET', '$base/rest/v1/', token: anonKey, extra: {
    'Accept': 'application/openapi+json',
  });
  notes.add('openapi status=${r['status']} type=${r['body'].runtimeType} len=${r['raw'].length}');
  final r2 = await req('GET', '$base/rest/v1/', token: serviceKey, extra: {
    'Accept': 'application/openapi+json',
  });
  var rpcN = 0;
  final body = r2['body'];
  if (body is Map && body['paths'] is Map) {
    final names = <String>[];
    for (final p in (body['paths'] as Map).keys) {
      final s = p.toString();
      if (s.startsWith('/rpc/')) names.add(s.substring(5));
    }
    rpcN = names.length;
    notes.add('openapi service rpcs=$rpcN sample=${names.take(30).toList()}');
    for (final n in names) {
      final x = n.toLowerCase();
      if (x.contains('credit') ||
          x.contains('debit') ||
          x.contains('payout') ||
          x.contains('admin') ||
          x.contains('lab') ||
          x.contains('nuke') ||
          x.contains('clawback') ||
          x.contains('settle')) {
        final a = await rpc(n, token: buyerJwt, body: {});
        notes.add('rpc7 $n buyer=${a['status']} ${a['raw']}');
      }
    }
  } else {
    notes.add('openapi service not map ${r2['status']}');
  }
}

Future<void> testWebReturn() async {
  final pidStamp = DateTime.now().millisecondsSinceEpoch;
  final p = await rest('products', method: 'POST', token: sellerJwt, body: {
    'seller_id': sellerId,
    'title': '$tag wr $pidStamp',
    'price': 5.0,
    'quantity': 1,
    'ref_code': 'WR-$pidStamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': [],
  });
  String? pid;
  if (p['body'] is List && (p['body'] as List).isNotEmpty) {
    pid = ((p['body'] as List).first as Map)['id']?.toString();
  }
  if (pid == null) return;
  createdP.add(pid);
  final o = await rest('orders', method: 'POST', token: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'hand',
  });
  String? oid;
  if (o['body'] is List && (o['body'] as List).isNotEmpty) {
    oid = ((o['body'] as List).first as Map)['id']?.toString();
  }
  if (oid == null) return;
  createdO.add(oid);
  for (final origin in [
    'https://evil.com',
    'https://fleaber.pt.evil.com',
    'https://evil.fleaber.pt',
    'http://fleaber.pt',
    'https://fleaber.pt/\\t@evil.com',
  ]) {
    final c = await edge('create-payment-intent', token: buyerJwt, body: {
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': 'hand',
      'web_return_origin': origin,
    });
    notes.add('web_return $origin ${c['status']} ${c['raw']}');
  }
}

Future<void> testChatForeign() async {
  final all = await rest('chats', token: serviceKey, qs: 'select=id,user_a,user_b&limit=30');
  if (all['body'] is! List) return;
  for (final c in all['body'] as List) {
    if (c is! Map) continue;
    if (c['user_a'] != buyerId && c['user_b'] != buyerId) {
      final m = await rest('chat_messages', token: buyerJwt, qs: 'chat_id=eq.${c['id']}&select=id,text,sender_id&limit=3');
      notes.add('foreign chat ${c['id']} ${m['status']} n=${m['body'] is List ? (m['body'] as List).length : m['raw']}');
      if (m['status'] == 200 && m['body'] is List && (m['body'] as List).isNotEmpty) {
        find('SATB-CHAT-04', 'P1', 'CHAT', 'Buyer lê mensagens de chat alheio.', m['raw']);
      }
      final ins = await rest('chat_messages', method: 'POST', token: buyerJwt, body: {
        'chat_id': c['id'],
        'sender_id': buyerId,
        'receiver_id': c['user_a'],
        'text': tag,
      });
      notes.add('inject foreign chat ${ins['status']} ${ins['raw']}');
      if (ins['status'] >= 200 && ins['status'] < 300) {
        find('SATB-CHAT-05', 'P1', 'CHAT', 'Buyer injeta mensagem em chat alheio.', ins['raw']);
      }
      break;
    }
  }
}

Future<void> testPriceTotalInsert() async {
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final p = await rest('products', method: 'POST', token: sellerJwt, body: {
    'seller_id': sellerId,
    'title': '$tag pt $stamp',
    'price': 8.5,
    'quantity': 2,
    'ref_code': 'PT-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': [],
  });
  String? pid;
  if (p['body'] is List && (p['body'] as List).isNotEmpty) {
    pid = ((p['body'] as List).first as Map)['id']?.toString();
  }
  if (pid == null) return;
  createdP.add(pid);
  final o = await rest('orders', method: 'POST', token: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'hand',
    'price_total': 0.01,
  });
  notes.add('price_total 0.01 insert ${o['status']} ${o['raw']}');
  String? oid;
  if (o['body'] is List && (o['body'] as List).isNotEmpty) {
    oid = ((o['body'] as List).first as Map)['id']?.toString();
  }
  if (oid == null) return;
  createdO.add(oid);
  final live = await adminRow('orders', oid);
  notes.add('price_total persisted ${live?['price_total']} contract=${live?['contract_unit_cents']}');
  final co = await edge('create-payment-intent', token: buyerJwt, body: {
    'buyer_id': buyerId,
    'order_id': oid,
    'shipping_method': 'hand',
  });
  notes.add('checkout after price_total 0.01 ${co['status']} ${co['raw']}');
  if (co['status'] == 200) {
    final amt = int.tryParse('${(co['body'] as Map?)?['server_amount_cents']}');
    if (amt != null && amt < 100) {
      find('SATB-PRC-PT', 'P0', 'PRICING', 'price_total JWT 0.01 ditou o checkout.', co['raw']);
    }
  }
}

Future<void> testBagSameSku() async {
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final p = await rest('products', method: 'POST', token: sellerJwt, body: {
    'seller_id': sellerId,
    'title': '$tag sku $stamp',
    'price': 3.0,
    'quantity': 1,
    'ref_code': 'SKU-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': [],
  });
  String? pid;
  if (p['body'] is List && (p['body'] as List).isNotEmpty) {
    pid = ((p['body'] as List).first as Map)['id']?.toString();
  }
  if (pid == null) return;
  createdP.add(pid);
  final oids = <String>[];
  for (var i = 0; i < 2; i++) {
    final o = await rest('orders', method: 'POST', token: buyerJwt, body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
    });
    if (o['body'] is List && (o['body'] as List).isNotEmpty) {
      oids.add(((o['body'] as List).first as Map)['id'].toString());
      createdO.add(oids.last);
    }
  }
  if (oids.length < 2) {
    notes.add('bag same sku only ${oids.length} orders');
    return;
  }
  final bag = await edge('create-payment-intent', token: buyerJwt, body: {
    'buyer_id': buyerId,
    'order_id': oids.first,
    'bag_checkout': true,
    'shipping_method': 'hand',
    'bag_lines': [
      {'order_id': oids[0]},
      {'order_id': oids[1]},
    ],
  });
  notes.add('bag same sku qty1+1 stock1 ${bag['status']} ${bag['raw']}');
  if (bag['status'] == 200) {
    find('SATB-BAG-SKU', 'P1', 'BAG', 'Saco com 2 linhas do mesmo SKU stock=1 criou Session.', bag['raw'],
        variant: 'same SKU', fp: 'settle oversell refund');
  }
}

Future<void> testPaidSkipEnviado() async {
  final paid = await e2e('setup_paid_order', {'initial_qty': 1});
  final oid = paid?['order_id']?.toString();
  final pid = paid?['product_id']?.toString();
  if (pid != null) createdP.add(pid);
  if (oid == null) return;
  createdO.add(oid);
  final before = await adminRow('orders', oid);
  final r = await rest('orders', method: 'PATCH', token: buyerJwt, qs: 'id=eq.$oid', body: {'status': 'concluido'});
  final after = await adminRow('orders', oid);
  notes.add('pago→concluido skip enviado ${before?['status']}→${after?['status']} ${r['status']}');
  // seller devolvida direct
  final dv = await rest('orders', method: 'PATCH', token: sellerJwt, qs: 'id=eq.$oid', body: {'status': 'devolvida'});
  final after2 = await adminRow('orders', oid);
  notes.add('seller devolvida from ${after?['status']} → ${after2?['status']} ${dv['status']} ${dv['raw']}');
}
