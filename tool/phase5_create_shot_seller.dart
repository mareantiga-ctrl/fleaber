// ignore_for_file: avoid_print
/// Create P5 screenshot seller without '+' in email (Android IME eats '+').
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

  final tag = DateTime.now().millisecondsSinceEpoch;
  final email = 'p5seller$tag@fleaber.test';
  const password = 'P5SellerShot!staging';

  final sellerId = await client.createAdminUser(
    email: email,
    password: password,
  );
  try {
    await client.insert('profiles', {
      'id': sellerId,
      'display_name': 'P5 Seller Shot',
      'full_name': 'P5 Seller Shot',
    });
  } catch (_) {}

  // Policy configured (for B/C/D shots) — clear later for gate A if needed
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

  // Seed live + pending + guaranteed for this seller
  final buyerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final buyerId = await client.userIdForAccessToken(buyerToken);
  final sellerToken = await client.signIn(email: email, password: password);

  await client.rpc(
    'batata_seller_buyer_trust_set',
    {'p_seller_id': sellerId, 'p_buyer_id': buyerId, 'p_mode': 'distrusted'},
    accessToken: sellerToken,
  );

  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'P5SHOT $tag',
    'price': 12,
    'quantity': 10,
    'ref_code': 'P5SHOT-$tag',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final live = await client.insert('lives', {
    'title': 'P5SHOT_$tag',
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
  });
  final item = await client.insert('live_items', {
    'live_id': live['id'],
    'ref_code': 'P5SHOT-$tag',
    'title': 'P5SHOT pedido',
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

  final product2 = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'P5SHOT-G $tag',
    'price': 15,
    'quantity': 3,
    'ref_code': 'P5SHOT-G-$tag',
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final item2 = await client.insert('live_items', {
    'live_id': live['id'],
    'ref_code': 'P5SHOT-G-$tag',
    'title': 'P5SHOT garantido',
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
  Map<String, dynamic>? guaranteed;
  try {
    guaranteed = await client.rpc(
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
  } catch (e) {
    guaranteed = {'ok': false, 'error': e.toString()};
  }

  final out = {
    'email': email,
    'password': password,
    'seller_id': sellerId,
    'live_id': live['id'],
    'pending_request_id': pending['request_id'],
    'pending_status': pending['status'],
    'pending_kind': pending['request_kind'],
    'guaranteed_request_id': guaranteed['request_id'],
    'guaranteed_status': guaranteed['status'],
    'guaranteed_kind': guaranteed['request_kind'],
  };
  final f = File(
    '14-unified-commerce-phase5-live-seller-studio/raw/p5_shot_seller.json',
  );
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  // Also write maestro env overlay
  final envOverlay = File(
    '14-unified-commerce-phase5-live-seller-studio/raw/p5_shot_maestro.env',
  );
  await envOverlay.writeAsString(
    'MAESTRO_SELLER_EMAIL=$email\nMAESTRO_SELLER_PASSWORD=$password\n',
  );
  print(jsonEncode(out));
  print('Wrote ${f.path}');
}
