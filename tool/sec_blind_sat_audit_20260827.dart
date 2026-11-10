// ignore_for_file: avoid_print
/// Auditoria cega saturação — bateria hostil independente (staging only).
/// dart run tool/sec_blind_sat_audit_20260827.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

typedef Json = Map<String, dynamic>;

Future<Json> req(
  String method,
  String url,
  Map<String, String> headers, {
  Object? body,
}) async {
  final uri = Uri.parse(url);
  late http.Response r;
  final encoded = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      r = await http.get(uri, headers: headers);
      break;
    case 'POST':
      r = await http.post(uri, headers: headers, body: encoded);
      break;
    case 'PATCH':
      r = await http.patch(uri, headers: headers, body: encoded);
      break;
    case 'PUT':
      r = await http.put(uri, headers: headers, body: encoded);
      break;
    case 'DELETE':
      r = await http.delete(uri, headers: headers, body: encoded);
      break;
    default:
      throw ArgumentError(method);
  }
  dynamic parsed;
  try {
    parsed = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    parsed = r.body;
  }
  return {'http': r.statusCode, 'body': parsed, 'raw': r.body, 'headers': r.headers};
}

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: not staging project');
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

  final findings = <Json>[];
  final coverage = <String, String>{};
  final blocked = <Json>[];
  final notes = <String>[];

  void finding({
    required String id,
    required String sev,
    required String surface,
    required String identity,
    required String action,
    required Object response,
    required String impact,
    required String confidence,
    String pre = '',
    Object? before,
    Object? after,
    List<String> variants = const [],
    String fp = '',
  }) {
    findings.add({
      'id': id,
      'sev': sev,
      'surface': surface,
      'pre': pre,
      'identity': identity,
      'action': action,
      'response': response,
      'before': before,
      'after': after,
      'impact': impact,
      'confidence': confidence,
      'variants': variants,
      'fp': fp,
    });
    stdout.writeln('FINDING $sev $id — $impact');
  }

  void mark(String surface, String status) {
    coverage[surface] = status;
  }

  void failClosed(String id, Object detail) {
    blocked.add({'id': id, 'detail': detail});
    stdout.writeln('BLOCKED $id — $detail');
  }

  Map<String, String> h(String token, {bool prefer = true}) => {
        'apikey': anon,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        if (prefer) 'Prefer': 'return=representation',
      };
  final ANON = {
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

  stdout.writeln('== sign-in ==');
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final BH = h(buyerTok);
  final SH = h(sellerTok);

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final createdProductIds = <String>[];
  final createdOrderIds = <String>[];
  String? victimId;
  String? victimTok;
  String? fixtureProductId;
  num catalogPrice = 47.0;
  const catalogQty = 8;

  Future<String> makeProduct({
    num price = 47,
    int qty = 8,
    String? title,
  }) async {
    final row = await sb.insert('products', {
      'seller_id': sellerId,
      'title': title ?? 'SAT-AUD $stamp ${Random().nextInt(99999)}',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final id = row['id'].toString();
    createdProductIds.add(id);
    return id;
  }

  Future<void> cleanup() async {
    for (final oid in createdOrderIds) {
      try {
        await http.delete(
          Uri.parse('$url/rest/v1/wallet_transactions?order_id=eq.$oid'),
          headers: SVC,
        );
      } catch (_) {}
      try {
        await http.delete(
          Uri.parse('$url/rest/v1/fleaber_commissions?order_id=eq.$oid'),
          headers: SVC,
        );
      } catch (_) {}
      await http.delete(
        Uri.parse('$url/rest/v1/orders?id=eq.$oid'),
        headers: SVC,
      );
    }
    for (final pid in createdProductIds) {
      try {
        await http.delete(
          Uri.parse('$url/rest/v1/product_offers?product_id=eq.$pid'),
          headers: SVC,
        );
      } catch (_) {}
      try {
        await http.delete(
          Uri.parse('$url/rest/v1/reviews?order_id=in.(${createdOrderIds.join(",")})'),
          headers: SVC,
        );
      } catch (_) {}
      try {
        await http.delete(
          Uri.parse('$url/rest/v1/chats?product_id=eq.$pid'),
          headers: SVC,
        );
      } catch (_) {}
      await http.delete(
        Uri.parse('$url/rest/v1/orders?product_id=eq.$pid'),
        headers: SVC,
      );
      await http.delete(
        Uri.parse('$url/rest/v1/products?id=eq.$pid'),
        headers: SVC,
      );
    }
    if (victimId != null) {
      try {
        await http.delete(
          Uri.parse('$url/auth/v1/admin/users/$victimId'),
          headers: SVC,
        );
      } catch (_) {}
    }
  }

  Json? firstRow(Object? body) {
    if (body is List && body.isNotEmpty && body.first is Map) {
      return Map<String, dynamic>.from(body.first as Map);
    }
    if (body is Map) return Map<String, dynamic>.from(body);
    return null;
  }

  Future<Json> insertOrder(Map<String, String> hdrs, Json row) async {
    final r = await req('POST', '$url/rest/v1/orders', hdrs, body: row);
    final fr = firstRow(r['body']);
    if (fr != null && fr['id'] != null) {
      createdOrderIds.add(fr['id'].toString());
    }
    return r;
  }

  Future<Json> checkout(String token, Json body) {
    return req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      h(token, prefer: false),
      body: body,
    );
  }

  try {
    // ------------------------------------------------------------------
    // OpenAPI / schema LIVE
    // ------------------------------------------------------------------
    stdout.writeln('== openapi ==');
    final openapi = await req('GET', '$url/rest/v1/', {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Accept': 'application/openapi+json',
    });
    mark('schema_openapi', openapi['http'] == 200 ? 'TESTED' : 'PARTIAL');
    final paths = (openapi['body'] is Map)
        ? (openapi['body'] as Map)['paths']
        : null;
    final orderCols = <String>[];
    final rpcNames = <String>[];
    if (paths is Map) {
      for (final k in paths.keys) {
        final ks = k.toString();
        if (ks.startsWith('/rpc/')) {
          rpcNames.add(ks.substring(5));
        }
      }
      final od = paths['/orders'];
      if (od is Map) {
        final post = od['post'] ?? od['get'];
        // best-effort extract
      }
    }
    notes.add('openapi_rpcs=${rpcNames.length}');
    stdout.writeln('RPCs visíveis OpenAPI: ${rpcNames.length}');

    // ------------------------------------------------------------------
    // Fixtures
    // ------------------------------------------------------------------
    fixtureProductId = await makeProduct(price: catalogPrice, qty: catalogQty);
    try {
      final vEmail = 'sat.aud.$stamp@fleaber.test';
      victimId = await sb.createAdminUser(
        email: vEmail,
        password: 'SatAudTest!234',
      );
      victimTok = await sb.signIn(email: vEmail, password: 'SatAudTest!234');
    } catch (err) {
      notes.add('victim_user_create_failed: $err');
    }

    // ------------------------------------------------------------------
    // PASS 2/4 — Order INSERT field matrix (buyer JWT)
    // ------------------------------------------------------------------
    stdout.writeln('== order INSERT matrix ==');
    mark('orders_insert_buyer', 'TESTED');

    Future<void> probeInsert(String id, Json extra, {String identity = 'buyer'}) async {
      final hdrs = identity == 'seller' ? SH : BH;
      final uid = identity == 'seller' ? sellerId : buyerId;
      final row = {
        'buyer_id': identity == 'seller' ? buyerId : uid,
        'seller_id': sellerId,
        'product_id': fixtureProductId,
        'quantity': 1,
        'price_total': catalogPrice,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
        ...extra,
      };
      if (identity == 'seller' && extra['buyer_id'] == null) {
        row['buyer_id'] = buyerId;
      }
      final r = await insertOrder(hdrs, row);
      final fr = firstRow(r['body']);
      stdout.writeln('INSERT $id http=${r['http']} id=${fr?['id']} status=${fr?['status']} pt=${fr?['price_total']} qty=${fr?['quantity']} cuc=${fr?['contract_unit_cents']} cq=${fr?['contract_qty']} paid=${fr?['amount_paid_cents']} pm=${fr?['payment_method']} stripe=${fr?['stripe_payment_intent_id']}');
      await Future<void>.delayed(Duration.zero);
      extra['_result'] = r;
      extra['_row'] = fr;
    }

    // Baseline
    final base = await insertOrder(BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': fixtureProductId,
      'quantity': 1,
      'price_total': catalogPrice,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    final baseRow = firstRow(base['body']);
    stdout.writeln('BASELINE http=${base['http']} row=$baseRow');
    if (baseRow == null) {
      notes.add('baseline_insert_failed ${base['http']} ${base['raw']}');
    }

    // Hostile contract_unit_cents
    final cheapContract = await insertOrder(BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': fixtureProductId,
      'quantity': 1,
      'price_total': 0.01,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      'contract_unit_cents': 1,
      'contract_qty': 1,
    });
    final cheapRow = firstRow(cheapContract['body']);
    stdout.writeln('CHEAP_CONTRACT http=${cheapContract['http']} $cheapRow');

    if (cheapRow != null && (cheapRow['contract_unit_cents'] == 1 || n(cheapRow['price_total']) <= 0.05)) {
      final ck = await checkout(buyerTok, {
        'order_id': cheapRow['id'],
        'buyer_id': buyerId,
        'shipping_method': 'entrega em mão',
      });
      stdout.writeln('CHEAP_CHECKOUT http=${ck['http']} body=${ck['body']}');
      final amt = extractAmount(ck['body']);
      final catalogCents = (catalogPrice * 100).round();
      if (amt != null && amt < catalogCents * 0.5) {
        finding(
          id: 'SAT-P0-01',
          sev: 'P0',
          surface: 'orders INSERT + create-payment-intent',
          identity: 'buyer JWT',
          pre: 'Produto catálogo $catalogPrice €, stock $catalogQty',
          action:
              'INSERT orders com contract_unit_cents=1, price_total=0.01; POST create-payment-intent',
          response: {
            'insert_http': cheapContract['http'],
            'insert_row': cheapRow,
            'checkout_http': ck['http'],
            'checkout': ck['body'],
            'amount_cents': amt,
          },
          after: cheapRow,
          impact:
              'Comprador define o preço autoritativo do contrato; Stripe cobra muito abaixo do catálogo.',
          confidence: 'alta',
          variants: ['contract_unit_cents no INSERT', 'seguido de checkout real'],
          fp:
              'Falsos positivos: amount inclui portes/proteção; comparar com catálogo unitário, não com 0.',
        );
      } else if (cheapRow['contract_unit_cents'] == 1) {
        finding(
          id: 'SAT-P1-01',
          sev: 'P1',
          surface: 'orders INSERT',
          identity: 'buyer JWT',
          action: 'INSERT contract_unit_cents=1 aceite',
          response: cheapRow,
          impact:
              'Coluna contract_* escrevível no INSERT JWT. Checkout pode ter realinhado; persistência do selo hostil permanece.',
          confidence: 'alta',
          variants: ['INSERT directo'],
        );
      } else {
        failClosed('cheap_contract_insert', {
          'http': cheapContract['http'],
          'row': cheapRow,
          'checkout': ck['body'],
        });
      }
    } else {
      failClosed('cheap_contract_insert', {
        'http': cheapContract['http'],
        'body': cheapContract['body'],
      });
    }

    // Proposta string without offer row
    final proposta = await insertOrder(BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': fixtureProductId,
      'quantity': 1,
      'price_total': 0.01,
      'status': 'reserva_pendente',
      'payment_method': 'Proposta de preço aceite',
      'shipping_method': 'entrega em mão',
    });
    final propRow = firstRow(proposta['body']);
    stdout.writeln('PROPOSTA http=${proposta['http']} $propRow');
    if (propRow != null) {
      final sealed = n(propRow['contract_unit_cents']);
      final ck = await checkout(buyerTok, {
        'order_id': propRow['id'],
        'buyer_id': buyerId,
        'shipping_method': 'entrega em mão',
      });
      final amt = extractAmount(ck['body']);
      stdout.writeln('PROPOSTA_CHECKOUT http=${ck['http']} amt=$amt body=${ck['body']}');
      if (sealed == 1 || (amt != null && amt < (catalogPrice * 100) * 0.5)) {
        finding(
          id: 'SAT-P0-02',
          sev: 'P0',
          surface: 'orders.seal_contract + checkout',
          identity: 'buyer JWT',
          pre: 'Sem product_offers aceite',
          action:
              'INSERT payment_method contém "proposta" + price_total=0.01; checkout',
          response: {
            'insert': propRow,
            'checkout_http': ck['http'],
            'checkout': ck['body'],
            'amount_cents': amt,
          },
          impact:
              'String "proposta" no payment_method sela preço abaixo do catálogo sem oferta real.',
          confidence: 'alta',
          variants: [
            'Proposta de preço aceite',
            'proposta',
            'PROPOSTA COMERCIAL',
          ],
        );
      } else {
        failClosed('proposta_without_offer', {
          'row': propRow,
          'checkout': ck['body'],
          'amt': amt,
        });
      }
    } else {
      failClosed('proposta_insert', proposta);
    }

    // Proposta variant strings
    for (final pm in ['proposta', 'xproposta', 'Minha proposta 0€']) {
      final r = await insertOrder(BH, {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': fixtureProductId,
        'quantity': 1,
        'price_total': 0.02,
        'status': 'reserva_pendente',
        'payment_method': pm,
        'shipping_method': 'entrega em mão',
      });
      final row = firstRow(r['body']);
      stdout.writeln('PROPOSTA_VAR "$pm" http=${r['http']} cuc=${row?['contract_unit_cents']} pt=${row?['price_total']}');
      if (row != null && n(row['contract_unit_cents']) <= 2) {
        finding(
          id: 'SAT-P0-02b-$pm',
          sev: 'P0',
          surface: 'orders.seal_contract',
          identity: 'buyer JWT',
          action: 'INSERT payment_method="$pm" price_total=0.02',
          response: row,
          impact: 'Variante semântica da proposta sela preço hostil.',
          confidence: 'alta',
          variants: [pm],
        );
      } else {
        failClosed('proposta_var_$pm', {'http': r['http'], 'row': row});
      }
    }

    // contract_qty vs quantity mismatch
    final qtyMismatch = await insertOrder(BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': fixtureProductId,
      'quantity': 1,
      'contract_qty': 7,
      'contract_unit_cents': (catalogPrice * 100).round(),
      'price_total': catalogPrice,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    final qmRow = firstRow(qtyMismatch['body']);
    stdout.writeln('QTY_MISMATCH http=${qtyMismatch['http']} $qmRow');
    if (qmRow != null && n(qmRow['contract_qty']) > n(qmRow['quantity'])) {
      final ck = await checkout(buyerTok, {
        'order_id': qmRow['id'],
        'buyer_id': buyerId,
        'shipping_method': 'entrega em mão',
      });
      final amt = extractAmount(ck['body']);
      stdout.writeln('QTY_MISMATCH_CHECKOUT amt=$amt body=${ck['body']}');
      finding(
        id: 'SAT-P1-02',
        sev: 'P1',
        surface: 'orders.contract_qty vs quantity + checkout',
        identity: 'buyer JWT',
        action: 'INSERT quantity=1 contract_qty=7; checkout usa contract_qty',
        response: {'row': qmRow, 'checkout': ck['body'], 'amount_cents': amt},
        impact:
            'Quantidade cobrada/consumida pode divergir da quantity visível/stock-checked.',
        confidence: 'alta',
        variants: ['contract_qty no INSERT', 'checkout'],
      );
    } else {
      failClosed('qty_mismatch', {'http': qtyMismatch['http'], 'row': qmRow});
    }

    // High price / low / qty extremes
    for (final spec in [
      {'id': 'price_0', 'price_total': 0, 'quantity': 1},
      {'id': 'price_neg', 'price_total': -1, 'quantity': 1},
      {'id': 'qty_0', 'price_total': catalogPrice, 'quantity': 0},
      {'id': 'qty_neg', 'price_total': catalogPrice, 'quantity': -1},
      {'id': 'qty_100', 'price_total': catalogPrice, 'quantity': 100},
      {'id': 'qty_9999', 'price_total': catalogPrice, 'quantity': 9999},
      {'id': 'qty_stock_plus', 'price_total': catalogPrice, 'quantity': catalogQty + 1},
    ]) {
      final r = await insertOrder(BH, {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': fixtureProductId,
        'quantity': spec['quantity'],
        'price_total': spec['price_total'],
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
      });
      final row = firstRow(r['body']);
      final okInsert = r['http'] == 201 && row != null;
      stdout.writeln('EXTREME ${spec['id']} http=${r['http']} qty=${row?['quantity']} pt=${row?['price_total']}');
      if (okInsert && (spec['id'] == 'qty_100' || spec['id'] == 'qty_9999' || spec['id'] == 'qty_stock_plus' || spec['id'] == 'qty_0' || spec['id'] == 'qty_neg')) {
        finding(
          id: 'SAT-P2-QTY-${spec['id']}',
          sev: 'P2',
          surface: 'orders.quantity INSERT',
          identity: 'buyer JWT',
          action: 'INSERT ${spec['id']}',
          response: {'http': r['http'], 'row': row, 'err': r['body']},
          impact: 'Quantidade extrema aceite no INSERT.',
          confidence: 'média',
        );
      } else {
        failClosed('extreme_${spec['id']}', {'http': r['http'], 'body': r['body']});
      }
    }

    // Terminal status / stripe ids / amount_paid / flags
    final forged = await insertOrder(BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': fixtureProductId,
      'quantity': 1,
      'price_total': catalogPrice,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      'stripe_payment_intent_id': 'pi_fake_hostile',
      'stripe_checkout_session_id': 'cs_fake_hostile',
      'stripe_refund_id': 're_fake',
      'amount_paid_cents': 990000,
      'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
      'wallet_refund_processed_at': DateTime.now().toUtc().toIso8601String(),
      'stock_units_applied': 1,
      'live_raffle_id': '00000000-0000-0000-0000-000000000001',
    });
    final forgedRow = firstRow(forged['body']);
    stdout.writeln('FORGED_FIELDS http=${forged['http']} $forgedRow');
    if (forgedRow != null) {
      final status = '${forgedRow['status']}'.toLowerCase();
      final paid = n(forgedRow['amount_paid_cents']);
      final pi = forgedRow['stripe_payment_intent_id'];
      if (status == 'pago' || paid > 0 || (pi != null && '$pi'.contains('fake'))) {
        finding(
          id: 'SAT-P0-03',
          sev: 'P0',
          surface: 'orders INSERT privileged cols',
          identity: 'buyer JWT',
          action: 'INSERT status=pago + Stripe IDs + amount_paid_cents',
          response: forgedRow,
          impact: 'Cliente persiste estado pago / captura / IDs Stripe falsos.',
          confidence: 'alta',
        );
      } else {
        failClosed('forged_paid_fields', {
          'status': forgedRow['status'],
          'amount_paid_cents': forgedRow['amount_paid_cents'],
          'pi': forgedRow['stripe_payment_intent_id'],
          'raffle': forgedRow['live_raffle_id'],
          'stock_units_applied': forgedRow['stock_units_applied'],
        });
      }
    }

    // Seller mismatch / third-party buyer
    if (victimId != null) {
      final stealBuyer = await insertOrder(BH, {
        'buyer_id': victimId,
        'seller_id': sellerId,
        'product_id': fixtureProductId,
        'quantity': 1,
        'price_total': catalogPrice,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
      });
      stdout.writeln('STEAL_BUYER http=${stealBuyer['http']} ${stealBuyer['body']}');
      final sbRow = firstRow(stealBuyer['body']);
      if (sbRow != null && sbRow['buyer_id'] == victimId) {
        finding(
          id: 'SAT-P1-03',
          sev: 'P1',
          surface: 'orders INSERT buyer_id',
          identity: 'buyer JWT',
          action: 'INSERT buyer_id de terceiro',
          response: sbRow,
          impact: 'Criar encomenda em nome de outra conta.',
          confidence: 'alta',
        );
      } else {
        failClosed('steal_buyer_id', stealBuyer);
      }
    }

    final sellerAsParty = await insertOrder(SH, {
      'buyer_id': victimId ?? buyerId,
      'seller_id': sellerId,
      'product_id': fixtureProductId,
      'quantity': 1,
      'price_total': 0.01,
      'status': 'premio_rifa',
      'payment_method': 'Prémio da Rifa',
      'shipping_method': 'entrega em mão',
      'contract_unit_cents': 0,
      'live_raffle_id': '00000000-0000-0000-0000-000000000001',
    });
    final sap = firstRow(sellerAsParty['body']);
    stdout.writeln('SELLER_PRIZE_FORGE http=${sellerAsParty['http']} $sap');
    if (sap != null &&
        '${sap['status']}'.toLowerCase() == 'premio_rifa') {
      finding(
        id: 'SAT-P1-04',
        sev: 'P1',
        surface: 'orders INSERT seller JWT premio_rifa',
        identity: 'seller JWT',
        action: 'INSERT status=premio_rifa / live_raffle_id',
        response: sap,
        impact: 'Vendedor forja encomenda-prémio sem draw.',
        confidence: 'alta',
      );
    } else {
      failClosed('seller_prize_forge', {'http': sellerAsParty['http'], 'row': sap, 'body': sellerAsParty['body']});
    }

    // Foreign product (create product as... can't easily; use random uuid)
    final ghost = await insertOrder(BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': '00000000-0000-0000-0000-000000000099',
      'quantity': 1,
      'price_total': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    });
    failClosed('ghost_product', {'http': ghost['http'], 'body': ghost['body']});

    // ------------------------------------------------------------------
    // UPDATE matrix / state machine
    // ------------------------------------------------------------------
    stdout.writeln('== status machine ==');
    mark('orders_status_machine', 'TESTED');
    if (baseRow != null) {
      final oid = baseRow['id'];
      for (final spec in [
        ['buyer', BH, 'pago'],
        ['buyer', BH, 'enviado'],
        ['buyer', BH, 'concluido'],
        ['buyer', BH, 'devolvida'],
        ['buyer', BH, 'cancelado'],
        ['seller', SH, 'pago'],
        ['seller', SH, 'enviado'],
        ['seller', SH, 'concluido'],
        ['seller', SH, 'devolvida'],
      ]) {
        final r = await req(
          'PATCH',
          '$url/rest/v1/orders?id=eq.$oid',
          spec[1] as Map<String, String>,
          body: {'status': spec[2]},
        );
        final row = firstRow(r['body']);
        stdout.writeln('STATUS ${spec[0]} → ${spec[2]} http=${r['http']} now=${row?['status'] ?? r['body']}');
        if (row != null && '${row['status']}' == spec[2] && spec[2] != 'enviado') {
          // seller→enviado from reserva may be legitimate; pago/concluido/devolvida from unpaid is not
          if (spec[2] == 'pago' || spec[2] == 'concluido' || spec[2] == 'devolvida') {
            finding(
              id: 'SAT-P1-ST-${spec[0]}-${spec[2]}',
              sev: 'P1',
              surface: 'orders.status UPDATE',
              identity: '${spec[0]} JWT',
              action: 'PATCH status=${spec[2]} from reserva_pendente unpaid',
              response: row,
              impact: 'Transição de estado não paga aceite via JWT.',
              confidence: 'alta',
            );
          }
        } else {
          failClosed('status_${spec[0]}_${spec[2]}', {
            'http': r['http'],
            'status': row?['status'],
          });
        }
      }

      // money col updates
      final moneyUp = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.$oid',
        BH,
        body: {
          'price_total': 0.01,
          'contract_unit_cents': 1,
          'quantity': 9,
          'amount_paid_cents': 12,
          'payment_method': 'MB WAY',
          'buyer_id': victimId ?? sellerId,
        },
      );
      final mu = firstRow(moneyUp['body']);
      stdout.writeln('MONEY_UPDATE $mu');
      if (mu != null &&
          (n(mu['price_total']) <= 0.05 ||
              mu['contract_unit_cents'] == 1 ||
              n(mu['amount_paid_cents']) == 12)) {
        finding(
          id: 'SAT-P0-04',
          sev: 'P0',
          surface: 'orders UPDATE money',
          identity: 'buyer JWT',
          action: 'PATCH price/contract/amount_paid',
          response: mu,
          impact: 'Campos financeiros mutáveis após INSERT.',
          confidence: 'alta',
        );
      } else {
        failClosed('money_update_frozen', mu ?? moneyUp['body']);
      }
    }

    // Seller marks MB WAY pago (own new order)
    final mb = await insertOrder(BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': fixtureProductId,
      'quantity': 1,
      'price_total': catalogPrice,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
      'shipping_method': 'entrega em mão',
    });
    final mbRow = firstRow(mb['body']);
    if (mbRow != null) {
      final beforeStock = await sb.select('products', filter: 'id=eq.$fixtureProductId', limit: 1);
      final r = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.${mbRow['id']}',
        SH,
        body: {'status': 'pago'},
      );
      final after = firstRow(r['body']);
      final afterStock = await sb.select('products', filter: 'id=eq.$fixtureProductId', limit: 1);
      stdout.writeln('MBWAY_PAGO http=${r['http']} status=${after?['status']} stock ${beforeStock.first['quantity']}→${afterStock.first['quantity']}');
      mark('off_platform_seller_pago', 'TESTED');
      // expected: seller CAN mark MB WAY pago; stock consumes; wallet should NOT mint
      if (after != null && '${after['status']}' == 'pago') {
        notes.add('MB WAY seller→pago allowed; stock ${beforeStock.first['quantity']}→${afterStock.first['quantity']}');
        // try wallet release via concluido
        final rel = await req(
          'PATCH',
          '$url/rest/v1/orders?id=eq.${mbRow['id']}',
          SH,
          body: {'status': 'concluido'},
        );
        final relRow = firstRow(rel['body']);
        stdout.writeln('MBWAY_CONCLUIDO ${relRow?['status']} wr=${relRow?['wallet_release_processed_at']}');
        final w = await sb.select(
          'wallet_transactions',
          filter: 'order_id=eq.${mbRow['id']}',
          limit: 20,
        );
        stdout.writeln('MBWAY_LEDGER $w');
        final minted = w.any((t) => t['type'] == 'venda' && n(t['amount']) > 0);
        if (minted) {
          finding(
            id: 'SAT-P0-05',
            sev: 'P0',
            surface: 'wallet + MB WAY',
            identity: 'seller JWT',
            action: 'MB WAY → pago → concluido',
            response: {'order': relRow, 'ledger': w},
            impact: 'Dinheiro off-platform criou fundos Fleaber.',
            confidence: 'alta',
          );
        } else {
          failClosed('mbway_no_wallet_mint', {'ledger': w, 'status': relRow?['status']});
        }
      }
    }

    // Empty payment_method → seller pago?
    final emptyPm = await insertOrder(BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': fixtureProductId,
      'quantity': 1,
      'price_total': catalogPrice,
      'status': 'reserva_pendente',
      'payment_method': '',
      'shipping_method': 'entrega em mão',
    });
    final ep = firstRow(emptyPm['body']);
    if (ep != null) {
      final r = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.${ep['id']}',
        SH,
        body: {'status': 'pago'},
      );
      final row = firstRow(r['body']);
      stdout.writeln('EMPTY_PM_PAGO http=${r['http']} status=${row?['status']} pm=${ep['payment_method']}');
      if (row != null && '${row['status']}' == 'pago') {
        finding(
          id: 'SAT-P1-05',
          sev: 'P1',
          surface: 'orders.payment_method empty + seller pago',
          identity: 'seller JWT',
          action: 'INSERT payment_method="" ; PATCH status=pago',
          response: row,
          impact:
              'Método vazio não é classificado como plataforma; vendedor marca pago sem captura Stripe e consome stock.',
          confidence: 'alta',
          variants: ['payment_method vazio', 'null se aceite'],
        );
      } else {
        failClosed('empty_pm_seller_pago', {'http': r['http'], 'row': row});
      }
    }

    // Catalog hike after seal
    if (baseRow != null) {
      await sb.patch('products', 'id=eq.$fixtureProductId', {'price': 199.0});
      final ck = await checkout(buyerTok, {
        'order_id': baseRow['id'],
        'buyer_id': buyerId,
        'shipping_method': 'entrega em mão',
      });
      final amt = extractAmount(ck['body']);
      stdout.writeln('CATALOG_HIKE_CHECKOUT amt=$amt http=${ck['http']}');
      await sb.patch('products', 'id=eq.$fixtureProductId', {'price': catalogPrice});
      mark('catalog_vs_contract', 'TESTED');
      if (amt != null && amt > 15000) {
        finding(
          id: 'SAT-P1-06',
          sev: 'P1',
          surface: 'checkout vs catalog',
          identity: 'buyer JWT',
          action: 'Subir products.price após order; checkout',
          response: ck['body'],
          impact: 'Checkout segue catálogo vivo em vez do contrato selado.',
          confidence: 'média',
        );
      } else {
        failClosed('catalog_hike_ignored_or_blocked', {'amt': amt, 'http': ck['http']});
      }
    }

    // ------------------------------------------------------------------
    // Checkout amount override
    // ------------------------------------------------------------------
    if (baseRow != null) {
      final ck = await checkout(buyerTok, {
        'order_id': baseRow['id'],
        'buyer_id': buyerId,
        'amount': 0.5,
        'item_price': 0.5,
        'shipping_method': 'entrega em mão',
      });
      final amt = extractAmount(ck['body']);
      stdout.writeln('CHECKOUT_AMOUNT_OVERRIDE amt=$amt http=${ck['http']} ${ck['body']}');
      mark('checkout_client_amount', 'TESTED');
      if (amt != null && amt < 200) {
        finding(
          id: 'SAT-P0-06',
          sev: 'P0',
          surface: 'create-payment-intent',
          identity: 'buyer JWT',
          action: 'POST amount=0.5 no body',
          response: ck['body'],
          impact: 'Cliente controla o valor cobrado pelo Stripe.',
          confidence: 'alta',
        );
      } else {
        failClosed('checkout_ignores_client_amount', {'amt': amt, 'http': ck['http']});
      }
    }

    // Bag checkout with mixed hostile line
    mark('bag_checkout', 'TESTED');
    final pBag = await makeProduct(price: 10, qty: 3, title: 'SAT BAG A $stamp');
    final pBag2 = await makeProduct(price: 25, qty: 3, title: 'SAT BAG B $stamp');
    final oA = await insertOrder(BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pBag,
      'quantity': 1,
      'price_total': 10,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    final oB = await insertOrder(BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pBag2,
      'quantity': 1,
      'price_total': 0.01,
      'contract_unit_cents': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Proposta de preço aceite',
      'shipping_method': 'entrega em mão',
    });
    final ra = firstRow(oA['body']);
    final rb = firstRow(oB['body']);
    if (ra != null && rb != null) {
      final bagCk = await checkout(buyerTok, {
        'buyer_id': buyerId,
        'bag_checkout': true,
        'bag_lines': [
          {'order_id': ra['id']},
          {'order_id': rb['id']},
        ],
        'shipping_method': 'entrega em mão',
      });
      stdout.writeln('BAG_CHECKOUT http=${bagCk['http']} ${bagCk['body']}');
      final amt = extractAmount(bagCk['body']);
      // expected ~ 10+25 + shipping + protection if sealed to catalog; or 10+0.01 if hostile
      if (amt != null && amt < 1500) {
        finding(
          id: 'SAT-P0-07',
          sev: 'P0',
          surface: 'bag checkout',
          identity: 'buyer JWT',
          action: 'Saco 2 linhas, uma com contrato 1 cêntimo',
          response: bagCk['body'],
          impact: 'Uma linha hostil reduz a captura do saco.',
          confidence: 'alta',
        );
      } else {
        failClosed('bag_mixed_line', {'amt': amt, 'http': bagCk['http'], 'b': rb});
      }
    }

    // Concurrent checkout
    if (baseRow != null) {
      mark('concurrency_double_checkout', 'TESTED');
      final f1 = checkout(buyerTok, {
        'order_id': baseRow['id'],
        'buyer_id': buyerId,
        'shipping_method': 'entrega em mão',
      });
      final f2 = checkout(buyerTok, {
        'order_id': baseRow['id'],
        'buyer_id': buyerId,
        'shipping_method': 'entrega em mão',
      });
      final rs = await Future.wait([f1, f2]);
      stdout.writeln('DOUBLE_CHECKOUT ${rs.map((r) => r['http']).toList()}');
      notes.add('double_checkout_http=${rs.map((r) => r['http']).toList()}');
    }

    // ------------------------------------------------------------------
    // RPC grants (JWT buyer + anon)
    // ------------------------------------------------------------------
    stdout.writeln('== RPC grants ==');
    mark('rpc_grants', 'TESTED');
    final rpcTargets = [
      'batata_credit_wallet_once',
      'batata_debit_wallet_once',
      'batata_clawback_seller_wallet_for_order',
      'batata_ensure_wallet',
      'batata_release_seller_wallet_for_order',
      'batata_refund_buyer_wallet_for_order',
      'batata_wallet_payout_debit',
      'batata_wallet_payout_finish',
      'batata_process_partial_refund_dispute',
      'batata_finalize_stripe_order_refund',
      'batata_generate_auto_feedback',
      'batata_create_raffle_prize_order',
      'batata_draw_live_raffle_winners',
      'batata_admin_list_profiles',
      'batata_admin_resolve_dispute',
      'staging_nuke_user_data',
      'batata_lab_clear_all_fm_pending',
      'batata_settle_live_tip_from_stripe',
      'batata_wallet_apply_tip_once',
      'batata_assert_wallet_rpc_grants',
      'batata_ingest_ocr_reservation_v2',
    ];
    for (final fn in rpcTargets) {
      final payloads = <Json>[
        {},
        {'p_order_id': baseRow?['id'] ?? '00000000-0000-0000-0000-000000000001'},
        {'p_now': '2099-01-01T00:00:00Z'},
        {'p_user_id': sellerId, 'p_amount_cents': 100, 'p_idempotency_key': 'sat-$stamp'},
        {'p_raffle_id': '00000000-0000-0000-0000-000000000001', 'p_winner_uid': buyerId},
      ];
      Json? last;
      for (final p in payloads) {
        last = await req('POST', '$url/rest/v1/rpc/$fn', BH, body: p);
        if (last['http'] != 404 && last['http'] != 400) break;
      }
      final httpCode = last?['http'];
      stdout.writeln('RPC $fn buyer http=$httpCode body=${_clip(last?['body'])}');
      // 200 with money mutation is finding; 403/401/42501 is fail-closed
      if (httpCode == 200 || httpCode == 204) {
        if (fn.contains('wallet') ||
            fn.contains('refund') ||
            fn.contains('payout') ||
            fn.contains('nuke') ||
            fn.contains('auto_feedback') ||
            fn.contains('raffle_prize') ||
            fn.contains('credit') ||
            fn.contains('debit') ||
            fn.contains('clawback') ||
            fn.contains('settle_live_tip')) {
          finding(
            id: 'SAT-P1-RPC-$fn',
            sev: fn.contains('nuke') || fn.contains('credit') || fn.contains('payout') || fn.contains('prize')
                ? 'P0'
                : 'P1',
            surface: 'RPC SECURITY DEFINER',
            identity: 'buyer JWT',
            action: 'POST /rpc/$fn',
            response: last?['body'],
            impact: 'RPC privilegiada executável por JWT (GRANT LIVE demasiado aberto).',
            confidence: 'média',
            fp: 'Pode ser no-op (return false) — verificar side-effects.',
          );
        } else {
          notes.add('RPC $fn buyer 200 (may be intended)');
        }
      } else {
        failClosed('rpc_buyer_$fn', {'http': httpCode, 'body': _clip(last?['body'])});
      }
      final anonR = await req('POST', '$url/rest/v1/rpc/$fn', ANON, body: {});
      if (anonR['http'] == 200) {
        finding(
          id: 'SAT-P0-RPC-ANON-$fn',
          sev: 'P0',
          surface: 'RPC anon',
          identity: 'anon',
          action: 'POST /rpc/$fn',
          response: anonR['body'],
          impact: 'RPC privilegiada executável anónima.',
          confidence: 'alta',
        );
      }
    }

    // auto_feedback future p_now specifically
    final af = await req(
      'POST',
      '$url/rest/v1/rpc/batata_generate_auto_feedback',
      BH,
      body: {'p_now': '2099-12-31T00:00:00Z'},
    );
    stdout.writeln('AUTO_FEEDBACK_FUTURE http=${af['http']} ${af['body']}');
    if (af['http'] == 200) {
      finding(
        id: 'SAT-P1-07',
        sev: 'P1',
        surface: 'batata_generate_auto_feedback',
        identity: 'buyer JWT',
        action: 'RPC p_now=2099 — salta espera 48h / pode libertar wallets',
        response: af['body'],
        impact:
            'Cliente invoca job de feedback automático com relógio arbitrário; composição com release de wallet.',
        confidence: 'média',
        fp: 'Pode falhar a meio por trigger de reviews; mesmo assim GRANT é incorrecto.',
      );
    }

    // ------------------------------------------------------------------
    // Wallets / profiles / chat / reviews / storage / lives
    // ------------------------------------------------------------------
    stdout.writeln('== wallets ==');
    mark('wallets', 'TESTED');
    final wSel = await req('GET', '$url/rest/v1/wallets?select=*&limit=5', BH);
    stdout.writeln('WALLET_SELECT_BUYER http=${wSel['http']} n=${_len(wSel['body'])}');
    final wOther = await req(
      'GET',
      '$url/rest/v1/wallets?id=eq.$sellerId&select=id,balance,stripe_account_id',
      BH,
    );
    stdout.writeln('WALLET_OTHER http=${wOther['http']} ${wOther['body']}');
    if (_len(wOther['body']) > 0) {
      finding(
        id: 'SAT-P1-08',
        sev: 'P1',
        surface: 'wallets SELECT',
        identity: 'buyer JWT',
        action: 'SELECT wallet do vendedor',
        response: wOther['body'],
        impact: 'Leitura de saldo/Connect de terceiro.',
        confidence: 'alta',
      );
    } else {
      failClosed('wallet_other_select', wOther['body']);
    }
    final wUp = await req(
      'PATCH',
      '$url/rest/v1/wallets?id=eq.$buyerId',
      BH,
      body: {'balance': 99999},
    );
    stdout.writeln('WALLET_UPDATE http=${wUp['http']} ${wUp['body']}');
    if (wUp['http'] == 200 && _len(wUp['body']) > 0) {
      finding(
        id: 'SAT-P0-08',
        sev: 'P0',
        surface: 'wallets UPDATE',
        identity: 'buyer JWT',
        action: 'PATCH balance=99999',
        response: wUp['body'],
        impact: 'Saldo de carteira escrevível pelo cliente.',
        confidence: 'alta',
      );
    } else {
      failClosed('wallet_balance_update', {'http': wUp['http'], 'body': wUp['body']});
    }
    final wIns = await req('POST', '$url/rest/v1/wallet_transactions', BH, body: {
      'wallet_id': buyerId,
      'amount': 50,
      'type': 'venda',
      'description': 'hostile',
    });
    stdout.writeln('WTX_INSERT http=${wIns['http']} ${wIns['body']}');
    if (wIns['http'] == 201) {
      finding(
        id: 'SAT-P0-09',
        sev: 'P0',
        surface: 'wallet_transactions INSERT',
        identity: 'buyer JWT',
        action: 'INSERT transação venda',
        response: wIns['body'],
        impact: 'Ledger forjável; pode inflacionar saldo se triggers creditarem.',
        confidence: 'alta',
      );
    } else {
      failClosed('wtx_insert', {'http': wIns['http']});
    }

    stdout.writeln('== profiles ==');
    mark('profiles', 'TESTED');
    final pOther = await req(
      'GET',
      '$url/rest/v1/profiles?id=eq.$sellerId&select=id,user_type,iban,mb_way,phone,phone_verified_at,legal_full_name',
      BH,
    );
    stdout.writeln('PROFILE_OTHER http=${pOther['http']} ${pOther['body']}');
    if (_len(pOther['body']) > 0) {
      final row = firstRow(pOther['body']);
      final pii = row != null &&
          (row['iban'] != null || row['mb_way'] != null || row['phone'] != null);
      finding(
        id: pii ? 'SAT-P1-09' : 'SAT-P2-09',
        sev: pii ? 'P1' : 'P2',
        surface: 'profiles SELECT',
        identity: 'buyer JWT',
        action: 'SELECT perfil vendedor (PII)',
        response: row ?? {},
        impact: pii
            ? 'PII financeiro/identidade de terceiro visível.'
            : 'Leitura de perfil alheio (campos não-PII).',
        confidence: 'alta',
      );
    } else {
      failClosed('profile_other_select', pOther['body']);
    }
    final pAdmin = await req(
      'PATCH',
      '$url/rest/v1/profiles?id=eq.$buyerId',
      BH,
      body: {'user_type': 'admin'},
    );
    final pAdminRow = firstRow(pAdmin['body']);
    stdout.writeln('PROFILE_ADMIN http=${pAdmin['http']} type=${pAdminRow?['user_type']}');
    if (pAdminRow != null && '${pAdminRow['user_type']}'.toLowerCase() == 'admin') {
      finding(
        id: 'SAT-P0-10',
        sev: 'P0',
        surface: 'profiles.user_type',
        identity: 'buyer JWT',
        action: 'PATCH user_type=admin',
        response: pAdminRow,
        impact: 'Auto-promoção a admin.',
        confidence: 'alta',
      );
    } else {
      failClosed('user_type_admin', pAdminRow ?? pAdmin['body']);
    }
    final pPhone = await req(
      'PATCH',
      '$url/rest/v1/profiles?id=eq.$buyerId',
      BH,
      body: {'phone_verified_at': DateTime.now().toUtc().toIso8601String()},
    );
    final pPhoneRow = firstRow(pPhone['body']);
    stdout.writeln('PHONE_VERIFIED http=${pPhone['http']} ${pPhoneRow?['phone_verified_at']}');
    if (pPhoneRow != null && pPhoneRow['phone_verified_at'] != null) {
      finding(
        id: 'SAT-P2-10',
        sev: 'P2',
        surface: 'profiles.phone_verified_at',
        identity: 'buyer JWT',
        action: 'PATCH phone_verified_at=now()',
        response: {'phone_verified_at': pPhoneRow['phone_verified_at']},
        impact:
            'Flag de verificação SMS forjável; pode desbloquear handles/payouts se a app confiar nela.',
        confidence: 'alta',
        fp: 'Só P1 se algum gate privilegiado depender exclusivamente desta coluna.',
      );
    } else {
      failClosed('phone_verified_at', pPhone['body']);
    }
    // restore phone_verified if we set it? don't wipe real data — only if we changed from null
    // skip restore of shared buyer

    stdout.writeln('== chat ==');
    mark('chat', 'TESTED');
    if (victimId != null && victimTok != null) {
      final cross = await req('POST', '$url/rest/v1/chats', BH, body: {
        'user_a': victimId,
        'user_b': sellerId,
        'last_message': 'spoof',
      });
      stdout.writeln('CHAT_THIRD_PARTIES http=${cross['http']} ${cross['body']}');
      if (cross['http'] == 201) {
        finding(
          id: 'SAT-P1-10',
          sev: 'P1',
          surface: 'chats INSERT',
          identity: 'buyer JWT',
          action: 'INSERT chat entre duas contas alheias',
          response: cross['body'],
          impact: 'Abrir canal privado de terceiros / injectar last_message.',
          confidence: 'alta',
        );
      } else {
        failClosed('chat_third_parties', {'http': cross['http']});
      }
    }
    final myChat = await req('POST', '$url/rest/v1/chats', BH, body: {
      'user_a': buyerId,
      'user_b': sellerId,
      'product_id': fixtureProductId,
      'last_message': 'sat-aud',
    });
    final chatRow = firstRow(myChat['body']);
    stdout.writeln('CHAT_OWN http=${myChat['http']} ${chatRow?['id']}');
    if (chatRow != null) {
      final spoofMsg = await req('POST', '$url/rest/v1/chat_messages', BH, body: {
        'chat_id': chatRow['id'],
        'sender_id': sellerId,
        'receiver_id': buyerId,
        'text': 'spoof-from-seller',
        'is_read': false,
      });
      stdout.writeln('MSG_SPOOF http=${spoofMsg['http']} ${spoofMsg['body']}');
      if (spoofMsg['http'] == 201) {
        finding(
          id: 'SAT-P1-11',
          sev: 'P1',
          surface: 'chat_messages INSERT',
          identity: 'buyer JWT',
          action: 'INSERT sender_id do vendedor',
          response: spoofMsg['body'],
          impact: 'Spoof de remetente no chat.',
          confidence: 'alta',
        );
      } else {
        failClosed('msg_sender_spoof', {'http': spoofMsg['http']});
      }
      final legitMsg = await req('POST', '$url/rest/v1/chat_messages', SH, body: {
        'chat_id': chatRow['id'],
        'sender_id': sellerId,
        'receiver_id': buyerId,
        'text': 'seller-original',
        'is_read': false,
      });
      final lm = firstRow(legitMsg['body']);
      if (lm != null) {
        final edit = await req(
          'PATCH',
          '$url/rest/v1/chat_messages?id=eq.${lm['id']}',
          BH,
          body: {'text': 'edited-by-buyer'},
        );
        final er = firstRow(edit['body']);
        stdout.writeln('MSG_EDIT_OTHER http=${edit['http']} text=${er?['text']}');
        if (er != null && er['text'] == 'edited-by-buyer') {
          finding(
            id: 'SAT-P1-12',
            sev: 'P1',
            surface: 'chat_messages UPDATE',
            identity: 'buyer JWT',
            action: 'PATCH texto da mensagem da contraparte',
            response: er,
            impact: 'Editar mensagem alheia.',
            confidence: 'alta',
          );
        } else {
          failClosed('msg_edit_other', {'http': edit['http'], 'text': er?['text']});
        }
      }
      if (victimTok != null) {
        final leak = await req(
          'GET',
          '$url/rest/v1/chat_messages?chat_id=eq.${chatRow['id']}&select=id,text,sender_id',
          h(victimTok),
        );
        stdout.writeln('MSG_CROSS_READ http=${leak['http']} n=${_len(leak['body'])}');
        if (_len(leak['body']) > 0) {
          finding(
            id: 'SAT-P1-13',
            sev: 'P1',
            surface: 'chat_messages SELECT',
            identity: 'victim JWT',
            action: 'SELECT mensagens de chat alheio',
            response: {'n': _len(leak['body'])},
            impact: 'Leitura cruzada de chat.',
            confidence: 'alta',
          );
        } else {
          failClosed('msg_cross_read', {'http': leak['http']});
        }
      }
    }

    stdout.writeln('== reviews ==');
    mark('reviews', 'TESTED');
    final rev = await req('POST', '$url/rest/v1/reviews', BH, body: {
      'order_id': baseRow?['id'],
      'buyer_id': sellerId,
      'target_id': buyerId,
      'stars': 5,
      'comment': 'hostile',
      'author_role': 'comprador',
      'is_automatic': true,
    });
    stdout.writeln('REVIEW_UNPAID http=${rev['http']} ${rev['body']}');
    if (rev['http'] == 201) {
      finding(
        id: 'SAT-P1-14',
        sev: 'P1',
        surface: 'reviews INSERT',
        identity: 'buyer JWT',
        action: 'Review em order não concluída + spoof ids',
        response: rev['body'],
        impact: 'Review sem compra concluída; possível libertação de wallet.',
        confidence: 'alta',
      );
    } else {
      failClosed('review_unpaid', {'http': rev['http']});
    }

    stdout.writeln('== offers ==');
    mark('product_offers', 'TESTED');
    final off = await req('POST', '$url/rest/v1/product_offers', BH, body: {
      'product_id': fixtureProductId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 0.50,
      'list_price': catalogPrice,
      'offered_by': 'buyer',
      'status': 'accepted',
    });
    final offRow = firstRow(off['body']);
    stdout.writeln('OFFER_SELF_ACCEPT http=${off['http']} $offRow');
    if (offRow != null && '${offRow['status']}' == 'accepted') {
      finding(
        id: 'SAT-P2-11',
        sev: 'P2',
        surface: 'product_offers INSERT',
        identity: 'buyer JWT',
        action: 'INSERT oferta já accepted a 0.50€',
        response: offRow,
        impact:
            'Comprador cria oferta “aceite” sem o vendedor; composição com selo proposta.',
        confidence: 'alta',
      );
      final follow = await insertOrder(BH, {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': fixtureProductId,
        'quantity': 1,
        'price_total': 0.50,
        'product_offer_id': offRow['id'],
        'status': 'reserva_pendente',
        'payment_method': 'Proposta de preço aceite',
        'shipping_method': 'entrega em mão',
      });
      final fr = firstRow(follow['body']);
      stdout.writeln('OFFER_FOLLOW_ORDER $fr');
      if (fr != null) {
        final ck = await checkout(buyerTok, {
          'order_id': fr['id'],
          'buyer_id': buyerId,
          'shipping_method': 'entrega em mão',
        });
        final amt = extractAmount(ck['body']);
        stdout.writeln('OFFER_FOLLOW_CHECKOUT amt=$amt ${ck['http']}');
        if (amt != null && amt < (catalogPrice * 100) * 0.5) {
          finding(
            id: 'SAT-P0-11',
            sev: 'P0',
            surface: 'offers + proposta + checkout',
            identity: 'buyer JWT',
            action: 'Oferta self-accepted 0.50€ → order → checkout',
            response: {'order': fr, 'checkout': ck['body'], 'amt': amt},
            impact: 'Composição: oferta forjada + selo proposta + Stripe barato.',
            confidence: 'alta',
          );
        }
      }
    } else {
      failClosed('offer_self_accept', {'http': off['http'], 'row': offRow});
    }

    stdout.writeln('== lives/stream keys ==');
    mark('lives_stream_keys', 'TESTED');
    final lives = await req(
      'GET',
      '$url/rest/v1/lives?select=id,seller_id,mux_stream_key,stream_key,mux_playback_id,status&limit=5',
      BH,
    );
    stdout.writeln('LIVES_SELECT http=${lives['http']} sample=${_clip(lives['body'])}');
    final hasKey = _anyKey(lives['body'], ['mux_stream_key', 'stream_key']);
    if (hasKey) {
      finding(
        id: 'SAT-P0-12',
        sev: 'P0',
        surface: 'lives SELECT stream keys',
        identity: 'buyer JWT',
        action: 'SELECT mux_stream_key/stream_key',
        response: {'sample': _clip(lives['body'])},
        impact: 'Stream key Mux leak — hijack de ingest / custo Mux.',
        confidence: 'alta',
      );
    } else {
      failClosed('stream_keys_hidden_or_null', {
        'http': lives['http'],
        'n': _len(lives['body']),
      });
    }
    mark('mux_create_authz', 'TESTED');
    final mux = await req(
      'POST',
      '$url/functions/v1/create-mux-live',
      h(buyerTok, prefer: false),
      body: {'title': 'Hostile live attempt SAT'},
    );
    stdout.writeln('MUX_BUYER http=${mux['http']} ${mux['body']}');
    if (mux['http'] == 200) {
      finding(
        id: 'SAT-P1-15',
        sev: 'P1',
        surface: 'create-mux-live',
        identity: 'buyer JWT',
        action: 'POST create-mux-live',
        response: mux['body'],
        impact: 'Comprador cria live Mux (custo / papel).',
        confidence: 'alta',
      );
    } else {
      failClosed('mux_buyer_forbidden', {'http': mux['http']});
    }

    stdout.writeln('== raffle tables ==');
    mark('raffles', 'TESTED');
    final rw = await req('POST', '$url/rest/v1/live_raffle_winners', BH, body: {
      'raffle_id': '00000000-0000-0000-0000-000000000001',
      'user_id': buyerId,
      'rank': 1,
    });
    stdout.writeln('RAFFLE_WINNER_INSERT http=${rw['http']} ${rw['body']}');
    if (rw['http'] == 201) {
      finding(
        id: 'SAT-P0-13',
        sev: 'P0',
        surface: 'live_raffle_winners INSERT',
        identity: 'buyer JWT',
        action: 'INSERT winner',
        response: rw['body'],
        impact: 'Comprador elege-se vencedor de rifa.',
        confidence: 'alta',
      );
    } else {
      failClosed('raffle_winner_insert', {'http': rw['http']});
    }

    stdout.writeln('== tips ==');
    mark('tips', 'TESTED');
    final tipIns = await req('POST', '$url/rest/v1/live_tips', BH, body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 1,
      'status': 'paid',
    });
    stdout.writeln('TIP_INSERT http=${tipIns['http']} ${tipIns['body']}');
    if (tipIns['http'] == 201) {
      finding(
        id: 'SAT-P1-16',
        sev: 'P1',
        surface: 'live_tips INSERT',
        identity: 'buyer JWT',
        action: 'INSERT tip already paid',
        response: tipIns['body'],
        impact: 'Tip pago forjado na tabela; settle pode creditar.',
        confidence: 'média',
      );
    } else {
      failClosed('tip_insert', {'http': tipIns['http']});
    }
    final tipCk = await req(
      'POST',
      '$url/functions/v1/create-live-tip-checkout',
      h(buyerTok, prefer: false),
      body: {
        'seller_id': sellerId,
        'amount_eur': 1,
        'live_id': '00000000-0000-0000-0000-000000000001',
      },
    );
    stdout.writeln('TIP_CHECKOUT http=${tipCk['http']} ${_clip(tipCk['body'])}');

    stdout.writeln('== storage ==');
    mark('storage', 'TESTED');
    final buckets = await req('GET', '$url/storage/v1/bucket', {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
    });
    stdout.writeln('BUCKETS http=${buckets['http']} ${_clip(buckets['body'])}');
    for (final b in ['chat_media', 'fleaber_private', 'product-images', 'products']) {
      final list = await req(
        'POST',
        '$url/storage/v1/object/list/$b',
        {
          'apikey': anon,
          'Authorization': 'Bearer $buyerTok',
          'Content-Type': 'application/json',
        },
        body: {'prefix': '', 'limit': 20},
      );
      stdout.writeln('STORAGE_LIST $b http=${list['http']} n=${_len(list['body'])}');
      if (list['http'] == 200 && _len(list['body']) > 0) {
        notes.add('storage_list_$b n=${_len(list['body'])}');
      }
    }
    final upCross = await req(
      'POST',
      '$url/storage/v1/object/chat_media/proofs/$sellerId/sat-aud-$stamp.txt',
      {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'text/plain',
        'x-upsert': 'true',
      },
      body: 'hostile-overwrite',
    );
    // body jsonEncode would break binary; redo with raw
    stdout.writeln('STORAGE_CROSS_ATTEMPT (json) http=${upCross['http']}');

    final upRaw = await http.post(
      Uri.parse('$url/storage/v1/object/chat_media/proofs/$sellerId/sat-aud-$stamp.txt'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'text/plain',
        'x-upsert': 'true',
      },
      body: 'hostile-overwrite',
    );
    stdout.writeln('STORAGE_CROSS_RAW http=${upRaw.statusCode} ${upRaw.body}');
    if (upRaw.statusCode == 200 || upRaw.statusCode == 201) {
      finding(
        id: 'SAT-P1-17',
        sev: 'P1',
        surface: 'storage chat_media',
        identity: 'buyer JWT',
        action: 'UPLOAD proofs/{sellerId}/...',
        response: {'http': upRaw.statusCode, 'body': upRaw.body},
        impact: 'Upload/overwrite no prefixo de outro utilizador (provas).',
        confidence: 'alta',
      );
    } else {
      failClosed('storage_cross_upload', {'http': upRaw.statusCode});
    }

    stdout.writeln('== reservations ==');
    mark('live_reservations', 'TESTED');
    final resv = await req('POST', '$url/rest/v1/live_reservation_requests', BH, body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'requested_qty': 99,
      'status': 'accepted',
      'source': 'fleaber_live',
    });
    stdout.writeln('RESV_INSERT http=${resv['http']} ${resv['body']}');
    if (resv['http'] == 201) {
      final rr = firstRow(resv['body']);
      finding(
        id: 'SAT-P2-12',
        sev: 'P2',
        surface: 'live_reservation_requests INSERT',
        identity: 'buyer JWT',
        action: 'INSERT accepted qty=99 sem live_item',
        response: rr ?? {},
        impact: 'Reserva aceite forjada; possível composição com checkout live.',
        confidence: 'média',
      );
    } else {
      failClosed('reservation_insert', {'http': resv['http']});
    }

    stdout.writeln('== edges misc ==');
    mark('refund_order_authz', 'TESTED');
    final refB = await req(
      'POST',
      '$url/functions/v1/refund-order',
      h(buyerTok, prefer: false),
      body: {'order_id': baseRow?['id']},
    );
    stdout.writeln('REFUND_BUYER http=${refB['http']} ${refB['body']}');
    if (refB['http'] == 200 && (refB['body'] is Map && (refB['body'] as Map)['ok'] == true) && (refB['body'] as Map)['skipped'] != true) {
      finding(
        id: 'SAT-P0-14',
        sev: 'P0',
        surface: 'refund-order',
        identity: 'buyer JWT',
        action: 'POST refund-order da própria compra',
        response: refB['body'],
        impact: 'Comprador dispara reembolso Stripe (função é seller-only).',
        confidence: 'alta',
      );
    } else {
      failClosed('refund_buyer', {'http': refB['http'], 'body': refB['body']});
    }
    mark('stripe_webhook', 'TESTED');
    final wh = await req(
      'POST',
      '$url/functions/v1/stripe-webhook',
      {'Content-Type': 'application/json', 'apikey': anon},
      body: {'type': 'checkout.session.completed', 'data': {}},
    );
    stdout.writeln('WEBHOOK_UNSIGNED http=${wh['http']} ${wh['body']}');
    if (wh['http'] == 200) {
      finding(
        id: 'SAT-P0-15',
        sev: 'P0',
        surface: 'stripe-webhook',
        identity: 'anon',
        action: 'POST sem assinatura',
        response: wh['body'],
        impact: 'Webhook Stripe sem verificação.',
        confidence: 'alta',
      );
    } else {
      failClosed('webhook_unsigned', {'http': wh['http']});
    }
    mark('crash_inject_unauth', 'TESTED');
    final crash = await req(
      'POST',
      '$url/functions/v1/refund-order',
      h(sellerTok, prefer: false),
      body: {
        'order_id': baseRow?['id'],
        'crash_inject': 'after_stripe_before_db',
      },
    );
    stdout.writeln('CRASH_NO_SECRET http=${crash['http']} ${crash['body']}');
    mark('ps_ocr', 'TESTED');
    final ocr = await req(
      'POST',
      '$url/functions/v1/ingest-ocr-reservation',
      {'apikey': anon, 'Authorization': 'Bearer $anon', 'Content-Type': 'application/json'},
      body: {
        'live_id': '00000000-0000-0000-0000-000000000001',
        'ocr_line_hash': 'abcdefghijkl',
        'detected_at': DateTime.now().toUtc().toIso8601String(),
        'device_id': 'sat-device-$stamp',
        'requested_qty': 1,
      },
    );
    stdout.writeln('OCR_NO_TOKEN http=${ocr['http']} ${ocr['body']}');
    if (ocr['http'] == 200 && ocr['body'] is Map && (ocr['body'] as Map)['ok'] == true) {
      finding(
        id: 'SAT-P1-18',
        sev: 'P1',
        surface: 'ingest-ocr-reservation',
        identity: 'anon',
        action: 'POST sem device token',
        response: ocr['body'],
        impact: 'Ingest OCR anónimo cria reservas.',
        confidence: 'alta',
      );
    } else {
      failClosed('ocr_no_token', {'http': ocr['http']});
    }
    final pair = await req(
      'POST',
      '$url/functions/v1/ps-pairing-claim',
      {'apikey': anon, 'Content-Type': 'application/json'},
      body: {'code': '000000', 'device_id': 'sat-$stamp'},
    );
    stdout.writeln('PS_PAIR http=${pair['http']} ${pair['body']}');
    mark('ps_pairing', 'TESTED');

    mark('create-connect-payout', 'TESTED');
    final po = await req(
      'POST',
      '$url/functions/v1/create-connect-account',
      h(buyerTok, prefer: false),
      body: {'user_id': sellerId, 'amount': 1, 'idempotency_key': 'sat-payout-$stamp'},
    );
    stdout.writeln('PAYOUT_CROSS http=${po['http']} ${_clip(po['body'])}');
    if (po['http'] == 200) {
      finding(
        id: 'SAT-P0-16',
        sev: 'P0',
        surface: 'create-connect-account',
        identity: 'buyer JWT',
        action: 'Payout com user_id do vendedor',
        response: _clip(po['body']),
        impact: 'Payout/onboarding cruzado.',
        confidence: 'média',
      );
    } else {
      failClosed('payout_cross_user', {'http': po['http']});
    }

    // Anon table probes
    stdout.writeln('== anon tables ==');
    mark('anon_rls', 'TESTED');
    for (final t in [
      'orders',
      'wallets',
      'wallet_transactions',
      'profiles',
      'chats',
      'chat_messages',
      'products',
      'lives',
      'live_items',
      'live_reservation_requests',
      'live_tips',
      'live_raffles',
      'live_raffle_winners',
      'reviews',
      'order_disputes',
    ]) {
      final r = await req('GET', '$url/rest/v1/$t?select=*&limit=3', ANON);
      stdout.writeln('ANON $t http=${r['http']} n=${_len(r['body'])}');
      if (r['http'] == 200 && _len(r['body']) > 0 && t != 'products' && t != 'reviews' && t != 'lives' && t != 'live_items') {
        finding(
          id: 'SAT-P1-ANON-$t',
          sev: t == 'orders' || t == 'wallets' || t == 'chats' ? 'P1' : 'P2',
          surface: 'RLS anon SELECT $t',
          identity: 'anon',
          action: 'GET $t',
          response: {'n': _len(r['body']), 'sample': _clip(r['body'])},
          impact: 'Tabela $t legível sem autenticação.',
          confidence: 'alta',
        );
      } else {
        failClosed('anon_$t', {'http': r['http'], 'n': _len(r['body'])});
      }
    }

    // Seller bundle discounts write as buyer
    mark('bundle_discounts', 'TESTED');
    final bd = await req(
      'POST',
      '$url/rest/v1/seller_bundle_discounts',
      BH,
      body: {
        'seller_id': sellerId,
        'enabled': true,
        'tier_2_pct': 50,
        'tier_3_pct': 50,
        'tier_5_pct': 50,
      },
    );
    stdout.writeln('BUNDLE_DISC_BUYER_WRITE http=${bd['http']} ${bd['body']}');
    if (bd['http'] == 201) {
      finding(
        id: 'SAT-P0-17',
        sev: 'P0',
        surface: 'seller_bundle_discounts',
        identity: 'buyer JWT',
        action: 'UPSERT 50% na loja alheia',
        response: bd['body'],
        impact: 'Comprador define descontos de conjunto do vendedor; checkout usa-os.',
        confidence: 'alta',
      );
    } else {
      failClosed('bundle_discount_foreign_write', {'http': bd['http']});
    }

    // disputes
    mark('disputes', 'TESTED');
    final disp = await req('POST', '$url/rest/v1/order_disputes', BH, body: {
      'order_id': baseRow?['id'],
      'buyer_id': buyerId,
      'reason': 'sat-aud',
      'status': 'aberta',
      'seller_refund_percent': 100,
    });
    stdout.writeln('DISPUTE_INSERT http=${disp['http']} ${disp['body']}');

    // realtime: skip (no socket in this harness) — note gap
    mark('realtime', 'NOT_TESTED_NO_SOCKET');
    mark('stripe_test_full_capture', 'PARTIAL_SESSION_ONLY');
    mark('payout_two_intents', 'NOT_TESTED_NO_CONNECT_FIXTURE');
    mark('mux_cost_rate', 'AUTHZ_ONLY_NO_CREATE');
    mark('livekit', 'NOT_TESTED');
    mark('director', 'NOT_TESTED');

    // Second pass: variants of blocked contract if first cheap worked
    stdout.writeln('== pass 2 variants ==');
    final v2 = await insertOrder(BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': fixtureProductId,
      'quantity': 1,
      'price_total': catalogPrice,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      'contract_unit_cents': 2,
    });
    stdout.writeln('V2_CUC2 ${firstRow(v2['body'])?['contract_unit_cents']}');

    // Seller price_total insert for buyer
    final sellerCheap = await insertOrder(SH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': fixtureProductId,
      'quantity': 1,
      'price_total': 0.01,
      'contract_unit_cents': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    final sc = firstRow(sellerCheap['body']);
    stdout.writeln('SELLER_CHEAP_INSERT $sc');
    if (sc != null && n(sc['contract_unit_cents']) == 1) {
      finding(
        id: 'SAT-P1-19',
        sev: 'P1',
        surface: 'orders INSERT seller JWT',
        identity: 'seller JWT',
        action: 'Vendedor cria order do comprador a 1 cêntimo',
        response: sc,
        impact:
            'Colusão/self-deal: vendedor sela contrato hostil na order do comprador (ou para si como buyer).',
        confidence: 'média',
        fp: 'Vendedor pode querer desconto; o problema é o campo contract_* cliente-controlado.',
      );
    }

    mark('orders', 'TESTED');
    mark('checkout', 'TESTED');
    mark('wallet', 'TESTED');
    mark('stock', 'PARTIAL');
    mark('auth', 'TESTED');
  } catch (err, st) {
    notes.add('harness_error: $err');
    stderr.writeln(err);
    stderr.writeln(st);
  } finally {
    stdout.writeln('== cleanup ==');
    await cleanup();
  }

  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'project': 'fxdknzrqjenzqcvnwqqq',
    'findings': findings,
    'blocked': blocked,
    'coverage': coverage,
    'notes': notes,
    'p0': findings.where((f) => f['sev'] == 'P0').map((f) => f['id']).toList(),
    'p1': findings.where((f) => f['sev'] == 'P1').map((f) => f['id']).toList(),
    'p2': findings.where((f) => f['sev'] == 'P2').map((f) => f['id']).toList(),
    'p3': findings.where((f) => f['sev'] == 'P3').map((f) => f['id']).toList(),
  };
  final file = File('tool/reports/SAT_BLIND_RAW_20260827.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('WROTE ${file.path}');
  stdout.writeln('FINDINGS ${findings.length} P0=${out['p0']} P1=${out['p1']}');
}

num n(Object? v) {
  if (v is num) return v;
  return num.tryParse('$v') ?? -1;
}

int _len(Object? b) {
  if (b is List) return b.length;
  return 0;
}

String _clip(Object? b, [int max = 400]) {
  final s = '$b';
  return s.length <= max ? s : s.substring(0, max);
}

bool _anyKey(Object? body, List<String> keys) {
  if (body is! List) return false;
  for (final row in body) {
    if (row is! Map) continue;
    for (final k in keys) {
      final v = row[k];
      if (v != null && '$v'.trim().isNotEmpty) return true;
    }
  }
  return false;
}

int? extractAmount(Object? body) {
  if (body is! Map) return null;
  for (final k in [
    'amount_total',
    'amount',
    'amount_cents',
    'stripe_amount_total',
    'total_cents',
  ]) {
    final v = body[k];
    if (v is num && v > 0) {
      return v > 10000 ? v.round() : (v < 1000 && v == v.roundToDouble() ? (v * (v < 50 ? 100 : 1)).round() : v.round());
    }
  }
  final nested = body['session'] ?? body['checkout'] ?? body['data'];
  if (nested is Map) {
    final a = nested['amount_total'] ?? nested['amount'];
    if (a is num) return a.round();
  }
  return null;
}
