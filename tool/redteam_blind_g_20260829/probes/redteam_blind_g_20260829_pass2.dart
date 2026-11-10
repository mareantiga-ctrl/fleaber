// ignore_for_file: avoid_print
/// Red Team cego G — PASS 2 invariantes / variantes. Staging only.
/// dart run tool/redteam_blind_g_20260829_pass2.dart
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

String clip(Object? v, [int n = 500]) {
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
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '');

  // disposable confirmed buyer
  final extraEmail = 'rtg2.buyer.$tag@staging.fleaber.lab';
  const extraPw = 'RtgLab!20260829';
  final extraId = await sb.createAdminUser(
    email: extraEmail,
    password: extraPw,
    userMetadata: {'user_type': 'comprador'},
  );
  await req('POST', '$url/rest/v1/profiles', SVC, {
    'id': extraId,
    'user_type': 'comprador',
    'display_name': 'RTG2 buyer',
  });
  final extraTok = await sb.signIn(email: extraEmail, password: extraPw);
  final XH = {
    'apikey': anon,
    'Authorization': 'Bearer $extraTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final extraProf = await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$extraId&select=id,user_type',
    SVC,
  );
  add('p2.extra.profile', 'AUTH', 'observe extra buyer user_type', 'service_role',
      extraProf,
      after: clip(extraProf['text'], 200));

  final emailAsExtra = await req(
    'POST',
    '$url/rest/v1/rpc/batata_find_user_id_by_email',
    XH,
    {'p_email': envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL')},
  );
  final emailBody = '${emailAsExtra['text']}'.replaceAll('"', '').trim();
  final emailLeak = emailBody.length == 36 && extraProf['text'].toString().contains('comprador');
  add(
    'p2.email.oracle.buyer',
    'PRIVACY',
    'find_user_id_by_email as confirmed comprador',
    'extra_buyer',
    emailAsExtra,
    before: clip(extraProf['text'], 120),
    after: emailBody,
    persisted: emailLeak,
    impact: emailLeak
        ? 'buyer enumerated seller UUID'
        : 'null or not seller',
    sev: emailLeak ? 'P2' : 'info',
  );

  // seller product 25.00 stock=2
  final prod = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'RTG2 contract $tag',
    'price': 25.00,
    'quantity': 2,
    'list_on_marketplace': true,
    'is_sold': false,
    'state': 'Bom',
    'category': 'Outros',
  });
  final pid = idOf(prod['body']);
  add('p2.fix.product', 'PRODUCTS', 'seller INSERT product 25€ qty=2', 'seller',
      prod,
      after: pid);

  String? orderCheap;
  String? orderFair;
  if (pid != null) {
    final cheap = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'price_total': 0.50,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app (seguro fleaber)',
      'shipping_method': 'hand',
      'contract_unit_cents': 1,
      'contract_qty': 99,
    });
    orderCheap = idOf(cheap['body']);
    final cheapLive = orderCheap == null ? null : await svcRow('orders', orderCheap);
    add(
      'p2.contract.cheap_insert',
      'PRICE / CONTRACT',
      'buyer INSERT price_total=0.50 contract_unit=1 qty=99',
      'buyer',
      cheap,
      after:
          'id=$orderCheap contract=${cheapLive?['contract_unit_cents']} qty=${cheapLive?['contract_qty']} price_total=${cheapLive?['price_total']} status=${cheapLive?['status']}',
      persisted: cheapLive != null &&
          (cheapLive['contract_unit_cents'] == 1 ||
              cheapLive['contract_unit_cents'] == 50 ||
              cheapLive['contract_qty'] == 99),
      impact: cheapLive == null
          ? 'insert failed'
          : 'sealed_unit=${cheapLive['contract_unit_cents']} sealed_qty=${cheapLive['contract_qty']} catalog=2500',
      sev: (cheapLive != null &&
              (cheapLive['contract_unit_cents'] == 1 ||
                  cheapLive['contract_unit_cents'] == 50))
          ? 'P1'
          : 'info',
    );

    if (orderCheap != null) {
      final cpi = await req(
        'POST',
        '$url/functions/v1/create-payment-intent',
        BH,
        {
          'order_id': orderCheap,
          'buyer_id': buyerId,
          'product_id': pid,
          'shipping_method': 'hand',
          'amount': 50,
        },
      );
      final txt = '${cpi['text']}';
      var amt = 0;
      try {
        final m = jsonDecode(txt);
        if (m is Map) {
          amt = int.tryParse('${m['server_amount_cents'] ?? m['amount_total'] ?? 0}') ?? 0;
        }
      } catch (_) {}
      final under = cpi['http'] == 200 && amt > 0 && amt < 2000;
      add(
        'p2.checkout.cheap_contract',
        'CHECKOUT',
        'CPI on buyer-cheap order',
        'buyer',
        cpi,
        after: 'server_amount_cents=$amt',
        persisted: under,
        impact: under
            ? 'SESSION amount $amt << catalog ~2500+fees'
            : 'http=${cpi['http']} amt=$amt',
        sev: under ? 'P1' : 'info',
      );
    }

    // fair order then seller drops catalog
    final fair = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'price_total': 25.00,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app (seguro fleaber)',
      'shipping_method': 'hand',
    });
    orderFair = idOf(fair['body']);
    final fairBefore = orderFair == null ? null : await svcRow('orders', orderFair);
    await req('PATCH', '$url/rest/v1/products?id=eq.$pid', SH, {'price': 1.00});
    if (orderFair != null) {
      final cpi2 = await req(
        'POST',
        '$url/functions/v1/create-payment-intent',
        BH,
        {
          'order_id': orderFair,
          'buyer_id': buyerId,
          'shipping_method': 'hand',
        },
      );
      var amt2 = 0;
      try {
        final m = jsonDecode('${cpi2['text']}');
        if (m is Map) {
          amt2 = int.tryParse('${m['server_amount_cents'] ?? 0}') ?? 0;
        }
      } catch (_) {}
      add(
        'p2.checkout.after_catalog_drop',
        'PRICE / CONTRACT',
        'CPI after seller drops catalog 25→1; order already sealed',
        'buyer',
        cpi2,
        before:
            'contract=${fairBefore?['contract_unit_cents']} catalog_was=2500',
        after: 'server_amount_cents=$amt2 catalog_now=100',
        impact: amt2 >= 2000
            ? 'sealed catalog at accept (invariant K holds)'
            : amt2 > 0 && amt2 < 500
                ? 'retroactive catalog used'
                : 'no session',
        sev: amt2 > 0 && amt2 < 500 ? 'P1' : 'info',
      );
      await req('PATCH', '$url/rest/v1/products?id=eq.$pid', SH, {'price': 25.00});
    }

    // qty overflow
    final q99 = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'price_total': 25,
      'quantity': 99,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app (seguro fleaber)',
      'shipping_method': 'hand',
    });
    final qid = idOf(q99['body']);
    final qrow = qid == null ? null : await svcRow('orders', qid);
    add(
      'p2.qty.overflow',
      'QUANTITY AUTHORITY',
      'buyer INSERT qty=99 stock=2',
      'buyer',
      q99,
      after: 'qty=${qrow?['quantity']} contract_qty=${qrow?['contract_qty']}',
      persisted: qrow != null && (qrow['quantity'] == 99 || qrow['contract_qty'] == 99),
      sev: qrow != null && (qrow['quantity'] == 99) ? 'P1' : 'info',
    );

    // prize_shipping spoof
    if (orderFair != null) {
      final prize = await req(
        'POST',
        '$url/functions/v1/create-payment-intent',
        BH,
        {
          'order_id': orderFair,
          'buyer_id': buyerId,
          'shipping_method': 'carrier',
          'prize_shipping': true,
        },
      );
      add(
        'p2.checkout.prize_spoof',
        'CHECKOUT',
        'prize_shipping=true on marketplace order',
        'buyer',
        prize,
        sev: prize['http'] == 200 &&
                '${prize['text']}'.contains('"server_amount_cents":') &&
                !'${prize['text']}'.contains('blocked')
            ? 'P1'
            : 'info',
      );
    }

    // bag hostile
    if (orderFair != null && orderCheap != null) {
      final bag = await req(
        'POST',
        '$url/functions/v1/create-payment-intent',
        BH,
        {
          'buyer_id': buyerId,
          'order_id': orderFair,
          'bag_checkout': true,
          'shipping_method': 'hand',
          'bag_lines': [
            {
              'order_id': orderFair,
              'product_id': pid,
              'seller_id': sellerId,
              'quantity': 1,
              'line_total_cents': 1,
            },
            {
              'order_id': orderCheap,
              'product_id': pid,
              'seller_id': sellerId,
              'quantity': 1,
              'line_total_cents': 1,
            },
          ],
        },
      );
      add(
        'p2.checkout.bag',
        'BAG / CART',
        'bag_checkout two lines line_total=1',
        'buyer',
        bag,
      );
    }
  }

  // offer self-accept
  if (pid != null) {
    final offer = await req('POST', '$url/rest/v1/product_offers', BH, {
      'product_id': pid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 0.50,
      'list_price': 25,
      'offered_by': 'buyer',
      'status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    });
    final oid = idOf(offer['body']);
    final orow = oid == null ? null : await svcRow('product_offers', oid);
    add(
      'p2.offer.self_accept',
      'OFFERS / PROPOSALS',
      'buyer INSERT offer status=accepted amount=0.50',
      'buyer',
      offer,
      after: 'status=${orow?['status']} responded=${orow?['responded_at']}',
      persisted: orow != null && '${orow['status']}' == 'accepted',
      sev: orow != null && '${orow['status']}' == 'accepted' ? 'P1' : 'info',
    );
    if (oid != null && '${orow?['status']}' == 'accepted') {
      final oord = await req('POST', '$url/rest/v1/orders', BH, {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'product_offer_id': oid,
        'price_total': 0.50,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'pagamento na app (seguro fleaber)',
        'shipping_method': 'hand',
      });
      final ooid = idOf(oord['body']);
      final oorow = ooid == null ? null : await svcRow('orders', ooid);
      add(
        'p2.offer.order_contract',
        'OFFERS / PROPOSALS',
        'order from self-accepted 0.50 offer',
        'buyer',
        oord,
        after: 'contract=${oorow?['contract_unit_cents']}',
        persisted: oorow != null && oorow['contract_unit_cents'] == 50,
        sev: oorow != null && oorow['contract_unit_cents'] == 50 ? 'P1' : 'info',
      );
      if (ooid != null) {
        final ocpi = await req(
          'POST',
          '$url/functions/v1/create-payment-intent',
          BH,
          {
            'order_id': ooid,
            'buyer_id': buyerId,
            'shipping_method': 'hand',
          },
        );
        add('p2.offer.checkout', 'CHECKOUT', 'CPI self-accepted offer order',
            'buyer', ocpi);
      }
    } else if (oid != null) {
      // pending offer, buyer PATCHes accepted
      final acc = await req(
        'PATCH',
        '$url/rest/v1/product_offers?id=eq.$oid',
        BH,
        {
          'status': 'accepted',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      final after = await svcRow('product_offers', oid);
      add(
        'p2.offer.patch_accept',
        'OFFERS / PROPOSALS',
        'buyer PATCH own offer → accepted',
        'buyer',
        acc,
        after: 'status=${after?['status']}',
        persisted: '${after?['status']}' == 'accepted',
        sev: '${after?['status']}' == 'accepted' ? 'P1' : 'info',
      );
    }
  }

  // reviews correct columns
  final paidOrd = await req(
    'GET',
    '$url/rest/v1/orders?buyer_id=eq.$buyerId&status=in.(pago,enviado,entregue,concluido)&select=id,status,seller_id,buyer_id,amount_paid_cents,payment_method&limit=3',
    SVC,
  );
  add('p2.rev.paid_orders', 'REVIEWS', 'list paid orders for review tests',
      'service_role', paidOrd, after: clip(paidOrd['text'], 300));
  if (paidOrd['body'] is List && (paidOrd['body'] as List).isNotEmpty) {
    final o = Map<String, dynamic>.from((paidOrd['body'] as List).first as Map);
    final rev = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': o['id'],
      'buyer_id': extraId,
      'target_id': o['seller_id'],
      'stars': 1,
      'comment': 'rtg2 forge extra author',
      'author_role': 'seller',
      'target_type': 'seller',
    });
    add(
      'p2.rev.forge_author',
      'REVIEWS',
      'lab buyer INSERT review with extra buyer_id + author_role seller',
      'buyer',
      rev,
      persisted: idOf(rev['body']) != null,
      sev: idOf(rev['body']) != null ? 'P1' : 'info',
    );
    final dup = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': o['id'],
      'buyer_id': buyerId,
      'target_id': o['seller_id'],
      'stars': 5,
      'comment': 'rtg2 dup',
      'author_role': 'buyer',
      'target_type': 'seller',
    });
    add('p2.rev.dup', 'REVIEWS', 'duplicate review same order', 'buyer', dup);
  }

  // disputes
  if (paidOrd['body'] is List && (paidOrd['body'] as List).isNotEmpty) {
    final o = Map<String, dynamic>.from((paidOrd['body'] as List).first as Map);
    final d = await req('POST', '$url/rest/v1/order_disputes', XH, {
      'order_id': o['id'],
      'buyer_id': extraId,
      'reason': 'rtg2',
      'description': 'cross dispute',
      'status': 'open',
    });
    add(
      'p2.disp.cross',
      'DISPUTES',
      'extra buyer INSERT dispute on lab order',
      'extra_buyer',
      d,
      persisted: idOf(d['body']) != null,
      sev: idOf(d['body']) != null ? 'P1' : 'info',
    );
  }

  // off-platform pago
  if (pid != null) {
    final off = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'price_total': 25,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'mb way',
      'shipping_method': 'hand',
    });
    final offId = idOf(off['body']);
    add('p2.off.insert', 'ORDER FSM', 'buyer INSERT mb way order', 'buyer', off,
        after: offId);
    if (offId != null) {
      final acc = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.$offId',
        SH,
        {'status': 'reservado'},
      );
      final accRow = await svcRow('orders', offId);
      add(
        'p2.off.seller_accept',
        'ORDER FSM',
        'seller PATCH → reservado',
        'seller',
        acc,
        after: '${accRow?['status']}',
      );
      final pay = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.$offId',
        SH,
        {'status': 'pago', 'amount_paid_cents': 2500},
      );
      final payRow = await svcRow('orders', offId);
      add(
        'p2.off.seller_pago',
        'ORDER FSM',
        'seller PATCH mbway → pago + amount_paid',
        'seller',
        pay,
        after:
            'status=${payRow?['status']} paid=${payRow?['amount_paid_cents']}',
        persisted: '${payRow?['status']}' == 'pago' ||
            payRow?['amount_paid_cents'] == 2500,
        sev: payRow?['amount_paid_cents'] == 2500
            ? 'P0'
            : '${payRow?['status']}' == 'pago'
                ? 'P1'
                : 'info',
      );
      final buyerPago = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.$offId',
        BH,
        {'status': 'pago'},
      );
      final bp = await svcRow('orders', offId);
      add(
        'p2.off.buyer_pago',
        'ORDER FSM',
        'buyer PATCH mbway → pago',
        'buyer',
        buyerPago,
        after: '${bp?['status']}',
        sev: '${bp?['status']}' == 'pago' ? 'P1' : 'info',
      );

      // banking oracle: extra buyer vs seller with no order
      final bankX = await req(
        'POST',
        '$url/rest/v1/rpc/batata_seller_direct_payment_details',
        XH,
        {'p_seller_id': sellerId},
      );
      add(
        'p2.bank.extra',
        'PRIVACY',
        'extra buyer banking details without relationship',
        'extra_buyer',
        bankX,
        sev: bankX['http'] == 200 &&
                '${bankX['text']}'.contains('iban') &&
                '${bankX['text']}'.length > 10
            ? 'P1'
            : 'info',
      );
      final bankB = await req(
        'POST',
        '$url/rest/v1/rpc/batata_seller_direct_payment_details',
        BH,
        {'p_seller_id': sellerId},
      );
      add(
        'p2.bank.lab_buyer',
        'PRIVACY',
        'lab buyer banking details (may have off-platform order)',
        'buyer',
        bankB,
      );

      final rel = await req(
        'POST',
        '$url/rest/v1/rpc/batata_release_seller_wallet_for_order',
        BH,
        {'p_order_id': offId},
      );
      add('p2.wallet.release.offplat', 'WALLET', 'release on mbway order',
          'buyer', rel);
    }
  }

  // stock=1 race inserts
  final p1 = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'RTG2 race $tag',
    'price': 8.00,
    'quantity': 1,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final racePid = idOf(p1['body']);
  if (racePid != null) {
    final futs = <Future<Map<String, dynamic>>>[];
    for (var i = 0; i < 12; i++) {
      futs.add(req('POST', '$url/rest/v1/orders', BH, {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': racePid,
        'price_total': 8,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'pagamento na app (seguro fleaber)',
        'shipping_method': 'hand',
      }));
    }
    final rs = await Future.wait(futs);
    final created = <String>[];
    for (final r in rs) {
      final id = idOf(r['body']);
      if (id != null) created.add(id);
    }
    add(
      'p2.race.orders.stock1',
      'STOCK',
      '12 parallel INSERT orders stock=1',
      'buyer',
      {'http': 200, 'text': 'created=${created.length} ids=$created'},
      after: 'created=${created.length}',
      impact: created.length > 1
          ? 'multiple pending orders on last unit'
          : 'single/zero created',
      sev: created.length > 1 ? 'P2' : 'info',
    );

    // dual CPI
    if (created.length >= 2) {
      final c1 = req('POST', '$url/functions/v1/create-payment-intent', BH, {
        'order_id': created[0],
        'buyer_id': buyerId,
        'shipping_method': 'hand',
      });
      final c2 = req('POST', '$url/functions/v1/create-payment-intent', BH, {
        'order_id': created[1],
        'buyer_id': buyerId,
        'shipping_method': 'hand',
      });
      final both = await Future.wait([c1, c2]);
      add('p2.race.cpi.a', 'CHECKOUT', 'parallel CPI order A', 'buyer', both[0]);
      add('p2.race.cpi.b', 'CHECKOUT', 'parallel CPI order B', 'buyer', both[1]);
      var sessions = 0;
      for (final r in both) {
        if (r['http'] == 200 && '${r['text']}'.contains('cs_')) sessions++;
      }
      add(
        'p2.race.cpi.summary',
        'STOCK',
        'two Sessions for stock=1',
        'buyer',
        {
          'http': 200,
          'text': 'sessions=$sessions a=${clip(both[0]['text'], 180)} b=${clip(both[1]['text'], 180)}'
        },
        after: 'sessions=$sessions',
        impact: sessions >= 2
            ? 'two Stripe sessions exist (not yet two captures)'
            : 'one or zero sessions',
        sev: sessions >= 2 ? 'P2' : 'info',
      );
    }
  }

  // live reservations
  final lives = await req(
    'GET',
    '$url/rest/v1/lives?seller_id=eq.$sellerId&select=id,status,is_active,mux_stream_key&limit=3',
    SVC,
  );
  add('p2.live.list', 'LIVE', 'observe seller lives (svc)', 'service_role', lives,
      after: clip(lives['text'], 250));
  final liveRow = firstRow(lives['body']);
  String? liveId;
  if (liveRow is Map) liveId = '${liveRow['id']}';
  if (liveId != null && liveId.length > 8) {
    final items = await req(
      'GET',
      '$url/rest/v1/live_items?live_id=eq.$liveId&select=id,price,quantity,seller_id,title&limit=5',
      SVC,
    );
    add('p2.live.items', 'LIVE ITEMS', 'list live_items', 'service_role', items);
    final li = firstRow(items['body']);
    if (li is Map) {
      final liid = '${li['id']}';
      final resA = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
        'live_id': liveId,
        'live_item_id': liid,
        'buyer_id': buyerId,
        'requested_qty': 99,
        'status': 'accepted',
      });
      add(
        'p2.res.insert.accepted',
        'LIVE RESERVATIONS',
        'buyer INSERT reservation qty=99 status=accepted',
        'buyer',
        resA,
        persisted: idOf(resA['body']) != null &&
            '${firstRow(resA['body']) is Map ? (firstRow(resA['body']) as Map)['status'] : ''}' ==
                'accepted',
        sev: idOf(resA['body']) != null &&
                '${firstRow(resA['body']) is Map ? (firstRow(resA['body']) as Map)['status'] : ''}' ==
                    'accepted'
            ? 'P1'
            : 'info',
      );
      final acceptRpc = await req(
        'POST',
        '$url/rest/v1/rpc/batata_live_reservation_accept_available',
        BH,
        {'p_reservation_id': idOf(resA['body']), 'p_seller_id': sellerId},
      );
      add(
        'p2.res.accept.rpc.buyer',
        'LIVE RESERVATIONS',
        'buyer EXECUTE accept_available',
        'buyer',
        acceptRpc,
      );
    }
    final muxSel = await req(
      'GET',
      '$url/rest/v1/lives?id=eq.$liveId&select=id,mux_stream_key,mux_playback_id',
      BH,
    );
    add('p2.live.streamkey.buyer', 'MUX', 'buyer SELECT stream key', 'buyer',
        muxSel);
    final muxSelS = await req(
      'GET',
      '$url/rest/v1/lives?id=eq.$liveId&select=id,mux_stream_key,mux_playback_id',
      SH,
    );
    add('p2.live.streamkey.seller', 'MUX', 'seller SELECT own stream key',
        'seller', muxSelS);
  }

  // storage: try common prefixes
  final stor = await req(
    'GET',
    '$url/storage/v1/object/public/chat_media/product_photos/$sellerId/probe',
    AH,
  );
  add('p2.stor.public.guess', 'STORAGE', 'GET public product photo path guess',
      'anon', stor);

  final listSeller = await req(
    'POST',
    '$url/storage/v1/object/list/chat_media',
    BH,
    {
      'prefix': 'product_photos/$sellerId',
      'limit': 10,
    },
  );
  add('p2.stor.list.seller_prefix', 'STORAGE',
      'buyer list product_photos/sellerId', 'buyer', listSeller);

  // notifications_view PII
  final nv = await req(
    'GET',
    '$url/rest/v1/notifications_view?select=*&limit=3',
    AH,
  );
  add(
    'p2.priv.notifications_view',
    'PRIVACY',
    'anon SELECT notifications_view *',
    'anon',
    nv,
    impact: nv['http'] == 200 && nv['body'] is List && (nv['body'] as List).isNotEmpty
        ? 'anon sees activity feed of others'
        : 'empty/blocked',
    sev: nv['http'] == 200 && nv['body'] is List && (nv['body'] as List).isNotEmpty
        ? 'P2'
        : 'info',
  );

  // device tokens
  final tok = await req(
    'GET',
    '$url/rest/v1/seller_device_tokens?select=*&limit=5',
    BH,
  );
  add('p2.priv.device_tokens', 'PRIVACY', 'buyer SELECT seller_device_tokens',
      'buyer', tok,
      sev: tok['http'] == 200 &&
              tok['body'] is List &&
              (tok['body'] as List).isNotEmpty
          ? 'P2'
          : 'info');

  // refund dual
  if (orderFair != null) {
    final r1 = req('POST', '$url/functions/v1/refund-order', SH, {
      'order_id': orderFair,
    });
    final r2 = req('POST', '$url/functions/v1/refund-order', SH, {
      'order_id': orderFair,
    });
    final rr = await Future.wait([r1, r2]);
    add('p2.refund.race.a', 'REFUNDS', 'parallel refund unpaid A', 'seller',
        rr[0]);
    add('p2.refund.race.b', 'REFUNDS', 'parallel refund unpaid B', 'seller',
        rr[1]);
  }

  // mux as seller
  final muxS = await req(
    'POST',
    '$url/functions/v1/create-mux-live',
    SH,
    {'title': 'RTG2 mux probe $tag'},
  );
  add(
    'p2.mux.seller.create',
    'MUX',
    'create-mux-live as seller (may mint live)',
    'seller',
    muxS,
    impact: muxS['http'] == 200
        ? 'stream credentials in response — seller own live OK'
        : 'blocked/error',
  );
  // if created, do NOT leave live running — complete it
  try {
    final m = jsonDecode('${muxS['text']}');
    if (m is Map && m['live_id'] != null) {
      final lid = '${m['live_id']}';
      final done = await req(
        'POST',
        '$url/functions/v1/complete-mux-live',
        SH,
        {'live_id': lid},
      );
      add('p2.mux.seller.complete', 'LIVE', 'complete mux live after probe',
          'seller', done);
      await req('PATCH', '$url/rest/v1/lives?id=eq.$lid', SVC, {
        'status': 'ended',
        'is_active': false,
      });
    }
  } catch (_) {}

  // cleanup
  if (pid != null) {
    await req('DELETE', '$url/rest/v1/product_offers?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  }
  if (racePid != null) {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$racePid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$racePid', SVC);
  }
  await req('DELETE', '$url/rest/v1/profiles?id=eq.$extraId', SVC);
  await http.delete(
    Uri.parse('$url/auth/v1/admin/users/$extraId'),
    headers: SVC,
  );

  final out = {
    'pass': 2,
    'project': stagingRef,
    'started': stamp,
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
  final f = File('tool/redteam_blind_g_20260829/pass2_raw.json');
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('WROTE ${f.path} probes=${probes.length}');
  for (final p in out['interesting'] as List) {
    stdout.writeln(
      '  ${p['severity_hint']} ${p['id']} http=${p['http']} ${p['after'] ?? ''} ${p['impact']}',
    );
  }
}
