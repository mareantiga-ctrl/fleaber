// dart run tool/redteam_blind_b_20260829T1755_observe.dart
// service_role: observação de fixtures (não actor de exploit)
import 'dart:convert';
import 'dart:io';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const ids = [
    '3da12d4e-a3b4-43c5-a435-a79ea3b985f7',
    'bfbfbb7b-1a2a-4ba2-a369-1d1b1838c0c6',
    '3d20acd2-ad9e-4024-9d7c-d1f89f79e3c0',
    '2cc6d6f1-6825-4fc5-a170-2e0bee38a54e',
    'd8abac50-bbc1-4160-8cab-16363382b794',
    '1e80fe5b-c96b-4c2c-8741-ad0027013959',
  ];
  final out = <String, Object?>{};
  for (final id in ids) {
    final orders = await client.select(
      'orders',
      filter: 'id=eq.$id',
      limit: 1,
    );
    if (orders.isNotEmpty) {
      final o = orders.first;
      out['order_$id'] = {
        'status': o['status'],
        'price_total': o['price_total'],
        'contract_unit_cents': o['contract_unit_cents'],
        'amount_paid_cents': o['amount_paid_cents'],
        'stock_units_applied': o['stock_units_applied'],
        'stripe_checkout_session_id': o['stripe_checkout_session_id'],
        'product_offer_id': o['product_offer_id'],
        'quantity': o['quantity'],
      };
    } else {
      final products = await client.select(
        'products',
        filter: 'id=eq.$id',
        limit: 1,
      );
      out[products.isEmpty ? 'missing_$id' : 'product_$id'] =
          products.isEmpty ? 'gone' : products.first;
    }
  }
  File('tool/redteam_blind_b_20260829T1755_observe.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
