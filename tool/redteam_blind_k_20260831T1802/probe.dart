// ignore_for_file: avoid_print
/// REDTEAM_BLIND_K_POS_HIJ_v1 — dart run tool/redteam_blind_k_20260831T1802/probe.dart
/// Staging only. No production. No SQL/Edge/Flutter patches.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../live_ops_staging_client.dart';

const stamp = 'RTK-20260831T1802';
final frozenAt = DateTime.now().toUtc().toIso8601String();

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  late http.Response r;
  if (method == 'POST') {
    r = await http.post(Uri.parse(u),
        headers: h, body: body == null ? null : jsonEncode(body));
  } else if (method == 'PATCH') {
    r = await http.patch(Uri.parse(u),
        headers: h, body: body == null ? null : jsonEncode(body));
  } else if (method == 'DELETE') {
    r = await http.delete(Uri.parse(u), headers: h);
  } else {
    r = await http.get(Uri.parse(u), headers: h);
  }
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  if (body is Map) {
    for (final k in ['id', 'order_id', 'chat_id', 'message_id']) {
      final s = '${body[k] ?? ''}'.trim();
      if (s.isNotEmpty && s != 'null') return s;
    }
  }
  return null;
}

Map<String, dynamic>? firstMap(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

double balOf(dynamic body) {
  final m = firstMap(body);
  return (m?['balance'] as num?)?.toDouble() ?? double.nan;
}

String jsonCard(String kind, [Map<String, dynamic>? extra]) {
  final m = <String, dynamic>{'kind': kind, ...?extra};
  return 'FLEABER_JSON_V1:${jsonEncode(m)}';
}

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT not staging');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  Map<String, String> H(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = H(buyerTok);
  final SH = H(sellerTok);
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (crashSecret.length >= 16) 'x-fleaber-e2e-secret': crashSecret,
  };

  // ---- 2.º buyer / 2.º seller (fixture) ----
  final pass2 = 'RtkK!2026-kpos';
  Future<({String id, String jwt})> ensureUser(String email, String name) async {
    final created = await req(
      'POST',
      '$url/auth/v1/admin/users',
      {
        'apikey': svc,
        'Authorization': 'Bearer $svc',
        'Content-Type': 'application/json',
      },
      {
        'email': email,
        'password': pass2,
        'email_confirm': true,
        'user_metadata': {'full_name': name},
      },
    );
    String id = '${firstMap(created['body'])?['id'] ?? ''}'.trim();
    if (id.isEmpty) {
      final listed = await req(
        'GET',
        '$url/auth/v1/admin/users?page=1&per_page=200',
        {'apikey': svc, 'Authorization': 'Bearer $svc'},
      );
      if (listed['body'] is Map && (listed['body'] as Map)['users'] is List) {
        for (final u in (listed['body'] as Map)['users'] as List) {
          if (u is Map && '${u['email']}' == email) {
            id = '${u['id']}';
            break;
          }
        }
      }
    }
    if (id.isEmpty) throw StateError('no user $email ${created['http']}');
    await req('POST', '$url/rest/v1/profiles', SVC, {
      'id': id,
      'display_name': name,
      'user_type': 'particular',
    });
    await req('POST', '$url/rest/v1/wallets', SVC, {'id': id, 'balance': 0});
    final tok = await sb.signIn(email: email, password: pass2);
    return (id: id, jwt: tok);
  }

  final b2 = await ensureUser('rtk-k-b2-$stamp@fleaber.invalid', 'RTK B2');
  final s2 = await ensureUser('rtk-k-s2-$stamp@fleaber.invalid', 'RTK S2');
  final B2H = H(b2.jwt);
  final S2H = H(s2.jwt);

  final findings = <Map<String, dynamic>>[];
  final notes = <String, dynamic>{};
  void find({
    required String id,
    required String lens,
    required String actor,
    required String title,
    required List<String> steps,
    required String expected,
    required String got,
    required String severity,
    Map<String, dynamic>? proof,
  }) {
    findings.add({
      'id': id,
      'lente': lens,
      'actor': actor,
      'title': title,
      'passos': steps,
      'esperado': expected,
      'obtido': got,
      'severidade': severity,
      'prova': proof ?? {},
    });
    stdout.writeln('[$severity] $id $lens $title — $got');
  }

  Future<double> wallet(String uid) async {
    final r = await req(
        'GET', '$url/rest/v1/wallets?id=eq.$uid&select=id,balance', SVC);
    return balOf(r['body']);
  }

  Future<Map<String, dynamic>?> orderRow(String oid) async {
    final r = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=id,status,buyer_id,seller_id,product_id,quantity,price_total,amount_paid_cents,payment_method,shipping_method,stripe_payment_intent_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied',
      SVC,
    );
    return firstMap(r['body']);
  }

  Future<List<dynamic>> txs(String oid) async {
    final r = await req(
      'GET',
      '$url/rest/v1/wallet_transactions?order_id=eq.$oid&select=id,wallet_id,amount,type,description',
      SVC,
    );
    return r['body'] is List ? r['body'] as List : [];
  }

  Future<Map<String, dynamic>> e2ePaid({
    required String bid,
    required String sid,
  }) async {
    return req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
      'buyer_id': bid,
      'seller_id': sid,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
    });
  }

  Future<Map<String, dynamic>> edge(
    String fn,
    Map<String, dynamic> body,
    Map<String, String> h,
  ) {
    return req('POST', '$url/functions/v1/$fn', {
      'apikey': h['apikey']!,
      'Authorization': h['Authorization']!,
      'Content-Type': 'application/json',
    }, body);
  }

  // =====================================================================
  // K4 / K5 — chat plain→JSON + imutável + recibo unpaid
  // =====================================================================
  final prodHold = firstMap((await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': '$stamp hold chat',
    'price': 4.2,
    'quantity': 3,
    'ref_code': '$stamp-HOLD',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': [],
  }))['body']);
  final holdPid = '${prodHold?['id'] ?? ''}';

  final holdOrd = firstMap((await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': holdPid,
    'price_total': 4.2,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
  }))['body']);
  final holdOid = '${holdOrd?['id'] ?? ''}';
  notes['hold_order'] = {'id': holdOid, 'http_insert': holdOrd};

  final chatRow = firstMap((await req('POST', '$url/rest/v1/chats', SVC, {
    'user_a': buyerId,
    'user_b': sellerId,
    'product_id': holdPid,
    'last_message': stamp,
  }))['body']);
  var chatId = '${chatRow?['id'] ?? ''}';
  if (chatId.isEmpty) {
    final existing = firstMap((await req(
      'GET',
      '$url/rest/v1/chats?or=(and(user_a.eq.$buyerId,user_b.eq.$sellerId),and(user_a.eq.$sellerId,user_b.eq.$buyerId))&select=id&limit=1',
      SVC,
    ))['body']);
    chatId = '${existing?['id'] ?? ''}';
  }
  notes['chat_id'] = chatId;

  Future<Map<String, dynamic>> insMsg(
    Map<String, String> h,
    String text, {
    String? sender,
  }) {
    return req('POST', '$url/rest/v1/chat_messages', h, {
      'chat_id': chatId,
      'sender_id': sender ?? '00000000-0000-0000-0000-000000000099',
      'text': text,
      'is_read': false,
    });
  }

  // K4 — INSERT server kinds
  for (final kind in [
    'order_paid',
    'marketplace_bag_paid',
    'auto_feedback_generated',
    'raffle_prize',
    'premio_rifa',
  ]) {
    final r = await insMsg(
        BH, jsonCard(kind, {'order_id': holdOid, 'total': 99.0}));
    final blocked = (r['http'] as int) >= 400;
    find(
      id: 'K4-INS-$kind',
      lens: 'K4',
      actor: 'buyer JWT',
      title: 'INSERT kind servidor $kind',
      steps: ['POST chat_messages FLEABER_JSON_V1 kind=$kind order unpaid'],
      expected: 'HTTP ≥400 / chat_system_card_server_only',
      got: 'HTTP ${r['http']} ${(r['text'] as String).length > 220 ? (r['text'] as String).substring(0, 220) : r['text']}',
      severity: blocked ? 'INFO' : 'P1',
      proof: {'http': r['http'], 'body': r['body']},
    );
  }

  // K4 — seguro_fleaber_paid on unpaid hold
  final segUnpaid = await insMsg(
    BH,
    jsonCard('seguro_fleaber_paid', {
      'order_id': holdOid,
      'total': 8888.88,
    }),
  );
  find(
    id: 'K4-INS-seguro-unpaid',
    lens: 'K4',
    actor: 'buyer JWT',
    title: 'INSERT seguro_fleaber_paid em hold não pago',
    steps: [
      'JWT buyer INSERT card seguro_fleaber_paid na encomenda reserva_pendente sem PI',
    ],
    expected: 'HTTP ≥400 chat_system_card_order_not_paid',
    got: 'HTTP ${segUnpaid['http']} ${segUnpaid['text']}',
    severity: (segUnpaid['http'] as int) >= 400 ? 'INFO' : 'P1',
    proof: {'http': segUnpaid['http'], 'body': segUnpaid['body'], 'order': holdOid},
  );

  // K4 — seller tries buyer-only kind
  final segSeller = await insMsg(
    SH,
    jsonCard('seguro_fleaber_paid', {'order_id': holdOid}),
  );
  find(
    id: 'K4-INS-seguro-seller',
    lens: 'K4',
    actor: 'seller JWT',
    title: 'Vendedor INSERT seguro_fleaber_paid (buyer-only)',
    steps: ['POST chat_messages JWT seller kind=seguro_fleaber_paid'],
    expected: 'HTTP ≥400',
    got: 'HTTP ${segSeller['http']} ${segSeller['text']}',
    severity: (segSeller['http'] as int) >= 400 ? 'INFO' : 'P1',
    proof: {'http': segSeller['http'], 'body': segSeller['body']},
  );

  // K4 — buyer2 not participant
  final b2ins = await req('POST', '$url/rest/v1/chat_messages', B2H, {
    'chat_id': chatId,
    'sender_id': b2.id,
    'text': jsonCard('seguro_fleaber_paid', {'order_id': holdOid}),
    'is_read': false,
  });
  find(
    id: 'K4-INS-b2-cross',
    lens: 'K4',
    actor: '2.º buyer JWT',
    title: 'buyer2 INSERT no chat alheio',
    steps: ['POST chat_messages chat de B1/S1 com JWT B2'],
    expected: 'HTTP ≥400 RLS',
    got: 'HTTP ${b2ins['http']} ${b2ins['text']}',
    severity: (b2ins['http'] as int) >= 400 ? 'INFO' : 'P1',
    proof: {'http': b2ins['http'], 'body': b2ins['body']},
  );

  // K4 — anon
  final anonIns = await insMsg(ANON, 'hello anon');
  find(
    id: 'K4-INS-anon',
    lens: 'K4',
    actor: 'anon',
    title: 'anon INSERT chat_messages',
    steps: ['POST chat_messages Authorization=anon'],
    expected: 'HTTP ≥400',
    got: 'HTTP ${anonIns['http']}',
    severity: (anonIns['http'] as int) >= 400 ? 'INFO' : 'P2',
    proof: {'http': anonIns['http'], 'body': anonIns['body']},
  );

  // K4 — plain → JSON server kind (P1 J)
  final plain = await insMsg(BH, 'rtk-plain-$stamp');
  final plainId = idOf(plain['body']);
  notes['plain_msg'] = {'id': plainId, 'http': plain['http']};
  Map<String, dynamic>? plainToJson;
  if (plainId != null) {
    plainToJson = await req(
      'PATCH',
      '$url/rest/v1/chat_messages?id=eq.$plainId',
      BH,
      {
        'text': jsonCard('marketplace_bag_paid', {
          'order_id': holdOid,
          'total': 42.0,
        }),
      },
    );
    find(
      id: 'K4-UPD-plain-to-server-kind',
      lens: 'K4',
      actor: 'buyer JWT',
      title: 'UPDATE plain → JSON kind servidor',
      steps: [
        'INSERT texto simples',
        'PATCH text=FLEABER_JSON_V1 marketplace_bag_paid',
      ],
      expected: 'HTTP ≥400 mesmas regras INSERT',
      got: 'HTTP ${plainToJson['http']} ${plainToJson['text']}',
      severity: (plainToJson['http'] as int) >= 400 ? 'INFO' : 'P1',
      proof: {
        'msg': plainId,
        'http': plainToJson['http'],
        'body': plainToJson['body']
      },
    );

    final p2seg = await req(
      'PATCH',
      '$url/rest/v1/chat_messages?id=eq.$plainId',
      BH,
      {
        'text': jsonCard('seguro_fleaber_paid', {
          'order_id': holdOid,
          'total': 77.0,
        }),
      },
    );
    find(
      id: 'K4-UPD-plain-to-seguro-unpaid',
      lens: 'K4',
      actor: 'buyer JWT',
      title: 'UPDATE plain → seguro_fleaber_paid unpaid',
      steps: ['PATCH da mensagem plain para card seguro em hold não pago'],
      expected: 'HTTP ≥400 order_not_paid',
      got: 'HTTP ${p2seg['http']} ${p2seg['text']}',
      severity: (p2seg['http'] as int) >= 400 ? 'INFO' : 'P1',
      proof: {'http': p2seg['http'], 'body': p2seg['body']},
    );
  }

  // K5 — JSON already stored is immutable
  final okJson = await insMsg(BH, jsonCard('price_offer', {
    'order_id': holdOid,
    'amount': 1.0,
  }));
  final jsonMsgId = idOf(okJson['body']);
  notes['json_msg'] = {'id': jsonMsgId, 'http': okJson['http'], 'body': okJson['body']};
  if (jsonMsgId != null) {
    final mut = await req(
      'PATCH',
      '$url/rest/v1/chat_messages?id=eq.$jsonMsgId',
      BH,
      {
        'text': jsonCard('seguro_fleaber_paid', {
          'order_id': holdOid,
          'total': 1.0,
        }),
      },
    );
    find(
      id: 'K5-UPD-json-immutable',
      lens: 'K5',
      actor: 'buyer JWT',
      title: 'UPDATE JSON já gravado',
      steps: [
        'INSERT JSON price_offer (allowlist)',
        'PATCH para seguro_fleaber_paid',
      ],
      expected: 'HTTP ≥400 chat_system_card_immutable',
      got: 'HTTP ${mut['http']} ${mut['text']}',
      severity: (mut['http'] as int) >= 400 ? 'INFO' : 'P1',
      proof: {'http': mut['http'], 'body': mut['body'], 'msg': jsonMsgId},
    );

    final sellerMut = await req(
      'PATCH',
      '$url/rest/v1/chat_messages?id=eq.$jsonMsgId',
      SH,
      {'text': 'hijack'},
    );
    final still = firstMap((await req(
      'GET',
      '$url/rest/v1/chat_messages?id=eq.$jsonMsgId&select=id,text,sender_id',
      SVC,
    ))['body']);
    final textStillJson =
        '${still?['text'] ?? ''}'.startsWith('FLEABER_JSON_V1:');
    find(
      id: 'K5-UPD-json-by-counterparty',
      lens: 'K5',
      actor: 'seller JWT',
      title: 'Contraparte tenta alterar JSON do comprador',
      steps: ['PATCH mensagem JSON alheia text=hijack'],
      expected: 'texto inalterado',
      got:
          'HTTP ${sellerMut['http']} still_json=$textStillJson text=${still?['text']}',
      severity: textStillJson ? 'INFO' : 'P1',
      proof: {
        'http': sellerMut['http'],
        'row': still,
        'patch_body': sellerMut['body']
      },
    );
  }

  // K4 — prefix / kind tricks
  final bom = await insMsg(
    BH,
    '\uFEFFFLEABER_JSON_V1:${jsonEncode({
          'kind': 'order_paid',
          'order_id': holdOid,
        })}',
  );
  notes['bom_insert'] = {'http': bom['http'], 'id': idOf(bom['body'])};

  final lower = await insMsg(
    BH,
    'fleaber_json_v1:${jsonEncode({'kind': 'order_paid'})}',
  );
  notes['lower_prefix'] = {'http': lower['http'], 'id': idOf(lower['body'])};

  // =====================================================================
  // K6 — off-platform pago sem captura → recibo seguro?
  // =====================================================================
  final maoProd = firstMap((await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': '$stamp mao',
    'price': 3.5,
    'quantity': 2,
    'ref_code': '$stamp-MAO',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': [],
  }))['body']);
  final maoPid = '${maoProd?['id'] ?? ''}';
  final maoOrd = firstMap((await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': maoPid,
    'price_total': 3.5,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
    'shipping_method': 'mao',
  }))['body']);
  var maoOid = '${maoOrd?['id'] ?? ''}';
  if (maoOid.isEmpty || maoOid == 'null') {
    final svcMao = firstMap((await req('POST', '$url/rest/v1/orders', SVC, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': maoPid,
      'price_total': 3.5,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
      'shipping_method': 'mao',
    }))['body']);
    maoOid = '${svcMao?['id'] ?? ''}';
  }
  notes['mao_order'] = {'id': maoOid, 'insert': maoOrd};

  if (maoOid.isNotEmpty && maoOid != 'null') {
    final toPago = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$maoOid',
      SH,
      {'status': 'pago'},
    );
    final maoAfterPago = await orderRow(maoOid);
    notes['mao_pago'] = {'patch': toPago['http'], 'row': maoAfterPago};

    final segMao = await insMsg(
      BH,
      jsonCard('seguro_fleaber_paid', {
        'order_id': maoOid,
        'total': 3.5,
      }),
    );
    final maoStatus = '${maoAfterPago?['status'] ?? ''}';
    final forged = (segMao['http'] as int) < 400 && maoStatus == 'pago';
    find(
      id: 'K6-INS-seguro-on-mao-pago',
      lens: 'K6',
      actor: 'buyer JWT',
      title: 'Recibo Seguro Fleaber em encomenda MB WAY marcada pago sem captura',
      steps: [
        'Hold MB WAY / mão',
        'Seller PATCH status=pago (off-platform, sem PI)',
        'Buyer INSERT seguro_fleaber_paid',
      ],
      expected:
          'Card seguro recusado (não é pagamento plataforma) OU status não chega a pago',
      got:
          'pago_http=${toPago['http']} status=$maoStatus seguro_http=${segMao['http']} ${segMao['text']}',
      severity: forged ? 'P1' : 'INFO',
      proof: {
        'pago_http': toPago['http'],
        'order': maoAfterPago,
        'seguro_http': segMao['http'],
        'seguro_body': segMao['body'],
        'msg_id': idOf(segMao['body']),
      },
    );
  }

  // =====================================================================
  // Money path — Stripe TEST paid
  // =====================================================================
  Future<String?> paidOrder(String bid, String sid, String tag) async {
    final paid = await e2ePaid(bid: bid, sid: sid);
    notes['paid_$tag'] = {
      'http': paid['http'],
      'body_clip': '${paid['text']}'.substring(
          0, (paid['text'] as String).length.clamp(0, 500)),
    };
    var oid = idOf(paid['body']);
    if (oid == null && paid['body'] is Map) {
      final m = paid['body'] as Map;
      oid = '${m['order_id'] ?? m['id'] ?? ''}'.trim();
      if (oid.isEmpty || oid == 'null') oid = null;
    }
    return oid;
  }

  // K3 — refund-order while still pago (legitimate)
  final k3Oid = await paidOrder(buyerId, sellerId, 'k3_pago');
  Map<String, dynamic>? k3Before;
  Map<String, dynamic>? k3Refund;
  Map<String, dynamic>? k3After;
  if (k3Oid != null) {
    k3Before = await orderRow(k3Oid);
    k3Refund = await edge('refund-order', {'order_id': k3Oid}, SH);
    k3After = await orderRow(k3Oid);
    final refundOk = (k3Refund['http'] as int) == 200 &&
        (k3Refund['body'] is Map) &&
        (k3Refund['body'] as Map)['ok'] == true;
    final hasRf = '${k3After?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty;
    find(
      id: 'K3-refund-while-pago',
      lens: 'K3',
      actor: 'seller JWT',
      title: 'refund-order Stripe TEST ainda em pago (anti-regressão)',
      steps: [
        'setup_paid_order Stripe TEST 5,90 €',
        'POST refund-order JWT vendedor enquanto status=pago',
      ],
      expected: 'ok=true + stripe_refund_id gravado',
      got:
          'HTTP ${k3Refund['http']} ok=${k3Refund['body'] is Map ? (k3Refund['body'] as Map)['ok'] : null} refund_id=${k3After?['stripe_refund_id']} status=${k3After?['status']}',
      severity: (refundOk && hasRf) ? 'INFO' : 'P1',
      proof: {
        'order': k3Oid,
        'before': k3Before,
        'edge': k3Refund['body'],
        'after': k3After,
      },
    );

    // buyer / seller2 must not refund
    final bRef = await edge('refund-order', {'order_id': k3Oid}, BH);
    find(
      id: 'K3-refund-buyer-forbidden',
      lens: 'K3',
      actor: 'buyer JWT',
      title: 'Comprador chama refund-order',
      steps: ['POST refund-order JWT buyer'],
      expected: '403 Sem permissão',
      got: 'HTTP ${bRef['http']} ${bRef['text']}',
      severity: (bRef['http'] as int) == 403 ? 'INFO' : 'P1',
      proof: {'http': bRef['http'], 'body': bRef['body']},
    );
    final s2Ref = await edge('refund-order', {'order_id': k3Oid}, S2H);
    find(
      id: 'K3-refund-s2-forbidden',
      lens: 'K3',
      actor: '2.º seller JWT',
      title: 'seller2 refund-order da encomenda de S1',
      steps: ['POST refund-order JWT seller2'],
      expected: '403',
      got: 'HTTP ${s2Ref['http']} ${s2Ref['text']}',
      severity: (s2Ref['http'] as int) == 403 ? 'INFO' : 'P1',
      proof: {'http': s2Ref['http'], 'body': s2Ref['body']},
    );
  }

  // K1/K2/K7 — paid → enviado → concluido → release → drain → devolvida
  final k1Oid = await paidOrder(buyerId, sellerId, 'k1_release');
  Map<String, dynamic> k1books = {};
  if (k1Oid != null) {
    final envio = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$k1Oid',
      SH,
      {'status': 'enviado'},
    );
    final conc = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$k1Oid',
      BH,
      {'status': 'concluido'},
    );
    notes['k1_status'] = {
      'envio': envio['http'],
      'envio_body': envio['body'],
      'concluido': conc['http'],
      'concluido_body': conc['body'],
      'row': await orderRow(k1Oid),
    };

    final sBalPreRel = await wallet(sellerId);
    final bBalPreRel = await wallet(buyerId);
    final rel = await req(
      'POST',
      '$url/rest/v1/rpc/batata_release_seller_wallet_for_order',
      BH,
      {'p_order_id': k1Oid},
    );
    final sBalPostRel = await wallet(sellerId);
    final credited = sBalPostRel - sBalPreRel;

    // K3 after release (concluido): should be blocked
    final refAfterRel = await edge('refund-order', {'order_id': k1Oid}, SH);
    find(
      id: 'K3-refund-after-release-concluido',
      lens: 'K3',
      actor: 'seller JWT',
      title: 'refund-order após concluido/release',
      steps: [
        'pago→enviado→concluido→release',
        'POST refund-order',
      ],
      expected:
          '403 order_refund_blocked_status (D0733) — recuperação via devolvida+Stripe, não anular envio',
      got: 'HTTP ${refAfterRel['http']} ${refAfterRel['text']}',
      severity: 'INFO',
      proof: {
        'http': refAfterRel['http'],
        'body': refAfterRel['body'],
        'row': await orderRow(k1Oid),
      },
    );

    // Try real payout; fall back to drain fixture (Connect often not ready)
    final payoutAmt = (sBalPostRel * 100).round();
    Map<String, dynamic>? payout;
    var drainedVia = 'none';
    if (payoutAmt > 0) {
      payout = await edge('create-connect-account', {
        'amount': payoutAmt,
        'idempotency_key': '$stamp-payout-$k1Oid',
      }, SH);
      notes['payout'] = {'http': payout['http'], 'body': payout['body']};
      if ((payout['http'] as int) == 200 &&
          payout['body'] is Map &&
          (payout['body'] as Map)['ok'] != false) {
        drainedVia = 'connect';
      }
    }
    var sBalPostDrain = await wallet(sellerId);
    if (sBalPostDrain > 0.0001) {
      await req(
        'PATCH',
        '$url/rest/v1/wallets?id=eq.$sellerId',
        SVC,
        {'balance': 0},
      );
      drainedVia = drainedVia == 'connect' ? 'connect+sim' : 'drain_fixture';
      sBalPostDrain = await wallet(sellerId);
    }

    final bBalPreDev = await wallet(buyerId);
    final sBalPreDev = await wallet(sellerId);
    final txsPre = await txs(k1Oid);

    // JWT actors try devolvida
    final jwtSdev = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$k1Oid',
      SH,
      {'status': 'devolvida'},
    );
    final jwtBdev = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$k1Oid',
      BH,
      {'status': 'devolvida'},
    );
    final rpcDev = await req(
      'POST',
      '$url/rest/v1/rpc/batata_refund_buyer_wallet_for_order',
      BH,
      {'p_order_id': k1Oid},
    );

    find(
      id: 'K1-jwt-cannot-devolvida-after-concluido',
      lens: 'K1',
      actor: 'seller JWT + buyer JWT',
      title: 'JWT não passa concluido → devolvida',
      steps: [
        'Após release, PATCH status=devolvida seller e buyer',
        'RPC batata_refund_buyer_wallet_for_order JWT buyer',
      ],
      expected: 'status permanece concluido; RPC false/erro',
      got:
          'seller_http=${jwtSdev['http']} buyer_http=${jwtBdev['http']} rpc=${rpcDev['body']} status=${(await orderRow(k1Oid))?['status']}',
      severity: 'INFO',
      proof: {
        'seller_patch': jwtSdev['body'],
        'buyer_patch': jwtBdev['body'],
        'rpc': rpcDev['body'],
        'row': await orderRow(k1Oid),
      },
    );

    // Fixture: service_role dispara o trigger (caminho admin/disputa)
    final toDev = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$k1Oid',
      SVC,
      {'status': 'devolvida'},
    );
    final rowDev = await orderRow(k1Oid);
    final bBalPostDev = await wallet(buyerId);
    final sBalPostDev = await wallet(sellerId);
    final txsPost = await txs(k1Oid);
    final reemb = txsPost
        .where((t) => t is Map && t['type'] == 'reembolso')
        .toList();
    final estorno = txsPost
        .where((t) => t is Map && t['type'] == 'estorno')
        .toList();
    final deltaBuyer = bBalPostDev - bBalPreDev;
    final deltaSeller = sBalPostDev - sBalPreDev;

    k1books = {
      'order': k1Oid,
      'credited_on_release': credited,
      'drained_via': drainedVia,
      'payout_http': payout?['http'],
      'seller_pre_rel': sBalPreRel,
      'seller_post_rel': sBalPostRel,
      'seller_pre_dev': sBalPreDev,
      'seller_post_dev': sBalPostDev,
      'buyer_pre_rel': bBalPreRel,
      'buyer_pre_dev': bBalPreDev,
      'buyer_post_dev': bBalPostDev,
      'delta_buyer': deltaBuyer,
      'delta_seller': deltaSeller,
      'devolvida_http': toDev['http'],
      'row': rowDev,
      'reemb_n': reemb.length,
      'estorno_n': estorno.length,
      'txs_pre': txsPre,
      'txs_post': txsPost,
      'pi': rowDev?['stripe_payment_intent_id'],
      'stripe_refund_id': rowDev?['stripe_refund_id'],
      'wallet_refund_processed_at': rowDev?['wallet_refund_processed_at'],
    };

    final minted = deltaBuyer > 0.001 || reemb.isNotEmpty;
    find(
      id: 'K1-devolvida-after-drain-no-mint',
      lens: 'K1',
      actor: 'service_role fixture PATCH devolvida (JWT bloqueado)',
      title: 'Após levantamento/drain, devolvida minta carteira do comprador?',
      steps: [
        'Stripe TEST pago 5,90 €',
        'Seller enviado + buyer concluido + release wallet',
        'Payout/drain seller balance=0',
        'service_role status=devolvida (JWT não consegue)',
      ],
      expected:
          'Δbuyer=0, sem tx reembolso, sem stripe_refund_id (buyer recupera via refund-order)',
      got:
          'Δbuyer=$deltaBuyer reemb=${reemb.length} estorno=${estorno.length} refund_id=${rowDev?['stripe_refund_id']} processed=${rowDev?['wallet_refund_processed_at']} status=${rowDev?['status']}',
      severity: minted ? 'P0' : 'INFO',
      proof: k1books,
    );

    final phantomEstorno = estorno.isNotEmpty && deltaSeller.abs() < 0.001;
    find(
      id: 'K2-clawback-no-phantom-estorno',
      lens: 'K2',
      actor: 'trigger devolvida + clawback',
      title: 'Estorno no livro sem Δbalance (saldo 0)',
      steps: [
        'Seller balance=0',
        'Trigger refund_buyer_wallet em devolvida',
      ],
      expected: 'sem linha estorno se o débito fail-closed; Δseller=0',
      got:
          'estorno_n=${estorno.length} Δseller=$deltaSeller txs=$estorno',
      severity: phantomEstorno ? 'P1' : 'INFO',
      proof: {
        'estorno': estorno,
        'delta_seller': deltaSeller,
        'seller_pre': sBalPreDev,
        'seller_post': sBalPostDev,
      },
    );

    // K7 — after devolvida, can seller Stripe-refund the PI?
    final refAfterDev = await edge('refund-order', {'order_id': k1Oid}, SH);
    final rowAfterRef = await orderRow(k1Oid);
    final stripeRf =
        '${rowAfterRef?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty;
    final edgeOk = refAfterDev['http'] == 200 &&
        refAfterDev['body'] is Map &&
        (refAfterDev['body'] as Map)['ok'] == true;
    find(
      id: 'K7-stripe-refund-after-devolvida-drained',
      lens: 'K7',
      actor: 'seller JWT',
      title: 'Composição: drain + devolvida + refund-order Stripe',
      steps: [
        'Estado: PI capturado, seller já levantou, devolvida sem mint',
        'POST refund-order JWT seller',
      ],
      expected:
          'Stripe refund do cartão (único caminho de recuperação do comprador)',
      got:
          'HTTP ${refAfterDev['http']} ok=${refAfterDev['body'] is Map ? (refAfterDev['body'] as Map)['ok'] : null} stripe_refund=${rowAfterRef?['stripe_refund_id']} skipped=${refAfterDev['body'] is Map ? (refAfterDev['body'] as Map)['skipped'] : null} ${refAfterDev['text']}',
      severity: (edgeOk && stripeRf)
          ? 'INFO'
          : ((refAfterDev['http'] as int) >= 400 ||
                  (refAfterDev['body'] is Map &&
                      (refAfterDev['body'] as Map)['skipped'] == true))
              ? 'P0'
              : 'P1',
      proof: {
        'edge': refAfterDev['body'],
        'http': refAfterDev['http'],
        'row': rowAfterRef,
        'buyer_wallet': await wallet(buyerId),
        'seller_wallet': await wallet(sellerId),
      },
    );

    // credit_wallet_once as JWT
    final creditJwt = await req(
      'POST',
      '$url/rest/v1/rpc/batata_credit_wallet_once',
      BH,
      {
        'p_wallet_id': buyerId,
        'p_order_id': k1Oid,
        'p_amount': 50,
        'p_type': 'reembolso',
        'p_description': 'rtk mint',
      },
    );
    find(
      id: 'K7-credit-wallet-jwt',
      lens: 'K7',
      actor: 'buyer JWT',
      title: 'RPC batata_credit_wallet_once directo',
      steps: ['POST rpc credit 50 € na própria wallet'],
      expected: '403 / GRANT só service_role',
      got: 'HTTP ${creditJwt['http']} ${creditJwt['text']}',
      severity: (creditJwt['http'] as int) >= 400 ? 'INFO' : 'P0',
      proof: {'http': creditJwt['http'], 'body': creditJwt['body']},
    );
  }

  // K6 — mão concluido (não partir o fluxo) + devolvida se release+drain
  if (maoOid.isNotEmpty && maoOid != 'null') {
    final rowM = await orderRow(maoOid);
    if ('${rowM?['status']}' == 'pago') {
      final cM = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.$maoOid',
        BH,
        {'status': 'concluido'},
      );
      find(
        id: 'K6-mao-concluido-still-works',
        lens: 'K6',
        actor: 'buyer JWT',
        title: 'mão/MB WAY pago → concluido (anti-quebra)',
        steps: ['PATCH concluido em encomenda off-platform paga'],
        expected: 'status=concluido',
        got: 'HTTP ${cM['http']} status=${(await orderRow(maoOid))?['status']}',
        severity: '${(await orderRow(maoOid))?['status']}' == 'concluido'
            ? 'INFO'
            : 'P2',
        proof: {'http': cM['http'], 'body': cM['body'], 'row': await orderRow(maoOid)},
      );
    }
  }

  // JWT cannot mutate money cols
  if (k1Oid != null) {
    final mutPm = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$k1Oid',
      BH,
      {'payment_method': 'MB WAY'},
    );
    find(
      id: 'K7-payment-method-immutable',
      lens: 'K7',
      actor: 'buyer JWT',
      title: 'JWT altera payment_method (plataforma → MB WAY)',
      steps: ['PATCH payment_method na encomenda já capturada'],
      expected: 'order_money_fields_immutable',
      got: 'HTTP ${mutPm['http']} ${mutPm['text']}',
      severity: (mutPm['http'] as int) >= 400 ? 'INFO' : 'P0',
      proof: {'http': mutPm['http'], 'body': mutPm['body']},
    );
    final mutRf = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$k1Oid',
      SH,
      {'stripe_refund_id': 're_fake_rtk'},
    );
    find(
      id: 'K7-stripe-refund-id-immutable',
      lens: 'K7',
      actor: 'seller JWT',
      title: 'JWT grava stripe_refund_id falso',
      steps: ['PATCH stripe_refund_id=re_fake'],
      expected: 'imutável',
      got: 'HTTP ${mutRf['http']} ${mutRf['text']}',
      severity: (mutRf['http'] as int) >= 400 ? 'INFO' : 'P0',
      proof: {'http': mutRf['http'], 'body': mutRf['body']},
    );
  }

  // cleanup holds (not paid PI leftover: k3 refunded, k1 may be devolvida)
  if (holdOid.isNotEmpty && holdOid != 'null') {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$holdOid', SVC, {
      'status': 'cancelado',
    });
  }

  final out = {
    'AUDITOR': 'REDTEAM_BLIND_K_POS_HIJ_v1',
    'FROZEN_AT': frozenAt,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'prefix': stamp,
    'actors': {
      'buyer': buyerId,
      'seller': sellerId,
      'buyer2': b2.id,
      'seller2': s2.id,
    },
    'findings': findings,
    'notes': notes,
  };
  final dir = Directory('tool/redteam_blind_k_20260831T1802');
  dir.createSync(recursive: true);
  File('${dir.path}/probe.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('--- findings ${findings.length} → ${dir.path}/probe.json ---');
  for (final f in findings) {
    stdout.writeln('${f['severidade']}\t${f['id']}');
  }
}
