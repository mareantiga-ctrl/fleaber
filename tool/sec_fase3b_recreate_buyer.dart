// ignore_for_file: avoid_print
/// Recria conta comprador de lab se o nuke a apagou.
/// dart run tool/sec_fase3b_recreate_buyer.dart
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final email = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final pass = envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final oldId = env['LIVE_OPS_TEST_BUYER_ID'];

  try {
    await sb.signIn(email: email, password: pass);
    print('BUYER_ALREADY_OK email=$email');
    return;
  } catch (_) {
    print('BUYER_MISSING — a recriar $email');
  }

  final id = await sb.createAdminUser(
    email: email,
    password: pass,
    userMetadata: {'full_name': 'Maestro Buyer'},
  );
  print('BUYER_CREATED id=$id (antigo=$oldId)');

  // Profile row
  try {
    await sb.insert('profiles', {
      'id': id,
      'full_name': 'Maestro Buyer',
      'user_type': 'comprador',
    });
  } catch (e) {
    print('profile_insert: $e');
  }

  try {
    await sb.rpc('batata_ensure_wallet', {'p_user_id': id});
  } catch (e) {
    print('wallet: $e');
  }

  // Smoke product qty: +1 se ainda 4 (deriva documentada)
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final products = await sb.select(
    'products',
    filter: 'seller_id=eq.$sellerId&quantity=eq.4',
    limit: 20,
  );
  print('products_qty4=${products.length}');
  for (final p in products) {
    print('  candidate ${p['id']} ${p['title']} qty=${p['quantity']}');
  }

  final envPath = File('tool/live_ops_staging.env');
  var text = await envPath.readAsString();
  if (oldId != null && oldId.isNotEmpty && text.contains(oldId)) {
    text = text.replaceAll(oldId, id);
    await envPath.writeAsString(text);
    print('UPDATED live_ops_staging.env BUYER_ID -> $id');
  } else {
    print('UPDATE manual LIVE_OPS_TEST_BUYER_ID=$id');
  }

  await sb.signIn(email: email, password: pass);
  print('BUYER_LOGIN_OK');
}
