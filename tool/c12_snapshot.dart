// ignore_for_file: avoid_print
/// Snapshot C12: live, artigo, reservas, saco.
///
///   dart run tool/c12_snapshot.dart
///   dart run tool/c12_snapshot.dart --label=after_reserve
library;

import 'dart:convert';
import 'dart:io';

import 'bag_crosscheck_logic.dart';
import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  var label = 'snap';
  for (final a in args) {
    if (a.startsWith('--label=')) label = a.split('=').last.trim();
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final env = _readEnv(File('.maestro/.env'));
  final liveId = env['MAESTRO_LIVE_ID']?.trim() ?? '';
  if (!isUuid(liveId)) {
    stderr.writeln('FAIL: MAESTRO_LIVE_ID');
    exit(1);
  }
  var buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  if (!isUuid(buyerId)) {
    final t = await client.signIn(
      email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    buyerId = await client.userIdForAccessToken(t);
  }

  final lives = await client.select('lives', filter: 'id=eq.$liveId', limit: 1);
  final items = await client.select(
    'live_items',
    filter: 'live_id=eq.$liveId&order=is_active.desc,created_at.asc',
    limit: 200,
  );
  final reservations = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId&order=created_at.desc',
    limit: 50,
  );
  final hubLives = await client.select(
    'hub_lives_public',
    filter: 'id=eq.$liveId',
    limit: 1,
  );
  final hubItems = await client.select(
    'hub_live_items_public',
    filter: 'live_id=eq.$liveId&order=is_active.desc,created_at.asc',
    limit: 200,
  );

  final productIds = items
      .map((e) => e['product_id']?.toString() ?? '')
      .where((id) => isUuid(id))
      .toSet();
  final products = <Map<String, dynamic>>[];
  for (final id in productIds) {
    products.addAll(
      await client.select('products', filter: 'id=eq.$id', limit: 1),
    );
  }

  final buyerRows = reservations
      .where((r) => r['buyer_id']?.toString() == buyerId)
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  final bag = BagCrosscheckLogic.fromRows(buyerRows);

  Map<String, dynamic> slimLive(Map<String, dynamic> r) => {
        'id': r['id'],
        'title': r['title'],
        'status': r['status'],
        'is_active': r['is_active'],
        'mux_playback_id': r['mux_playback_id'],
      };
  Map<String, dynamic> slimItem(Map<String, dynamic> r) => {
        'id': r['id'],
        'title': r['title'],
        'price': r['price'],
        'status': r['status'],
        'is_active': r['is_active'],
        'product_id': r['product_id'],
      };
  Map<String, dynamic> slimRes(Map<String, dynamic> r) => {
        'id': r['id'],
        'status': r['status'],
        'requested_qty': r['requested_qty'],
        'source': r['source'],
        'buyer_id': r['buyer_id'],
        'live_item_id': r['live_item_id'],
      };

  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'label': label,
    'live_id': liveId,
    'buyer_id': buyerId,
    'live': lives.isEmpty ? null : slimLive(lives.first),
    'hub_live': hubLives.isEmpty ? null : slimLive(hubLives.first),
    'items': items.map(slimItem).toList(),
    'hub_items': hubItems.map(slimItem).toList(),
    'products': products
        .map(
          (p) => {
            'id': p['id'],
            'title': p['title'],
            'price': p['price'],
            'quantity': p['quantity'],
            'list_on_marketplace': p['list_on_marketplace'],
          },
        )
        .toList(),
    'reservations': reservations.map(slimRes).toList(),
    'bag': {
      'in_bag_rows': bag.inBagRowCount,
      'in_bag_units': bag.inBagUnitQty,
      'pending_any': bag.pendingAnySource,
      'pending_visible': bag.pendingVisibleInBag,
      'diagnoses': bag.diagnoses,
    },
  };

  final dest = Directory('tool/reports/battery_c12_2026-08-18/bd');
  dest.createSync(recursive: true);
  final file = File('${dest.path}/c12_$label.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(
    'label=$label live=${out['live']} bag=${out['bag']} '
    'res=${reservations.length} items=${items.length}',
  );
  print('wrote ${file.path}');
}

Map<String, String> _readEnv(File file) {
  final out = <String, String>{};
  if (!file.existsSync()) return out;
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    out[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return out;
}
