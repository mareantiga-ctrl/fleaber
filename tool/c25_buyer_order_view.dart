// ignore_for_file: avoid_print
import 'dart:convert';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL')),
    anonKey: envRequire(e, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final token = await c.signIn(
    email: envRequire(e, 'MAESTRO_BUYER_EMAIL').isNotEmpty
        ? envRequire(e, 'MAESTRO_BUYER_EMAIL')
        : 'axinoqua@axinoquaa.pt',
    password: envRequire(e, 'MAESTRO_BUYER_PASSWORD').isNotEmpty
        ? envRequire(e, 'MAESTRO_BUYER_PASSWORD')
        : 'testeteste',
  );
  final oid = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
  final rows = await c.selectAsUser(
    'orders',
    accessToken: token,
    filter: 'id=eq.$oid',
    limit: 1,
  );
  final reviews = await c.selectAsUser(
    'reviews',
    accessToken: token,
    filter: 'order_id=eq.$oid',
    limit: 5,
  );
  print(jsonEncode({
    'buyer_sees_order': rows.isEmpty ? null : rows.first,
    'buyer_sees_reviews': reviews.length,
  }));
}
