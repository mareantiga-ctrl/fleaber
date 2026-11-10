// ignore_for_file: avoid_print
/// Contrato reservas live: pending sobrevive a `lives.status=ended`.
/// Não espera 45 min reais — prova insert (`expires_at` ~45 min), stock
/// retido, live ended, depois expire RPC e stock libertado.
/// Live descartável. Não toca em MAESTRO_SMOKE_LIVE.
///
///   dart run tool/c6_pending_after_live_end.dart
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

const _title = 'C6_PENDING_AFTER_END';

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

Future<Map<String, dynamic>> _stock(
  LiveOpsStagingClient client,
  String liveItemId,
) async {
  final raw = await client.rpc('batata_live_item_stock', {
    'p_live_item_id': liveItemId,
  });
  if (raw is Map) return Map<String, dynamic>.from(raw);
  throw StateError('stock rpc inválido: $raw');
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

  var fail = 0;
  void check(String name, bool ok, [String detail = '']) {
    print('${ok ? "PASS" : "FAIL"} $name ${detail.isEmpty ? "" : "— $detail"}');
    if (!ok) fail++;
  }

  try {
    final live = await client.insert('lives', {
      'title': _title,
      'status': 'live',
      'seller_id': sellerId,
      'vendedor_id': sellerId,
      'is_active': true,
    });
    final liveId = live['id']!.toString();
    final product = await client.insert('products', {
      'seller_id': sellerId,
      'title': 'C6 pending-after-end product',
      'price': 5,
      'quantity': 3,
      'ref_code': 'C6PAE-${DateTime.now().millisecondsSinceEpoch}',
      'list_on_marketplace': false,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
    final productId = product['id']!.toString();
    final item = await client.insert('live_items', {
      'live_id': liveId,
      'ref_code': product['ref_code'],
      'title': 'C6 pending item',
      'price': 5,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': productId,
      'checkout_product_id': productId,
    });
    final itemId = item['id']!.toString();

    final beforeStock = await _stock(client, itemId);
    check(
      'BD antes: stock livre 3',
      (beforeStock['available_qty'] as num?)?.toInt() == 3 &&
          (beforeStock['pending_bag_qty'] as num?)?.toInt() == 0,
      '$beforeStock',
    );

    final req = await client.insert('live_reservation_requests', {
      'live_id': liveId,
      'live_item_id': itemId,
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'requested_qty': 2,
      'source': 'fleaber_live',
      'status': 'pending',
    });
    final reqId = req['id']!.toString();
    final expiresAt = DateTime.tryParse(req['expires_at']?.toString() ?? '');
    final createdAt = DateTime.tryParse(req['created_at']?.toString() ?? '');
    var ttlMin = -1.0;
    if (expiresAt != null && createdAt != null) {
      ttlMin = expiresAt.difference(createdAt).inSeconds / 60.0;
    }
    check(
      'insert pending define expires_at ~45 min',
      ttlMin >= 44 && ttlMin <= 46,
      'ttl=${ttlMin.toStringAsFixed(1)} min expires_at=${req['expires_at']}',
    );

    final held = await _stock(client, itemId);
    check(
      'BD com pending: 2 un. retidas no saco',
      (held['pending_bag_qty'] as num?)?.toInt() == 2 &&
          (held['available_qty'] as num?)?.toInt() == 1,
      'pending=${held['pending_bag_qty']} avail=${held['available_qty']}',
    );

    await client.patch('lives', 'id=eq.$liveId', {
      'status': 'ended',
      'is_active': false,
      'ended_at': DateTime.now().toUtc().toIso8601String(),
    });

    final liveAfter = await client.select(
      'lives',
      filter: 'id=eq.$liveId',
      limit: 1,
    );
    check(
      'live ended',
      liveAfter.isNotEmpty && liveAfter.first['status'] == 'ended',
      '${liveAfter.first['status']}',
    );

    final still = await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$reqId',
      limit: 1,
    );
    check(
      'pending sobrevive ao terminar a live',
      still.isNotEmpty && still.first['status'] == 'pending',
      '${still.first['status']}',
    );

    final afterEnd = await _stock(client, itemId);
    check(
      'stock continua retido após ended',
      (afterEnd['pending_bag_qty'] as num?)?.toInt() == 2 &&
          (afterEnd['available_qty'] as num?)?.toInt() == 1,
      'pending=${afterEnd['pending_bag_qty']} avail=${afterEnd['available_qty']}',
    );

    final expireRes = await client.rpc(
      'batata_process_live_reservation_request',
      {
        'p_request_id': reqId,
        'p_action': 'expire',
        'p_processed_by': sellerId,
      },
      accessToken: sellerToken,
    );
    check(
      'RPC expire ok',
      expireRes is Map && expireRes['ok'] == true,
      '$expireRes',
    );

    final expiredRow = await client.select(
      'live_reservation_requests',
      filter: 'id=eq.$reqId',
      limit: 1,
    );
    check(
      'BD final: status expired',
      expiredRow.isNotEmpty && expiredRow.first['status'] == 'expired',
      '${expiredRow.first['status']}',
    );

    final released = await _stock(client, itemId);
    check(
      'BD final: stock libertado',
      (released['pending_bag_qty'] as num?)?.toInt() == 0 &&
          (released['available_qty'] as num?)?.toInt() == 3,
      'pending=${released['pending_bag_qty']} avail=${released['available_qty']}',
    );

    print(
      'NOTA: não há cron no repositório que passe pending→expired aos 45 min. '
      'O campo expires_at é preenchido; a passagem de estado exige RPC expire '
      '(ou PATCH). Sem isso o saco e o stock ficam retidos para além dos 45 min.',
    );
  } finally {
    await _wipe(client, sellerId);
  }

  exit(fail > 0 ? 1 : 0);
}
