/// Passagem 3 — composição reserva→order, PM pix, PII cols certas, cleanup Mux, disputa em pago.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

const tag = 'SAT27C3';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';
typedef Json = Map<String, dynamic>;
final findings = <Json>[];
final probes = <Json>[];

void rec(String n, Object? d) => probes.add({'name': n, 'data': d});
String clip(Object? o, [int n = 280]) {
  final s = o is String ? o : jsonEncode(o);
  return s.length <= n ? s : '${s.substring(0, n)}…';
}
Json? rowOf(Object? b) {
  if (b is List && b.isNotEmpty && b.first is Map) return Map<String, dynamic>.from(b.first as Map);
  if (b is Map && b['id'] != null) return Map<String, dynamic>.from(b);
  return null;
}

Future<Json> req(String method, String url, String anon, String tok, {Object? body, Map<String, String>? extra}) async {
  final headers = {
    'apikey': tok == extra?['x-svc'] ? tok : anon,
    'Authorization': 'Bearer $tok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
    ...?extra,
  };
  headers.remove('x-svc');
  final uri = Uri.parse(url);
  final c = http.Client();
  try {
    final r = switch (method) {
      'GET' => await c.get(uri, headers: headers).timeout(const Duration(seconds: 25)),
      'POST' => await c.post(uri, headers: headers, body: body == null ? null : jsonEncode(body)).timeout(const Duration(seconds: 40)),
      'PATCH' => await c.patch(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 25)),
      'DELETE' => await c.delete(uri, headers: headers).timeout(const Duration(seconds: 25)),
      _ => throw StateError(method),
    };
    Object? parsed = r.body;
    try { parsed = r.body.isEmpty ? null : jsonDecode(r.body); } catch (_) {}
    return {'http': r.statusCode, 'body': parsed};
  } finally {
    c.close();
  }
}

void finding(String id, String sev, String surface, String impact, Object? after, {String variant = '', String fp = ''}) {
  findings.add({
    'id': id, 'severity': sev, 'surface': surface, 'impact': impact, 'after': after,
    'variant': variant, 'false_positive_considered': fp, 'confidence': 'alta',
    'identity': 'jwt', 'request': id, 'response': after, 'before': null, 'preconditions': variant,
  });
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final BH = await sb.signIn(email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'), password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'));
  final SH = await sb.signIn(email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'), password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'));
  final bUid = await sb.userIdForAccessToken(BH);
  final sUid = await sb.userIdForAccessToken(SH);

  Future<Json> R(String m, String p, {String? tok, Object? body}) =>
      req(m, p.startsWith('http') ? p : '$url$p', anon, tok ?? anon, body: body);

  // restore + cleanup mux leftover
  await R('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: svc, body: {'user_type': 'comprador', 'iban': null});
  final muxDone = await R('POST', '$url/functions/v1/complete-mux-live', tok: BH, body: {'live_id': '1be4a44b-4505-404b-b506-852eeceb67be'});
  rec('complete_mux_leftover', {'http': muxDone['http'], 'body': clip(muxDone['body'])});
  await R('PATCH', '$url/rest/v1/lives?id=eq.1be4a44b-4505-404b-b506-852eeceb67be', tok: svc, body: {'status': 'ended', 'is_active': false});
  await R('DELETE', '$url/rest/v1/live_reservation_requests?id=eq.b62d018c-8a59-4734-a314-b3dfc842f0c5', tok: svc);

  final ut = rowOf((await R('GET', '$url/rest/v1/profiles?id=eq.$bUid&select=user_type,iban', tok: svc))['body']);
  rec('buyer_restored', ut);

  // PII without email
  final sel = 'id,full_name,iban,mb_way,phone,user_type,phone_verified_at,stripe_account_id';
  final anonP = await R('GET', '$url/rest/v1/profiles?select=$sel&limit=8');
  rec('anon_pii', {'http': anonP['http'], 'n': anonP['body'] is List ? (anonP['body'] as List).length : 0, 'sample': clip(anonP['body'], 250)});
  if (anonP['http'] == 200 && anonP['body'] is List) {
    for (final row in (anonP['body'] as List).whereType<Map>()) {
      final leaks = ['iban', 'mb_way', 'phone', 'stripe_account_id'].where((c) => row[c] != null && '${row[c]}'.trim().isNotEmpty);
      if (leaks.isNotEmpty) {
        finding('SAT27C3-PII-ANON', 'P1', 'PROFILES', 'PII anon ${leaks.join(",")}', row);
        break;
      }
    }
  }
  final xs = await R('GET', '$url/rest/v1/profiles?id=eq.$sUid&select=$sel', tok: BH);
  rec('buyer_read_seller', {'http': xs['http'], 'row': rowOf(xs['body'])});
  final xsRow = rowOf(xs['body']);
  if (xsRow != null) {
    final leaks = ['iban', 'mb_way', 'phone', 'stripe_account_id'].where((c) => xsRow[c] != null && '${xsRow[c]}'.trim().isNotEmpty);
    if (leaks.isNotEmpty) finding('SAT27C3-PII-X', 'P1', 'PROFILES', 'PII seller via buyer ${leaks.join(",")}', xsRow);
  }

  Future<Json?> prod(double price, int qty) async {
    final r = await R('POST', '$url/rest/v1/products', tok: SH, body: {
      'seller_id': sUid, 'title': '$tag $price', 'price': price, 'quantity': qty,
      'ref_code': '$tag-${DateTime.now().microsecondsSinceEpoch}', 'list_on_marketplace': true,
      'available_for_live': false, 'is_sold': false, 'image_urls': <String>[], 'category': 'Outros', 'state': 'Bom',
    });
    return rowOf(r['body']);
  }

  // pix / crypto / empty / proposta — fresh stock
  final p = await prod(13.0, 5);
  for (final pm in ['pix', 'crypto', 'proposta aceite', 'Pagamento na app (Seguro Fleaber)']) {
    final o = await R('POST', '$url/rest/v1/orders', tok: BH, body: {
      'product_id': p?['id'], 'buyer_id': bUid, 'seller_id': sUid, 'price_total': 13, 'quantity': 1,
      'status': 'reserva_pendente', 'payment_method': pm,
    });
    final orow = rowOf(o['body']);
    rec('pm_$pm', {'http': o['http'], 'id': orow?['id']});
    if (orow?['id'] == null) continue;
    await R('PATCH', '$url/rest/v1/orders?id=eq.${orow!['id']}', tok: SH, body: {'status': 'pago'});
    final live = rowOf((await R('GET', '$url/rest/v1/orders?id=eq.${orow['id']}&select=status,payment_method,amount_paid_cents', tok: svc))['body']);
    rec('pago_$pm', live);
    final isOff = pm.toLowerCase().contains('mb way');
    if ('${live?['status']}' == 'pago' && !isOff && pm != 'Pagamento na app (Seguro Fleaber)' && (live?['amount_paid_cents'] == null || live?['amount_paid_cents'] == 0)) {
      finding('SAT27C3-PM-$pm', 'P1', 'ORDERS', 'PM "$pm" permitiu seller→pago', live, variant: pm);
    }
    await R('DELETE', '$url/rest/v1/orders?id=eq.${orow['id']}', tok: svc);
  }

  // reservation qty → order qty composition
  final items = await R('GET', '$url/rest/v1/live_items?select=id,live_id,seller_id,price,product_id&seller_id=eq.$sUid&limit=3', tok: svc);
  Json? li = items['body'] is List && (items['body'] as List).isNotEmpty
      ? Map<String, dynamic>.from((items['body'] as List).first as Map)
      : null;
  rec('li', li);
  if (li?['id'] != null) {
    final res = await R('POST', '$url/rest/v1/live_reservation_requests', tok: BH, body: {
      'live_id': li!['live_id'], 'live_item_id': li['id'], 'seller_id': sUid, 'buyer_id': bUid,
      'requested_qty': 9, 'source': 'fleaber_live', 'status': 'accepted',
    });
    final rr = rowOf(res['body']);
    rec('res3', {'http': res['http'], 'qty': rr?['requested_qty'], 'st': rr?['status']});
    // try convert pending to accepted as buyer
    if (rr?['id'] != null) {
      final acc = await R('PATCH', '$url/rest/v1/live_reservation_requests?id=eq.${rr!['id']}', tok: BH, body: {'status': 'accepted'});
      rec('res_self_accept', {'http': acc['http'], 'body': clip(acc['body'])});
      final accS = await R('PATCH', '$url/rest/v1/live_reservation_requests?id=eq.${rr['id']}', tok: SH, body: {'status': 'accepted'});
      rec('res_seller_accept', {'http': accS['http'], 'body': clip(accS['body'])});
      final after = rowOf((await R('GET', '$url/rest/v1/live_reservation_requests?id=eq.${rr['id']}&select=status,requested_qty', tok: svc))['body']);
      rec('res_after', after);
    }
    final pid = li['product_id'];
    if (pid != null) {
      final o9 = await R('POST', '$url/rest/v1/orders', tok: BH, body: {
        'product_id': pid, 'live_item_id': li['id'], 'buyer_id': bUid, 'seller_id': sUid,
        'price_total': 90, 'quantity': 9, 'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app (Seguro Fleaber)',
      });
      rec('order_qty9_live', {'http': o9['http'], 'body': clip(o9['body'])});
      final o9r = rowOf(o9['body']);
      if (o9r != null && (o9r['quantity'] == 9 || o9r['contract_qty'] == 9)) {
        finding('SAT27C3-RES-ORD', 'P1', 'COMPOSITION', 'Order qty 9 a partir de reserva pending qty 9', o9r);
        await R('DELETE', '$url/rest/v1/orders?id=eq.${o9r['id']}', tok: svc);
      }
    }
    if (rr?['id'] != null) {
      await R('DELETE', '$url/rest/v1/live_reservation_requests?id=eq.${rr!['id']}', tok: svc);
    }
  }

  // dispute/review on concluido MB WAY leftover if any — create pago via seller off-platform real
  final p2 = await prod(8.0, 2);
  final o2 = await R('POST', '$url/rest/v1/orders', tok: BH, body: {
    'product_id': p2?['id'], 'buyer_id': bUid, 'seller_id': sUid, 'price_total': 8, 'quantity': 1,
    'status': 'reserva_pendente', 'payment_method': 'Pagamento direto ao vendedor (MB WAY/transf)',
  });
  final o2r = rowOf(o2['body']);
  if (o2r?['id'] != null) {
    await R('PATCH', '$url/rest/v1/orders?id=eq.${o2r!['id']}', tok: SH, body: {'status': 'pago'});
    await R('PATCH', '$url/rest/v1/orders?id=eq.${o2r['id']}', tok: SH, body: {'status': 'enviado'});
    await R('PATCH', '$url/rest/v1/orders?id=eq.${o2r['id']}', tok: BH, body: {'status': 'concluido'});
    final st = rowOf((await R('GET', '$url/rest/v1/orders?id=eq.${o2r['id']}&select=status', tok: svc))['body']);
    rec('mb_concluido', st);
    final rev = await R('POST', '$url/rest/v1/reviews', tok: BH, body: {
      'order_id': o2r['id'], 'buyer_id': bUid, 'target_id': sUid, 'stars': 1, 'comment': '$tag', 'author_role': 'comprador',
    });
    rec('review_concluido', {'http': rev['http'], 'body': clip(rev['body'])});
    final d = await R('POST', '$url/rest/v1/order_disputes', tok: BH, body: {
      'order_id': o2r['id'], 'buyer_id': bUid, 'reason': 'outro', 'description': tag,
    });
    rec('dispute_concluido', {'http': d['http'], 'body': clip(d['body'])});
    final drow = rowOf(d['body']);
    if (drow?['id'] != null) {
      final rel = await R('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', tok: BH, body: {'p_order_id': o2r['id']});
      rec('release_while_dispute', {'http': rel['http'], 'body': clip(rel['body'])});
      final upd = await R('PATCH', '$url/rest/v1/order_disputes?id=eq.${drow!['id']}', tok: BH, body: {'seller_refund_percent': 100, 'status': 'resolvida'});
      rec('buyer_resolve_dispute', {'http': upd['http'], 'body': clip(upd['body'])});
      await R('DELETE', '$url/rest/v1/order_disputes?id=eq.${drow['id']}', tok: svc);
    }
    await R('DELETE', '$url/rest/v1/reviews?order_id=eq.${o2r['id']}', tok: svc);
    await R('DELETE', '$url/rest/v1/orders?id=eq.${o2r['id']}', tok: svc);
  }
  if (p?['id'] != null) await R('DELETE', '$url/rest/v1/products?id=eq.${p!['id']}', tok: svc);
  if (p2?['id'] != null) await R('DELETE', '$url/rest/v1/products?id=eq.${p2!['id']}', tok: svc);

  // confirm mux as comprador still 403
  final muxB = await R('POST', '$url/functions/v1/create-mux-live', tok: BH, body: {'title': '$tag should 403'});
  rec('mux_as_comprador', {'http': muxB['http'], 'body': clip(muxB['body'])});

  File('tool/reports/SAT_CEGA_PASS3_RAW_20260827.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'meta': {'tag': tag, 'when': DateTime.now().toUtc().toIso8601String()},
      'findings': findings,
      'probes': probes,
    }),
  );
  stdout.writeln('PASS3 FINDINGS=${findings.length}');
  for (final f in findings) {
    stdout.writeln('  ${f['severity']} ${f['id']} — ${f['impact']}');
  }
}
