// ignore_for_file: avoid_print
/// Seed cross-pool + gravado + marketplace para SL-G UI (Disp nos cards).
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

const _titleLive = 'STOCK_LC_CROSS_LIVE';
const _titleVod = 'STOCK_LC_CROSS_VOD';

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final sellerEmail = envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPassword = envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD');
  final buyerEmail = envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPassword = envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD');

  final sellerToken = await client.signIn(email: sellerEmail, password: sellerPassword);
  var sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  if (!isUuid(sellerId)) {
    sellerId = await client.userIdForAccessToken(sellerToken);
  }
  final buyerToken = await client.signIn(email: buyerEmail, password: buyerPassword);
  final buyerId = await client.userIdForAccessToken(buyerToken);

  for (final t in [_titleLive, _titleVod, 'REGRESSION_INT_TEST']) {
    final lives = await client.select(
      'lives',
      filter: 'seller_id=eq.$sellerId&title=eq.$t',
      limit: 5,
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

  final ref = 'SL-CROSS-${DateTime.now().millisecondsSinceEpoch % 100000}';
  final product = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'SL Cross pool product',
    'price': 12,
    'quantity': 10,
    'ref_code': ref,
    'list_on_marketplace': true,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = product['id']!.toString();

  // VOD (gravado) — live terminada
  final vod = await client.insert('lives', {
    'title': _titleVod,
    'status': 'ended',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': false,
    'mux_playback_id': 'maestro-cross-vod-playback',
  });
  final vodId = vod['id']!.toString();
  await client.insert('live_items', {
    'live_id': vodId,
    'ref_code': ref,
    'title': 'SL Cross gravado item',
    'price': 12,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': productId,
    'checkout_product_id': productId,
    'logical_item_id': productId,
  });

  // Venda gravado (order product_id)
  await client.insert('orders', {
    'product_id': productId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'price_total': 12,
    'status': 'pago',
    'quantity': 1,
    'payment_method': 'Pagamento na App',
  });

  // Live activa B — mesmo pool
  final liveB = await client.insert('lives', {
    'title': _titleLive,
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
    'mux_playback_id': 'maestro-cross-live-playback',
  });
  final liveBId = liveB['id']!.toString();
  final itemB = await client.insert('live_items', {
    'live_id': liveBId,
    'ref_code': ref,
    'title': 'SL Cross live item',
    'price': 12,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': productId,
    'checkout_product_id': productId,
    'logical_item_id': productId,
  });

  final stock = await client.rpc('batata_live_item_stock', {
    'p_live_item_id': itemB['id'],
  });
  print('Cross UI seed: liveB=$liveBId vod=$vodId product=$productId');
  print('  stock liveB: $stock');

  _patchEnv(
    liveId: liveBId,
    vodLiveId: vodId,
    productId: productId,
    itemTitle: 'SL Cross live item',
    sellerId: sellerId,
  );
}

void _patchEnv({
  required String liveId,
  required String vodLiveId,
  required String productId,
  required String itemTitle,
  required String sellerId,
}) {
  final f = File('.maestro/.env');
  if (!f.existsSync()) return;
  final lines = f.readAsLinesSync();
  final out = <String>[];
  var backupWritten = false;
  for (final line in lines) {
    if (line.startsWith('MAESTRO_LIVE_ID=') && !backupWritten) {
      out.add('MAESTRO_LIVE_ID_SLA_BACKUP=${line.substring('MAESTRO_LIVE_ID='.length)}');
      out.add('MAESTRO_LIVE_ID=$liveId');
      backupWritten = true;
      continue;
    }
    if (line.startsWith('MAESTRO_LIVE_ID_SLA_BACKUP=')) continue;
    if (line.startsWith('MAESTRO_CROSS_')) continue;
    if (line.startsWith('MAESTRO_ITEM_TITLE=')) {
      out.add('MAESTRO_ITEM_TITLE=$itemTitle');
      continue;
    }
    out.add(line);
  }
  out.add('MAESTRO_CROSS_VOD_LIVE_ID=$vodLiveId');
  out.add('MAESTRO_CROSS_PRODUCT_ID=$productId');
  out.add('MAESTRO_CROSS_SELLER_ID=$sellerId');
  f.writeAsStringSync('${out.join('\n')}\n');
}
