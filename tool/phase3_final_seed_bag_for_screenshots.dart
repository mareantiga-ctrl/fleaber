// ignore_for_file: avoid_print
/// Seeds a mixed seller bag for real UI screenshots, writes seed JSON.
///
///   dart run tool/phase3_final_seed_bag_for_screenshots.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'live_ops_staging_client.dart';

Future<void> main() async {
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
  final tag = 'p3ui_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999)}';

  await client.patch('profiles', 'id=eq.$sellerId', {'hub_published': true});
  await client.patch(
    'seller_reservation_settings',
    'seller_id=eq.$sellerId',
    {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
  );

  Future<Map<String, String>> seed(String suffix, int qty) async {
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'QA $tag $suffix',
      'price': 12.5,
      'quantity': qty,
      'ref_code': 'QA-$tag-$suffix',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final live = await client.insert('lives', {
      'title': 'QA_$tag\_$suffix',
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final item = await client.insert('live_items', {
      'live_id': live['id'],
      'ref_code': 'QA-$tag-$suffix',
      'title': 'QA $suffix',
      'price': 12.5,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': product['id'],
      'checkout_product_id': product['id'],
      'quantity': null,
    });
    return {
      'productId': '${product['id']}',
      'liveId': '${live['id']}',
      'itemId': '${item['id']}',
    };
  }

  Future<String?> reserve(Map<String, String> s) async {
    final r = await client.rpc(
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
    return r['request_id']?.toString();
  }

  // Guaranteed
  await client.rpc(
    'batata_seller_buyer_trust_set',
    {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
    accessToken: sellerToken,
  );
  final sG = await seed('G', 3);
  final idG = await reserve(sG);

  // Pending
  await client.rpc(
    'batata_seller_buyer_trust_set',
    {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
    accessToken: sellerToken,
  );
  final sP = await seed('P', 2);
  final idP = await reserve(sP);

  // Unguaranteed
  await client.patch(
    'seller_reservation_settings',
    'seller_id=eq.$sellerId',
    {'policy_mode': 'pay_only', 'untrusted_mode': 'pay_required'},
  );
  await client.rpc(
    'batata_seller_buyer_trust_set',
    {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
    accessToken: sellerToken,
  );
  final sU = await seed('U', 2);
  final idU = await reserve(sU);

  // Unavailable (unguaranteed loses stock to another buyer)
  await client.patch(
    'seller_reservation_settings',
    'seller_id=eq.$sellerId',
    {'policy_mode': 'pay_only', 'untrusted_mode': 'pay_required'},
  );
  final sX = await seed('X', 1);
  final idX = await reserve(sX);
  final buyerBEmail = staging['LIVE_OPS_TEST_BUYER_B_EMAIL']?.trim();
  final buyerBPassword = staging['LIVE_OPS_TEST_BUYER_B_PASSWORD']?.trim();
  String? idTake;
  if (buyerBEmail != null &&
      buyerBEmail.isNotEmpty &&
      buyerBPassword != null &&
      buyerBPassword.isNotEmpty) {
    final buyerBToken = await client.signIn(
      email: buyerBEmail,
      password: buyerBPassword,
    );
    final buyerBId = await client.userIdForAccessToken(buyerBToken);
    await client.rpc(
      'batata_seller_buyer_trust_set',
      {'p_seller_id': sellerId, 'p_buyer_id': buyerBId, 'p_mode': 'trusted'},
      accessToken: sellerToken,
    );
    final rTake = await client.rpc(
      'batata_reserve_with_policy',
      {
        'p_seller_id': sellerId,
        'p_buyer_id': buyerBId,
        'p_live_id': sX['liveId'],
        'p_live_item_id': sX['itemId'],
        'p_qty': 1,
        'p_source': 'fleaber_live',
        'p_guest_session_id': null,
        'p_identity_linked': true,
        'p_notes': null,
      },
      accessToken: buyerBToken,
    ) as Map<String, dynamic>;
    idTake = rTake['request_id']?.toString();
  } else {
    // Fallback: zero product qty so seller-bag marks unavailable.
    await client.patch('products', 'id=eq.${sX['productId']}', {'quantity': 0});
  }

  // Marketplace adapter line
  final mp = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'QA MP $tag',
    'price': 9,
    'quantity': 5,
    'ref_code': 'QA-MP-$tag',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final mpOrder = await client.insert('orders', {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': mp['id'],
    'quantity': 1,
    'status': 'reserva_pendente',
    'is_reservation': true,
    'price_total': 9.0,
    'payment_method': 'manual',
  });

  // Reset policy for later interactive use
  await client.patch(
    'seller_reservation_settings',
    'seller_id=eq.$sellerId',
    {'policy_mode': 'trust', 'untrusted_mode': 'approval'},
  );

  final out = {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'live_id': sG['liveId'],
    'guaranteed_request_id': idG,
    'pending_request_id': idP,
    'unguaranteed_request_id': idU,
    'unavailable_request_id': idX,
    'unavailable_take_request_id': idTake,
    'marketplace_order_id': mpOrder['id']?.toString(),
    'buyer_email': envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    'buyer_password': envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    'supabase_url': normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    'supabase_anon_key': envRequire(staging, 'SUPABASE_ANON_KEY'),
  };

  final file = File('tool/reports/phase3_qa_seed.json');
  await file.parent.create(recursive: true);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('WROTE ${file.path}');
  print(jsonEncode(out));
}
