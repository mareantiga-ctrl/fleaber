// Red Team Cego B — pass 2 (composition + privacy columns)
// dart run tool/redteam_blind_b_20260829T1755_pass2.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260829T1755';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const tag = 'RTB-B-${stamp}-p2';

typedef Json = Map<String, dynamic>;

final findings = <Json>[];
final probes = <Json>[];
final cleanup = <String, List<String>>{
  'products': [],
  'orders': [],
  'lives': [],
  'live_items': [],
  'live_reservation_requests': [],
  'product_offers': [],
  'reviews': [],
  'auth_users': [],
};

void note(String id, String title, Json data) =>
    probes.add({'id': id, 'title': title, ...data});

void finding(Json f) => findings.add(f);

Json snap(http.Response r, {int max = 900}) {
  var b = r.body;
  if (b.length > max) b = '${b.substring(0, max)}…';
  return {'status': r.statusCode, 'body': b};
}

Future<http.Response> rest(
  String url,
  String key,
  String bearer, {
  String method = 'GET',
  required String path,
  Object? body,
}) {
  final headers = {
    'apikey': key,
    'Authorization': 'Bearer $bearer',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final uri = Uri.parse('$url$path');
  switch (method) {
    case 'POST':
      return http.post(uri, headers: headers, body: jsonEncode(body));
    case 'PATCH':
      return http.patch(uri, headers: headers, body: jsonEncode(body));
    case 'DELETE':
      return http.delete(uri, headers: headers);
    default:
      return http.get(uri, headers: headers);
  }
}

String? idOf(http.Response r) {
  try {
    final v = jsonDecode(r.body);
    if (v is List && v.isNotEmpty) return (v.first as Json)['id']?.toString();
    if (v is Map) return v['id']?.toString();
  } catch (_) {}
  return null;
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) throw StateError('not staging');
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  stdout.writeln('pass2 $stamp');

  await privacyPass(url, anon, svc, buyerJwt, sellerJwt, buyerId, sellerId);
  await financePass(url, anon, buyerJwt, sellerJwt, buyerId, sellerId);
  await stockPass(
    client,
    url,
    anon,
    svc,
    buyerJwt,
    sellerJwt,
    buyerId,
    sellerId,
    env,
  );

  for (final e in cleanup.entries) {
    for (final id in e.value) {
      try {
        await client.deleteWhere(e.key, 'id=eq.$id');
      } catch (_) {}
    }
  }

  final out = {
    'pass': 2,
    'frozen_at': DateTime.now().toUtc().toIso8601String(),
    'findings': findings,
    'probes': probes,
  };
  File('tool/redteam_blind_b_${stamp}_pass2.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  stdout.writeln(
    'pass2 findings=${findings.length} '
    'P0=${findings.where((f) => f['severity'] == 'P0').length} '
    'P1=${findings.where((f) => f['severity'] == 'P1').length} '
    'P2=${findings.where((f) => f['severity'] == 'P2').length}',
  );
}

Future<void> privacyPass(
  String url,
  String anon,
  String svc,
  String buyerJwt,
  String sellerJwt,
  String buyerId,
  String sellerId,
) async {
  final tables = [
    'profiles',
    'orders',
    'chat_messages',
    'chats',
    'stripe_checkout_events',
    'wallets',
    'wallet_transactions',
    'order_disputes',
    'reviews',
    'ps_ingest_audit',
    'ps_pairing_sessions',
    'live_private_messages',
    'live_messages',
    'fleaber_commissions',
    'batata_anon_rate_limits',
    'seller_device_tokens',
    'live_raffle_audit_log',
    'hub_profiles_public',
  ];
  for (final t in tables) {
    final r = await rest(
      url,
      anon,
      buyerJwt,
      path: '/rest/v1/$t?select=*&limit=8',
    );
    note('p2.priv.buyer.$t', 'buyer SELECT * $t', snap(r));
  }

  final crossEvt = await rest(
    url,
    anon,
    buyerJwt,
    path: '/rest/v1/stripe_checkout_events?buyer_id=neq.$buyerId&select=id,session_id,buyer_id,order_id,event,detail&limit=8',
  );
  note('p2.priv.events_cross', 'buyer GET events of others', snap(crossEvt));
  if (crossEvt.statusCode == 200 &&
      crossEvt.body.contains('session_id') &&
      !crossEvt.body.startsWith('[]')) {
    finding({
      'id': 'RTB-B-1755-P1-EVENTS-CROSS',
      'title': 'Buyer lê stripe_checkout_events de terceiros (session_id)',
      'severity': 'P1',
      'actor': 'buyer JWT',
      'preconditions': 'RLS events',
      'request': 'GET stripe_checkout_events?buyer_id=neq.self',
      'before': {},
      'result': snap(crossEvt),
      'after': snap(crossEvt),
      'impact': 'session_id + metadata financeira cross-user; GET settle',
      'reproduction': 'SELECT events filtrado a outro buyer_id',
    });
  }

  final prof = await rest(
    url,
    anon,
    buyerJwt,
    path:
        '/rest/v1/profiles?id=eq.$sellerId&select=id,phone,iban,mb_way,legal_full_name,shipping_line1,full_name,user_type',
  );
  note('p2.priv.profile_seller', 'buyer GET seller profile PII cols', snap(prof));
  if (prof.statusCode == 200 && prof.body.contains(sellerId)) {
    finding({
      'id': 'RTB-B-1755-P1-PROFILE-CROSS',
      'title': 'Buyer lê perfil do seller (row alheia)',
      'severity': 'P1',
      'actor': 'buyer JWT',
      'preconditions': 'UUID seller conhecido',
      'request': 'GET /profiles?id=eq.seller',
      'before': {},
      'result': snap(prof),
      'after': snap(prof),
      'impact': 'cross-user PII (phone/morada/iban se preenchidos)',
      'reproduction': 'GET profiles de outro id',
    });
  }

  final dir = await rest(
    url,
    anon,
    buyerJwt,
    path: '/rest/v1/profiles_directory_public?id=eq.$sellerId&select=*',
  );
  note('p2.priv.directory', 'directory public seller', snap(dir));

  final foreignOrders = await rest(
    url,
    svc,
    svc,
    path:
        '/rest/v1/orders?select=id,buyer_id,seller_id,status,price_total&buyer_id=neq.$buyerId&seller_id=neq.$buyerId&limit=5',
  );
  note('p2.priv.foreign_obs', 'observe foreign orders', {
    'status': foreignOrders.statusCode,
    'n': _n(foreignOrders.body),
  });
  for (final oid in _ids(foreignOrders.body).take(3)) {
    final r = await rest(
      url,
      anon,
      buyerJwt,
      path: '/rest/v1/orders?id=eq.$oid&select=*',
    );
    note('p2.priv.order_uuid', 'buyer GET foreign order *', snap(r));
    if (r.statusCode == 200 && r.body.contains(oid) && r.body.contains('"id"')) {
      finding({
        'id': 'RTB-B-1755-P1-ORDER-UUID',
        'title': 'Buyer lê order alheia por UUID',
        'severity': 'P1',
        'actor': 'buyer JWT',
        'preconditions': 'UUID conhecido',
        'request': 'GET /orders?id=eq.foreign&select=*',
        'before': {},
        'result': snap(r),
        'after': snap(r),
        'impact': 'cross-user encomenda',
        'reproduction': 'GET order por id sem ser party',
      });
    }
  }

  // Chat enum: pick a chat_id from seller messages that might not include buyer
  final sellerChats = await rest(
    url,
    anon,
    sellerJwt,
    path: '/rest/v1/chat_messages?select=chat_id,sender_id,text&limit=20',
  );
  note('p2.priv.seller_chats', 'seller own messages sample', snap(sellerChats, max: 400));
  final chatIds = <String>{};
  try {
    final list = jsonDecode(sellerChats.body);
    if (list is List) {
      for (final e in list) {
        chatIds.add('${(e as Json)['chat_id']}');
      }
    }
  } catch (_) {}
  for (final cid in chatIds.take(3)) {
    final r = await rest(
      url,
      anon,
      buyerJwt,
      path: '/rest/v1/chat_messages?chat_id=eq.$cid&select=id,chat_id,sender_id,text&limit=5',
    );
    note('p2.priv.chat_enum', 'buyer GET chat $cid', snap(r, max: 400));
    if (r.statusCode == 200 && r.body.contains('"id"') && r.body != '[]') {
      // may be legitimate shared chat with seller
      final onlySeller = !r.body.contains(buyerId);
      if (onlySeller && r.body.contains('"text"')) {
        finding({
          'id': 'RTB-B-1755-P1-CHAT-ENUM',
          'title': 'Buyer lê mensagens de chat por UUID sem ser participante',
          'severity': 'P1',
          'actor': 'buyer JWT',
          'preconditions': 'chat_id conhecido',
          'request': 'GET chat_messages?chat_id=eq.{id}',
          'before': {'chat_id': cid},
          'result': snap(r, max: 400),
          'after': snap(r, max: 400),
          'impact': 'cross-user chat',
          'reproduction': 'GET messages by chat_id',
        });
      }
    }
  }
}

int _n(String body) {
  try {
    final v = jsonDecode(body);
    if (v is List) return v.length;
  } catch (_) {}
  return -1;
}

List<String> _ids(String body) {
  try {
    final v = jsonDecode(body);
    if (v is List) {
      return v
          .map((e) => (e as Json)['id']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
  } catch (_) {}
  return [];
}

Future<void> financePass(
  String url,
  String anon,
  String buyerJwt,
  String sellerJwt,
  String buyerId,
  String sellerId,
) async {
  final partial = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/rpc/batata_process_partial_refund_dispute',
    body: {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_percent': 100,
    },
  );
  note('p2.fin.partial', 'partial refund 100% fake order', snap(partial));

  final finish = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/rpc/batata_wallet_payout_finish',
    body: {
      'p_idempotency_key': '$tag-fin',
      'p_stripe_transfer_id': 'tr_x',
      'p_failed': false,
    },
  );
  note('p2.fin.payout_finish', 'payout_finish as buyer', snap(finish));
  if (finish.statusCode >= 200 && finish.statusCode < 300) {
    finding({
      'id': 'RTB-B-1755-P1-PAYOUT-FINISH',
      'title': 'Buyer JWT chama payout_finish',
      'severity': 'P1',
      'actor': 'buyer JWT',
      'preconditions': 'RPC grant',
      'request': 'rpc batata_wallet_payout_finish',
      'before': {},
      'result': snap(finish),
      'after': snap(finish),
      'impact': 'marcar transfer Stripe sem ser o débito',
      'reproduction': 'RPC finish com JWT buyer',
    });
  }

  // Real live for tip-from-wallet
  final lives = await rest(
    url,
    anon,
    sellerJwt,
    path: '/rest/v1/hub_lives_public?select=id,seller_id&limit=5',
  );
  note('p2.fin.hub_lives', 'hub lives as seller', snap(lives, max: 400));
  String? liveId;
  try {
    final list = jsonDecode(lives.body);
    if (list is List && list.isNotEmpty) {
      liveId = (list.first as Json)['id']?.toString();
    }
  } catch (_) {}
  if (liveId != null) {
    final tip = await rest(
      url,
      anon,
      buyerJwt,
      method: 'POST',
      path: '/rest/v1/rpc/batata_send_live_tip_from_wallet',
      body: {
        'p_live_id': liveId,
        'p_seller_id': sellerId,
        'p_amount': 1,
        'p_message': tag,
      },
    );
    note('p2.fin.tip_wallet', 'tip from wallet real live', snap(tip));
  }
}

Future<void> stockPass(
  LiveOpsStagingClient client,
  String url,
  String anon,
  String svc,
  String buyerJwt,
  String sellerJwt,
  String buyerId,
  String sellerId,
  Map<String, String> env,
) async {
  final prod = await rest(
    url,
    anon,
    sellerJwt,
    method: 'POST',
    path: '/rest/v1/products',
    body: {
      'seller_id': sellerId,
      'title': '$tag stock1',
      'price': 6.5,
      'quantity': 1,
      'is_sold': false,
      'list_on_marketplace': true,
    },
  );
  note('p2.stock.product', 'create stock=1', snap(prod));
  final productId = idOf(prod);
  if (productId == null) return;
  cleanup['products']!.add(productId);

  Future<http.Response> order({
    required String jwt,
    required String bid,
    double priceTotal = 0.01,
    String pm = 'Pagamento na app',
    String? liveId,
    String? liveItemId,
    String? offerId,
    int qty = 1,
  }) {
    return rest(
      url,
      anon,
      jwt,
      method: 'POST',
      path: '/rest/v1/orders',
      body: {
        'buyer_id': bid,
        'seller_id': sellerId,
        'product_id': productId,
        'quantity': qty,
        'price_total': priceTotal,
        'status': 'reserva_pendente',
        'payment_method': pm,
        'shipping_method': 'hand',
        if (liveId != null) 'live_id': liveId,
        if (liveItemId != null) 'live_item_id': liveItemId,
        if (offerId != null) 'product_offer_id': offerId,
      },
    );
  }

  final o1 = await order(jwt: buyerJwt, bid: buyerId, priceTotal: 0.01);
  note('p2.stock.o1', 'order price_total=0.01', snap(o1));
  final order1 = idOf(o1);
  if (order1 != null) cleanup['orders']!.add(order1);

  Json? sealed;
  if (order1 != null) {
    final obs = await rest(
      url,
      svc,
      svc,
      path:
          '/rest/v1/orders?id=eq.$order1&select=id,status,price_total,contract_unit_cents,contract_qty,quantity',
    );
    note('p2.stock.sealed', 'sealed vs client price_total', snap(obs));
    try {
      sealed = (jsonDecode(obs.body) as List).first as Json;
    } catch (_) {}
  }

  final ck1 = order1 == null
      ? null
      : await http.post(
          Uri.parse('$url/functions/v1/create-payment-intent'),
          headers: {
            'apikey': anon,
            'Authorization': 'Bearer $buyerJwt',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'buyer_id': buyerId,
            'order_id': order1,
            'shipping_method': 'hand',
            'amount': 1,
          }),
        );
  if (ck1 != null) {
    note('p2.stock.ck1', 'checkout spoof amount=1', snap(ck1));
    var charged = 0;
    try {
      final m = jsonDecode(ck1.body) as Json;
      charged = int.tryParse('${m['server_amount_cents'] ?? 0}') ?? 0;
    } catch (_) {}
    final stored = sealed == null
        ? -1
        : ((num.tryParse('${sealed['price_total']}') ?? 0) * 100).round();
    if (ck1.statusCode == 200 && charged >= 50 && stored >= 0 && stored < charged) {
      finding({
        'id': 'RTB-B-1755-P1-PRICE-TOTAL-SPLIT',
        'title': 'price_total cliente ≠ montante Stripe (contrato)',
        'severity': 'P1',
        'actor': 'buyer JWT',
        'preconditions': 'INSERT orders.price_total=0.01; catálogo 6.50€',
        'request':
            'POST /orders price_total=0.01; POST create-payment-intent amount=1',
        'before': sealed,
        'result': snap(ck1),
        'after': {
          'price_total_cents': stored,
          'stripe_quote_cents': charged,
          'contract_unit_cents': sealed?['contract_unit_cents'],
        },
        'impact':
            'oversell refund e fallback refund usam price_total; captura usa contrato. Desvio ${charged - stored} cêntimos por unidade.',
        'reproduction':
            'INSERT price_total mínimo; checkout; comparar server_amount_cents com orders.price_total; oversell refund em create-payment-intent usa euroToCents(price_total).',
      });
    }
  }

  // Second order same SKU + checkout (hold)
  final o2 = await order(jwt: buyerJwt, bid: buyerId, priceTotal: 0.01);
  note('p2.stock.o2', 'second order same SKU', snap(o2));
  final order2 = idOf(o2);
  if (order2 != null) {
    cleanup['orders']!.add(order2);
    final ck2 = await http.post(
      Uri.parse('$url/functions/v1/create-payment-intent'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerJwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'buyer_id': buyerId,
        'order_id': order2,
        'shipping_method': 'hand',
      }),
    );
    note('p2.stock.ck2', 'second checkout stock=1', snap(ck2));
    if (ck1 != null &&
        ck1.statusCode == 200 &&
        ck2.statusCode == 200 &&
        ck1.body.contains('checkoutSessionId') &&
        ck2.body.contains('checkoutSessionId')) {
      finding({
        'id': 'RTB-B-1755-P2-DOUBLE-SESSION',
        'title': 'Duas Checkout Sessions no mesmo stock=1',
        'severity': 'P2',
        'actor': 'buyer JWT',
        'preconditions': 'quantity=1; duas orders',
        'request': '2x create-payment-intent',
        'before': {'product': productId},
        'result': {'ck1': snap(ck1, max: 300), 'ck2': snap(ck2, max: 300)},
        'after': {'sessions': 2},
        'impact':
            'hold não atómico; settle deve refund oversell. Combinado com price_total=0.01 o refund oversell é 1 cêntimo.',
        'reproduction': 'duas orders + dois checkouts antes de pagar',
      });
    }

    if (order1 != null) {
      final bag = await http.post(
        Uri.parse('$url/functions/v1/create-payment-intent'),
        headers: {
          'apikey': anon,
          'Authorization': 'Bearer $buyerJwt',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'buyer_id': buyerId,
          'order_id': order1,
          'bag_checkout': true,
          'shipping_method': 'hand',
          'bag_lines': [
            {'order_id': order2},
            {'order_id': order2},
          ],
        }),
      );
      note('p2.stock.bag_dup', 'bag duplicate order2', snap(bag));
      if (bag.statusCode == 200 && bag.body.contains('checkout')) {
        var cents = 0;
        try {
          cents = int.tryParse('${(jsonDecode(bag.body) as Json)['server_amount_cents']}') ?? 0;
        } catch (_) {}
        finding({
          'id': 'RTB-B-1755-P1-BAG-DUP',
          'title': 'Bag duplica a mesma order no total Stripe',
          'severity': 'P1',
          'actor': 'buyer JWT',
          'preconditions': 'order checkoutable',
          'request': 'bag_lines=[order,order]',
          'before': {'order': order2},
          'result': snap(bag),
          'after': {'server_amount_cents': cents},
          'impact': 'cobrança a dobrar; settle itera linhas duplicadas',
          'reproduction': 'bag_checkout com o mesmo order_id duas vezes',
        });
      }
    }
  }

  // Offer reuse with price_total
  final off = await rest(
    url,
    anon,
    buyerJwt,
    method: 'POST',
    path: '/rest/v1/product_offers',
    body: {
      'product_id': productId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 3.5,
      'offered_by': 'buyer',
      'status': 'pending',
    },
  );
  note('p2.offer.ins', 'offer insert', snap(off));
  final offerId = idOf(off);
  if (offerId != null) {
    cleanup['product_offers']!.add(offerId);
    await rest(
      url,
      anon,
      sellerJwt,
      method: 'PATCH',
      path: '/rest/v1/product_offers?id=eq.$offerId',
      body: {
        'status': 'accepted',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    final made = <String>[];
    for (var i = 0; i < 2; i++) {
      final so = await rest(
        url,
        anon,
        sellerJwt,
        method: 'POST',
        path: '/rest/v1/orders',
        body: {
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'product_id': productId,
          'product_offer_id': offerId,
          'quantity': 1,
          'price_total': 3.5,
          'status': 'reservado',
          'payment_method': 'MB WAY',
          'shipping_method': 'hand',
        },
      );
      note('p2.offer.order_$i', 'seller order from offer $i', snap(so));
      final oid = idOf(so);
      if (oid != null) {
        made.add(oid);
        cleanup['orders']!.add(oid);
      }
    }
    if (made.length >= 2) {
      finding({
        'id': 'RTB-B-1755-P1-OFFER-REUSE',
        'title': 'Uma oferta aceite gera duas orders seller-side',
        'severity': 'P1',
        'actor': 'seller JWT',
        'preconditions': 'product_offers.status=accepted; stock=1',
        'request': '2x POST /orders product_offer_id=same',
        'before': {'offer': offerId, 'product': productId},
        'result': {'order_ids': made},
        'after': {'orders': made.length},
        'impact': 'duas reservas económicas na mesma unidade; checkout/pago duplo',
        'reproduction': 'aceitar oferta; INSERT duas orders com o mesmo product_offer_id',
      });
    }
  }

  // Live dual inventory via service setup
  final live = await rest(
    url,
    svc,
    svc,
    method: 'POST',
    path: '/rest/v1/lives',
    body: {
      'seller_id': sellerId,
      'title': '$tag live',
      'status': 'ended',
      'is_active': false,
    },
  );
  note('p2.live.create', 'service insert live', snap(live));
  final liveId = idOf(live);
  if (liveId != null) {
    cleanup['lives']!.add(liveId);
    final li = await rest(
      url,
      svc,
      svc,
      method: 'POST',
      path: '/rest/v1/live_items',
      body: {
        'live_id': liveId,
        'seller_id': sellerId,
        'product_id': productId,
        'title': '$tag li',
        'price': 6.5,
        'quantity': 2,
      },
    );
    note('p2.live.item', 'live_item qty=2 product qty=1', snap(li));
    final liveItemId = idOf(li);
    if (liveItemId != null) {
      cleanup['live_items']!.add(liveItemId);
      final res = await rest(
        url,
        anon,
        sellerJwt,
        method: 'POST',
        path: '/rest/v1/live_reservation_requests',
        body: {
          'live_id': liveId,
          'live_item_id': liveItemId,
          'seller_id': sellerId,
          'buyer_id': buyerId,
          'requested_qty': 2,
          'status': 'accepted',
          'source': 'fleaber_live',
        },
      );
      note('p2.live.res2', 'seller accept qty=2 vs product=1', snap(res));
      final rid = idOf(res);
      if (rid != null) cleanup['live_reservation_requests']!.add(rid);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        finding({
          'id': 'RTB-B-1755-P1-LIVE-QTY-DESYNC',
          'title': 'Reserva live qty=2 aceite com products.quantity=1',
          'severity': 'P1',
          'actor': 'seller JWT',
          'preconditions': 'live_item.quantity=2; product.quantity=1',
          'request': 'POST live_reservation_requests status=accepted requested_qty=2',
          'before': {'product_qty': 1, 'live_item_qty': 2},
          'result': snap(res),
          'after': snap(res),
          'impact': 'capacidade live independente do stock marketplace; oversell composto',
          'reproduction': 'criar live_item com qty > products.quantity; aceitar reserva',
        });
      }
      final st = await rest(
        url,
        anon,
        sellerJwt,
        method: 'POST',
        path: '/rest/v1/rpc/batata_live_item_stock',
        body: {'p_live_item_id': liveItemId},
      );
      note('p2.live.stock', 'live_item_stock rpc', snap(st));

      final lo = await order(
        jwt: buyerJwt,
        bid: buyerId,
        priceTotal: 6.5,
        liveId: liveId,
        liveItemId: liveItemId,
      );
      note('p2.live.order', 'marketplace+live order after reservation', snap(lo));
      final loid = idOf(lo);
      if (loid != null) {
        cleanup['orders']!.add(loid);
        final clk = await http.post(
          Uri.parse('$url/functions/v1/create-payment-intent'),
          headers: {
            'apikey': anon,
            'Authorization': 'Bearer $buyerJwt',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'buyer_id': buyerId,
            'order_id': loid,
            'shipping_method': 'hand',
          }),
        );
        note('p2.live.checkout', 'checkout live order after accepted qty=2', snap(clk));
      }
    }
  }

  // Disposable second buyer for race checkout
  final email2 = 'rtb-b-p2-$stamp@staging.fleaber.bot';
  String? buyer2Id;
  try {
    buyer2Id = await client.createAdminUser(
      email: email2,
      password: 'RtbB-pass-1755!',
      userMetadata: {'full_name': tag},
    );
    cleanup['auth_users']!.add(buyer2Id);
  } catch (e) {
    note('p2.buyer2.create', 'create disposable', {'error': e.toString()});
  }
  if (buyer2Id != null) {
    // profile row may need insert
    try {
      await rest(
        url,
        svc,
        svc,
        method: 'POST',
        path: '/rest/v1/profiles',
        body: {
          'id': buyer2Id,
          'full_name': tag,
          'user_type': 'comprador',
        },
      );
    } catch (_) {}
    String? jwt2;
    try {
      jwt2 = await client.signIn(email: email2, password: 'RtbB-pass-1755!');
    } catch (e) {
      note('p2.buyer2.login', 'login', {'error': e.toString()});
    }
    if (jwt2 != null) {
      final ox = await order(jwt: jwt2, bid: buyer2Id, priceTotal: 6.5);
      note('p2.buyer2.order', 'second buyer order stock=1', snap(ox));
      final oid = idOf(ox);
      if (oid != null) {
        cleanup['orders']!.add(oid);
        final ck = await http.post(
          Uri.parse('$url/functions/v1/create-payment-intent'),
          headers: {
            'apikey': anon,
            'Authorization': 'Bearer $jwt2',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'buyer_id': buyer2Id,
            'order_id': oid,
            'shipping_method': 'hand',
          }),
        );
        note('p2.buyer2.ck', 'second buyer checkout', snap(ck));
      }
    }
  }

  // Stripe pay if secret present
  final sk = (env['STRIPE_SECRET_KEY'] ?? '').trim();
  if (sk.startsWith('sk_test_') && ck1 != null && ck1.statusCode == 200) {
    try {
      final m = jsonDecode(ck1.body) as Json;
      final cs = '${m['checkoutSessionId'] ?? ''}';
      if (cs.startsWith('cs_')) {
        final paid = await _tryPayCheckout(sk, cs);
        note('p2.stripe.pay1', 'pay session 1', paid);
      }
    } catch (e) {
      note('p2.stripe.pay1', 'pay failed', {'error': e.toString()});
    }
  }

  // Reviews columns
  final revCols = await rest(
    url,
    anon,
    buyerJwt,
    path: '/rest/v1/reviews?select=*&limit=1',
  );
  note('p2.rev.cols', 'reviews sample', snap(revCols, max: 500));

  // MB WAY collusion with price_total
  final mb = await order(
    jwt: buyerJwt,
    bid: buyerId,
    priceTotal: 6.5,
    pm: 'MB WAY',
  );
  note('p2.mb.order', 'MB WAY order', snap(mb));
  final mbid = idOf(mb);
  if (mbid != null) {
    cleanup['orders']!.add(mbid);
    final a = await rest(
      url,
      anon,
      sellerJwt,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$mbid',
      body: {'status': 'reservado'},
    );
    note('p2.mb.reservado', 'seller reservado', snap(a));
    final p = await rest(
      url,
      anon,
      sellerJwt,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$mbid',
      body: {'status': 'pago'},
    );
    note('p2.mb.pago', 'seller pago MB WAY', snap(p));
    final after = await rest(
      url,
      svc,
      svc,
      path:
          '/rest/v1/orders?id=eq.$mbid&select=id,status,amount_paid_cents,stock_units_applied',
    );
    final prodA = await rest(
      url,
      svc,
      svc,
      path: '/rest/v1/products?id=eq.$productId&select=id,quantity,is_sold',
    );
    final wt = await rest(
      url,
      svc,
      svc,
      path: '/rest/v1/wallet_transactions?order_id=eq.$mbid&select=*',
    );
    note('p2.mb.after', 'observe MB WAY pago', {
      'order': snap(after),
      'product': snap(prodA),
      'ledger': snap(wt),
    });
  }
}

Future<Json> _tryPayCheckout(String sk, String sessionId) async {
  final auth = 'Basic ${base64Encode(utf8.encode('$sk:'))}';
  final sess = await http.get(
    Uri.parse('https://api.stripe.com/v1/checkout/sessions/$sessionId'),
    headers: {'Authorization': auth},
  );
  if (sess.statusCode != 200) return snap(sess);
  final sm = jsonDecode(sess.body) as Json;
  final pi = sm['payment_intent']?.toString() ?? '';
  if (pi.isEmpty) return {'session': snap(sess), 'error': 'no_pi'};
  final confirm = await http.post(
    Uri.parse('https://api.stripe.com/v1/payment_intents/$pi/confirm'),
    headers: {
      'Authorization': auth,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'payment_method=pm_card_visa',
  );
  return {'session_status': sm['status'], 'confirm': snap(confirm)};
}
