// ignore_for_file: avoid_print
/// RTC-C pass3 — disputa composta (fluxo entregue) + oferta com chat_id
/// dart run tool/rtc_c_deep_cash_20260830T1115_pass3.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

String clip(Object? o, [int n = 360]) {
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
      '$url/rest/v1/wallet_transactions?order_id=eq.$oid&select=type,amount&order=created_at.asc',
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
    print('$k  ${clip(v, 420)}');
  }

  final setup = await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
    'probe': 'setup_paid_order',
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'initial_qty': 2,
  });
  final oidRaw = setup['body'] is Map ? (setup['body'] as Map)['order_id'] : null;
  final oid = (oidRaw == null || '$oidRaw'.isEmpty) ? null : '$oidRaw';
  final pi = setup['body'] is Map ? '${(setup['body'] as Map)['payment_intent_id']}' : '';
  hit('setup', {'http': setup['http'], 'oid': oid, 'pi': pi});
  if (oid == null) {
    stderr.writeln('no order');
    exit(3);
  }

  final b0 = await bal(buyerId);
  final s0 = await bal(sellerId);

  hit('ship', await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'status': 'enviado'}));
  hit('recv', {
    'patch': await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'concluido'}),
    'row': await row('orders', oid),
  });

  // Buyer dispute after concluido
  final d1 = await req('POST', '$url/rest/v1/order_disputes', BH, {
    'order_id': oid,
    'buyer_id': buyerId,
    'reason': 'item_not_as_described',
    'description': 'RTC pass3 disputa apos concluido para testar restituição composta carteira e stripe',
    'proof_photos': <String>[],
    'status': 'aberta',
    'current_turn': 'vendedor',
    'next_deadline': DateTime.now().toUtc().add(const Duration(hours: 72)).toIso8601String(),
  });
  hit('dispute_jwt', {'http': d1['http'], 'clip': clip(d1['text'], 200), 'id': idOf(d1['body'])});

  // Fixture: service insert dispute if RLS blocked (observe-only actor still JWT on RPC)
  var did = idOf(d1['body']);
  if (did == null) {
    final dFix = await req('POST', '$url/rest/v1/order_disputes', SVC, {
      'order_id': oid,
      'buyer_id': buyerId,
      'reason': 'item_not_as_described',
      'description': 'RTC pass3 fixture disputa',
      'proof_photos': <String>[],
      'status': 'aberta',
      'current_turn': 'vendedor',
      'next_deadline': DateTime.now().toUtc().add(const Duration(hours: 72)).toIso8601String(),
    });
    did = idOf(dFix['body']);
    hit('dispute_fixture', {'http': dFix['http'], 'id': did, 'clip': clip(dFix['text'], 180)});
  }

  if (did != null) {
    final offer = await req('PATCH', '$url/rest/v1/order_disputes?id=eq.$did', SH, {
      'seller_offer_type': 'partial_refund',
      'seller_refund_percent': 100,
      'status': 'respondida_vendedor',
      'current_turn': 'comprador',
    });
    hit('seller_offer', {
      'http': offer['http'],
      'row': await row('order_disputes', did),
    });

    // buyer forges 50% extra
    final forge = await req('PATCH', '$url/rest/v1/order_disputes?id=eq.$did', BH, {
      'seller_refund_percent': 100,
      'seller_offer_set_by': buyerId,
    });
    hit('buyer_forge', {
      'http': forge['http'],
      'row': await row('order_disputes', did),
    });

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
      'body': clip(rpc['text'], 200),
      'wallet_cents': wcent['body'],
      'tx': await txs(oid),
      'dB': (await bal(buyerId)) - b0,
      'dS': (await bal(sellerId)) - s0,
      'order': await row('orders', oid),
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
      'rf': clip(rf['text'], 240),
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

  // Offer with chat
  final chat = await req('POST', '$url/rest/v1/chats', BH, {
    'user_a': buyerId,
    'user_b': sellerId,
  });
  hit('chat', {'http': chat['http'], 'id': idOf(chat['body']), 'clip': clip(chat['text'], 120)});
  final prod = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'RTC-p3 offer 18',
    'price': 18.0,
    'quantity': 2,
    'ref_code': 'RTC-p3-off',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  final cid = idOf(chat['body']);
  if (pid != null && cid != null) {
    final off = await req('POST', '$url/rest/v1/product_offers', BH, {
      'product_id': pid,
      'chat_id': cid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 6.0,
      'list_price': 18.0,
      'offered_by': 'buyer',
      'status': 'pending',
      'expires_at': DateTime.now().toUtc().add(const Duration(hours: 48)).toIso8601String(),
    });
    hit('offer', {'http': off['http'], 'id': idOf(off['body']), 'clip': clip(off['text'], 180)});
    final opid = idOf(off['body']);
    if (opid != null) {
      final acc = await req('PATCH', '$url/rest/v1/product_offers?id=eq.$opid', SH, {
        'status': 'accepted',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      });
      hit('accept', {'http': acc['http']});
      final ord = await req('POST', '$url/rest/v1/orders', BH, {
        'product_id': pid,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'price_total': 6.0,
        'quantity': 1,
        'status': 'reservado',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
        'product_offer_id': opid,
      });
      final oid2 = idOf(ord['body']);
      hit('offer_order', {
        'http': ord['http'],
        'row': oid2 != null ? await row('orders', oid2) : clip(ord['text'], 180),
      });
      if (oid2 != null) {
        final ck = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
          'buyer_id': buyerId,
          'order_id': oid2,
          'product_id': pid,
          'amount': 50,
          'shipping_method': 'hand',
        });
        hit('offer_ck', {
          'http': ck['http'],
          'server': (ck['body'] is Map) ? (ck['body'] as Map)['server_amount_cents'] : clip(ck['text'], 160),
        });
      }
    }
  }

  await File('tool/reports/REDTEAM_PARALLEL_C_20260830T1115_pass3.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'pass': 3,
      'at': DateTime.now().toUtc().toIso8601String(),
      'hits': hits,
    }),
  );
  print('pass3 hits=${hits.length}');
}
