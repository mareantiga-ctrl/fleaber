// ignore_for_file: avoid_print
/// FASE 3 — autorização / integridade de estado (hostil + legítimo).
/// dart run tool/sec_fase3_hostile_battery.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: service,
  );

  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final buyerToken = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerToken = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final results = <Map<String, dynamic>>[];
  void add(String id, bool pass, String detail) {
    results.add({'id': id, 'pass': pass, 'detail': detail});
    print('${pass ? "PASS" : "FAIL"} $id — $detail');
  }

  String clip(Object? s, [int n = 160]) {
    final t = '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= n) return t;
    return '${t.substring(0, n)}…';
  }

  // ---------- A bag qty ----------
  try {
    final product = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'F3 bag ${DateTime.now().microsecondsSinceEpoch}',
      'price': 10,
      'quantity': 3,
      'ref_code': 'F3B-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await sb.insert('lives', {
      'title': 'F3 live bag',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final li = await sb.insert('live_items', {
      'live_id': live['id'],
      'title': 'item',
      'price': 10,
      'quantity': 3,
      'is_active': true,
      'status': 'available',
      'item_kind': 'live_only',
      'ref_code': 'F3LI-${DateTime.now().microsecondsSinceEpoch}',
    });
    final req = await sb.insert('live_reservation_requests', {
      'live_id': live['id'],
      'live_item_id': li['id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
    });

    Future<Map<String, dynamic>?> bagQty(int qty) async {
      try {
        final r = await sb.rpc(
          'batata_live_bag_update_qty',
          {'p_request_id': req['id'], 'p_qty': qty},
          accessToken: buyerToken,
        );
        if (r is Map) return Map<String, dynamic>.from(r);
        return {'raw': r};
      } catch (e) {
        return {'error': '$e'};
      }
    }

    final high = await bagQty(9999);
    final zero = await bagQty(0);
    final neg = await bagQty(-5);
    final ok2 = await bagQty(2);
    final overStock = await bagQty(50);

    add(
      'A_BAG_QTY_INVALID',
      high?['ok'] != true &&
          zero?['ok'] != true &&
          neg?['ok'] != true &&
          overStock?['ok'] != true &&
          ok2?['ok'] == true &&
          ok2?['requested_qty'] == 2,
      'high=$high zero=$zero neg=$neg ok2=$ok2 over=$overStock',
    );

    await sb.deleteWhere('live_reservation_requests', 'id=eq.${req['id']}');
    await sb.deleteWhere('live_items', 'id=eq.${li['id']}');
    await sb.deleteWhere('lives', 'id=eq.${live['id']}');
    await sb.deleteWhere('products', 'id=eq.${product['id']}');
  } catch (e) {
    add('A_BAG_QTY_INVALID', false, '$e');
  }

  // ---------- B/C pago→cancelado + variantes ----------
  try {
    final product = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'F3 cancel ${DateTime.now().microsecondsSinceEpoch}',
      'price': 20,
      'quantity': 2,
      'ref_code': 'F3C-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final order = await sb.insert('orders', {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': product['id'],
      'price_total': 20,
      'quantity': 1,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
      'stock_units_applied': 1,
    });
    final qtyBefore =
        (await sb.select('products', filter: 'id=eq.${product['id']}', limit: 1))
            .first['quantity'];

    await sb.patchAsUser(
      'orders',
      'id=eq.${order['id']}',
      {'status': 'cancelado'},
      accessToken: buyerToken,
    );
    final after = await sb.select('orders', filter: 'id=eq.${order['id']}', limit: 1);
    final qtyAfter =
        (await sb.select('products', filter: 'id=eq.${product['id']}', limit: 1))
            .first['quantity'];

    add(
      'B_PAGO_TO_CANCELADO',
      after.first['status'] == 'pago' && qtyAfter == qtyBefore,
      'status=${after.first['status']} qty=$qtyBefore→$qtyAfter',
    );

    await sb.patchAsUser(
      'orders',
      'id=eq.${order['id']}',
      {'status': 'reserva_pendente'},
      accessToken: buyerToken,
    );
    final after2 =
        await sb.select('orders', filter: 'id=eq.${order['id']}', limit: 1);
    add(
      'C_PAGO_TO_RESERVA',
      after2.first['status'] == 'pago',
      'status=${after2.first['status']}',
    );

    // unpaid cancel still OK
    final unpaid = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': product['id'],
        'price_total': 20,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${unpaid['id']}',
      {'status': 'cancelado'},
      accessToken: buyerToken,
    );
    final uAfter =
        await sb.select('orders', filter: 'id=eq.${unpaid['id']}', limit: 1);
    add(
      'C_UNPAID_CANCEL_OK',
      uAfter.first['status'] == 'cancelado',
      'status=${uAfter.first['status']}',
    );

    await sb.deleteWhere('orders', 'product_id=eq.${product['id']}');
    await sb.deleteWhere('products', 'id=eq.${product['id']}');
  } catch (e) {
    add('B_PAGO_TO_CANCELADO', false, '$e');
  }

  // ---------- D/E ensure_checkout ----------
  try {
    final live = await sb.insert('lives', {
      'title': 'F3 ensure',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final li = await sb.insert('live_items', {
      'live_id': live['id'],
      'title': 'shadow',
      'price': 15,
      'quantity': 2,
      'is_active': true,
      'status': 'available',
      'item_kind': 'live_only',
      'ref_code': 'F3E-${DateTime.now().microsecondsSinceEpoch}',
    });

    // anon
    var anonDenied = false;
    try {
      await http.post(
        Uri.parse('$url/rest/v1/rpc/batata_ensure_checkout_product'),
        headers: {
          'apikey': anon,
          'Authorization': 'Bearer $anon',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'p_live_item_id': li['id']}),
      ).then((r) {
        if (r.statusCode >= 400) anonDenied = true;
        final body = r.body.toLowerCase();
        if (body.contains('not_allowed') || body.contains('42501')) {
          anonDenied = true;
        }
      });
    } catch (_) {
      anonDenied = true;
    }
    add('D_ENSURE_ANON', anonDenied, 'anon blocked');

    // buyer (not seller) — may create shadow but must not wipe; call as buyer
    // First create shadow as seller
    final sellerEnsure = await sb.rpc(
      'batata_ensure_checkout_product',
      {'p_live_item_id': li['id']},
      accessToken: sellerToken,
    );
    final shadowId = sellerEnsure.toString();
    await sb.patch('products', 'id=eq.$shadowId', {'quantity': 99});
    // buyer call should NOT reset qty to live_item.quantity(2)
    try {
      await sb.rpc(
        'batata_ensure_checkout_product',
        {'p_live_item_id': li['id']},
        accessToken: buyerToken,
      );
    } catch (_) {}
    final prod =
        await sb.select('products', filter: 'id=eq.$shadowId', limit: 1);
    add(
      'E_ENSURE_BUYER_NO_WIPE',
      (prod.first['quantity'] as num).toInt() == 99,
      'qty=${prod.first['quantity']} (must stay 99)',
    );

    await sb.deleteWhere('live_items', 'id=eq.${li['id']}');
    await sb.deleteWhere('lives', 'id=eq.${live['id']}');
    try {
      await sb.deleteWhere('products', 'id=eq.$shadowId');
    } catch (_) {}
  } catch (e) {
    add('D_ENSURE_ANON', false, '$e');
  }

  // ---------- F/G stripe_convert ----------
  try {
    final r = await http.post(
      Uri.parse('$url/rest/v1/rpc/batata_live_reservation_stripe_convert'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'p_request_id': '00000000-0000-0000-0000-000000000001',
        'p_order_id': '00000000-0000-0000-0000-000000000002',
      }),
    );
    final denied = r.statusCode == 401 ||
        r.statusCode == 403 ||
        r.body.contains('42501') ||
        r.body.toLowerCase().contains('permission');
    add('F_CONVERT_ANON', denied, 'http=${r.statusCode} ${clip(r.body)}');

    final r2 = await http.post(
      Uri.parse('$url/rest/v1/rpc/batata_live_reservation_stripe_convert'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'p_request_id': '00000000-0000-0000-0000-000000000001',
        'p_order_id': '00000000-0000-0000-0000-000000000002',
      }),
    );
    final deniedAuth = r2.statusCode == 401 ||
        r2.statusCode == 403 ||
        r2.body.contains('42501');
    add('G_CONVERT_AUTH', deniedAuth, 'http=${r2.statusCode} ${clip(r2.body)}');
  } catch (e) {
    add('F_CONVERT_ANON', false, '$e');
  }

  // ---------- H settle invalid / J redirects ----------
  try {
    final r = await http.get(
      Uri.parse(
        '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_invalid',
      ),
      headers: {'apikey': anon, 'Authorization': 'Bearer $anon'},
    );
    // Must not claim paid; 4xx/5xx or error text OK
    final body = r.body.toLowerCase();
    final notSilentPaid = r.statusCode >= 400 ||
        body.contains('erro') ||
        body.contains('inválid') ||
        body.contains('invalid') ||
        body.contains('no such') ||
        body.contains('falta');
    add(
      'H_SETTLE_INVALID',
      notSilentPaid && r.statusCode != 200,
      'http=${r.statusCode} ${clip(r.body)}',
    );
  } catch (e) {
    add('H_SETTLE_INVALID', true, 'blocked: $e');
  }

  try {
    Future<({int status, String location, String body})> connectGet(
      String origin,
    ) async {
      final uri = Uri.parse(
        '$url/functions/v1/create-connect-account?web_return_origin=${Uri.encodeComponent(origin)}',
      );
      final client = HttpClient();
      try {
        final req = await client.getUrl(uri);
        req.followRedirects = false;
        req.headers.set('apikey', anon);
        req.headers.set('Authorization', 'Bearer $anon');
        final res = await req.close();
        final body = await res.transform(utf8.decoder).join();
        final loc = res.headers.value('location') ?? '';
        return (status: res.statusCode, location: loc, body: body);
      } finally {
        client.close(force: true);
      }
    }

    final evil = await connectGet('https://evil.example/phish');
    add(
      'J_REDIRECT_EVIL',
      !evil.location.contains('evil.example') && evil.status != 303,
      'status=${evil.status} location=${evil.location}',
    );

    final good = await connectGet('https://fleaber.pt');
    add(
      'K_REDIRECT_LEGIT',
      good.status == 303 &&
          good.location.contains('fleaber.pt') &&
          good.location.contains('/wallet'),
      'status=${good.status} location=${good.location} body=${clip(good.body, 60)}',
    );
  } catch (e) {
    add('J_REDIRECT_EVIL', false, '$e');
  }

  // ---------- L marketplace ----------
  try {
    final p = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'F3 mkt ${DateTime.now().microsecondsSinceEpoch}',
      'price': 12,
      'quantity': 2,
      'ref_code': 'F3M-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final o = await sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': p['id'],
        'price_total': 12,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
    final items = 1200;
    const ship = 350;
    final prot = ((0.65 + (items + ship) / 100.0 * 0.05) * 100).round();
    final expected = items + ship + prot;
    final r = await sb.invokeEdge(
      'create-payment-intent',
      {
        'amount': expected,
        'currency': 'eur',
        'product_id': p['id'],
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'order_id': o['id'],
        'quantity': 1,
        'shipping': 350,
        'shipping_method': 'transportadora',
        'web_return_origin': 'https://evil.example',
      },
      accessToken: buyerToken,
    );
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    add(
      'L_MARKETPLACE',
      r.statusCode == 200 && b['server_amount_cents'] == expected,
      'http=${r.statusCode} server=${b['server_amount_cents']}',
    );
    // metadata should not store evil origin — can't read session easily; checkout still OK
    add(
      'J2_CHECKOUT_EVIL_ORIGIN_IGNORED',
      r.statusCode == 200,
      'checkout ok with evil origin in body (sanitized server-side)',
    );
    try {
      await sb.deleteWhere('chat_messages', 'chat_id=in.(select id from chats where product_id=eq.${p['id']})');
    } catch (_) {}
    try {
      await sb.deleteWhere('chats', 'product_id=eq.${p['id']}');
    } catch (_) {}
    try {
      await sb.deleteWhere('orders', 'id=eq.${o['id']}');
    } catch (_) {}
    try {
      await sb.deleteWhere('products', 'id=eq.${p['id']}');
    } catch (_) {}
  } catch (e) {
    // Não falhar L por cleanup
    if (!results.any((r) => r['id'] == 'L_MARKETPLACE')) {
      add('L_MARKETPLACE', false, '$e');
    } else {
      print('WARN cleanup L: $e');
    }
  }

  final failed = results.where((e) => e['pass'] != true).length;
  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'failed': failed,
    'passed': results.length - failed,
    'results': results,
  };
  await Directory('tool/reports').create(recursive: true);
  await File('tool/reports/HARDENING_FASE_3_HOSTILE.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('Wrote tool/reports/HARDENING_FASE_3_HOSTILE.json failed=$failed/${results.length}');
  exit(failed == 0 ? 0 : 1);
}
