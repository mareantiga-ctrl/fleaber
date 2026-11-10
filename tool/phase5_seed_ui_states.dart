// ignore_for_file: avoid_print
/// Seed Phase 5 UI states for real-app screenshots (staging only).
///
///   dart run tool/phase5_seed_ui_states.dart
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

  final tag = 'p5ui_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999)}';

  // Ensure policy configured (approval mode) for ask-seller shots
  final pol = await client.select(
    'seller_reservation_settings',
    filter: 'seller_id=eq.$sellerId',
    limit: 1,
  );
  if (pol.isEmpty) {
    await client.insert('seller_reservation_settings', {
      'seller_id': sellerId,
      'policy_mode': 'trust',
      'untrusted_mode': 'approval',
      'normal_ttl_seconds': 3600,
      'trusted_ttl_seconds': 86400,
      'accept_fleaber_global_trust': true,
      'configured_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  } else {
    await client.patch('seller_reservation_settings', 'seller_id=eq.$sellerId', {
      'untrusted_mode': 'approval',
      'normal_ttl_seconds': 3600,
      'trusted_ttl_seconds': 86400,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // Buyer untrusted for pending
  await client.rpc(
    'batata_seller_buyer_trust_set',
    {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
    accessToken: sellerToken,
  );

  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'P5UI $tag',
    'price': 12,
    'quantity': 5,
    'ref_code': 'P5UI-$tag',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final live = await client.insert('lives', {
    'title': 'P5UI_$tag',
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
  });
  final item = await client.insert('live_items', {
    'live_id': live['id'],
    'ref_code': 'P5UI-$tag',
    'title': 'P5UI pedido',
    'price': 12,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': product['id'],
    'checkout_product_id': product['id'],
    'quantity': null,
  });

  final pending = await client.rpc(
    'batata_reserve_with_policy',
    {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': live['id'],
      'p_live_item_id': item['id'],
      'p_qty': 1,
      'p_source': 'fleaber_live',
      'p_guest_session_id': null,
      'p_identity_linked': true,
      'p_notes': null,
    },
    accessToken: buyerToken,
  ) as Map<String, dynamic>;

  // Second product+item for guaranteed (trusted)
  final product2 = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'P5UI-G $tag',
    'price': 15,
    'quantity': 3,
    'ref_code': 'P5UI-G-$tag',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final item2 = await client.insert('live_items', {
    'live_id': live['id'],
    'ref_code': 'P5UI-G-$tag',
    'title': 'P5UI garantido',
    'price': 15,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': product2['id'],
    'checkout_product_id': product2['id'],
    'quantity': null,
  });
  await client.rpc(
    'batata_seller_buyer_trust_set',
    {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'trusted'},
    accessToken: sellerToken,
  );
  final guaranteed = await client.rpc(
    'batata_reserve_with_policy',
    {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
      'p_live_id': live['id'],
      'p_live_item_id': item2['id'],
      'p_qty': 1,
      'p_source': 'fleaber_live',
      'p_guest_session_id': null,
      'p_identity_linked': true,
      'p_notes': null,
    },
    accessToken: buyerToken,
  ) as Map<String, dynamic>;

  final out = {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'live_id': live['id'],
    'product_id': product['id'],
    'pending_request_id': pending['request_id'],
    'pending_kind': pending['request_kind'],
    'pending_status': pending['status'],
    'guaranteed_request_id': guaranteed['request_id'],
    'guaranteed_kind': guaranteed['request_kind'],
    'guaranteed_status': guaranteed['status'],
    'studio_hint':
        'Open Seller Studio for live ${live['id']} — expect Pediu + Reservado rows',
    'policy_settings_hint':
        'Conta → Definições → Política de reservas (or first-live gate)',
    'tag': tag,
  };

  final dir = Directory('14-unified-commerce-phase5-live-seller-studio/raw');
  await dir.create(recursive: true);
  final f = File('${dir.path}/ui_seed_for_screenshots.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
  print('Wrote ${f.path}');
}
