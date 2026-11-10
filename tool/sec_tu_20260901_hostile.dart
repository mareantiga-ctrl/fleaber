// ignore_for_file: avoid_print
/// T/U/Q clears — dart run tool/sec_tu_20260901_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'POST'
      ? await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
          : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  if (body is Map && body['id'] != null) {
    final s = '${body['id']}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

Map<String, dynamic>? firstMap(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

String? orderIdFromE2E(dynamic body) {
  if (body is Map) {
    final m = Map<String, dynamic>.from(body);
    final direct = '${m['order_id'] ?? ''}'.trim();
    if (direct.isNotEmpty && direct != 'null') return direct;
    final nested = m['order'];
    if (nested is Map) {
      final oid = '${nested['id'] ?? ''}'.trim();
      if (oid.isNotEmpty && oid != 'null') return oid;
    }
  }
  return idOf(body);
}

bool denied(Map<String, dynamic> r, [String? needle]) {
  final http = r['http'] as int? ?? 0;
  final text = '${r['text'] ?? r['body'] ?? ''}'.toLowerCase();
  if (needle != null && text.contains(needle.toLowerCase())) return true;
  return http == 403 || http == 409 || http == 400 || text.contains('42501');
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: not staging');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  Map<String, String> jwt(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = jwt(buyerTok);
  final SH = jwt(sellerTok);
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (crashSecret.length >= 16) 'x-fleaber-e2e-secret': crashSecret,
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
    'Accept': 'application/json',
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  // Fechar leftover hostis anteriores (não deixar directo aberto).
  await req(
    'PATCH',
    '$url/rest/v1/lives?title=eq.TU-hostile-live&is_active=eq.true',
    SVC,
    {'status': 'ended', 'is_active': false},
  );
  await req(
    'PATCH',
    '$url/rest/v1/lives?title=eq.TU-hostile-live-b&is_active=eq.true',
    SVC,
    {'status': 'ended', 'is_active': false},
  );

  // ----- P0: parcial em pedido_devolucao -----
  final paid = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
      'shipping_method': 'mao',
    },
  );
  final oid = orderIdFromE2E(paid['body']);
  add('fixture_paid', oid != null && oid.isNotEmpty, {
    'oid': oid,
    'http': paid['http'],
  });

  if (oid != null && oid.isNotEmpty) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SVC, {
      'shipping_method': 'mao',
      'payment_method': 'pagamento na app',
    });
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'status': 'enviado'});
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'entregue'});
    final st1 = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=id,status,shipping_method,payment_method',
      SVC,
    );
    stdout.writeln('DEBUG order $oid → ${st1['body']}');
    final dispIns = await req('POST', '$url/rest/v1/order_disputes', BH, {
      'order_id': oid,
      'buyer_id': buyerId,
      'reason': 'danificado',
      'description': 'TU hostile P0',
      'proof_photos': <String>[],
      'status': 'aberta',
      'current_turn': 'vendedor',
    });
    stdout.writeln('DEBUG dispute insert → ${dispIns['http']} ${dispIns['body']}');
    await req('PATCH', '$url/rest/v1/order_disputes?order_id=eq.$oid', SH, {
      'seller_refund_percent': 40,
      'seller_offer_type': 'partial_refund',
      'status': 'respondida_vendedor',
    });
    await req('PATCH', '$url/rest/v1/order_disputes?order_id=eq.$oid', SVC, {
      'seller_refund_percent': 40,
      'seller_offer_type': 'partial_refund',
      'seller_offer_set_by': sellerId,
      'status': 'respondida_vendedor',
    });
    final offerRow = await req(
      'GET',
      '$url/rest/v1/order_disputes?order_id=eq.$oid&select=id,status,seller_refund_percent,seller_offer_type,seller_offer_set_by',
      SVC,
    );
    stdout.writeln('DEBUG dispute $oid → ${offerRow['body']}');
    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid',
      BH,
      {'status': 'pedido_devolucao'},
    );
    final partial = await req(
      'POST',
      '$url/rest/v1/rpc/batata_process_partial_refund_dispute',
      BH,
      {'p_order_id': oid},
    );
    add(
      'P0_partial_pedido_devolucao_blocked',
      denied(partial, 'dispute_partial_refund_requires_stripe'),
      {'http': partial['http'], 'body': partial['body']},
    );

    // P1: seller forge buyer_decision + resolvida
    final forge = await req(
      'PATCH',
      '$url/rest/v1/order_disputes?order_id=eq.$oid',
      SH,
      {
        'buyer_decision': 'accepted_partial_refund',
        'status': 'resolvida',
      },
    );
    final forgeRow = firstMap(forge['body']);
    final forgeSt = '${forgeRow?['status'] ?? ''}'.toLowerCase();
    add(
      'P1_seller_forge_resolvida_blocked',
      forgeSt != 'resolvida' &&
          (forge['http'] == 200 || denied(forge)),
      {'http': forge['http'], 'status': forgeSt, 'body': forge['body']},
    );

    // P1: seller recusada unilateral — nova disputa noutro order
    final paid2 = await req(
      'POST',
      '$url/functions/v1/sec-fase2-e2e-oversell',
      E2E,
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'probe': 'setup_paid_order',
        'initial_qty': 2,
        'shipping_method': 'mao',
      },
    );
    final oid2 = orderIdFromE2E(paid2['body']);
    if (oid2 != null && oid2.isNotEmpty) {
      await req('PATCH', '$url/rest/v1/orders?id=eq.$oid2', SVC, {
        'shipping_method': 'mao',
        'payment_method': 'pagamento na app',
      });
      await req('PATCH', '$url/rest/v1/orders?id=eq.$oid2', SH, {'status': 'enviado'});
      await req('PATCH', '$url/rest/v1/orders?id=eq.$oid2', BH, {'status': 'entregue'});
      await req('POST', '$url/rest/v1/order_disputes', BH, {
        'order_id': oid2,
        'buyer_id': buyerId,
        'reason': 'danificado',
        'description': 'TU hostile recusada',
        'proof_photos': <String>[],
        'status': 'aberta',
        'current_turn': 'vendedor',
      });
      await req(
        'PATCH',
        '$url/rest/v1/order_disputes?order_id=eq.$oid2',
        SH,
        {'status': 'recusada'},
      );
      final recGet = await req(
        'GET',
        '$url/rest/v1/order_disputes?order_id=eq.$oid2&select=status',
        SVC,
      );
      final recRow = firstMap(recGet['body']);
      final recSt = '${recRow?['status'] ?? ''}'.toLowerCase();
      add(
        'P1_seller_recusada_blocked',
        recSt.isNotEmpty && recSt != 'recusada',
        {'status': recSt},
      );
    } else {
      add('P1_seller_recusada_blocked', false, {'fixture': paid2['body']});
    }
  }

  // ----- P2 URLs -----
  if (oid != null && oid.isNotEmpty) {
    final evilQ = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
      'proof_url': 'https://fleaber.app/l?next=https://evil.test/steal',
    });
    add(
      'P2_proof_query_wrap_blocked',
      denied(evilQ, 'order_proof_url_denied'),
      {'http': evilQ['http']},
    );
    final evilSb = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {
      'proof_url':
          'https://abcdefghijklmnop.supabase.co/storage/v1/object/public/x.jpg',
    });
    add(
      'P2_proof_other_supabase_blocked',
      denied(evilSb, 'order_proof_url_denied'),
      {'http': evilSb['http']},
    );
  }

  // ----- P1 convert fleaber_live sem pagar -----
  final liveIns = await req('POST', '$url/rest/v1/lives', SVC, {
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'title': 'TU-hostile-live',
    'status': 'live',
    'is_active': true,
    'viewer_count': 1,
  });
  final liveId = idOf(liveIns['body']);
  add('fixture_live', liveId != null, {
    'http': liveIns['http'],
    'body': liveIns['body'],
  });
  String? itemId;
  if (liveId != null) {
    final prod = await req('POST', '$url/rest/v1/products', SVC, {
      'seller_id': sellerId,
      'title': 'TU-hostile-sku',
      'price': 12,
      'quantity': 3,
      'list_on_marketplace': true,
      'is_sold': false,
    });
    final pid = idOf(prod['body']);
    final item = await req('POST', '$url/rest/v1/live_items', SVC, {
      'live_id': liveId,
      'title': 'TU-hostile-item',
      'quantity': 2,
      'price': 12,
      'status': 'available',
      'is_active': true,
      'ref_code': 'TUHOST1',
      'item_kind': 'live_only',
    });
    itemId = idOf(item['body']);
    add('fixture_live_item', itemId != null, {
      'http': item['http'],
      'body': item['body'],
    });
    if (itemId != null) {
      final res = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
        'live_id': liveId,
        'live_item_id': itemId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'requested_qty': 1,
        'status': 'pending',
        'source': 'fleaber_live',
      });
      final rid = idOf(res['body']);
      add('fixture_reservation', rid != null, {
        'http': res['http'],
        'body': res['body'],
      });
      if (rid != null) {
        await req(
          'POST',
          '$url/rest/v1/rpc/batata_process_live_reservation_request',
          SH,
          {'p_request_id': rid, 'p_action': 'accept'},
        );
        final conv = await req(
          'POST',
          '$url/rest/v1/rpc/batata_process_live_reservation_request',
          SH,
          {'p_request_id': rid, 'p_action': 'convert'},
        );
        final cbody = '${conv['body'] ?? conv['text']}'.toLowerCase();
        add(
          'P1_convert_fleaber_live_requires_paid',
          cbody.contains('convert_requires_paid_order') ||
              cbody.contains('ok":false'),
          {'http': conv['http'], 'body': conv['body']},
        );

        final liveB = await req('POST', '$url/rest/v1/lives', SVC, {
          'seller_id': sellerId,
          'vendedor_id': sellerId,
          'title': 'TU-hostile-live-b',
          'status': 'live',
          'is_active': true,
        });
        final liveBId = idOf(liveB['body']);
        final move = await req(
          'PATCH',
          '$url/rest/v1/live_items?id=eq.$itemId',
          SH,
          {'live_id': liveBId},
        );
        add(
          'P1_live_item_move_blocked',
          denied(move, 'live_item_live_id_immutable') ||
              denied(move, 'live_item_not_authorized'),
          {'http': move['http'], 'text': move['text']},
        );
        if (liveBId != null) {
          await req('PATCH', '$url/rest/v1/lives?id=eq.$liveBId', SVC, {
            'status': 'ended',
            'is_active': false,
          });
        }
      }
    }
  }

  // ----- P2 Hub qty=0 -----
  final ghost = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'TU-hostile-ghost-qty0',
    'price': 9,
    'quantity': 0,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final gid = idOf(ghost['body']);
  if (gid != null) {
    final hub = await req(
      'GET',
      '$url/rest/v1/hub_products_public?id=eq.$gid&select=id',
      BH,
    );
    final hubN = hub['body'] is List ? (hub['body'] as List).length : -1;
    add('P2_hub_qty0_hidden', hubN == 0, {'http': hub['http'], 'n': hubN});
  } else {
    add('P2_hub_qty0_hidden', false, ghost['body']);
  }

  // ----- P2 bundle unlist -----
  final pA = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'TU-bundle-a',
    'price': 20,
    'quantity': 2,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final pB = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'TU-bundle-b',
    'price': 20,
    'quantity': 2,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final idA = idOf(pA['body']);
  final idB = idOf(pB['body']);
  if (idA != null && idB != null) {
    final bun = await req('POST', '$url/rest/v1/product_bundles', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_ids': [idA, idB],
      'status': 'pending',
    });
    final bunId = idOf(bun['body']);
    final unlist = await req(
      'PATCH',
      '$url/rest/v1/products?id=eq.$idA',
      SH,
      {'list_on_marketplace': false},
    );
    add(
      'P2_unlist_active_bundle_blocked',
      denied(unlist, 'product_in_active_bundle'),
      {'http': unlist['http'], 'bundle': bunId, 'text': unlist['text']},
    );
  } else {
    add('P2_unlist_active_bundle_blocked', false, 'sku fixture failed');
  }

  // ----- P2 OCR: buyer denied; lab seller (tem loja) ok -----
  final buyerOcr = await req(
    'POST',
    '$url/rest/v1/rpc/batata_create_seller_device_token',
    BH,
    {'p_device_id': 'tu-hostile-buyer-ocr'},
  );
  final bOcr = buyerOcr['body'];
  add(
    'P2_ocr_buyer_denied',
    bOcr is Map && (bOcr['ok'] == false || bOcr['error'] == 'not_seller'),
    buyerOcr['body'],
  );
  final sellerOcr = await req(
    'POST',
    '$url/rest/v1/rpc/batata_create_seller_device_token',
    SH,
    {'p_device_id': 'tu-hostile-seller-ocr'},
  );
  final sOcr = sellerOcr['body'];
  add(
    'P2_ocr_seller_with_shop_ok',
    sOcr is Map && sOcr['ok'] == true,
    {'ok': sOcr is Map ? sOcr['ok'] : null},
  );

  // cleanup lives
  if (liveId != null) {
    await req('PATCH', '$url/rest/v1/lives?id=eq.$liveId', SVC, {
      'status': 'ended',
      'is_active': false,
    });
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final path =
      'tool/reports/sec_tu_20260901_hostile_${DateTime.now().millisecondsSinceEpoch}.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert({
    'tag': 'sec_tu_20260901',
    'pass': results.length - failed,
    'fail': failed,
    'results': results,
  }));
  stdout.writeln('\n$failed FAIL / ${results.length} → $path');
  exit(failed == 0 ? 0 : 1);
}
