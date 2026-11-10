// RTC C pass 2 — fechar lacunas: oversell full JSON, disputa reason válido, offer status, shipping.
// dart run tool/rtc_deep_cash_20260830T0900_pass2.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260830T0900';
const tag = 'RTC-$stamp-p2';

late String url, anon, svc, buyerJwt, sellerJwt, buyerId, sellerId;
String? e2eSecret;
final out = <String, dynamic>{};
final createdP = <String>[];
final createdO = <String>[];
final createdD = <String>[];

Future<http.Response> call(
  String method,
  String path, {
  String? token,
  Object? body,
  bool service = false,
  Map<String, String>? extra,
}) {
  final h = <String, String>{
    'apikey': service ? svc : anon,
    'Authorization': 'Bearer ${service ? svc : (token ?? anon)}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
    ...?extra,
  };
  final uri = Uri.parse('$url$path');
  if (method == 'GET') return http.get(uri, headers: h);
  if (method == 'PATCH') {
    return http.patch(uri, headers: h, body: jsonEncode(body));
  }
  if (method == 'DELETE') return http.delete(uri, headers: h);
  return http.post(uri, headers: h, body: body == null ? null : jsonEncode(body));
}

dynamic decode(http.Response r) {
  if (r.body.isEmpty) return null;
  try {
    return jsonDecode(r.body);
  } catch (_) {
    return r.body;
  }
}

Map<String, dynamic>? first(dynamic d) {
  if (d is List && d.isNotEmpty && d.first is Map) {
    return Map<String, dynamic>.from(d.first as Map);
  }
  if (d is Map<String, dynamic>) return d;
  if (d is Map) return Map<String, dynamic>.from(d);
  return null;
}

Future<Map<String, dynamic>?> getOrder(String id) async {
  final r = await call(
    'GET',
    '/rest/v1/orders?id=eq.$id&select=id,status,price_total,amount_paid_cents,stock_units_applied,stripe_refund_id,stripe_payment_intent_id,wallet_release_processed_at,wallet_refund_processed_at,contract_unit_cents,contract_qty,product_offer_id,quantity',
    service: true,
  );
  return first(decode(r));
}

Future<Map<String, dynamic>?> wallet(String id) async {
  final r = await call('GET', '/rest/v1/wallets?id=eq.$id&select=id,balance', service: true);
  return first(decode(r));
}

Future<http.Response> e2e(Map<String, dynamic> body) {
  return call(
    'POST',
    '/functions/v1/sec-fase2-e2e-oversell',
    token: anon,
    body: body,
    extra: {if (e2eSecret != null) 'x-fleaber-e2e-secret': e2eSecret!},
  );
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  e2eSecret = env['FLEABER_STAGING_CRASH_INJECT_SECRET']?.trim();
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  buyerId = await sb.userIdForAccessToken(buyerJwt);
  sellerId = await sb.userIdForAccessToken(sellerJwt);

  try {
    // 1) Oversell e2e full body
    final ov = await e2e({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'initial_qty': 1,
    });
    out['oversell_http'] = ov.statusCode;
    out['oversell'] = decode(ov);
    final ovj = first(decode(ov));
    if (ovj?['product_id'] != null) createdP.add(ovj!['product_id'].toString());
    if (ovj?['order_a_id'] != null) createdO.add(ovj!['order_a_id'].toString());
    if (ovj?['order_b_id'] != null) createdO.add(ovj!['order_b_id'].toString());

    // 2) Offer self-accept: persistiu status?
    final pOfr = await call('POST', '/rest/v1/products', token: sellerJwt, body: {
      'seller_id': sellerId,
      'title': '$tag offer',
      'price': 22.00,
      'quantity': 3,
      'ref_code': tag,
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': [],
    });
    final prod = first(decode(pOfr));
    if (prod?['id'] != null) createdP.add(prod!['id'].toString());
    final ofr = await call('POST', '/rest/v1/product_offers', token: buyerJwt, body: {
      'product_id': prod!['id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 0.50,
      'list_price': 22,
      'offered_by': 'buyer',
      'status': 'accepted',
    });
    final ofrLive = first(decode(ofr));
    out['offer_insert'] = {'http': ofr.statusCode, 'row': ofrLive};
    if (ofrLive?['id'] != null) {
      final o1 = await call('POST', '/rest/v1/orders', token: buyerJwt, body: {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': prod['id'],
        'product_offer_id': ofrLive!['id'],
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
      });
      final ord = first(decode(o1));
      if (ord?['id'] != null) createdO.add(ord!['id'].toString());
      out['offer_order'] = {
        'http': o1.statusCode,
        'contract_unit_cents': ord?['contract_unit_cents'],
        'contract_qty': ord?['contract_qty'],
        'product_offer_id': ord?['product_offer_id'],
        'price_total': ord?['price_total'],
      };
      if (ord?['id'] != null) {
        final ck = await call('POST', '/functions/v1/create-payment-intent', token: buyerJwt, body: {
          'buyer_id': buyerId,
          'order_id': ord!['id'],
          'shipping_method': 'hand',
        });
        out['offer_checkout'] = {'http': ck.statusCode, 'body': decode(ck)};
      }
    }

    // 3) Disputa composition com reason válido + captura
    final setup = await e2e({
      'probe': 'setup_paid_order',
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'initial_qty': 2,
    });
    final paid = first(decode(setup));
    out['paid_setup'] = {'http': setup.statusCode, 'order_id': paid?['order_id'], 'pi': paid?['payment_intent_id']};
    if (paid?['order_id'] != null) createdO.add(paid!['order_id'].toString());
    if (paid?['product_id'] != null) createdP.add(paid!['product_id'].toString());
    if (paid?['order_id'] != null) {
      final oid = paid!['order_id'].toString();
      await call('PATCH', '/rest/v1/orders?id=eq.$oid', token: sellerJwt, body: {'status': 'enviado'});
      await call('PATCH', '/rest/v1/orders?id=eq.$oid', token: sellerJwt, body: {'status': 'entregue'});
      final st = await getOrder(oid);
      out['after_entregue'] = st;
      final wb0 = await wallet(buyerId);
      final ws0 = await wallet(sellerId);
      final disp = await call('POST', '/rest/v1/order_disputes', token: buyerJwt, body: {
        'order_id': oid,
        'buyer_id': buyerId,
        'reason': 'outro',
        'description': 'RTC pass2',
      });
      final dr = first(decode(disp));
      out['dispute_insert'] = {'http': disp.statusCode, 'row': dr, 'raw': disp.body};
      if (dr?['id'] != null) {
        createdD.add(dr!['id'].toString());
        final patch = await call(
          'PATCH',
          '/rest/v1/order_disputes?id=eq.${dr['id']}',
          token: sellerJwt,
          body: {
            'seller_refund_percent': 100,
            'seller_offer_type': 'partial_refund',
          },
        );
        out['dispute_seller_offer'] = {'http': patch.statusCode, 'row': first(decode(patch)), 'raw': patch.body};
      }
      final part = await call(
        'POST',
        '/rest/v1/rpc/batata_process_partial_refund_dispute',
        token: buyerJwt,
        body: {'p_order_id': oid, 'p_refund_percent': 100},
      );
      final wb1 = await wallet(buyerId);
      final ws1 = await wallet(sellerId);
      out['partial'] = {
        'http': part.statusCode,
        'body': decode(part),
        'dBuyer': (wb1?['balance'] ?? 0) - (wb0?['balance'] ?? 0),
        'dSeller': (ws1?['balance'] ?? 0) - (ws0?['balance'] ?? 0),
      };
      final rf = await call('POST', '/functions/v1/refund-order', token: sellerJwt, body: {'order_id': oid});
      out['stripe_refund_after_partial'] = {
        'http': rf.statusCode,
        'body': decode(rf),
        'order': await getOrder(oid),
        'wallet_buyer': await wallet(buyerId),
      };
      if (paid['payment_intent_id'] != null) {
        final listed = await e2e({
          'probe': 'list_stripe_refunds',
          'payment_intent_id': paid['payment_intent_id'],
        });
        out['pi_refunds'] = decode(listed);
      }
    }

    // 4) Off-platform disputa válida
    final pOff = await call('POST', '/rest/v1/products', token: sellerJwt, body: {
      'seller_id': sellerId,
      'title': '$tag mbway',
      'price': 11.00,
      'quantity': 2,
      'ref_code': '$tag-mb',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': [],
    });
    final po = first(decode(pOff));
    if (po?['id'] != null) createdP.add(po!['id'].toString());
    final oOff = await call('POST', '/rest/v1/orders', token: buyerJwt, body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': po!['id'],
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
      'shipping_method': 'hand',
    });
    final oo = first(decode(oOff));
    if (oo?['id'] != null) createdO.add(oo!['id'].toString());
    final offId = oo!['id'].toString();
    await call('PATCH', '/rest/v1/orders?id=eq.$offId', token: sellerJwt, body: {'status': 'pago'});
    await call('PATCH', '/rest/v1/orders?id=eq.$offId', token: sellerJwt, body: {'status': 'enviado'});
    await call('PATCH', '/rest/v1/orders?id=eq.$offId', token: sellerJwt, body: {'status': 'entregue'});
    final dOff = await call('POST', '/rest/v1/order_disputes', token: buyerJwt, body: {
      'order_id': offId,
      'buyer_id': buyerId,
      'reason': 'nao_corresponde',
      'description': 'RTC mbway',
    });
    final dOffR = first(decode(dOff));
    out['offplat_dispute'] = {'http': dOff.statusCode, 'row': dOffR, 'raw': dOff.body};
    if (dOffR?['id'] != null) {
      createdD.add(dOffR!['id'].toString());
      await call('PATCH', '/rest/v1/order_disputes?id=eq.${dOffR['id']}', token: sellerJwt, body: {
        'seller_refund_percent': 100,
        'seller_offer_type': 'partial_refund',
      });
    }
    final wbA = await wallet(buyerId);
    final partOff = await call(
      'POST',
      '/rest/v1/rpc/batata_process_partial_refund_dispute',
      token: buyerJwt,
      body: {'p_order_id': offId, 'p_refund_percent': 100},
    );
    final wbB = await wallet(buyerId);
    out['offplat_partial'] = {
      'http': partOff.statusCode,
      'body': decode(partOff),
      'dBuyer': (wbB?['balance'] ?? 0) - (wbA?['balance'] ?? 0),
      'order': await getOrder(offId),
    };
  } finally {
    for (final id in createdD) {
      await call('DELETE', '/rest/v1/order_disputes?id=eq.$id', service: true);
    }
    for (final id in createdO) {
      await call('DELETE', '/rest/v1/orders?id=eq.$id', service: true);
    }
    for (final id in createdP) {
      await call('DELETE', '/rest/v1/products?id=eq.$id', service: true);
    }
  }

  final f = File('tool/reports/REDTEAM_PARALLEL_C_${stamp}_pass2.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert({
    'FROZEN_AT': DateTime.now().toUtc().toIso8601String(),
    'AUDITOR': 'PARALLEL_C_DEEP_CASH',
    ...out,
  }));
  stdout.writeln('WROTE ${f.path}');
}
