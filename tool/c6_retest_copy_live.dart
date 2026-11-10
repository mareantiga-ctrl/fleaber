// ignore_for_file: avoid_print
/// Live descartável para reteste copy C6 (Esgotado + saco artigos/unidades).
/// Não toca em MAESTRO_SMOKE_LIVE.
///
///   dart run tool/c6_retest_copy_live.dart
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

const _title = 'C6_RETEST_COPY';
const _fakePlaybackId = 'maestro-smoke-staging-playback';

Future<void> _wipe(LiveOpsStagingClient client, String sellerId) async {
  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&title=eq.$_title',
    limit: 10,
  );
  for (final live in lives) {
    final id = live['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    await client.deleteWhere('live_reservation_requests', 'live_id=eq.$id');
    await client.deleteWhere('orders', 'live_id=eq.$id');
    await client.deleteWhere('live_items', 'live_id=eq.$id');
    await client.deleteWhere('lives', 'id=eq.$id');
  }
}

Future<Map<String, dynamic>> _product(
  LiveOpsStagingClient client, {
  required String sellerId,
  required String title,
  required String ref,
}) {
  return client.insert('products', {
    'seller_id': sellerId,
    'title': title,
    'price': 5,
    'quantity': 5,
    'ref_code': ref,
    'list_on_marketplace': false,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
}

Future<Map<String, dynamic>> _item(
  LiveOpsStagingClient client, {
  required String liveId,
  required Map<String, dynamic> product,
  required String title,
}) {
  return client.insert('live_items', {
    'live_id': liveId,
    'ref_code': product['ref_code'],
    'title': title,
    'price': 5,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': product['id'],
    'checkout_product_id': product['id'],
  });
}

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  var sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  var buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  final sellerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  if (!isUuid(sellerId)) {
    sellerId = await client.userIdForAccessToken(sellerToken);
  }
  if (!isUuid(buyerId)) {
    final t = await client.signIn(
      email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    buyerId = await client.userIdForAccessToken(t);
  }

  await _wipe(client, sellerId);

  final live = await client.insert('lives', {
    'title': _title,
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
    'mux_playback_id': _fakePlaybackId,
  });
  final liveId = live['id']!.toString();
  final stamp = DateTime.now().millisecondsSinceEpoch % 100000;

  final productA = await _product(
    client,
    sellerId: sellerId,
    title: 'C6 Artigo A',
    ref: 'C6A-$stamp',
  );
  final productB = await _product(
    client,
    sellerId: sellerId,
    title: 'C6 Artigo B',
    ref: 'C6B-$stamp',
  );
  final productC = await _product(
    client,
    sellerId: sellerId,
    title: 'C6 Artigo C',
    ref: 'C6C-$stamp',
  );

  final itemA = await _item(
    client,
    liveId: liveId,
    product: productA,
    title: 'C6 Artigo A',
  );
  final itemB = await _item(
    client,
    liveId: liveId,
    product: productB,
    title: 'C6 Artigo B',
  );
  final itemC = await _item(
    client,
    liveId: liveId,
    product: productC,
    title: 'C6 Artigo C',
  );

  await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': itemB['id'],
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 1,
    'source': 'fleaber_live',
    'status': 'pending',
    'notes': 'C6_RETEST_COPY B',
  });
  await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': itemC['id'],
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 2,
    'source': 'fleaber_live',
    'status': 'pending',
    'notes': 'C6_RETEST_COPY C',
  });

  final envFile = File('.maestro/.env');
  final lines = envFile.existsSync() ? envFile.readAsLinesSync() : <String>[];
  final out = <String>[];
  var wroteLive = false;
  var wroteTitle = false;
  for (final line in lines) {
    if (line.startsWith('MAESTRO_LIVE_ID=')) {
      out.add('MAESTRO_LIVE_ID=$liveId');
      wroteLive = true;
    } else if (line.startsWith('MAESTRO_ITEM_TITLE=')) {
      out.add('MAESTRO_ITEM_TITLE=C6 Artigo A');
      wroteTitle = true;
    } else {
      out.add(line);
    }
  }
  if (!wroteLive) out.add('MAESTRO_LIVE_ID=$liveId');
  if (!wroteTitle) out.add('MAESTRO_ITEM_TITLE=C6 Artigo A');
  envFile.writeAsStringSync('${out.join('\n')}\n');

  print('C6 retest copy live OK');
  print('  live_id=$liveId');
  print('  item_a=${itemA['id']} (marcar esgotado)');
  print('  item_b=${itemB['id']} qty 1 pending');
  print('  item_c=${itemC['id']} qty 2 pending');
  print('  wrote ${envFile.path}');
}
