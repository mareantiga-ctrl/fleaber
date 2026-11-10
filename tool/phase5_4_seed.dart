// ignore_for_file: avoid_print
/// Phase 5.4 staging seeds for REAL device screenshots.
///
///   dart run tool/phase5_4_seed.dart realistic|guaranteed|cancel|expiry|pending|bag
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final scenario = (args.isEmpty ? '' : args.first).trim().toLowerCase();
  if (!const {
    'realistic',
    'guaranteed',
    'cancel',
    'expiry',
    'pending',
    'bag',
  }.contains(scenario)) {
    stderr.writeln(
      'usage: dart run tool/phase5_4_seed.dart '
      'realistic|guaranteed|cancel|expiry|pending|bag',
    );
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
  final tag = 'p54_${scenario}_${DateTime.now().millisecondsSinceEpoch}_'
      '${Random().nextInt(999)}';

  Future<void> upsertPolicy() async {
    final existing = await client.select(
      'seller_reservation_settings',
      filter: 'seller_id=eq.$sellerId',
      limit: 1,
    );
    final payload = {
      'policy_mode': 'trust',
      'untrusted_mode': 'approval',
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
    required String title,
    required String itemTitle,
    required String ref,
    required int qty,
    String? buyerDisplayName,
  }) async {
    if (buyerDisplayName != null && buyerDisplayName.isNotEmpty) {
      try {
        await client.patch(
          'profiles',
          'id=eq.$buyerId',
          {'full_name': buyerDisplayName},
        );
      } catch (_) {
        try {
          await client.insert('profiles', {
            'id': buyerId,
            'full_name': buyerDisplayName,
          });
        } catch (_) {}
      }
    }
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': itemTitle,
      'price': 24.5,
      'quantity': qty,
      'ref_code': ref,
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': title,
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': ref,
      'title': itemTitle,
      'price': 24.5,
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
      'ref': ref,
    };
  }

  Future<Map<String, dynamic>> reserve({
    required Map<String, String> s,
  }) async {
    return await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyerId,
        'p_live_id': s['liveId'],
        'p_live_item_id': s['itemId'],
        'p_qty': 1,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: buyerToken,
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

  if (scenario == 'realistic') {
    await setTrust('trusted', buyer: buyerId);
    final s = await seedLive(
      title: 'Novidades de Outono — Roupa, Malas e Acessórios',
      itemTitle: 'Casaco bege',
      ref: 'CB01',
      qty: 3,
      buyerDisplayName: 'Maria S.',
    );
    final r = await reserve(s: s);
    final id = r['request_id']?.toString();
    out = {
      'scenario': 'realistic',
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'live_id': s['liveId'],
      'item_id': s['itemId'],
      'product_id': s['productId'],
      'ref': s['ref'],
      'request_id': id,
      'reserve_rpc': r,
      'row': await lrr(id),
      'available_qty': await avail(s['itemId']!),
      'live_title': 'Novidades de Outono — Roupa, Malas e Acessórios',
      'buyer_display': 'Maria S.',
      'item_title': 'Casaco bege',
    };
  } else if (scenario == 'pending') {
    await setTrust('distrusted', buyer: buyerId);
    final s = await seedLive(
      title: 'Pendentes — prova Recusar',
      itemTitle: 'Camisola azul',
      ref: 'CA02',
      qty: 4,
      buyerDisplayName: 'Maria S.',
    );
    final r = await reserve(s: s);
    final id = r['request_id']?.toString();
    out = {
      'scenario': 'pending',
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'live_id': s['liveId'],
      'item_id': s['itemId'],
      'product_id': s['productId'],
      'ref': s['ref'],
      'request_id': id,
      'reserve_rpc': r,
      'row': await lrr(id),
      'available_qty': await avail(s['itemId']!),
    };
  } else if (scenario == 'guaranteed' || scenario == 'cancel') {
    await setTrust('trusted', buyer: buyerId);
    final s = await seedLive(
      title: scenario == 'cancel'
          ? 'Cancelamento voluntário'
          : 'Reserva garantida',
      itemTitle: scenario == 'cancel' ? 'Mala camel' : 'Vestido floral',
      ref: scenario == 'cancel' ? 'MC03' : 'VF04',
      qty: 2,
      buyerDisplayName: 'Maria S.',
    );
    final before = await avail(s['itemId']!);
    final r = await reserve(s: s);
    final id = r['request_id']?.toString();
    out = {
      'scenario': scenario,
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
      'row': await lrr(id),
      'available_qty_before': before,
      'available_qty_after': await avail(s['itemId']!),
    };
  } else if (scenario == 'expiry') {
    await setTrust('trusted', buyer: buyerId);
    final s = await seedLive(
      title: 'Expiry histórico',
      itemTitle: 'Cachecol lã',
      ref: 'CL05',
      qty: 2,
      buyerDisplayName: 'Maria S.',
    );
    final r = await reserve(s: s);
    final id = r['request_id']?.toString();
    out = {
      'scenario': 'expiry',
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'live_id': s['liveId'],
      'item_id': s['itemId'],
      'product_id': s['productId'],
      'ref': s['ref'],
      'request_id': id,
      'reserve_rpc': r,
      'row': await lrr(id),
      'available_qty': await avail(s['itemId']!),
    };
  } else {
    // bag: two lines, then zero stock on B → bag_changed on Pagar
    await setTrust('trusted', buyer: buyerId);
    final a = await seedLive(
      title: 'Saco mudou — checkout',
      itemTitle: 'Camisa branca',
      ref: 'CB10',
      qty: 3,
      buyerDisplayName: 'Maria S.',
    );
    final productB = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'Calças ganga',
      'price': 18,
      'quantity': 1,
      'ref_code': 'CG11',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final itemB = await client.insert('live_items', {
      'live_id': a['liveId'],
      'ref_code': 'CG11',
      'title': 'Calças ganga',
      'price': 18,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productB['id'],
      'checkout_product_id': productB['id'],
      'quantity': null,
    });
    final rA = await reserve(s: a);
    final rB = await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyerId,
        'p_live_id': a['liveId'],
        'p_live_item_id': itemB['id'],
        'p_qty': 1,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    final idB = rB['request_id']?.toString();
    // Soft hold (bag_hold_none + pending) so begin returns
    // bag_changed_confirmation_required when product B is sold — not the hard
    // order_hold_product_sold path used for guaranteed/accepted holds.
    // Client: multi-line bag skips C8B when avail=0 so begin can show
    // FleaberBagChangedDialog (see payBagLines).
    if (idB != null) {
      await client.patch(
        'live_reservation_requests',
        'id=eq.$idB',
        {
          'status': 'pending',
          'request_kind': 'bag_hold_none',
          'expires_at': null,
        },
      );
    }
    final lines = [
      {
        'product_id': a['productId'],
        'live_item_id': a['itemId'],
        'reservation_request_id': rA['request_id'],
        'quantity': 1,
      },
      {
        'product_id': productB['id'],
        'live_item_id': itemB['id'],
        'reservation_request_id': idB,
        'quantity': 1,
      },
    ];
    out = {
      'scenario': 'bag',
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'buyer_email': envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      'buyer_password': envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
      'live_id': a['liveId'],
      'product_a': a['productId'],
      'product_b': productB['id'],
      'item_a': a['itemId'],
      'item_b': itemB['id'],
      'rid_a': rA['request_id'],
      'rid_b': idB,
      'lines': lines,
      'note':
          'Open checkout with both lines visible, then run phase5_4_bag_zero_b',
      'tag': tag,
    };
  }

  final dir = Directory('14-unified-commerce-phase5.4-final-visual-proof/raw');
  await dir.create(recursive: true);
  final f = File('${dir.path}/seed_$scenario.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
  print('Wrote ${f.path}');
}
