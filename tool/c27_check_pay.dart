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
  const liveId = '4901d8c0-49db-4471-a2f8-c7154e6d5e26';
  const buyerId = '7848848c-92df-4341-ad2a-7a5c24f1c250';
  const reqId = '2eafca8c-c9d9-46f4-8059-7fc87f7365dd';
  final req = (await client.select('live_reservation_requests', filter: 'id=eq.\', limit: 1)).first;
  final orders = await client.select('orders', filter: 'buyer_id=eq.\&order=created_at.desc', limit: 8);
  final slim = orders.map((o) => {
    'id': o['id'],
    'status': o['status'],
    'payment_method': o['payment_method'],
    'price_total': o['price_total'] ?? o['total'],
    'live_id': o['live_id'],
    'created_at': o['created_at'],
    'title': o['product_title'] ?? o['title'],
  }).toList();
  print(jsonEncode({
    'reservation': {
      'id': req['id'],
      'status': req['status'],
      'order_id': req['order_id'],
    },
    'orders': slim,
  }));
  File('tool/reports/battery_c27_2026-08-23/bd/c27_orders_after_pay.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'reservation': req,
      'orders': orders,
    }));
}
