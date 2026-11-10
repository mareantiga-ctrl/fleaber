// ignore_for_file: avoid_print
/// Seed Phase 5.2 scenarios G / L / M / N1 / N2 for real TCL evidence.
///
///   dart run tool/phase5_2_seed_scenario.dart g|l|m|n1|n2
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final scenario = (args.isEmpty ? '' : args.first).trim().toLowerCase();
  if (!const {'g', 'l', 'm', 'n1', 'n2'}.contains(scenario)) {
    stderr.writeln('usage: dart run tool/phase5_2_seed_scenario.dart g|l|m|n1|n2');
    exit(2);
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final sellerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerId = await client.userIdForAccessToken(sellerToken);
  final buyerId = await client.userIdForAccessToken(buyerToken);

  // Secondary buyer for L/M (trust promote target ≠ stock consumer)
  final buyerBEmail =
      'p52.b.${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
  const buyerBPassword = 'P52BuyerB!staging';
  final buyerBId = await client.createAdminUser(
    email: buyerBEmail,
    password: buyerBPassword,
  );
  try {
    await client.insert('profiles', {
      'id': buyerBId,
      'display_name': 'P52 Buyer B',
    });
  } catch (_) {}
  final buyerBToken =
      await client.signIn(email: buyerBEmail, password: buyerBPassword);

  final tag =
      'p52_${scenario}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999)}';

  Future<void> upsertPolicy({String untrustedMode = 'approval'}) async {
    final existing = await client.select(
      'seller_reservation_settings',
      filter: 'seller_id=eq.$sellerId',
      limit: 1,
    );
    final payload = {
      'policy_mode': 'trust',
      'untrusted_mode': untrustedMode,
      'normal_ttl_seconds': 3600,
      'trusted_ttl_seconds': 86400,
      'accept_fleaber_global_trust': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (existing.isEmpty) {
      await client.insert('seller_reservation_settings', {
        'seller_id': sellerId,
        ...payload,
        'configured_at': DateTime.now().toUtc().toIso8601String(),
      });
    } else {
      await client.patch(
        'seller_reservation_settings',
        'seller_id=eq.$sellerId',
        payload,
      );
    }
  }

  Future<void> setTrust(String mode, {required String buyer}) async {
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyer, 'p_mode': mode},
      accessToken: sellerToken,
    );
  }

  Future<Map<String, String>> seedLive({
    required String suffix,
    required int qty,
  }) async {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'P52 $tag-$suffix',
      'price': 11,
      'quantity': qty,
      'ref_code': 'P52-$tag-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'P52_${tag}_$suffix',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'P52-$tag-$suffix',
      'title': 'P52 $suffix',
      'price': 11,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': product['id'],
      'checkout_product_id': product['id'],
      'quantity': null,
    });
    return {
      'productId': product['id']!.toString(),
      'liveId': live['id']!.toString(),
      'itemId': item['id']!.toString(),
      'ref': 'P52-$tag-$suffix',
    };
  }

  Future<Map<String, dynamic>> reserve({
    required Map<String, String> s,
    required String token,
    required String buyer,
  }) async {
    return await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyer,
        'p_live_id': s['liveId'],
        'p_live_item_id': s['itemId'],
        'p_qty': 1,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: token,
    ) as Map<String, dynamic>;
  }

  Future<int> avail(String itemId) async {
    final snap = await client.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': itemId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    return (snap['available_qty'] as num?)?.toInt() ?? -1;
  }

  Future<Map<String, dynamic>?> lrr(String? id) async {
    if (id == null || id.isEmpty) return null;
    final rows = await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$id',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  await upsertPolicy();

  late Map<String, dynamic> out;

  if (scenario == 'g') {
    await setTrust('distrusted', buyer: buyerId);
    final s = await seedLive(suffix: 'G', qty: 5);
    final r = await reserve(s: s, token: buyerToken, buyer: buyerId);
    final id = r['request_id']?.toString();
    out = {
      'scenario': 'G',
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'buyer_email': envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      'live_id': s['liveId'],
      'item_id': s['itemId'],
      'product_id': s['productId'],
      'ref': s['ref'],
      'request_id': id,
      'reserve_rpc': r,
      'row_before': await lrr(id),
      'available_qty_before': await avail(s['itemId']!),
      'hint': 'Studio → Pendentes → Rejeitar on Pediu row',
    };
  } else if (scenario == 'l') {
    // Buyer B pending (untrusted), stock available for promote.
    await setTrust('clear', buyer: buyerBId);
    await setTrust('distrusted', buyer: buyerBId);
    final s = await seedLive(suffix: 'L', qty: 3);
    final r = await reserve(s: s, token: buyerBToken, buyer: buyerBId);
    final id = r['request_id']?.toString();
    out = {
      'scenario': 'L',
      'seller_id': sellerId,
      'buyer_id': buyerBId,
      'buyer_email': buyerBEmail,
      'buyer_password': buyerBPassword,
      'live_id': s['liveId'],
      'item_id': s['itemId'],
      'product_id': s['productId'],
      'ref': s['ref'],
      'request_id': id,
      'reserve_rpc': r,
      'row_before': await lrr(id),
      'available_qty_before': await avail(s['itemId']!),
      'trust_before': await client.select(
        'seller_buyer_trust',
        filter: 'seller_id=eq.$sellerId&buyer_id=eq.$buyerBId',
        limit: 1,
      ),
      'hint': 'Studio → open 1 reservas on active item → Confiar',
    };
  } else if (scenario == 'm') {
    // Buyer B approval_pending stays open; stock driven to 0 without
    // auto-closing B (consume only part of inventory, then zero product qty).
    await setTrust('clear', buyer: buyerBId);
    await setTrust('distrusted', buyer: buyerBId);
    final s = await seedLive(suffix: 'M', qty: 2);
    final rPending =
        await reserve(s: s, token: buyerBToken, buyer: buyerBId);
    final idPending = rPending['request_id']?.toString();
    await setTrust('trusted', buyer: buyerId);
    final rConsume =
        await reserve(s: s, token: buyerToken, buyer: buyerId);
    final idConsume = rConsume['request_id']?.toString();
    // Leave B pending; remove remaining free units at product level.
    await client.patch(
      'products',
      'id=eq.${s['productId']}',
      {'quantity': 1}, // only the guaranteed unit remains as on-hand
    );
    var pendingAfterStock = await lrr(idPending);
    var available = await avail(s['itemId']!);
    // If still free units, force zero free stock for promote check.
    if (available > 0) {
      await client.patch(
        'products',
        'id=eq.${s['productId']}',
        {'quantity': 1},
      );
      available = await avail(s['itemId']!);
    }
    out = {
      'scenario': 'M',
      'seller_id': sellerId,
      'buyer_id': buyerBId,
      'buyer_email': buyerBEmail,
      'buyer_password': buyerBPassword,
      'consumer_buyer_id': buyerId,
      'live_id': s['liveId'],
      'item_id': s['itemId'],
      'product_id': s['productId'],
      'ref': s['ref'],
      'pending_request_id': idPending,
      'consume_request_id': idConsume,
      'pending_row_before': pendingAfterStock,
      'consume_row': await lrr(idConsume),
      'available_qty_before': available,
      'trust_before': await client.select(
        'seller_buyer_trust',
        filter: 'seller_id=eq.$sellerId&buyer_id=eq.$buyerBId',
        limit: 1,
      ),
      'hint':
          'Studio → reservas sheet for pending buyer B → Confiar; expect trust OK, no promote',
    };
  } else if (scenario == 'n1') {
    await setTrust('trusted', buyer: buyerId);
    final s = await seedLive(suffix: 'N1', qty: 2);
    final before = await avail(s['itemId']!);
    final r = await reserve(s: s, token: buyerToken, buyer: buyerId);
    final id = r['request_id']?.toString();
    out = {
      'scenario': 'N1',
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'buyer_email': envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      'buyer_password': envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
      'live_id': s['liveId'],
      'item_id': s['itemId'],
      'product_id': s['productId'],
      'ref': s['ref'],
      'request_id': id,
      'reserve_rpc': r,
      'row_before': await lrr(id),
      'available_qty_before_reserve': before,
      'available_qty_after_reserve': await avail(s['itemId']!),
      'hint':
          'Seller shot before; buyer Cancelar reserva in bag; seller shot after',
    };
  } else {
    // n2
    await setTrust('trusted', buyer: buyerId);
    final s = await seedLive(suffix: 'N2', qty: 2);
    final before = await avail(s['itemId']!);
    final r = await reserve(s: s, token: buyerToken, buyer: buyerId);
    final id = r['request_id']?.toString();
    out = {
      'scenario': 'N2',
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'live_id': s['liveId'],
      'item_id': s['itemId'],
      'product_id': s['productId'],
      'ref': s['ref'],
      'request_id': id,
      'reserve_rpc': r,
      'row_before': await lrr(id),
      'available_qty_before_reserve': before,
      'available_qty_after_reserve': await avail(s['itemId']!),
      'hint':
          'Seller shot before; patch expires_at past + batata_expire_guaranteed_reservations; seller after',
    };
  }

  final dir = Directory(
    '14-unified-commerce-phase5.2-final-evidence/raw',
  );
  await dir.create(recursive: true);
  final f = File('${dir.path}/seed_$scenario.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
  print('Wrote ${f.path}');
}
