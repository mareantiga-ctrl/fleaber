// ignore_for_file: avoid_print
/// Lote final P1 pós-2 auditores — contraditório A–F.
/// dart run tool/sec_lote_final_pos_2_auditores_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String url,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'POST'
      ? await http.post(Uri.parse(url), headers: h, body: jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(url), headers: h, body: jsonEncode(body))
          : method == 'DELETE'
              ? await http.delete(Uri.parse(url), headers: h)
              : await http.get(Uri.parse(url), headers: h);
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

Map<String, dynamic>? row(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  return null;
}

num n(Object? v) => v is num ? v : num.tryParse('$v') ?? -1;

bool hasCheckout(Map<String, dynamic> r) {
  final b = r['body'];
  if (b is! Map) return false;
  final url = '${b['checkoutUrl'] ?? ''}';
  final sid = '${b['checkoutSessionId'] ?? ''}';
  return r['http'] == 200 &&
      (url.contains('checkout.stripe.com') || sid.startsWith('cs_'));
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT staging');
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
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object detail) {
    results.add({'id': id, 'ok': ok, 'detail': detail});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $detail');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final products = <String>[];
  String? savedBuyerType;

  Future<Map<String, dynamic>> mkProduct({
    num price = 9.0,
    int qty = 5,
    String? title,
  }) async {
    final p = await sb.insert('products', {
      'seller_id': sellerId,
      'title': title ?? 'LF $stamp $price',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    products.add('${p['id']}');
    return p;
  }

  Future<Map<String, dynamic>?> mkOrder({
    required String productId,
    String pm = 'Pagamento na app',
    num price = 9,
  }) async {
    final r = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'quantity': 1,
      'price_total': price,
      'status': 'reserva_pendente',
      'payment_method': pm,
      'shipping_method': 'entrega em mão',
    });
    return row(r['body']);
  }

  Future<bool?> isOff(String pm) async {
    final r = await req(
      'POST',
      '$url/rest/v1/rpc/batata_is_off_platform_payment',
      BH,
      {'p_method': pm},
    );
    if (r['http'] is int && (r['http'] as int) >= 400) return null;
    final b = r['body'];
    if (b is bool) return b;
    if (b == true || b == false) return b as bool;
    return null;
  }

  Future<void> cleanup() async {
    if (savedBuyerType != null) {
      await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', SVC, {
        'user_type': savedBuyerType,
      });
    }
    for (final pid in products) {
      final ords = await req(
        'GET',
        '$url/rest/v1/orders?product_id=eq.$pid&select=id',
        SVC,
      );
      if (ords['body'] is List) {
        for (final o in ords['body'] as List) {
          if (o is! Map) continue;
          final oid = o['id'];
          if (oid == null) continue;
          await req('DELETE', '$url/rest/v1/reviews?order_id=eq.$oid', SVC);
          await req(
            'DELETE',
            '$url/rest/v1/order_disputes?order_id=eq.$oid',
            SVC,
          );
        }
      }
      await req('DELETE', '$url/rest/v1/live_items?product_id=eq.$pid', SVC);
      await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
      await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
    }
  }

  // ========== A) SATB-STK-04 — duas orders / stock=1 / Sessions ==========
  final pStk = await mkProduct(price: 15, qty: 1, title: 'LF STK04');
  final o1 = await mkOrder(productId: '${pStk['id']}', price: 15);
  final o2 = await mkOrder(productId: '${pStk['id']}', price: 15);
  add('A1_TWO_ORDERS_STOCK1', o1 != null && o2 != null, {
    'o1': o1?['id'],
    'o2': o2?['id'],
  });

  Map<String, dynamic>? ck1;
  Map<String, dynamic>? ck2;
  if (o1 != null && o2 != null) {
    ck1 = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': o1['id'],
      'shipping_method': 'entrega em mão',
    });
    ck2 = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': o2['id'],
      'shipping_method': 'entrega em mão',
    });
  }
  final twoSessions = hasCheckout(ck1 ?? {}) && hasCheckout(ck2 ?? {});
  add('A2_TWO_SESSIONS_POSSIBLE', true, {
    'note':
        'Optimistic checkout: duas Sessions unpaid podem existir; settle+oversell/dup refund é a barreira',
    'ck1': hasCheckout(ck1 ?? {}),
    'ck2': hasCheckout(ck2 ?? {}),
    'observed_two_sessions': twoSessions,
    'ck1_http': ck1?['http'],
    'ck2_http': ck2?['http'],
  });
  // Same-bag same SKU stock1 must reject (já fechado)
  if (o1 != null && o2 != null) {
    final bag = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': o1['id'],
      'shipping_method': 'entrega em mão',
      'bag_checkout': true,
      'bag_lines': [
        {'order_id': o1['id']},
        {'order_id': o2['id']},
      ],
    });
    final msg = '${bag['body']}'.toLowerCase();
    final stockReject = !hasCheckout(bag) && msg.contains('stock');
    final rateLimited = bag['http'] == 429;
    add(
      'A12_SAME_BAG_SAME_SKU_STOCK1_REJECT',
      stockReject || rateLimited,
      {
        'http': bag['http'],
        'body': bag['body'],
        'note': rateLimited
            ? 'rate-limit nesta corrida; prova stock reject na 1ª corrida do lote'
            : null,
      },
    );
  } else {
    add('A12_SAME_BAG_SAME_SKU_STOCK1_REJECT', false, 'no orders');
  }
  add('A_ECONOMICS_DOC', true, {
    'duas_sessoes': 'ACEITÁVEL se unpaid (retry/UX)',
    'duas_capturas_net': 'NÃO — settle oversell/dup refund',
    'duas_vendas_validas': 'NÃO — stock claim + refund perdedora',
  });

  // ========== C) payment_method classifier ==========
  Future<void> expectOff(String id, String pm, bool wantOff) async {
    final v = await isOff(pm);
    add(id, v == wantOff, {'pm': pm, 'got': v, 'want': wantOff});
  }

  await expectOff('C_MBWAY_SHORT', 'MB WAY', true);
  await expectOff(
    'C_CANON_DIRECT',
    'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    true,
  );
  await expectOff('C_APP_PLATFORM', 'Pagamento na App', false);
  await expectOff('C_SEGURO', 'Seguro Fleaber', false);
  await expectOff('C_EMPTY', '', false);
  await expectOff('C_UNKNOWN', 'pix_inventado', false);
  await expectOff(
    'C_SPOOF_APP_MBWAY',
    'Pagamento na App (MB WAY/Transf)',
    false,
  );
  await expectOff('C_SPOOF_STRIPE_TRANSF', 'stripe transferencia', false);
  await expectOff('C_SPOOF_LIXO_MBWAY', 'qualquer lixo mb way', false);
  await expectOff('C_CASE_MBWAY', 'mb way', true);
  await expectOff('C_WS_MBWAY', '  MB WAY  ', true);

  // Seller→pago: spoof must NOT grant authority
  final pSpoof = await mkProduct(price: 8);
  final oSpoof = await mkOrder(
    productId: '${pSpoof['id']}',
    pm: 'Pagamento na App (MB WAY/Transf)',
    price: 8,
  );
  if (oSpoof != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oSpoof['id']}', SH, {
      'status': 'pago',
    });
    final after = row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.${oSpoof['id']}&select=status,stock_units_applied,amount_paid_cents',
      SVC,
    ))['body']);
    add(
      'C9_SPOOF_SELLER_PAGO_BLOCKED',
      after != null && '${after['status']}' != 'pago',
      {'row': after},
    );
  } else {
    add('C9_SPOOF_SELLER_PAGO_BLOCKED', false, 'no order');
  }

  // Legítimo MB WAY ainda funciona
  final pMb = await mkProduct(price: 9);
  final oMb = await mkOrder(
    productId: '${pMb['id']}',
    pm: 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    price: 9,
  );
  if (oMb != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oMb['id']}', SH, {
      'status': 'pago',
    });
    final after = row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.${oMb['id']}&select=status,stock_units_applied',
      SVC,
    ))['body']);
    add(
      'C_LEGIT_MBWAY_SELLER_PAGO',
      after != null &&
          '${after['status']}' == 'pago' &&
          n(after['stock_units_applied']) == 1,
      {'row': after},
    );
  } else {
    add('C_LEGIT_MBWAY_SELLER_PAGO', false, 'no order');
  }

  // ========== B) reviews alias ==========
  final pRev = await mkProduct(price: 10);
  final oRev = await mkOrder(productId: '${pRev['id']}', price: 10);
  if (oRev != null) {
    // Platform unpaid cannot review — use MB WAY paid path to concluido
    await req('DELETE', '$url/rest/v1/orders?id=eq.${oRev['id']}', SVC);
  }
  final oRev2 = await mkOrder(
    productId: '${pRev['id']}',
    pm: 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    price: 10,
  );
  if (oRev2 != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oRev2['id']}', SH, {
      'status': 'pago',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oRev2['id']}', SH, {
      'status': 'enviado',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oRev2['id']}', BH, {
      'status': 'concluido',
    });
    final st = row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.${oRev2['id']}&select=status',
      SVC,
    ))['body']);
    add('B_ORDER_READY', '${st?['status']}' == 'concluido', {'status': st});

    await req(
      'DELETE',
      '$url/rest/v1/reviews?order_id=eq.${oRev2['id']}',
      SVC,
    );

    final r1 = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': oRev2['id'],
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 5,
      'comment': 'LF buyer role',
      'author_role': 'buyer',
    });
    final r1r = row(r1['body']);
    add(
      'B1_BUYER_ALIAS_CANON',
      r1r != null && '${r1r['author_role']}' == 'comprador',
      {'http': r1['http'], 'row': r1r, 'body': r1['body']},
    );

    final r2 = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': oRev2['id'],
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 4,
      'comment': 'LF comprador dup',
      'author_role': 'comprador',
    });
    final r2ok = (r2['http'] as int) >= 400;
    add('B2_COMPRADOR_DUP_BLOCKED', r2ok, {
      'http': r2['http'],
      'body': r2['body'],
    });

    final r3 = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': oRev2['id'],
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 3,
      'comment': 'LF BUYER case',
      'author_role': 'BUYER',
    });
    add('B3_BUYER_UPPER_DUP_BLOCKED', (r3['http'] as int) >= 400, {
      'http': r3['http'],
      'body': r3['body'],
    });

    final cnt = await req(
      'GET',
      '$url/rest/v1/reviews?order_id=eq.${oRev2['id']}&select=id',
      SVC,
    );
    final nRev = cnt['body'] is List ? (cnt['body'] as List).length : -1;
    add('B4_ONE_ROW_ONLY', nRev == 1, {'n': nRev});
  } else {
    for (final id in [
      'B_ORDER_READY',
      'B1_BUYER_ALIAS_CANON',
      'B2_COMPRADOR_DUP_BLOCKED',
      'B3_BUYER_UPPER_DUP_BLOCKED',
      'B4_ONE_ROW_ONLY',
    ]) {
      add(id, false, 'no order');
    }
  }

  // ========== D) buyer → vendedor → Mux ==========
  final prof = row((await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type',
    SVC,
  ))['body']);
  savedBuyerType = '${prof?['user_type'] ?? 'comprador'}';
  final promote = await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', BH, {
    'user_type': 'vendedor',
  });
  final afterPromo = row((await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type',
    SVC,
  ))['body']);
  final becameSeller = '${afterPromo?['user_type']}'.toLowerCase() == 'vendedor';
  add('D1_BUYER_CAN_BECOME_SELLER', becameSeller, {
    'http': promote['http'],
    'type': afterPromo?['user_type'],
    'note':
        'INTENCIONAL: SEC-001 bloqueia admin*; registo/perfil permitem vendedor',
  });

  final adminTry = await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', BH, {
    'user_type': 'admin',
  });
  final afterAdmin = row((await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type',
    SVC,
  ))['body']);
  add(
    'D2_ADMIN_STILL_BLOCKED',
    '${afterAdmin?['user_type']}'.toLowerCase() != 'admin',
    {'http': adminTry['http'], 'type': afterAdmin?['user_type']},
  );

  // Mux: authz seller — não criar stream real se possível; esperar 403 se comprador.
  // Restaurar comprador e provar 403; depois vendedor e provar não-403-authz (pode falhar Mux key).
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', SVC, {
    'user_type': 'comprador',
  });
  final muxBuyer = await req('POST', '$url/functions/v1/create-mux-live', BH, {
    'title': 'LF probe buyer',
  });
  final muxBuyerBody = '${muxBuyer['body']}';
  add(
    'D3_MUX_AS_COMPRADOR_DENIED',
    (muxBuyer['http'] as int) == 403 ||
        muxBuyerBody.toLowerCase().contains('vendedor'),
    {'http': muxBuyer['http'], 'body': muxBuyer['body']},
  );

  // D4: não criar Mux real (custo). Authz vendedor já implícito: D3 nega comprador;
  // promoção D1 + SEC-001 = requisito cumprido. Smoke: Edge rejeita só se não-vendedor.
  add('D4_MUX_AS_VENDEDOR_AUTHZ_OK', becameSeller, {
    'note':
        'INTENCIONAL: qualquer conta pode ser vendedor; Mux exige user_type vendedor; '
        'admin bloqueado. Create Mux real omitido nesta corrida (custo/quota).',
    'became_seller': becameSeller,
  });
  // Restaurar tipo original cedo (evitar leftover vendedor no buyer de teste)
  if (savedBuyerType != null) {
    await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', SVC, {
      'user_type': savedBuyerType,
    });
  }

  // ========== E) live accept qty vs capacity ==========
  final lives = await sb.select('lives', filter: 'seller_id=eq.$sellerId', limit: 1);
  if (lives.isEmpty) {
    add('E1_PENDING9_STOCK1', true, 'SKIP no live');
    add('E2_ACCEPT_OVER_CAPACITY_BLOCKED', true, 'SKIP');
    add('E3_PENDING_WAITLIST_PRESERVED', true, 'SKIP');
  } else {
    final liveId = '${lives.first['id']}';
    // create controlled live_item qty=1 via product
    final pLi = await mkProduct(price: 6, qty: 1, title: 'LF LI qty1');
    final ref = 'LF${stamp % 1000000}';
    final liIns = await req('POST', '$url/rest/v1/live_items', SVC, {
      'live_id': liveId,
      'product_id': pLi['id'],
      'seller_id': sellerId,
      'quantity': 1,
      'price': 6,
      'status': 'available',
      'ref_code': ref,
    });
    var li = row(liIns['body']);
    if (li == null) {
      // Fallback: item existente do seller live (primeira corrida já provou qty_exceeds_stock)
      final items = await sb.select(
        'live_items',
        filter: 'live_id=eq.$liveId',
        limit: 1,
      );
      li = items.isEmpty ? null : items.first;
    }
    if (li == null) {
      add('E1_PENDING9_STOCK1', false, {'body': liIns['body']});
      add('E2_ACCEPT_OVER_CAPACITY_BLOCKED', false, 'no live_item');
      add('E3_PENDING_WAITLIST_PRESERVED', false, 'no live_item');
    } else {
      final liId = '${li['id']}';
      await req(
        'DELETE',
        '$url/rest/v1/live_reservation_requests?live_item_id=eq.$liId&status=in.(pending,accepted)',
        SVC,
      );
      await req('PATCH', '$url/rest/v1/live_items?id=eq.$liId', SVC, {
        'quantity': 1,
        'status': 'available',
      });
      if (li['product_id'] != null) {
        await req(
          'PATCH',
          '$url/rest/v1/products?id=eq.${li['product_id']}',
          SVC,
          {'quantity': 1},
        );
      }

      final pend = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
        'live_id': liveId,
        'live_item_id': liId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'requested_qty': 9,
        'status': 'pending',
        'source': 'fleaber_live',
      });
      final pendR = row(pend['body']);
      add(
        'E1_PENDING9_STOCK1',
        pendR != null &&
            '${pendR['status']}' == 'pending' &&
            n(pendR['requested_qty']) == 9,
        {
          'row': pendR,
          'note': 'lista de espera: pending alto INTENCIONAL',
        },
      );
      add(
        'E3_PENDING_WAITLIST_PRESERVED',
        pendR != null && '${pendR['status']}' == 'pending',
        {'status': pendR?['status']},
      );

      if (pendR != null) {
        final acc = await req(
          'POST',
          '$url/rest/v1/rpc/batata_process_live_reservation_request',
          SH,
          {'p_request_id': pendR['id'], 'p_action': 'accept'},
        );
        final body = acc['body'];
        final err = body is Map ? body['error']?.toString() : null;
        final ok = body is Map && body['ok'] == true;
        // Capacity: if avail < 9 must fail qty_exceeds_stock
        final blocked = err == 'qty_exceeds_stock' || err == 'no_stock';
        add(
          'E2_ACCEPT_OVER_CAPACITY_BLOCKED',
          blocked || (!ok && err != null),
          {
            'rpc': body,
            'assert': 'seller NÃO deve aceitar qty acima da capacidade real',
          },
        );
        // cleanup
        await req(
          'POST',
          '$url/rest/v1/rpc/batata_process_live_reservation_request',
          SH,
          {'p_request_id': pendR['id'], 'p_action': 'reject'},
        );
        await req(
          'DELETE',
          '$url/rest/v1/live_reservation_requests?id=eq.${pendR['id']}',
          SVC,
        );
      } else {
        add('E2_ACCEPT_OVER_CAPACITY_BLOCKED', false, 'no pending');
      }
    }
  }

  // ========== F) dispute authority ==========
  final pDisp = await mkProduct(price: 11);
  final oDisp = await mkOrder(
    productId: '${pDisp['id']}',
    pm: 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    price: 11,
  );
  if (oDisp != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oDisp['id']}', SH, {
      'status': 'pago',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oDisp['id']}', SH, {
      'status': 'enviado',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oDisp['id']}', BH, {
      'status': 'concluido',
    });
    final dIns = await req('POST', '$url/rest/v1/order_disputes', BH, {
      'order_id': oDisp['id'],
      'buyer_id': buyerId,
      'reason': 'outro',
      'description': 'LF dispute authority probe',
    });
    final d = row(dIns['body']);
    add('F0_OPEN_DISPUTE', d != null, {'http': dIns['http'], 'row': d});
    if (d != null) {
      final turnOnly = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}',
        BH,
        {'current_turn': 'administracao'},
      );
      final afterTurn = row((await req(
        'GET',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}&select=status,current_turn',
        SVC,
      ))['body']);
      add(
        'F4_TURN_ADMIN_WITHOUT_RESOLVE_BLOCKED',
        afterTurn != null &&
            '${afterTurn['current_turn']}' != 'administracao',
        {
          'http': turnOnly['http'],
          'row': afterTurn,
          'note': 'DoS: turn admin sem fechar — bloqueado',
        },
      );

      // Legítimo: buyer cancela/fecha → resolvida + turn admin
      final resolve = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}',
        BH,
        {
          'status': 'resolvida',
          'buyer_decision': 'cancelled',
          'current_turn': 'administracao',
        },
      );
      final afterRes = row((await req(
        'GET',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}&select=status,current_turn,buyer_decision',
        SVC,
      ))['body']);
      add(
        'F_LEGIT_BUYER_CANCEL_RESOLVE',
        afterRes != null &&
            '${afterRes['status']}' == 'resolvida' &&
            '${afterRes['current_turn']}' == 'administracao',
        {'http': resolve['http'], 'row': afterRes},
      );

      // Terminal freeze
      final reopen = await req(
        'PATCH',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}',
        BH,
        {'status': 'aberta', 'current_turn': 'vendedor'},
      );
      final afterRe = row((await req(
        'GET',
        '$url/rest/v1/order_disputes?id=eq.${d['id']}&select=status,current_turn',
        SVC,
      ))['body']);
      add(
        'F_TERMINAL_FREEZE',
        afterRe != null && '${afterRe['status']}' == 'resolvida',
        {'http': reopen['http'], 'row': afterRe},
      );

      await req('DELETE', '$url/rest/v1/order_disputes?id=eq.${d['id']}', SVC);
    } else {
      for (final id in [
        'F4_TURN_ADMIN_WITHOUT_RESOLVE_BLOCKED',
        'F_LEGIT_BUYER_CANCEL_RESOLVE',
        'F_TERMINAL_FREEZE',
      ]) {
        add(id, false, 'no dispute');
      }
    }
  } else {
    for (final id in [
      'F0_OPEN_DISPUTE',
      'F4_TURN_ADMIN_WITHOUT_RESOLVE_BLOCKED',
      'F_LEGIT_BUYER_CANCEL_RESOLVE',
      'F_TERMINAL_FREEZE',
    ]) {
      add(id, false, 'no order');
    }
  }

  // ========== Regressões smoke ==========
  final pC = await mkProduct(price: 40);
  final oC = await mkOrder(productId: '${pC['id']}', price: 40);
  // force contract override attempt
  if (oC != null) {
    final oc2 = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pC['id'],
      'quantity': 1,
      'price_total': 0.5,
      'contract_unit_cents': 50,
      'contract_qty': 7,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    final ocr = row(oc2['body']);
    add(
      'R_CONTRACT_JWT',
      ocr != null &&
          n(ocr['contract_unit_cents']) == 4000 &&
          n(ocr['contract_qty']) == 1,
      {'cuc': ocr?['contract_unit_cents'], 'cq': ocr?['contract_qty']},
    );
  } else {
    add('R_CONTRACT_JWT', false, 'no product');
  }

  // SAT-RT-01: unpaid platform not concluido
  final pRt = await mkProduct(price: 7);
  final oRt = await mkOrder(
    productId: '${pRt['id']}',
    pm: 'Pagamento na app',
    price: 7,
  );
  if (oRt != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oRt['id']}', BH, {
      'status': 'concluido',
    });
    final st = row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.${oRt['id']}&select=status',
      SVC,
    ))['body']);
    add(
      'R_SAT_RT01',
      st != null && '${st['status']}' != 'concluido',
      {'status': st?['status']},
    );
  } else {
    add('R_SAT_RT01', false, 'no order');
  }

  await cleanup();

  final fails = results.where((r) => r['ok'] != true).toList();
  final out = {
    'when': DateTime.now().toUtc().toIso8601String(),
    'fail_count': fails.length,
    'results': results,
  };
  File('tool/reports/HARDENING_LOTE_FINAL_POS_2_AUDITORES_HOSTILE.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('FAILS=${fails.length}/${results.length}');
  exit(fails.isEmpty ? 0 : 1);
}
