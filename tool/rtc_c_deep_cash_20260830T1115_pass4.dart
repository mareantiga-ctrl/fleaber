// ignore_for_file: avoid_print
/// dart run tool/rtc_c_deep_cash_20260830T1115_pass4.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

String clip(Object? o, [int n = 400]) {
  final s = o is String ? o : jsonEncode(o);
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

num n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

Future<Map<String, dynamic>> req(
  String method,
  String url,
  Map<String, String> h, [
  Object? body,
]) async {
  final uri = Uri.parse(url);
  final enc = body == null ? null : jsonEncode(body);
  late http.Response r;
  switch (method) {
    case 'POST':
      r = await http.post(uri, headers: h, body: enc);
      break;
    case 'PATCH':
      r = await http.patch(uri, headers: h, body: enc);
      break;
    default:
      r = await http.get(uri, headers: h);
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
    final s = '${body['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final e2e = (env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerTok = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  Map<String, String> H(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = H(buyerTok);
  final SH = H(sellerTok);
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final E2E = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
    'x-fleaber-e2e-secret': e2e,
  };

  Future<Map<String, dynamic>?> row(String table, String id) async {
    final r = await req('GET', '$url/rest/v1/$table?id=eq.$id&select=*&limit=1', SVC);
    final b = r['body'];
    if (b is List && b.isNotEmpty && b.first is Map) {
      return Map<String, dynamic>.from(b.first as Map);
    }
    return null;
  }

  Future<double> bal(String uid) async {
    final r = await req('GET', '$url/rest/v1/wallets?id=eq.$uid&select=balance', SVC);
    final b = r['body'];
    if (b is List && b.isNotEmpty && b.first is Map) {
      return n((b.first as Map)['balance']).toDouble();
    }
    return 0;
  }

  Future<List<Map<String, dynamic>>> txs(String oid) async {
    final r = await req(
      'GET',
      '$url/rest/v1/wallet_transactions?order_id=eq.$oid&select=type,amount',
      SVC,
    );
    final b = r['body'];
    if (b is List) {
      return [for (final e in b) if (e is Map) Map<String, dynamic>.from(e)];
    }
    return [];
  }

  final hits = <Map<String, dynamic>>[];
  void hit(String k, Object v) {
    hits.add({'k': k, 'v': v});
    print('$k  ${clip(v, 480)}');
  }

  const oid = 'bca3c659-f8f8-4889-ac44-11d241be2a26';
  const pi = 'pi_3UA5vKH7FWYUN3jh1oIFq02U';
  final before = await row('orders', oid);
  hit('order_before', before ?? 'missing');

  final b0 = await bal(buyerId);
  final s0 = await bal(sellerId);

  // release first (seller) — may mint venda
  final rel = await req(
    'POST',
    '$url/rest/v1/rpc/batata_release_seller_wallet_for_order',
    SH,
    {'p_order_id': oid},
  );
  hit('release', {
    'http': rel['http'],
    'body': clip(rel['text'], 120),
    'dS': (await bal(sellerId)) - s0,
    'tx': await txs(oid),
  });

  final d1 = await req('POST', '$url/rest/v1/order_disputes', BH, {
    'order_id': oid,
    'buyer_id': buyerId,
    'reason': 'nao_corresponde',
    'description': 'RTC pass4 artigo nao corresponde descricao teste composto',
    'proof_photos': <String>[],
    'status': 'aberta',
    'current_turn': 'vendedor',
    'next_deadline': DateTime.now().toUtc().add(const Duration(hours: 72)).toIso8601String(),
  });
  var did = idOf(d1['body']);
  hit('dispute_jwt', {'http': d1['http'], 'id': did, 'clip': clip(d1['text'], 180)});
  if (did == null) {
    final dFix = await req('POST', '$url/rest/v1/order_disputes', SVC, {
      'order_id': oid,
      'buyer_id': buyerId,
      'reason': 'nao_corresponde',
      'description': 'RTC pass4 fixture',
      'proof_photos': <String>[],
      'status': 'aberta',
      'current_turn': 'vendedor',
      'next_deadline': DateTime.now().toUtc().add(const Duration(hours: 72)).toIso8601String(),
    });
    did = idOf(dFix['body']);
    hit('dispute_fix', {'http': dFix['http'], 'id': did, 'clip': clip(dFix['text'], 180)});
  }

  if (did != null) {
    hit('pedido_dev', await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid',
      BH,
      {'status': 'pedido_devolucao'},
    ));

    final offer = await req('PATCH', '$url/rest/v1/order_disputes?id=eq.$did', SH, {
      'seller_offer_type': 'partial_refund',
      'seller_refund_percent': 100,
      'status': 'respondida_vendedor',
      'current_turn': 'comprador',
    });
    hit('seller_offer', {'http': offer['http'], 'row': await row('order_disputes', did)});

    final rpc = await req(
      'POST',
      '$url/rest/v1/rpc/batata_process_partial_refund_dispute',
      BH,
      {'p_order_id': oid, 'p_refund_percent': 100},
    );
    final wcent = await req(
      'POST',
      '$url/rest/v1/rpc/batata_order_wallet_reembolso_cents',
      BH,
      {'p_order_id': oid},
    );
    hit('disp_rpc', {
      'http': rpc['http'],
      'body': clip(rpc['text'], 220),
      'wallet_cents': wcent['body'],
      'tx': await txs(oid),
      'dB': (await bal(buyerId)) - b0,
      'dS': (await bal(sellerId)) - s0,
    });

    final rf = await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': oid});
    final listed = await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
      'probe': 'list_stripe_refunds',
      'payment_intent_id': pi,
    });
    var stripeRf = 0;
    if (listed['body'] is Map) {
      final refunds = (listed['body'] as Map)['refunds'];
      if (refunds is List) {
        for (final e in refunds) {
          if (e is Map) stripeRf += n(e['amount']).round();
        }
      }
    }
    final wc = n(wcent['body']).round();
    hit('compose', {
      'rf_http': rf['http'],
      'rf': clip(rf['text'], 280),
      'wallet_cents': wc,
      'stripe_cents': stripeRf,
      'sum': wc + stripeRf,
      'captured': 590,
      'over': (wc + stripeRf) > 591,
      'dB': (await bal(buyerId)) - b0,
      'dS': (await bal(sellerId)) - s0,
      'tx': await txs(oid),
      'order': await row('orders', oid),
    });
  }

  await File('tool/reports/REDTEAM_PARALLEL_C_20260830T1115_pass4.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'pass': 4,
      'at': DateTime.now().toUtc().toIso8601String(),
      'hits': hits,
    }),
  );
  print('pass4 hits=${hits.length}');
}
