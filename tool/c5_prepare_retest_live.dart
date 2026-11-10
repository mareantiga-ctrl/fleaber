// ignore_for_file: avoid_print
/// Cria live de reteste C5 SEM apagar a live/encomenda da corrida anterior.
///
///   dart run tool/c5_prepare_retest_live.dart
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

const _title = 'C5_RETEST_214';
const _fakePlaybackId = 'maestro-smoke-staging-playback';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  var sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  final sellerEmail = envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPassword = envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD');
  final buyerEmail = envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPassword = envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final sellerToken = await client.signIn(
    email: sellerEmail,
    password: sellerPassword,
  );
  if (!isUuid(sellerId)) {
    sellerId = await client.userIdForAccessToken(sellerToken);
  }

  final old = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&title=eq.$_title',
    limit: 5,
  );
  for (final live in old) {
    final id = live['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    await client.deleteWhere('live_reservation_requests', 'live_id=eq.$id');
    await client.deleteWhere('orders', 'live_id=eq.$id');
    await client.deleteWhere('live_items', 'live_id=eq.$id');
    await client.deleteWhere('lives', 'id=eq.$id');
  }

  final live = await client.insert('lives', {
    'title': _title,
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
    'mux_playback_id': _fakePlaybackId,
  });
  final liveId = live['id']!.toString();
  final ref = 'C5R-${DateTime.now().millisecondsSinceEpoch % 100000}';

  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'Maestro smoke product',
    'price': 5,
    'quantity': 5,
    'ref_code': ref,
    'list_on_marketplace': false,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = product['id']!.toString();

  final item = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': ref,
    'title': 'Maestro smoke item',
    'price': 5,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': productId,
    'checkout_product_id': productId,
  });
  final liveItemId = item['id']!.toString();

  var buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  if (!isUuid(buyerId)) {
    final buyerToken = await client.signIn(
      email: buyerEmail,
      password: buyerPassword,
    );
    buyerId = await client.userIdForAccessToken(buyerToken);
  }

  await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': liveItemId,
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 2,
    'source': 'fleaber_live',
    'status': 'pending',
  });

  final envFile = File('.maestro/.env');
  final lines = envFile.existsSync() ? envFile.readAsLinesSync() : <String>[];
  final out = <String>[];
  var wroteLive = false;
  for (final line in lines) {
    if (line.startsWith('MAESTRO_LIVE_ID=')) {
      out.add('MAESTRO_LIVE_ID=$liveId');
      wroteLive = true;
    } else {
      out.add(line);
    }
  }
  if (!wroteLive) out.add('MAESTRO_LIVE_ID=$liveId');
  envFile.writeAsStringSync('${out.join('\n')}\n');

  print('C5 retest live OK');
  print('  live_id=$liveId');
  print('  ref=$ref');
  print('  qty pending=2');
  print('  wrote ${envFile.path}');
}
