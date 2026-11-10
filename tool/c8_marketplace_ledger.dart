// ignore_for_file: avoid_print
/// Snapshot marketplace do vendedor de testes (Corrida 8).
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const sellerId = '980f4fa1-0004-42f9-abca-69f1a9c29588';
  const buyerId = 'd6pnqgz5jvnnbm9x'; // may be device; profile from env
  var buyer = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  if (!isUuid(buyer)) {
    final t = await client.signIn(
      email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    buyer = await client.userIdForAccessToken(t);
  }

  final products = await client.select(
    'products',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 25,
  );
  print('buyer=$buyer');
  final listed = products
      .where((p) => p['list_on_marketplace'] == true)
      .map((p) => {
            'id': p['id'],
            'title': p['title'],
            'price': p['price'],
            'qty': p['quantity'],
            'sold': p['is_sold'],
            'ref': p['ref_code'],
          })
      .toList();
  print('listed=${listed.length}');
  print(const JsonEncoder.withIndent('  ').convert(listed));
}
