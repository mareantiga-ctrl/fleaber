// ignore_for_file: avoid_print
/// C27 — após go-live: ligar C27 Produto A (+ B inactivo) à live activa.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _titleA = 'C27 Produto A';
const _titleB = 'C27 Produto B';
const _reportDir = 'tool/reports/battery_c27_2026-08-23';

Future<Map<String, dynamic>> _ensureItem(
  LiveOpsStagingClient client, {
  required String liveId,
  required Map<String, dynamic> product,
  required bool active,
}) async {
  final productId = product['id']!.toString();
  final title = product['title']?.toString() ?? '';
  final ref = product['ref_code']?.toString() ?? '';
  final price = product['price'] ?? 0;
  final existing = await client.select(
    'live_items',
    filter: 'live_id=eq.$liveId&product_id=eq.$productId',
    limit: 1,
  );
  if (existing.isNotEmpty) {
    final id = existing.first['id']!.toString();
    await client.patch('live_items', 'id=eq.$id', {
      'is_active': active,
      'status': 'available',
      'title': title,
      'ref_code': ref,
      'price': price,
    });
    return {'live_item_id': id, 'created': false};
  }
  final item = await client.insert('live_items', {
    'live_id': liveId,
    'ref_code': ref,
    'title': title,
    'price': price,
    'is_active': active,
    'status': 'available',
    'item_kind': 'marketplace_product',
    'product_id': productId,
    'checkout_product_id': productId,
  });
  return {'live_item_id': item['id'], 'created': true};
}

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  var sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  if (!isUuid(sellerId)) {
    final t = await client.signIn(
      email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
    );
    sellerId = await client.userIdForAccessToken(t);
  }

  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 20,
  );
  Map<String, dynamic>? active;
  for (final l in lives) {
    if ((l['status'] ?? '').toString().toLowerCase() == 'live' &&
        l['is_active'] != false) {
      active = l;
      break;
    }
  }
  if (active == null) {
    stderr.writeln('FAIL: nenhuma live activa');
    exit(2);
  }
  final liveId = active['id']!.toString();

  Future<Map<String, dynamic>?> latestProduct(String title) async {
    final rows = await client.select(
      'products',
      filter:
          'seller_id=eq.$sellerId&title=eq.${Uri.encodeQueryComponent(title)}&order=created_at.desc',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  final productA = await latestProduct(_titleA);
  final productB = await latestProduct(_titleB);
  if (productA == null || productB == null) {
    stderr.writeln('FAIL: produtos C27 em falta — correr c27_prepare.dart');
    exit(1);
  }

  await client.patch('live_items', 'live_id=eq.$liveId', {'is_active': false});
  final itemA = await _ensureItem(client, liveId: liveId, product: productA, active: true);
  final itemB = await _ensureItem(client, liveId: liveId, product: productB, active: false);

  _patchMaestroLiveId(liveId);

  final out = {
    'live_id': liveId,
    'title': active['title'],
    'product_a': productA['id'],
    'live_item_a': itemA['live_item_id'],
    'product_b': productB['id'],
    'live_item_b': itemB['live_item_id'],
  };
  Directory('$_reportDir/bd').createSync(recursive: true);
  File('$_reportDir/bd/c27_active_live.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  print(jsonEncode(out));
}

void _patchMaestroLiveId(String liveId) {
  final file = File('.maestro/.env');
  final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
  final out = <String>[];
  var wrote = false;
  for (final line in lines) {
    if (line.startsWith('MAESTRO_LIVE_ID=')) {
      out.add('MAESTRO_LIVE_ID=$liveId');
      wrote = true;
    } else {
      out.add(line);
    }
  }
  if (!wrote) out.add('MAESTRO_LIVE_ID=$liveId');
  file.writeAsStringSync('${out.join('\n')}\n');
}
