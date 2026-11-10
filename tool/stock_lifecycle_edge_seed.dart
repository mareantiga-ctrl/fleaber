// ignore_for_file: avoid_print
/// Seed live isolada para SL-E (waitlist, reject, partial, overstock) + actualiza .maestro/.env.
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

const _title = 'STOCK_LC_EDGE_LIVE';

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

  final old = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&title=eq.$_title',
    limit: 5,
  );
  for (final live in old) {
    final id = live['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    await client.deleteWhere('live_reservation_requests', 'live_id=eq.$id');
    await client.deleteWhere('live_items', 'live_id=eq.$id');
    await client.deleteWhere('lives', 'id=eq.$id');
  }

  final live = await client.insert('lives', {
    'title': _title,
    'status': 'live',
    'seller_id': sellerId,
    'vendedor_id': sellerId,
    'is_active': true,
    'mux_playback_id': 'maestro-edge-staging-playback',
  });
  final liveId = live['id']!.toString();

  // Item A — waitlist (qty 1, aceite esgota, pending na fila)
  final prodA = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'SL Edge waitlist',
    'price': 5,
    'quantity': 1,
    'ref_code': 'SL-WL',
    'list_on_marketplace': false,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final itemA = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': 'SL-WL',
    'title': 'SL Edge waitlist item',
    'price': 5,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': prodA['id'],
    'checkout_product_id': prodA['id'],
  });
  final rAccept = await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': itemA['id'],
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
  });
  await client.rpc('batata_process_live_reservation_request', {
    'p_request_id': rAccept['id'],
    'p_action': 'accept',
    'p_processed_by': sellerId,
    'p_notes': 'edge_waitlist_setup',
  });
  await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': itemA['id'],
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
    'notes': 'edge_waitlist_ui',
  });

  // Item B — overstock + reject UX
  final prodB = await client.insert('products', {
    'seller_id': sellerId,
    'title': 'SL Edge ops',
    'price': 5,
    'quantity': 5,
    'ref_code': 'SL-EDGE',
    'list_on_marketplace': false,
    'available_for_live': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final itemB = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': 'SL-EDGE',
    'title': 'SL Edge smoke item',
    'price': 5,
    'is_active': true,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': prodB['id'],
    'checkout_product_id': prodB['id'],
  });
  await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': itemB['id'],
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 3,
    'status': 'pending',
    'source': 'fleaber_live',
    'notes': 'edge_overstock_ui',
  });
  await client.insert('live_reservation_requests', {
    'live_id': liveId,
    'live_item_id': itemB['id'],
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
    'notes': 'edge_reject_ui',
  });

  _patchEnv(
    liveId: liveId,
    itemId: itemB['id']!.toString(),
    waitlistItemId: itemA['id']!.toString(),
  );

  print('EDGE seed OK live=$liveId');
  print('  itemA waitlist=${itemA['id']} itemB ops=${itemB['id']}');
}

void _patchEnv({
  required String liveId,
  required String itemId,
  required String waitlistItemId,
}) {
  final f = File('.maestro/.env');
  if (!f.existsSync()) return;
  final lines = f.readAsLinesSync();
  final out = <String>[];
  var backupDone = false;
  for (final line in lines) {
    if (line.startsWith('MAESTRO_LIVE_ID=') && !backupDone) {
      out.add('MAESTRO_LIVE_ID_SLA_BACKUP=${line.substring('MAESTRO_LIVE_ID='.length)}');
      out.add('MAESTRO_LIVE_ID=$liveId');
      backupDone = true;
      continue;
    }
    if (line.startsWith('MAESTRO_LIVE_ID_SLA_BACKUP=')) continue;
    if (line.startsWith('MAESTRO_LIVE_ITEM_ID=')) {
      out.add('MAESTRO_LIVE_ITEM_ID=$itemId');
      continue;
    }
    if (line.startsWith('MAESTRO_ITEM_TITLE=')) {
      out.add('MAESTRO_ITEM_TITLE=SL Edge smoke item');
      continue;
    }
    if (line.startsWith('MAESTRO_EDGE_')) continue;
    out.add(line);
  }
  if (!backupDone) out.add('MAESTRO_LIVE_ID=$liveId');
  out.add('MAESTRO_EDGE_WAITLIST_ITEM_ID=$waitlistItemId');
  f.writeAsStringSync('${out.join('\n')}\n');
}
