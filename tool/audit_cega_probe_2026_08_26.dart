// ignore_for_file: avoid_print
/// Probe temporário de auditoria cega — JWT buyer/seller + anon.
/// Não usa service_role para "provar" defesas. Não paga Stripe. Não altera produção.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

late String url;
late String anon;
late String buyerId;
late String sellerId;

void main() async {
  final env = loadLiveOpsStagingEnv();
  url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: 'unused',
  );

  final buyerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  print('auth buyer_ok seller_ok');

  await _anonSurface();
  await _profiles(buyerJwt);
  await _wallets(buyerJwt, sellerJwt);
  await _orders(buyerJwt, sellerJwt);
  await _raffle(buyerJwt, sellerJwt);
  await _tips(buyerJwt);
  await _storage(buyerJwt);
  await _edges(buyerJwt, sellerJwt);
  await _livesKeys(buyerJwt, sellerJwt);
  await _adminEscalation(buyerJwt);
  print('PROBE_DONE');
}

Map<String, String> _h(String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> get _anonH => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    };

Future<http.Response> _get(String path, Map<String, String> headers) =>
    http.get(Uri.parse('$url$path'), headers: headers);

Future<http.Response> _post(
  String path,
  Map<String, String> headers,
  Object body,
) =>
    http.post(Uri.parse('$url$path'), headers: headers, body: jsonEncode(body));

Future<http.Response> _patch(
  String path,
  Map<String, String> headers,
  Object body,
) =>
    http.patch(Uri.parse('$url$path'), headers: headers, body: jsonEncode(body));

Future<http.Response> _rpc(
  String fn,
  String jwt,
  Map<String, dynamic> params,
) =>
    http.post(
      Uri.parse('$url/rest/v1/rpc/$fn'),
      headers: _h(jwt),
      body: jsonEncode(params),
    );

Future<http.Response> _edge(
  String fn,
  String jwt,
  Object body, {
  String method = 'POST',
}) {
  final uri = Uri.parse('$url/functions/v1/$fn');
  final headers = _h(jwt);
  if (method == 'GET') return http.get(uri, headers: headers);
  return http.post(uri, headers: headers, body: jsonEncode(body));
}

void _out(String id, int status, String note, {String? body}) {
  final snippet = (body ?? '').replaceAll('\n', ' ');
  final cut = snippet.length > 220 ? snippet.substring(0, 220) : snippet;
  print('FINDING $id status=$status $note body=$cut');
}

Future<void> _anonSurface() async {
  final tables = [
    'profiles',
    'orders',
    'wallets',
    'wallet_transactions',
    'lives',
    'products',
    'live_tips',
    'live_raffles',
    'live_reservation_requests',
    'chat_messages',
    'fleaber_commissions',
    'hub_profiles_public',
  ];
  for (final t in tables) {
    final r = await _get('/rest/v1/$t?select=*&limit=1', _anonH);
    _out('ANON_SELECT_$t', r.statusCode, 'anon select', body: r.body);
  }

  final list = await http.post(
    Uri.parse('$url/storage/v1/object/list/chat_media'),
    headers: _anonH,
    body: jsonEncode({
      'prefix': 'order_proofs/',
      'limit': 5,
      'offset': 0,
    }),
  );
  _out(
    'ANON_STORAGE_LIST_PROOFS',
    list.statusCode,
    'anon list order_proofs count_or_err',
    body: list.body.length > 400
        ? 'len=${list.body.length} sample_keys=${_storageNames(list.body)}'
        : list.body,
  );

  final listRoot = await http.post(
    Uri.parse('$url/storage/v1/object/list/chat_media'),
    headers: _anonH,
    body: jsonEncode({'prefix': '', 'limit': 8, 'offset': 0}),
  );
  _out(
    'ANON_STORAGE_LIST_ROOT',
    listRoot.statusCode,
    'anon list bucket root',
    body: 'len=${listRoot.body.length} names=${_storageNames(listRoot.body)}',
  );
}

String _storageNames(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is List) {
      return decoded
          .map((e) => e is Map ? (e['name'] ?? e['id'] ?? '?').toString() : '?')
          .take(8)
          .join('|');
    }
  } catch (_) {}
  return 'unparsed';
}

Future<void> _profiles(String buyerJwt) async {
  final other = await _get(
    '/rest/v1/profiles?id=eq.$sellerId&select=id,full_name,iban,mb_way,phone,user_type,email',
    _h(buyerJwt),
  );
  _out('BUYER_SELECT_SELLER_PROFILE', other.statusCode,
      'cross-user profile', body: other.body);

  final ownIban = await _get(
    '/rest/v1/profiles?id=eq.$buyerId&select=id,iban,mb_way',
    _h(buyerJwt),
  );
  _out('BUYER_SELECT_OWN_IBAN', ownIban.statusCode, 'own iban cols',
      body: ownIban.body);

  final dir = await _get(
    '/rest/v1/profiles_directory_public?select=id,full_name&limit=3',
    _h(buyerJwt),
  );
  _out('BUYER_DIRECTORY', dir.statusCode, 'directory view',
      body: 'len=${dir.body.length}');

  final payout = await _rpc('batata_seller_direct_payment_details', buyerJwt, {
    'p_seller_id': sellerId,
  });
  _out('BUYER_SELLER_PAYOUT_RPC', payout.statusCode,
      'iban rpc without necessarily open order', body: payout.body);

  final emailOracle = await _rpc('batata_find_user_id_by_email', buyerJwt, {
    'p_email': envDummyEmail(),
  });
  _out('EMAIL_ORACLE', emailOracle.statusCode, 'email to uuid',
      body: emailOracle.body);
}

String envDummyEmail() => 'naoexiste-auditoria-${DateTime.now().millisecondsSinceEpoch}@fleaber.test';

Future<void> _wallets(String buyerJwt, String sellerJwt) async {
  final patch = await _patch(
    '/rest/v1/wallets?id=eq.$buyerId',
    _h(buyerJwt),
    {'balance': 99999.12},
  );
  _out('BUYER_PATCH_WALLET', patch.statusCode, 'forge balance',
      body: patch.body);

  final otherW = await _get(
    '/rest/v1/wallets?id=eq.$sellerId&select=id,balance',
    _h(buyerJwt),
  );
  _out('BUYER_SELECT_SELLER_WALLET', otherW.statusCode, 'cross wallet',
      body: otherW.body);

  final ins = await _post(
    '/rest/v1/wallets',
    _h(buyerJwt),
    {'id': buyerId, 'balance': 88888},
  );
  _out('BUYER_INSERT_WALLET', ins.statusCode, 'insert invented balance',
      body: ins.body);

  final tx = await _post(
    '/rest/v1/wallet_transactions',
    _h(buyerJwt),
    {
      'wallet_id': buyerId,
      'amount': 500,
      'type': 'venda',
      'description': 'audit_cega',
    },
  );
  _out('BUYER_INSERT_WALLET_TX', tx.statusCode, 'insert ledger', body: tx.body);

  final payoutRpc = await _rpc('batata_wallet_payout_debit', buyerJwt, {
    'p_user_id': buyerId,
    'p_amount_cents': 100,
    'p_idempotency_key': 'auditcega-${DateTime.now().millisecondsSinceEpoch}',
  });
  _out('BUYER_PAYOUT_DEBIT_RPC', payoutRpc.statusCode, 'client debit rpc',
      body: payoutRpc.body);

  final credit = await _rpc('batata_credit_wallet_once', buyerJwt, {
    'p_wallet_id': buyerId,
    'p_order_id': '00000000-0000-0000-0000-000000000001',
    'p_amount': 10,
    'p_type': 'venda',
    'p_description': 'audit',
  });
  _out('BUYER_CREDIT_WALLET_RPC', credit.statusCode, 'credit once as user',
      body: credit.body);

  final own = await _get(
    '/rest/v1/wallets?id=eq.$buyerId&select=id,balance',
    _h(buyerJwt),
  );
  _out('BUYER_OWN_WALLET', own.statusCode, 'own wallet readable',
      body: own.body);
}

Future<void> _orders(String buyerJwt, String sellerJwt) async {
  final products = await _get(
    '/rest/v1/products?seller_id=eq.$sellerId&select=id,price,quantity,title&limit=1',
    _h(sellerJwt),
  );
  _out('SELLER_OWN_PRODUCT', products.statusCode, 'seller product',
      body: products.body.substring(0, products.body.length.clamp(0, 180)));

  String? productId;
  try {
    final list = jsonDecode(products.body);
    if (list is List && list.isNotEmpty) {
      productId = list.first['id']?.toString();
    }
  } catch (_) {}

  if (productId != null) {
    final fakePaid = await _post(
      '/rest/v1/orders',
      _h(buyerJwt),
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': productId,
        'quantity': 1,
        'price_total': 0.01,
        'status': 'pago',
        'payment_method': 'Seguro Fleaber',
      },
    );
    _out('BUYER_INSERT_ORDER_PAGO', fakePaid.statusCode, 'insert already paid',
        body: fakePaid.body);

    String? createdId;
    try {
      final decoded = jsonDecode(fakePaid.body);
      if (decoded is List && decoded.isNotEmpty) {
        createdId = decoded.first['id']?.toString();
        _out(
          'BUYER_INSERT_ORDER_PAGO_STATUS',
          fakePaid.statusCode,
          'resulting_status=${decoded.first['status']}',
          body: 'qty=${decoded.first['quantity']} total=${decoded.first['price_total']}',
        );
      }
    } catch (_) {}

    if (createdId != null) {
      final markPaid = await _patch(
        '/rest/v1/orders?id=eq.$createdId',
        _h(buyerJwt),
        {'status': 'pago'},
      );
      _out('BUYER_PATCH_OWN_PAGO', markPaid.statusCode, 'buyer self-pay',
          body: markPaid.body);

      final bumpQty = await _patch(
        '/rest/v1/orders?id=eq.$createdId',
        _h(buyerJwt),
        {'quantity': 99, 'price_total': 0.01},
      );
      _out('BUYER_PATCH_PREPAY_QTY', bumpQty.statusCode, 'prepay qty/price',
          body: bumpQty.body);

      final cancel = await _patch(
        '/rest/v1/orders?id=eq.$createdId',
        _h(buyerJwt),
        {'status': 'cancelado'},
      );
      _out('BUYER_CANCEL_PREPAY', cancel.statusCode, 'cleanup cancel',
          body: cancel.body);
    }

    final sellerFake = await _post(
      '/rest/v1/orders',
      _h(sellerJwt),
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': productId,
        'quantity': 1,
        'price_total': 1,
        'status': 'pago',
        'payment_method': 'MB WAY',
      },
    );
    _out('SELLER_INSERT_ORDER_PAGO', sellerFake.statusCode,
        'seller forges paid order for buyer', body: sellerFake.body);

    String? sellerOrderId;
    String? sellerOrderStatus;
    try {
      final decoded = jsonDecode(sellerFake.body);
      if (decoded is List && decoded.isNotEmpty) {
        sellerOrderId = decoded.first['id']?.toString();
        sellerOrderStatus = decoded.first['status']?.toString();
      }
    } catch (_) {}
    _out(
      'SELLER_INSERT_ORDER_PAGO_STATUS',
      sellerFake.statusCode,
      'status=$sellerOrderStatus id=${sellerOrderId ?? "none"}',
    );

    if (sellerOrderId != null) {
      final sellerMark = await _patch(
        '/rest/v1/orders?id=eq.$sellerOrderId',
        _h(sellerJwt),
        {'status': 'pago'},
      );
      _out('SELLER_PATCH_PAGO', sellerMark.statusCode, 'seller marks paid',
          body: sellerMark.body);

      final sellerCancel = await _patch(
        '/rest/v1/orders?id=eq.$sellerOrderId',
        _h(sellerJwt),
        {'status': 'cancelado'},
      );
      _out('SELLER_CANCEL_FORGED', sellerCancel.statusCode, 'cleanup',
          body: sellerCancel.body);
    }
  }

  final prize = await _post(
    '/rest/v1/orders',
    _h(buyerJwt),
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'quantity': 1,
      'price_total': 0,
      'status': 'premio_rifa',
      'payment_method': 'Prémio da Rifa',
    },
  );
  _out('BUYER_FORGE_PRIZE_ORDER', prize.statusCode, 'forge raffle prize',
      body: prize.body);
}

Future<void> _raffle(String buyerJwt, String sellerJwt) async {
  final create = await _rpc('batata_create_live_raffle', buyerJwt, {
    'p_live_id': '00000000-0000-0000-0000-000000000001',
  });
  _out('BUYER_CREATE_RAFFLE', create.statusCode, 'buyer create raffle',
      body: create.body);

  final prizeOrder = await _rpc('batata_create_raffle_prize_order', buyerJwt, {
    'p_raffle_id': '00000000-0000-0000-0000-000000000001',
    'p_winner_id': buyerId,
    'p_winner_count': 1,
  });
  _out('BUYER_PRIZE_ORDER_RPC', prizeOrder.statusCode, 'buyer prize rpc',
      body: prizeOrder.body);

  final draw = await _rpc('batata_draw_live_raffle_winners', buyerJwt, {
    'p_raffle_id': '00000000-0000-0000-0000-000000000001',
  });
  _out('BUYER_DRAW_RAFFLE', draw.statusCode, 'buyer draw', body: draw.body);
}

Future<void> _tips(String buyerJwt) async {
  final pending = await _rpc('batata_create_live_tip_pending', buyerJwt, {
    'p_live_id': null,
    'p_seller_id': sellerId,
    'p_amount': 50,
    'p_message': 'audit_cega_do_not_pay',
  });
  _out('BUYER_CREATE_TIP_50', pending.statusCode, 'pending tip 50eur',
      body: pending.body);

  String? tipId;
  try {
    final decoded = jsonDecode(pending.body);
    if (decoded is String) tipId = decoded;
    if (decoded is Map && decoded['id'] != null) tipId = decoded['id'].toString();
  } catch (_) {
    final t = pending.body.replaceAll('"', '').trim();
    if (t.length == 36) tipId = t;
  }

  if (tipId != null) {
    final checkout = await _edge('create-live-tip-checkout', buyerJwt, {
      'tip_id': tipId,
      'seller_id': sellerId,
      'amount_eur': 1,
    });
    _out(
      'TIP_UNDERPAY_CHECKOUT',
      checkout.statusCode,
      'checkout 1eur against tip 50eur',
      body: checkout.body,
    );

    try {
      final map = jsonDecode(checkout.body);
      if (map is Map) {
        print(
          'FINDING TIP_UNDERPAY_DETAIL tip_id=$tipId checkoutUrl=${map['checkoutUrl'] != null} session=${map['checkoutSessionId']}',
        );
      }
    } catch (_) {}

    final settleRpc = await _rpc('batata_settle_live_tip_from_stripe', buyerJwt, {
      'p_tip_id': tipId,
      'p_stripe_session_id': 'cs_test_audit',
    });
    _out('BUYER_SETTLE_TIP_RPC', settleRpc.statusCode, 'buyer settle tip',
        body: settleRpc.body);
  }

  final noCap = await _rpc('batata_create_live_tip_pending', buyerJwt, {
    'p_seller_id': sellerId,
    'p_amount': 99999,
  });
  _out('TIP_PENDING_NO_CAP', noCap.statusCode, 'pending tip 99999',
      body: noCap.body);
}

Future<void> _storage(String jwt) async {
  final path = 'order_proofs/audit_cega_${DateTime.now().millisecondsSinceEpoch}.txt';
  final upload = await http.post(
    Uri.parse('$url/storage/v1/object/chat_media/$path'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'text/plain',
      'x-upsert': 'true',
    },
    body: 'audit-cega-disposable',
  );
  _out('AUTH_UPLOAD_UNOWNED_PREFIX', upload.statusCode,
      'upload order_proofs without uid path=$path', body: upload.body);

  if (upload.statusCode < 300) {
    final pub = await http.get(
      Uri.parse('$url/storage/v1/object/public/chat_media/$path'),
    );
    _out('ANON_READ_PUBLIC_PROOF', pub.statusCode, 'anon GET public object',
        body: 'len=${pub.body.length}');
  }

  final hijack = await http.post(
    Uri.parse(
      '$url/storage/v1/object/chat_media/product_photos/$sellerId/audit_cega.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'text/plain',
    },
    body: 'hijack-attempt',
  );
  _out('BUYER_UPLOAD_SELLER_PRODUCT_PREFIX', hijack.statusCode,
      'write into seller product_photos prefix', body: hijack.body);
}

Future<void> _edges(String buyerJwt, String sellerJwt) async {
  final refund = await _edge('refund-order', buyerJwt, {
    'order_id': '00000000-0000-0000-0000-000000000001',
  });
  _out('BUYER_REFUND_EDGE', refund.statusCode, 'buyer refund other order',
      body: refund.body);

  final webhook = await http.post(
    Uri.parse('$url/functions/v1/stripe-webhook'),
    headers: {
      'apikey': anon,
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'type': 'checkout.session.completed'}),
  );
  _out('WEBHOOK_NO_SIG', webhook.statusCode, 'unsigned webhook',
      body: webhook.body);

  final settleGet = await http.get(
    Uri.parse(
      '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_not_real',
    ),
    headers: {'apikey': anon},
  );
  _out('SETTLE_GET_NO_JWT', settleGet.statusCode, 'public settle URL',
      body: settleGet.body);

  final pairing = await http.post(
    Uri.parse('$url/functions/v1/ps-pairing-claim'),
    headers: {'apikey': anon, 'Content-Type': 'application/json'},
    body: jsonEncode({'code': '000000', 'device_id': 'audit-cega'}),
  );
  _out('PS_PAIRING_NO_JWT', pairing.statusCode, 'pairing without jwt',
      body: pairing.body);

  final nuke = await _edge('delete-test-account', buyerJwt, {
    'confirm': 'APAGAR TUDO',
  });
  _out('DELETE_TEST_ACCOUNT', nuke.statusCode, 'nuke as buyer',
      body: nuke.body);

  final mux = await _edge('create-mux-live', buyerJwt, {'title': 'x'});
  _out('BUYER_CREATE_MUX_SHORT_TITLE', mux.statusCode, 'mux title too short',
      body: mux.body);

  final cpi = await _edge('create-payment-intent', buyerJwt, {
    'amount': 1,
    'buyer_id': buyerId,
  });
  _out('CPI_CLIENT_AMOUNT', cpi.statusCode, 'client amount without order',
      body: cpi.body);
}

Future<void> _livesKeys(String buyerJwt, String sellerJwt) async {
  final buyerLives = await _get(
    '/rest/v1/lives?select=id,status,mux_stream_key,stream_key,mux_playback_id&limit=3',
    _h(buyerJwt),
  );
  _out('BUYER_LIVES_KEYS', buyerLives.statusCode, 'buyer select stream keys',
      body: buyerLives.body);

  final sellerLives = await _get(
    '/rest/v1/lives?seller_id=eq.$sellerId&select=id,status,mux_stream_key,stream_key&limit=2',
    _h(sellerJwt),
  );
  _out('SELLER_LIVES_KEYS', sellerLives.statusCode, 'seller select own keys',
      body: sellerLives.body);

  final msgs = await _get(
    '/rest/v1/live_messages?select=id,body,user_id&limit=3',
    _h(buyerJwt),
  );
  _out('BUYER_LIVE_MESSAGES', msgs.statusCode, 'live chat dump',
      body: 'len=${msgs.body.length} status_detail=${msgs.body.substring(0, msgs.body.length.clamp(0, 160))}');
}

Future<void> _adminEscalation(String buyerJwt) async {
  final patch = await _patch(
    '/rest/v1/profiles?id=eq.$buyerId',
    _h(buyerJwt),
    {'user_type': 'admin'},
  );
  _out('BUYER_SET_ADMIN', patch.statusCode, 'self promote admin',
      body: patch.body);

  final read = await _get(
    '/rest/v1/profiles?id=eq.$buyerId&select=id,user_type',
    _h(buyerJwt),
  );
  _out('BUYER_USER_TYPE_AFTER', read.statusCode, 'user_type after admin patch',
      body: read.body);

  final adminList = await _rpc('batata_admin_list_profiles', buyerJwt, {
    'p_limit': 5,
  });
  _out('BUYER_ADMIN_LIST', adminList.statusCode, 'admin rpc as buyer',
      body: adminList.body);
}
