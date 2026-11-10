// ignore_for_file: avoid_print
/// Aplica seed demo UX H-v1 em staging + auditoria.
/// Uso: dart run tool/hub_h_v1_staging_setup.dart
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _demoHandle = 'fleahub-demo-ux';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerId =
      env['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '980f4fa1-0004-42f9-abca-69f1a9c29588';
  final buyerId =
      env['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '7848848c-92df-4341-ad2a-7a5c24f1c250';

  print('H-v1 staging setup — seed demo UX');
  print('Seller: $sellerId');
  print('---');

  Map<String, dynamic>? seedResult;
  try {
    final raw = await client.rpc('batata_staging_h_v1_ux_demo_seed', {
      'p_seller_id': sellerId,
      'p_buyer_id': buyerId,
    });
    seedResult = raw is Map ? Map<String, dynamic>.from(raw) : null;
    if (seedResult?['ok'] != true) {
      print('FAIL seed: $seedResult');
      exit(1);
    }
    print('OK  batata_staging_h_v1_ux_demo_seed');
    print('    handle=${seedResult!['handle']} followers=${seedResult['follower_count']}');
  } catch (e) {
    print('FAIL batata_staging_h_v1_ux_demo_seed: $e');
    exit(1);
  }

  final resolve = await client.rpc('batata_resolve_handle', {
    'p_handle': _demoHandle,
  });
  print('resolve: $resolve');
  if (resolve is! Map || resolve['found'] != true) exit(1);

  final hubRows = await client.select(
    'hub_profiles_public',
    filter: 'handle=eq.$_demoHandle',
    limit: 1,
  );
  if (hubRows.isEmpty) {
    print('FAIL hub_profiles_public vazio');
    exit(1);
  }
  final hub = hubRows.first;
  print('hub_profiles_public:');
  print('  full_name=${hub['full_name']}');
  print('  follower_count=${hub['follower_count']}');
  print('  hub_bio=${(hub['hub_bio']?.toString() ?? '').substring(0, (hub['hub_bio']?.toString().length ?? 0).clamp(0, 60))}...');

  if (!hub.containsKey('follower_count')) {
    print('FAIL follower_count em falta na view');
    exit(1);
  }

  final lives = await client.select(
    'hub_lives_public',
    filter: 'seller_handle=eq.$_demoHandle',
    limit: 20,
  );
  final products = await client.select(
    'hub_products_public',
    filter: 'seller_handle=eq.$_demoHandle&is_sold=eq.false',
    limit: 20,
  );
  final reviews = await client.select(
    'hub_reviews_public',
    filter: 'target_id=eq.${hub['id']}',
    limit: 20,
  );

  print('lives=${lives.length} products=${products.length} reviews=${reviews.length}');

  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final dir = 'tool/reports/h_v1_staging_setup_$stamp';
  Directory(dir).createSync(recursive: true);
  File('$dir/setup.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'handle': _demoHandle,
      'seed': seedResult,
      'resolve': resolve,
      'hub_profile': hub,
      'counts': {
        'lives': lives.length,
        'products': products.length,
        'reviews': reviews.length,
      },
    }),
  );
  File('tool/reports/h_v1_staging_setup_LATEST.txt').writeAsStringSync('$dir\n');
  print('Report: $dir/setup.json');
  print('URL path: /$_demoHandle');
}
