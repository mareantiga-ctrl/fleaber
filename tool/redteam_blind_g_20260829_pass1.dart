// ignore_for_file: avoid_print
/// Red Team cego G — PASS 1 cobertura. Staging only.
/// dart run tool/redteam_blind_g_20260829_pass1.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  late http.Response r;
  try {
    r = method == 'POST'
        ? await http.post(Uri.parse(u), headers: h, body: jsonEncode(body))
        : method == 'PATCH'
            ? await http.patch(Uri.parse(u), headers: h, body: jsonEncode(body))
            : method == 'DELETE'
                ? await http.delete(Uri.parse(u), headers: h)
                : method == 'PUT'
                    ? await http.put(Uri.parse(u), headers: h, body: jsonEncode(body))
                    : await http.get(Uri.parse(u), headers: h);
  } catch (e) {
    return {'http': 0, 'body': null, 'text': '$e'};
  }
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

String clip(Object? v, [int n = 360]) {
  final s = '$v';
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

dynamic firstRow(dynamic body) {
  if (body is List && body.isNotEmpty) return body.first;
  if (body is Map) return body;
  return null;
}

String? idOf(dynamic body) {
  final row = firstRow(body);
  if (row is Map) {
    final s = '${row['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

num? numOf(dynamic v) {
  if (v is num) return v;
  return num.tryParse('$v');
}

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) {
    stderr.writeln('ABORT: not staging $stagingRef');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );

  final tag = DateTime.now().toUtc().toIso8601String().replaceAll(':', '');
  final outDir = Directory('tool/redteam_blind_g_20260829');
  outDir.createSync(recursive: true);

  final AH = {
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

  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final extraBuyerEmail = 'rtg.buyer.$stamp@staging.fleaber.lab';
  final extraSellerEmail = 'rtg.seller.$stamp@staging.fleaber.lab';
  const extraPw = 'RtgLab!20260829';
  final extraBuyerId = await sb.createAdminUser(
    email: extraBuyerEmail,
    password: extraPw,
    userMetadata: {'user_type': 'comprador'},
  );
  final extraSellerId = await sb.createAdminUser(
    email: extraSellerEmail,
    password: extraPw,
    userMetadata: {'user_type': 'vendedor'},
  );
  await req('POST', '$url/rest/v1/profiles', SVC, {
    'id': extraBuyerId,
    'user_type': 'comprador',
    'display_name': 'RTG extra buyer',
  });
  await req('POST', '$url/rest/v1/profiles', SVC, {
    'id': extraSellerId,
    'user_type': 'vendedor',
    'display_name': 'RTG extra seller',
  });
  final extraBuyerTok = await sb.signIn(email: extraBuyerEmail, password: extraPw);
  final extraSellerTok = await sb.signIn(email: extraSellerEmail, password: extraPw);
  final XBH = {
    'apikey': anon,
    'Authorization': 'Bearer $extraBuyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final XSH = {
    'apikey': anon,
    'Authorization': 'Bearer $extraSellerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final probes = <Map<String, dynamic>>[];
  void add({
    required String id,
    required String surface,
    required String attack,
    required String identity,
    required Map<String, dynamic> res,
    String? before,
    String? after,
    String impact = '',
    String severity = 'info',
    bool persisted = false,
  }) {
    probes.add({
      'id': id,
      'surface': surface,
      'attack': attack,
      'identity': identity,
      'http': res['http'],
      'response': clip(res['text']),
      'before': before,
      'after': after,
      'persisted': persisted,
      'impact': impact,
      'severity_hint': severity,
    });
  }

  Future<Map<String, dynamic>?> svcRow(String table, String id) async {
    final r = await req(
      'GET',
      '$url/rest/v1/$table?id=eq.$id&select=*&limit=1',
      SVC,
    );
    final row = firstRow(r['body']);
    return row is Map ? Map<String, dynamic>.from(row) : null;
  }

  // ---- inventory OpenAPI ----
  Future<Map<String, dynamic>> openApi(Map<String, String> h) async {
    final r = await http.get(
      Uri.parse('$url/rest/v1/'),
      headers: {
        ...h,
        'Accept': 'application/openapi+json',
      },
    );
    dynamic p;
    try {
      p = jsonDecode(r.body);
    } catch (_) {
      p = null;
    }
    final paths = <String>[];
    if (p is Map && p['paths'] is Map) {
      paths.addAll((p['paths'] as Map).keys.map((e) => '$e'));
    }
    return {'http': r.statusCode, 'path_count': paths.length, 'paths': paths};
  }

  final oaAnon = await openApi(AH);
  final oaBuyer = await openApi(BH);
  final oaSeller = await openApi(SH);
  final oaSvc = await openApi(SVC);

  List<String> pathsOf(Map<String, dynamic> oa) =>
      ((oa['paths'] as List?) ?? const []).cast<String>();

  final tablePaths = pathsOf(oaSvc)
      .where((p) => !p.contains('/rpc/') && p != '/')
      .map((p) => p.replaceFirst(RegExp(r'^/'), ''))
      .where((p) => p.isNotEmpty && !p.contains('{'))
      .toList()
    ..sort();
  final rpcPaths = pathsOf(oaBuyer)
      .where((p) => p.contains('/rpc/'))
      .map((p) => p.split('/rpc/').last)
      .toList()
    ..sort();
  final rpcAnon = pathsOf(oaAnon)
      .where((p) => p.contains('/rpc/'))
      .map((p) => p.split('/rpc/').last)
      .toList()
    ..sort();

  add(
    id: 'inv.openapi.anon',
    surface: 'AUTH',
    attack: 'OpenAPI anon',
    identity: 'anon',
    res: {'http': oaAnon['http'], 'text': 'paths=${oaAnon['path_count']}'},
  );
  add(
    id: 'inv.openapi.buyer',
    surface: 'RPCs',
    attack: 'OpenAPI buyer JWT',
    identity: 'buyer',
    res: {
      'http': oaBuyer['http'],
      'text': 'paths=${oaBuyer['path_count']} rpcs=${rpcPaths.length}',
    },
  );

  // ---- RLS sweep ----
  final sensitiveTables = <String>{
    'orders',
    'products',
    'profiles',
    'wallets',
    'wallet_transactions',
    'wallet_payout_ledger',
    'fleaber_commissions',
    'chats',
    'chat_messages',
    'reviews',
    'reviews_gerais',
    'order_disputes',
    'order_dispute_replies',
    'lives',
    'live_items',
    'live_reservation_requests',
    'live_tips',
    'live_raffles',
    'live_raffle_tickets',
    'product_offers',
    'product_bundles',
    'favorites',
    'follows',
    'seller_helpers',
    'staff_action_logs',
    'app_logs',
    'user_notifications',
    'stripe_checkout_events',
    'ps_ingest_audit',
    'ps_pairing_sessions',
    'seller_payout_details',
    'payout_details',
    ...tablePaths.take(80),
  };

  for (final t in sensitiveTables) {
    for (final ident in [
      ['anon', AH],
      ['buyer', BH],
      ['seller', SH],
    ]) {
      final r = await req(
        'GET',
        '$url/rest/v1/$t?select=*&limit=5',
        ident[1] as Map<String, String>,
      );
      final n = r['body'] is List ? (r['body'] as List).length : 0;
      var leak = false;
      var leakNote = '';
      if (r['http'] == 200 && r['body'] is List) {
        for (final row in r['body'] as List) {
          if (row is! Map) continue;
          final uid = ident[0] == 'buyer'
              ? buyerId
              : ident[0] == 'seller'
                  ? sellerId
                  : '';
          final ids = [
            row['buyer_id'],
            row['seller_id'],
            row['user_id'],
            row['wallet_id'],
            row['author_id'],
            row['id'],
            row['sender_id'],
          ].map((x) => '$x').toList();
          if (ident[0] == 'anon' && n > 0) {
            leak = true;
            leakNote = 'anon rows=$n';
            break;
          }
          if (uid.isNotEmpty) {
            final foreign = ids.any((x) =>
                x.length > 10 &&
                x != uid &&
                x != 'null' &&
                !x.contains(uid));
            if (foreign &&
                (t == 'wallets' ||
                    t == 'wallet_transactions' ||
                    t == 'chats' ||
                    t == 'chat_messages' ||
                    t == 'order_disputes' ||
                    t == 'stripe_checkout_events' ||
                    t.contains('payout'))) {
              leak = true;
              leakNote = 'possible cross-user row';
              break;
            }
          }
        }
      }
      add(
        id: 'rls.select.$t.${ident[0]}',
        surface: t,
        attack: 'SELECT * limit 5',
        identity: ident[0] as String,
        res: r,
        impact: leak ? leakNote : 'rows=$n',
        severity: leak ? 'P2' : 'info',
        persisted: leak,
      );
    }
  }

  // stream keys / secrets columns
  for (final col in [
    'mux_stream_key',
    'stream_key',
    'livekit_egress_id',
    'stripe_account_id',
    'iban',
    'mb_way',
  ]) {
    final r = await req(
      'GET',
      '$url/rest/v1/lives?select=id,seller_id,$col&limit=20',
      BH,
    );
    var leaked = false;
    if (r['body'] is List) {
      for (final row in r['body'] as List) {
        if (row is Map &&
            row[col] != null &&
            '${row[col]}'.trim().isNotEmpty &&
            '${row['seller_id']}' != buyerId) {
          leaked = true;
        }
      }
    }
    add(
      id: 'priv.lives.$col.buyer',
      surface: 'LIVE',
      attack: 'SELECT lives.$col as buyer',
      identity: 'buyer',
      res: r,
      impact: leaked ? 'foreign $col visible' : 'no foreign secret',
      severity: leaked ? 'P1' : 'info',
      persisted: leaked,
    );
  }

  final profBank = await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$sellerId&select=id,iban,mb_way,user_type,external_payments_enabled',
    BH,
  );
  final bankRow = firstRow(profBank['body']);
  final iban = bankRow is Map ? '${bankRow['iban'] ?? ''}' : '';
  add(
    id: 'priv.profiles.banking.buyer',
    surface: 'PRIVACY',
    attack: 'buyer SELECT seller IBAN/MB WAY',
    identity: 'buyer',
    res: profBank,
    impact: iban.isNotEmpty ? 'IBAN visible to buyer JWT' : 'empty/hidden',
    severity: iban.length > 8 ? 'P2' : 'info',
    persisted: iban.length > 8,
  );

  // ---- financial field writes ----
  final prodFix = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'RTG-P1 $tag',
    'price': 12.50,
    'quantity': 1,
    'list_on_marketplace': true,
    'is_sold': false,
    'state': 'Bom',
    'category': 'Outros',
  });
  final productId = idOf(prodFix['body']);
  add(
    id: 'fix.product',
    surface: 'PRODUCTS',
    attack: 'fixture product stock=1',
    identity: 'service_role',
    res: prodFix,
    after: productId,
  );

  if (productId != null) {
    final beforeP = await svcRow('products', productId);
    final priceAttacks = [
      ['buyer', BH, {'price': 0.01}],
      ['buyer', BH, {'quantity': 999}],
      ['buyer', BH, {'is_sold': false, 'seller_id': buyerId}],
      ['extra_buyer', XBH, {'price': 1}],
      ['seller', SH, {'price': 0.01}],
    ];
    for (var i = 0; i < priceAttacks.length; i++) {
      final a = priceAttacks[i];
      final r = await req(
        'PATCH',
        '$url/rest/v1/products?id=eq.$productId',
        a[1] as Map<String, String>,
        a[2],
      );
      final after = await svcRow('products', productId);
      final changed = '${after?['price']}' != '${beforeP?['price']}' ||
          '${after?['quantity']}' != '${beforeP?['quantity']}' ||
          '${after?['seller_id']}' != '${beforeP?['seller_id']}';
      add(
        id: 'cat.patch.$i.${a[0]}',
        surface: 'CATALOG',
        attack: 'PATCH product ${a[2]}',
        identity: a[0] as String,
        res: r,
        before: 'price=${beforeP?['price']} qty=${beforeP?['quantity']}',
        after: 'price=${after?['price']} qty=${after?['quantity']} seller=${after?['seller_id']}',
        persisted: changed && a[0] != 'seller',
        impact: changed ? 'catalog mutated' : 'unchanged',
        severity: changed && a[0] != 'seller' ? 'P1' : 'info',
      );
      if (changed && a[0] != 'seller') {
        await req('PATCH', '$url/rest/v1/products?id=eq.$productId', SVC, {
          'price': 12.50,
          'quantity': 1,
          'seller_id': sellerId,
        });
      }
    }
  }

  // wallets
  final wBefore = await req(
    'GET',
    '$url/rest/v1/wallets?id=eq.$buyerId&select=*',
    SVC,
  );
  final wPatch = await req(
    'PATCH',
    '$url/rest/v1/wallets?id=eq.$buyerId',
    BH,
    {'balance': 99999.99},
  );
  final wAfter = await req(
    'GET',
    '$url/rest/v1/wallets?id=eq.$buyerId&select=*',
    SVC,
  );
  final balB = firstRow(wBefore['body']);
  final balA = firstRow(wAfter['body']);
  final minted = numOf(balA is Map ? balA['balance'] : null) !=
      numOf(balB is Map ? balB['balance'] : null);
  add(
    id: 'fin.wallet.patch.buyer',
    surface: 'WALLET',
    attack: 'PATCH wallets.balance=99999',
    identity: 'buyer',
    res: wPatch,
    before: '${balB is Map ? balB['balance'] : null}',
    after: '${balA is Map ? balA['balance'] : null}',
    persisted: minted,
    impact: minted ? 'JWT minted balance' : 'blocked',
    severity: minted ? 'P0' : 'info',
  );

  final wIns = await req('POST', '$url/rest/v1/wallet_transactions', BH, {
    'wallet_id': buyerId,
    'amount': 500,
    'type': 'reembolso',
    'description': 'RTG mint',
  });
  add(
    id: 'fin.ledger.insert.buyer',
    surface: 'LEDGER',
    attack: 'INSERT wallet_transactions +500',
    identity: 'buyer',
    res: wIns,
    persisted: wIns['http'] == 201,
    impact: wIns['http'] == 201 ? 'ledger write' : 'blocked',
    severity: wIns['http'] == 201 ? 'P0' : 'info',
  );

  final wInsOther = await req('POST', '$url/rest/v1/wallet_transactions', BH, {
    'wallet_id': sellerId,
    'amount': 500,
    'type': 'venda',
    'description': 'RTG cross',
  });
  add(
    id: 'fin.ledger.insert.cross',
    surface: 'LEDGER',
    attack: 'INSERT ledger into seller wallet as buyer',
    identity: 'buyer',
    res: wInsOther,
    persisted: wInsOther['http'] == 201,
    severity: wInsOther['http'] == 201 ? 'P0' : 'info',
  );

  // orders financial columns
  final ordFix = await req('POST', '$url/rest/v1/orders', SVC, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': productId,
    'price_total': 12.50,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'pagamento na app (seguro fleaber)',
    'shipping_method': 'hand',
  });
  final orderId = idOf(ordFix['body']);
  add(
    id: 'fix.order',
    surface: 'ORDERS',
    attack: 'fixture unpaid order',
    identity: 'service_role',
    res: ordFix,
    after: orderId,
  );

  if (orderId != null) {
    final moneyPatches = <Map<String, dynamic>>[
      {'price_total': 0.50},
      {'amount_paid_cents': 1},
      {'amount_paid_cents': 1250},
      {'quantity': 99},
      {'status': 'pago'},
      {'status': 'concluido'},
      {'stripe_payment_intent_id': 'pi_fake_rtg'},
      {'stripe_checkout_session_id': 'cs_fake_rtg'},
      {'buyer_id': extraBuyerId},
      {'seller_id': extraSellerId},
      {'product_id': productId},
      {'contract_unit_cents': 1},
      {'contract_qty': 99},
    ];
    final beforeO = await svcRow('orders', orderId);
    for (var i = 0; i < moneyPatches.length; i++) {
      final patch = moneyPatches[i];
      final r = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.$orderId',
        BH,
        patch,
      );
      final after = await svcRow('orders', orderId);
      final key = patch.keys.first;
      final changed = '${after?[key]}' != '${beforeO?[key]}';
      add(
        id: 'ord.patch.buyer.$i.$key',
        surface: 'ORDERS',
        attack: 'buyer PATCH $patch',
        identity: 'buyer',
        res: r,
        before: '$key=${beforeO?[key]}',
        after: '$key=${after?[key]} status=${after?['status']}',
        persisted: changed,
        impact: changed ? 'authoritative field mutated' : 'blocked/reverted',
        severity: changed &&
                (key.contains('paid') ||
                    key.contains('stripe') ||
                    key == 'status' &&
                        '${after?['status']}'.contains('pago'))
            ? 'P0'
            : changed
                ? 'P1'
                : 'info',
      );
    }

    final sellerMoney = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$orderId',
      SH,
      {'amount_paid_cents': 99999, 'status': 'pago', 'price_total': 0.01},
    );
    final afterS = await svcRow('orders', orderId);
    add(
      id: 'ord.patch.seller.money',
      surface: 'ORDERS',
      attack: 'seller PATCH amount_paid+pago+price',
      identity: 'seller',
      res: sellerMoney,
      after:
          'paid=${afterS?['amount_paid_cents']} status=${afterS?['status']} price=${afterS?['price_total']}',
      persisted: '${afterS?['amount_paid_cents']}' == '99999' ||
          '${afterS?['status']}' == 'pago',
      severity: '${afterS?['amount_paid_cents']}' == '99999' ? 'P0' : 'info',
    );

    // buyer insert order as other buyer / paid
    final ghost = await req('POST', '$url/rest/v1/orders', SH, {
      'buyer_id': extraBuyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'price_total': 12.50,
      'quantity': 1,
      'status': 'pago',
      'payment_method': 'pagamento na app (seguro fleaber)',
      'shipping_method': 'hand',
      'amount_paid_cents': 1250,
    });
    final ghostId = idOf(ghost['body']);
    var ghostPersisted = false;
    if (ghostId != null) {
      final g = await svcRow('orders', ghostId);
      ghostPersisted = g != null &&
          ('${g['status']}' == 'pago' ||
              '${g['buyer_id']}' == extraBuyerId &&
                  '${g['amount_paid_cents']}' == '1250');
    }
    add(
      id: 'ord.ghost.seller.insert',
      surface: 'AUTHORITY',
      attack: 'seller INSERT order paid for extra buyer',
      identity: 'seller',
      res: ghost,
      after: ghostId,
      persisted: ghostPersisted,
      impact: ghostPersisted ? 'ghost sale' : 'blocked or sanitized',
      severity: ghostPersisted && '${firstRow(ghost['body']) is Map ? (firstRow(ghost['body']) as Map)['status'] : ''}' == 'pago'
          ? 'P0'
          : ghostId != null
              ? 'P2'
              : 'info',
    );

    final buyerPaidIns = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'price_total': 0.01,
      'quantity': 1,
      'status': 'pago',
      'payment_method': 'pagamento na app (seguro fleaber)',
      'shipping_method': 'hand',
      'amount_paid_cents': 1,
    });
    add(
      id: 'ord.insert.buyer.pago',
      surface: 'ORDER FSM',
      attack: 'buyer INSERT status=pago amount_paid=1',
      identity: 'buyer',
      res: buyerPaidIns,
      after: '${firstRow(buyerPaidIns['body'])}',
      persisted: idOf(buyerPaidIns['body']) != null &&
          '${firstRow(buyerPaidIns['body']) is Map ? (firstRow(buyerPaidIns['body']) as Map)['status'] : ''}' ==
              'pago',
      severity: idOf(buyerPaidIns['body']) != null &&
              '${firstRow(buyerPaidIns['body']) is Map ? (firstRow(buyerPaidIns['body']) as Map)['status'] : ''}' ==
                  'pago'
          ? 'P0'
          : 'info',
    );
  }

  // profiles elevation
  final utBefore = await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type',
    SVC,
  );
  final utPatch = await req(
    'PATCH',
    '$url/rest/v1/profiles?id=eq.$buyerId',
    BH,
    {'user_type': 'admin'},
  );
  final utAfter = await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type',
    SVC,
  );
  final utA = firstRow(utAfter['body']);
  final elevated = utA is Map &&
      ['admin', 'administrador', 'admim', 'vendedor', 'seller']
          .contains('${utA['user_type']}'.toLowerCase());
  final utB = firstRow(utBefore['body']);
  final changedType = utA is Map &&
      utB is Map &&
      '${utA['user_type']}' != '${utB['user_type']}';
  add(
    id: 'auth.profile.user_type',
    surface: 'AUTH',
    attack: 'buyer PATCH user_type=admin',
    identity: 'buyer',
    res: utPatch,
    before: '${utB is Map ? utB['user_type'] : null}',
    after: '${utA is Map ? utA['user_type'] : null}',
    persisted: changedType,
    impact: elevated && changedType ? 'privilege elevation' : 'blocked',
    severity: changedType && elevated ? 'P0' : 'info',
  );

  // ---- RPCs ----
  final rpcHostile = <String, Map<String, dynamic>>{
    'batata_wallet_payout_debit': {
      'p_user_id': sellerId,
      'p_amount_cents': 1,
      'p_idempotency_key': 'rtg-payout-$stamp',
    },
    'batata_wallet_payout_finish': {
      'p_idempotency_key': 'rtg-payout-$stamp',
      'p_stripe_transfer_id': 'tr_fake',
      'p_failed': false,
    },
    'batata_wallet_apply_tip_once': {
      'p_wallet_id': buyerId,
      'p_tip_id': buyerId,
      'p_amount': 50,
      'p_type': 'gorjeta_recebida',
      'p_description': 'rtg',
    },
    'batata_credit_wallet_once': {
      'p_wallet_id': buyerId,
      'p_order_id': orderId,
      'p_amount': 10,
      'p_type': 'reembolso',
      'p_description': 'rtg',
    },
    'batata_debit_wallet_once': {
      'p_wallet_id': sellerId,
      'p_order_id': orderId,
      'p_amount': 1,
      'p_type': 'levantamento',
      'p_description': 'rtg',
    },
    'batata_release_seller_wallet_for_order': {'p_order_id': orderId},
    'batata_refund_buyer_wallet_for_order': {'p_order_id': orderId},
    'batata_process_partial_refund_dispute': {
      'p_order_id': orderId,
      'p_refund_percent': 100,
    },
    'batata_clawback_seller_wallet_for_order': {'p_order_id': orderId},
    'batata_finalize_stripe_order_refund': {
      'p_order_id': orderId,
      'p_refund_id': 're_fake',
      'p_payment_intent_id': 'pi_fake',
      'p_session_id': 'cs_fake',
      'p_amount_cents': 1,
    },
    'batata_send_live_tip_from_wallet': {
      'p_live_id': null,
      'p_seller_id': sellerId,
      'p_amount': 1,
      'p_message': 'rtg',
    },
    'batata_create_raffle_prize_order': {
      'p_live_id': buyerId,
      'p_winner_id': buyerId,
      'p_qty': 1,
    },
    'batata_award_live_raffle_tickets': {
      'p_live_id': buyerId,
      'p_user_id': buyerId,
      'p_source': 'manual',
      'p_qty': 10,
      'p_note': 'rtg',
    },
    'batata_find_user_id_by_email': {
      'p_email': envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    },
    'batata_seller_direct_payment_details': {'p_seller_id': sellerId},
    'batata_is_admin': {},
    'batata_ensure_wallet': {'p_user_id': sellerId},
    'batata_lab_clear_fm_pending': {'p_user_id': sellerId},
    'batata_ps_claim_pairing': {
      'p_code': '000000',
      'p_device_id': 'rtg',
      'p_app_version': '1',
    },
    'batata_generate_auto_feedback': {},
  };

  for (final ident in [
    ['buyer', BH],
    ['seller', SH],
    ['anon', AH],
    ['extra_buyer', XBH],
  ]) {
    for (final entry in rpcHostile.entries) {
      final r = await req(
        'POST',
        '$url/rest/v1/rpc/${entry.key}',
        ident[1] as Map<String, String>,
        entry.value,
      );
      final httpCode = r['http'] as int;
      final exec = httpCode != 404 && httpCode != 401 && httpCode != 403;
      final okish = httpCode >= 200 && httpCode < 300;
      var sev = 'info';
      if (okish &&
          (entry.key.contains('payout') ||
              entry.key.contains('credit_wallet') ||
              entry.key.contains('apply_tip') ||
              entry.key.contains('finalize_stripe'))) {
        sev = 'P0';
      } else if (okish &&
          (entry.key.contains('release') ||
              entry.key.contains('refund_buyer') ||
              entry.key.contains('partial_refund') ||
              entry.key.contains('raffle'))) {
        sev = 'P1';
      } else if (exec && httpCode == 200 && entry.key.contains('find_user')) {
        sev = 'P2';
      }
      add(
        id: 'rpc.${entry.key}.${ident[0]}',
        surface: 'RPC',
        attack: 'EXECUTE ${entry.key}',
        identity: ident[0] as String,
        res: r,
        persisted: okish,
        impact: okish ? 'executed' : 'http=$httpCode',
        severity: sev,
      );
    }
  }

  // RPCs exposed to buyer but not in hostile list
  for (final name in rpcPaths.take(80)) {
    if (rpcHostile.containsKey(name)) continue;
    final r = await req('POST', '$url/rest/v1/rpc/$name', BH, {});
    add(
      id: 'rpc.probe.$name.buyer',
      surface: 'RPC',
      attack: 'EXECUTE $name {}',
      identity: 'buyer',
      res: r,
      impact: 'http=${r['http']}',
    );
  }

  // ---- Edge functions ----
  final edges = [
    'create-payment-intent',
    'refund-order',
    'create-live-tip-checkout',
    'create-connect-account',
    'create-mux-live',
    'complete-mux-live',
    'livekit-mux-publish',
    'resolve-mux-playback',
    'ingest-ocr-reservation',
    'ps-pairing-claim',
    'ps-heartbeat',
    'ps-panel-log',
    'stripe-webhook',
    'delete-test-account',
    'send-sms-bulkgate',
    'meta-data-deletion',
    'livekit-egress-cleanup',
  ];

  if (orderId != null && productId != null) {
    final piLow = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'order_id': orderId,
        'product_id': productId,
        'buyer_id': extraBuyerId,
        'seller_id': extraSellerId,
        'amount': 50,
        'quantity': 99,
        'item_price': 0.01,
        'shipping': 0,
        'protection_fee': 0,
        'shipping_method': 'hand',
      },
    );
    add(
      id: 'edge.cpi.underpay',
      surface: 'CHECKOUT',
      attack: 'create-payment-intent amount=50 qty=99 swapped parties',
      identity: 'buyer',
      res: piLow,
      impact: clip(piLow['text'], 500),
      severity: (piLow['http'] == 200 &&
              '${piLow['text']}'.contains('cs_') &&
              '${piLow['text']}'.contains('"amount":50'))
          ? 'P1'
          : 'info',
    );

    final piHand = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      BH,
      {
        'order_id': orderId,
        'product_id': productId,
        'shipping_method': 'hand',
        'amount': 1,
      },
    );
    add(
      id: 'edge.cpi.hand',
      surface: 'CHECKOUT',
      attack: 'legitimate-shape checkout (hand)',
      identity: 'buyer',
      res: piHand,
    );

    final settleFake = await req(
      'GET',
      '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_fake_rtg',
      BH,
    );
    add(
      id: 'edge.cpi.settle.fake',
      surface: 'SETTLE',
      attack: 'GET settle fake session_id',
      identity: 'buyer',
      res: settleFake,
      severity: settleFake['http'] == 200 &&
              '${settleFake['text']}'.toLowerCase().contains('pago')
          ? 'P0'
          : 'info',
    );
  }

  final refundAsBuyer = await req(
    'POST',
    '$url/functions/v1/refund-order',
    BH,
    {'order_id': orderId, 'amount': 999999},
  );
  add(
    id: 'edge.refund.buyer',
    surface: 'REFUNDS',
    attack: 'refund-order as buyer',
    identity: 'buyer',
    res: refundAsBuyer,
    severity: refundAsBuyer['http'] == 200 &&
            '${refundAsBuyer['text']}'.contains('"ok":true') &&
            !'${refundAsBuyer['text']}'.contains('skipped')
        ? 'P1'
        : 'info',
  );

  final refundAsSeller = await req(
    'POST',
    '$url/functions/v1/refund-order',
    SH,
    {'order_id': orderId},
  );
  add(
    id: 'edge.refund.seller.unpaid',
    surface: 'REFUNDS',
    attack: 'refund-order unpaid as seller',
    identity: 'seller',
    res: refundAsSeller,
  );

  final payoutCross = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    BH,
    {
      'user_id': sellerId,
      'amount': 1,
      'idempotency_key': 'rtg-connect-$stamp',
    },
  );
  add(
    id: 'edge.connect.cross',
    surface: 'PAYOUT',
    attack: 'create-connect-account user_id=seller amount=1 as buyer',
    identity: 'buyer',
    res: payoutCross,
    severity: payoutCross['http'] == 200 ? 'P1' : 'info',
  );

  final muxBuyer = await req(
    'POST',
    '$url/functions/v1/create-mux-live',
    BH,
    {'title': 'RTG buyer live hijack'},
  );
  add(
    id: 'edge.mux.buyer',
    surface: 'MUX',
    attack: 'create-mux-live as buyer',
    identity: 'buyer',
    res: muxBuyer,
    impact: clip(muxBuyer['text'], 400),
    severity: muxBuyer['http'] == 200 &&
            '${muxBuyer['text']}'.contains('stream_key')
        ? 'P2'
        : 'info',
  );

  final livekit = await req(
    'POST',
    '$url/functions/v1/livekit-mux-publish',
    BH,
    {'step': 'token', 'live_id': buyerId, 'stream_key': 'sk_fake'},
  );
  add(
    id: 'edge.livekit.token.buyer',
    surface: 'LIVEKIT',
    attack: 'livekit token for foreign live_id',
    identity: 'buyer',
    res: livekit,
  );

  final ocr = await req(
    'POST',
    '$url/functions/v1/ingest-ocr-reservation',
    BH,
    {
      'live_id': buyerId,
      'requested_qty': 99,
      'ocr_raw_line': 'quero 99',
      'device_id': 'rtg',
    },
  );
  add(
    id: 'edge.ocr.buyer',
    surface: 'PS/OCR',
    attack: 'ingest-ocr-reservation as buyer qty=99',
    identity: 'buyer',
    res: ocr,
  );

  final pair = await req(
    'POST',
    '$url/functions/v1/ps-pairing-claim',
    AH,
    {'code': '000000', 'device_id': 'rtg-brute'},
  );
  add(
    id: 'edge.ps.claim.anon',
    surface: 'PS/OCR',
    attack: 'ps-pairing-claim 000000 as anon',
    identity: 'anon',
    res: pair,
    severity: pair['http'] == 200 && '${pair['text']}'.contains('"ok":true')
        ? 'P1'
        : 'info',
  );

  final wh = await req(
    'POST',
    '$url/functions/v1/stripe-webhook',
    AH,
    {
      'type': 'checkout.session.completed',
      'data': {
        'object': {'id': 'cs_test', 'payment_status': 'paid'},
      },
    },
  );
  add(
    id: 'edge.webhook.nosig',
    surface: 'WEBHOOK',
    attack: 'stripe-webhook without signature',
    identity: 'anon',
    res: wh,
    severity: wh['http'] == 200 ? 'P0' : 'info',
  );

  final sms = await req(
    'POST',
    '$url/functions/v1/send-sms-bulkgate',
    AH,
    {
      'user': {'phone': '+351910000000'},
      'sms': {'otp': '000000'},
    },
  );
  add(
    id: 'edge.sms.anon',
    surface: 'AUTH',
    attack: 'send-sms-bulkgate unauthenticated',
    identity: 'anon',
    res: sms,
    severity: sms['http'] == 200 ? 'P2' : 'info',
  );

  final nuke = await req(
    'POST',
    '$url/functions/v1/delete-test-account',
    BH,
    {'confirm': 'APAGAR TUDO'},
  );
  add(
    id: 'edge.nuke.buyer',
    surface: 'AUTH',
    attack: 'delete-test-account as lab buyer',
    identity: 'buyer',
    res: nuke,
  );

  for (final fn in edges) {
    final r = await req('POST', '$url/functions/v1/$fn', AH, {});
    add(
      id: 'edge.anon.$fn',
      surface: 'EDGE FUNCTIONS',
      attack: 'POST empty as anon',
      identity: 'anon',
      res: r,
      impact: 'http=${r['http']}',
    );
  }

  // reviews
  if (orderId != null) {
    final rev = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': orderId,
      'author_id': extraBuyerId,
      'target_id': sellerId,
      'rating': 1,
      'comment': 'rtg forged',
      'author_role': 'buyer',
    });
    add(
      id: 'rep.review.forge',
      surface: 'REVIEWS',
      attack: 'INSERT review as extra author on unpaid order',
      identity: 'buyer',
      res: rev,
      persisted: idOf(rev['body']) != null,
      severity: idOf(rev['body']) != null ? 'P1' : 'info',
    );
  }

  // disputes
  if (orderId != null) {
    final disp = await req('POST', '$url/rest/v1/order_disputes', XBH, {
      'order_id': orderId,
      'opened_by': extraBuyerId,
      'reason': 'rtg',
      'status': 'open',
    });
    add(
      id: 'disp.cross.insert',
      surface: 'DISPUTES',
      attack: 'extra buyer INSERT dispute on foreign order',
      identity: 'extra_buyer',
      res: disp,
      persisted: idOf(disp['body']) != null,
      severity: idOf(disp['body']) != null ? 'P1' : 'info',
    );
  }

  // chat leak
  final chats = await req(
    'GET',
    '$url/rest/v1/chats?select=*&limit=20',
    XBH,
  );
  var chatLeak = false;
  if (chats['body'] is List) {
    for (final row in chats['body'] as List) {
      if (row is Map) {
        final a = '${row['buyer_id'] ?? row['user_a'] ?? ''}';
        final b = '${row['seller_id'] ?? row['user_b'] ?? ''}';
        if (a != extraBuyerId && b != extraBuyerId && a.length > 8) {
          chatLeak = true;
        }
      }
    }
  }
  add(
    id: 'priv.chats.extra',
    surface: 'CHAT',
    attack: 'extra buyer SELECT chats',
    identity: 'extra_buyer',
    res: chats,
    impact: chatLeak ? 'foreign chats' : 'own/empty',
    severity: chatLeak ? 'P1' : 'info',
    persisted: chatLeak,
  );

  // storage
  final buckets = await req('GET', '$url/storage/v1/bucket', BH);
  add(
    id: 'stor.buckets.buyer',
    surface: 'STORAGE',
    attack: 'list buckets',
    identity: 'buyer',
    res: buckets,
  );
  for (final b in ['chat_media', 'product_photos', 'proofs', 'dispute_proofs']) {
    final list = await req(
      'POST',
      '$url/storage/v1/object/list/$b',
      BH,
      {'prefix': '', 'limit': 20},
    );
    add(
      id: 'stor.list.$b.buyer',
      surface: 'STORAGE',
      attack: 'list objects $b',
      identity: 'buyer',
      res: list,
    );
  }

  // collusion: extra seller + extra buyer cheap product
  final collProd = await req('POST', '$url/rest/v1/products', XSH, {
    'seller_id': extraSellerId,
    'title': 'RTG collusion $tag',
    'price': 100,
    'quantity': 1,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final collPid = idOf(collProd['body']);
  if (collPid != null) {
    final cheap = await req(
      'PATCH',
      '$url/rest/v1/products?id=eq.$collPid',
      XSH,
      {'price': 0.50},
    );
    add(
      id: 'col.catalog.price',
      surface: 'CATALOG',
      attack: 'collusion seller drops price before checkout',
      identity: 'extra_seller',
      res: cheap,
      impact: 'seller owns catalog — expected unless contract frozen',
    );
  }

  // tips
  final tipIns = await req('POST', '$url/rest/v1/live_tips', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 1,
    'seller_amount': 1,
    'status': 'completed',
    'payment_source': 'stripe',
  });
  add(
    id: 'tip.insert.completed',
    surface: 'TIPS',
    attack: 'buyer INSERT live_tips completed',
    identity: 'buyer',
    res: tipIns,
    persisted: idOf(tipIns['body']) != null,
    severity: idOf(tipIns['body']) != null ? 'P1' : 'info',
  );

  // cleanup fixtures (not lab users)
  if (productId != null) {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$productId', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$productId', SVC);
  }
  if (collPid != null) {
    await req('DELETE', '$url/rest/v1/products?id=eq.$collPid', SVC);
  }
  await req('DELETE', '$url/rest/v1/profiles?id=eq.$extraBuyerId', SVC);
  await req('DELETE', '$url/rest/v1/profiles?id=eq.$extraSellerId', SVC);
  await http.delete(
    Uri.parse('$url/auth/v1/admin/users/$extraBuyerId'),
    headers: SVC,
  );
  await http.delete(
    Uri.parse('$url/auth/v1/admin/users/$extraSellerId'),
    headers: SVC,
  );

  final interesting = probes
      .where((p) =>
          p['severity_hint'] == 'P0' ||
          p['severity_hint'] == 'P1' ||
          p['persisted'] == true)
      .toList();

  final out = {
    'pass': 1,
    'project': stagingRef,
    'frozen': false,
    'started': tag,
    'identities': {
      'buyer': buyerId,
      'seller': sellerId,
      'extra_buyer_deleted': extraBuyerId,
      'extra_seller_deleted': extraSellerId,
      'service_role': 'setup_observe_cleanup_only',
    },
    'inventory': {
      'openapi_anon_http': oaAnon['http'],
      'openapi_anon_paths': oaAnon['path_count'],
      'openapi_buyer_paths': oaBuyer['path_count'],
      'openapi_seller_paths': oaSeller['path_count'],
      'openapi_svc_paths': oaSvc['path_count'],
      'tables_svc': tablePaths,
      'rpcs_buyer': rpcPaths,
      'rpcs_anon': rpcAnon,
    },
    'probe_count': probes.length,
    'interesting': interesting,
    'probes': probes,
    'production_touched': false,
    'fase4': false,
  };

  final file = File('tool/redteam_blind_g_20260829/pass1_raw.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('WROTE ${file.path} probes=${probes.length} interesting=${interesting.length}');
  for (final p in interesting) {
    stdout.writeln(
      '  ${p['severity_hint']} ${p['id']} http=${p['http']} persisted=${p['persisted']} ${p['impact']}',
    );
  }
}
