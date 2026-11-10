// ignore_for_file: avoid_print
/// RTC-C pass2 — disputa composta + settle replay 2 PI + offer + dual session
/// dart run tool/rtc_c_deep_cash_20260830T1115_pass2.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

const tag = 'RTC-20260830T1115p2';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';

String clip(Object? o, [int n = 400]) {
  final s = o is String ? o : jsonEncode(o);
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

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

num n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) {
    stderr.writeln('ABORT');
    exit(2);
  }
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

  Future<List<Map<String, dynamic>>> tx(String oid) async {
    final r = await req(
      'GET',
      '$url/rest/v1/wallet_transactions?order_id=eq.$oid&select=type,amount,created_at&order=created_at.asc',
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
    print('$k\n  ${clip(v, 500)}\n');
  }

  // ---- settle_get_replay: 2 capturas mesma order, GET 2× ----
  final replay = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'probe': 'settle_get_replay',
      'buyer_id': buyerId,
      'seller_id': sellerId,
    },
  );
  hit('settle_get_replay', {
    'http': replay['http'],
    'body': replay['body'],
  });

  // Refunds on BOTH PIs
  if (replay['body'] is Map) {
    final m = replay['body'] as Map;
    for (final key in ['setup_pi', 'payment_intent_id']) {
      final pi = '${m[key] ?? ''}';
      if (pi.startsWith('pi_')) {
        final listed = await req(
          'POST',
          '$url/functions/v1/sec-fase2-e2e-oversell',
          E2E,
          {'probe': 'list_stripe_refunds', 'payment_intent_id': pi},
        );
        hit('refunds_$key', listed['body']);
      }
    }
  }

  // ---- captura + disputa 100% + refund Stripe ----
  final setup = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'probe': 'setup_paid_order',
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'initial_qty': 2,
    },
  );
  hit('setup_paid', {
    'http': setup['http'],
    'ok': (setup['body'] is Map) ? (setup['body'] as Map)['ok'] : null,
    'order_id': (setup['body'] is Map) ? (setup['body'] as Map)['order_id'] : null,
    'pi': (setup['body'] is Map) ? (setup['body'] as Map)['payment_intent_id'] : null,
  });
  final oid = (setup['body'] is Map) ? '${(setup['body'] as Map)['order_id']}' : '';
  final piPaid = (setup['body'] is Map)
      ? '${(setup['body'] as Map)['payment_intent_id']}'
      : '';

  if (oid.isNotEmpty) {
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);

    // seller → enviado (para disputa)
    final envio = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid',
      SH,
      {'status': 'enviado'},
    );
    hit('seller_enviado', {'http': envio['http'], 'row': await row('orders', oid)});

    // buyer insert dispute
    final dispIns = await req('POST', '$url/rest/v1/order_disputes', BH, {
      'order_id': oid,
      'buyer_id': buyerId,
      'reason': 'item_not_as_described',
      'description': '$tag disputa caixa composta reembolso carteira e stripe residual',
      'proof_photos': <String>[],
      'status': 'aberta',
      'current_turn': 'vendedor',
      'next_deadline': DateTime.now().toUtc().add(const Duration(hours: 72)).toIso8601String(),
    });
    hit('dispute_insert', {'http': dispIns['http'], 'clip': clip(dispIns['text'], 220)});
    String? did;
    final db = dispIns['body'];
    if (db is List && db.isNotEmpty && db.first is Map) {
      did = '${(db.first as Map)['id']}';
    } else if (db is Map) {
      did = '${db['id']}';
    }

    // buyer forge 100% offer
    if (did != null && did.isNotEmpty && did != 'null') {
      final forge = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.$did',
        BH,
        {
          'seller_offer_type': 'partial_refund',
          'seller_refund_percent': 100,
          'seller_offer_set_by': buyerId,
        },
      );
      hit('buyer_forge_offer', {
        'http': forge['http'],
        'row': await row('order_disputes', did),
      });

      final sellerOffer = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.$did',
        SH,
        {
          'seller_offer_type': 'partial_refund',
          'seller_refund_percent': 100,
          'status': 'respondida_vendedor',
          'current_turn': 'comprador',
        },
      );
      hit('seller_offer_100', {
        'http': sellerOffer['http'],
        'row': await row('order_disputes', did),
      });
    }

    final rpcDisp = await req(
      'POST',
      '$url/rest/v1/rpc/batata_process_partial_refund_dispute',
      BH,
      {'p_order_id': oid, 'p_refund_percent': 100},
    );
    final walletCents = await req(
      'POST',
      '$url/rest/v1/rpc/batata_order_wallet_reembolso_cents',
      BH,
      {'p_order_id': oid},
    );
    hit('dispute_rpc', {
      'http': rpcDisp['http'],
      'body': clip(rpcDisp['text'], 200),
      'wallet_cents': walletCents['body'],
      'tx': await tx(oid),
      'dBuyer': (await bal(buyerId)) - b0,
      'dSeller': (await bal(sellerId)) - s0,
      'order': await row('orders', oid),
    });

    final rf = await req(
      'POST',
      '$url/functions/v1/refund-order',
      SH,
      {'order_id': oid},
    );
    final listed = piPaid.startsWith('pi_')
        ? await req(
            'POST',
            '$url/functions/v1/sec-fase2-e2e-oversell',
            E2E,
            {'probe': 'list_stripe_refunds', 'payment_intent_id': piPaid},
          )
        : null;
    var stripeRf = 0;
    if (listed?['body'] is Map) {
      final refunds = (listed!['body'] as Map)['refunds'];
      if (refunds is List) {
        for (final e in refunds) {
          if (e is Map) stripeRf += n(e['amount']).round();
        }
      }
    }
    final wCents = n(walletCents['body']).round();
    hit('compose_refund', {
      'refund_http': rf['http'],
      'refund_body': clip(rf['text'], 280),
      'wallet_cents': wCents,
      'stripe_refund_cents': stripeRf,
      'sum': wCents + stripeRf,
      'captured': 590,
      'dBuyer': (await bal(buyerId)) - b0,
      'dSeller': (await bal(sellerId)) - s0,
      'tx': await tx(oid),
      'order': await row('orders', oid),
      'over_capture': (wCents + stripeRf) > 591,
    });
  }

  // ---- offer pending + seller accept + checkout quote ----
  final pOff = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': '$tag offer 18.00',
    'price': 18.0,
    'quantity': 2,
    'ref_code': '$tag-off',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  String? pid;
  if (pOff['body'] is List && (pOff['body'] as List).isNotEmpty) {
    pid = '${((pOff['body'] as List).first as Map)['id']}';
  }
  hit('offer_product', {'http': pOff['http'], 'id': pid});
  if (pid != null) {
    final pend = await req('POST', '$url/rest/v1/product_offers', BH, {
      'product_id': pid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 6.0,
      'status': 'pending',
    });
    hit('offer_pending', {'http': pend['http'], 'clip': clip(pend['text'], 200)});
    String? opid;
    if (pend['body'] is List && (pend['body'] as List).isNotEmpty) {
      opid = '${((pend['body'] as List).first as Map)['id']}';
    }
    if (opid != null) {
      final acc = await req(
        'PATCH',
        '$url/rest/v1/product_offers?id=eq.$opid',
        SH,
        {
          'status': 'accepted',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      hit('offer_accept', {'http': acc['http'], 'clip': clip(acc['text'], 180)});
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
      String? oid2;
      if (ord['body'] is List && (ord['body'] as List).isNotEmpty) {
        oid2 = '${((ord['body'] as List).first as Map)['id']}';
      }
      hit('offer_order', {
        'http': ord['http'],
        'id': oid2,
        'row': oid2 != null ? await row('orders', oid2) : clip(ord['text'], 180),
      });
      if (oid2 != null) {
        final ck = await req(
          'POST',
          '$url/functions/v1/create-payment-intent',
          BH,
          {
            'buyer_id': buyerId,
            'order_id': oid2,
            'product_id': pid,
            'amount': 50,
            'shipping_method': 'hand',
          },
        );
        hit('offer_checkout', {
          'http': ck['http'],
          'server': (ck['body'] is Map)
              ? (ck['body'] as Map)['server_amount_cents']
              : clip(ck['text'], 180),
        });
      }
    }
  }

  // qty=99 error
  if (pid != null) {
    final q99 = await req('POST', '$url/rest/v1/orders', BH, {
      'product_id': pid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': 0.01,
      'quantity': 99,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
    });
    hit('qty99', {'http': q99['http'], 'clip': clip(q99['text'], 220)});
  }

  // Dual session same unpaid order (stock plenty)
  if (pid != null) {
    final o = await req('POST', '$url/rest/v1/orders', BH, {
      'product_id': pid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': 18.0,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
    });
    String? oid3;
    if (o['body'] is List && (o['body'] as List).isNotEmpty) {
      oid3 = '${((o['body'] as List).first as Map)['id']}';
    }
    if (oid3 != null) {
      final ck1 = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
        'buyer_id': buyerId,
        'order_id': oid3,
        'product_id': pid,
        'amount': 50,
        'shipping_method': 'hand',
      });
      final ck2 = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
        'buyer_id': buyerId,
        'order_id': oid3,
        'product_id': pid,
        'amount': 50,
        'shipping_method': 'hand',
      });
      hit('dual_session', {
        'ck1': '${ck1['http']} ${(ck1['body'] is Map) ? (ck1['body'] as Map)['checkoutSessionId'] : clip(ck1['text'], 80)}',
        'ck2': '${ck2['http']} ${(ck2['body'] is Map) ? (ck2['body'] as Map)['checkoutSessionId'] : clip(ck2['text'], 80)}',
        'amt1': (ck1['body'] is Map) ? (ck1['body'] as Map)['server_amount_cents'] : null,
        'amt2': (ck2['body'] is Map) ? (ck2['body'] as Map)['server_amount_cents'] : null,
      });
    }
  }

  final out = {
    'pass': 2,
    'tag': tag,
    'at': DateTime.now().toUtc().toIso8601String(),
    'hits': hits,
  };
  await File('tool/reports/REDTEAM_PARALLEL_C_20260830T1115_pass2.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('wrote pass2 json hits=${hits.length}');
}
