import 'dart:convert';
import 'dart:io';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final seed = jsonDecode(File('tool/reports/phase3_qa_seed.json').readAsStringSync()) as Map<String, dynamic>;
  final keep = <String>{
    for (final k in [
      'guaranteed_request_id',
      'pending_request_id',
      'unguaranteed_request_id',
      'unavailable_request_id',
    ])
      if ((seed[k] ?? '').toString().isNotEmpty) seed[k].toString(),
  };
  final buyerId = seed['buyer_id'];
  final sellerId = seed['seller_id'];
  final buyerToken = await client.signIn(
    email: seed['buyer_email'] as String,
    password: seed['buyer_password'] as String,
  );
  final bag = await client.rpc(
    'batata_commerce_seller_bag',
    {'p_seller_id': sellerId},
    accessToken: buyerToken,
  ) as Map;
  final lines = ((bag['lrr_lines'] as List?) ?? [])
      .cast<dynamic>()
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  for (final m in lines) {
    final id = m['id']?.toString() ?? '';
    if (id.isEmpty || keep.contains(id)) continue;
    await client.patch('live_reservation_requests', 'id=eq.$id', {
      'status': 'rejected',
      'notes': 'bag_removed',
    });
    print('cancelled leftover $id');
  }
  // Close old marketplace noise except latest seed order
  final keepMp = seed['marketplace_order_id']?.toString();
  final mp = ((bag['marketplace_adapter_lines'] as List?) ?? [])
      .cast<dynamic>()
      .map((e) => Map<String, dynamic>.from(e as Map));
  for (final m in mp) {
    final id = m['id']?.toString() ?? '';
    if (id.isEmpty || id == keepMp) continue;
    await client.patch('orders', 'id=eq.$id', {
      'status': 'cancelado',
      'is_reservation': false,
    });
    print('closed mp $id');
  }
  print('done keep=$keep mp=$keepMp');
}
