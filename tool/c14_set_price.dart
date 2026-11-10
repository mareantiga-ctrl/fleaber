// ignore_for_file: avoid_print
/// Corrida 14 — definir preço do C14 na live activa (11,00 €).
///
///   dart run tool/c14_set_price.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _price = 11.0;
const _productTitle = 'C14 Produto A';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final env = File('.maestro/.env');
  var liveId = '';
  if (env.existsSync()) {
    for (final line in env.readAsLinesSync()) {
      if (line.startsWith('MAESTRO_LIVE_ID=')) {
        liveId = line.substring('MAESTRO_LIVE_ID='.length).trim();
      }
    }
  }
  if (!isUuid(liveId)) {
    stderr.writeln('FAIL: MAESTRO_LIVE_ID');
    exit(1);
  }

  var sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  if (!isUuid(sellerId)) {
    final t = await client.signIn(
      email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
    );
    sellerId = await client.userIdForAccessToken(t);
  }

  final products = await client.select(
    'products',
    filter:
        'seller_id=eq.$sellerId&title=eq.${Uri.encodeQueryComponent(_productTitle)}&order=created_at.desc',
    limit: 1,
  );
  if (products.isEmpty) {
    stderr.writeln('FAIL: produto C14');
    exit(1);
  }
  final productId = products.first['id']!.toString();
  await client.patch('products', 'id=eq.$productId', {'price': _price});

  final items = await client.select(
    'live_items',
    filter: 'live_id=eq.$liveId&product_id=eq.$productId',
    limit: 1,
  );
  if (items.isEmpty) {
    stderr.writeln('FAIL: live_item C14');
    exit(1);
  }
  final liveItemId = items.first['id']!.toString();
  await client.patch('live_items', 'id=eq.$liveItemId', {'price': _price});

  final dest = File('tool/reports/battery_c14_2026-08-18/bd/c14_set_price.json');
  dest.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'live_id': liveId,
      'product_id': productId,
      'live_item_id': liveItemId,
      'price': _price,
    }),
  );
  print('C14 price=$_price product=$productId live_item=$liveItemId live=$liveId');
}
