// ignore_for_file: avoid_print
/// C27 — estado reserva + encomendas pós-pagamento.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

const _liveId = '4901d8c0-49db-4471-a2f8-c7154e6d5e26';
const _buyerId = '7848848c-92df-4341-ad2a-7a5c24f1c250';
const _reqB = '2eafca8c-c9d9-46f4-8059-7fc87f7365dd';
const _reqA = '40250c32-1ba9-41d6-a026-952255b93bf3';
const _out = 'tool/reports/battery_c27_2026-08-23/bd/c27_audit_pay_state.json';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final reqs = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$_liveId&order=created_at.desc',
    limit: 20,
  );
  final orders = await client.select(
    'orders',
    filter: 'buyer_id=eq.$_buyerId&order=created_at.desc',
    limit: 12,
  );
  final live =
      (await client.select('lives', filter: 'id=eq.$_liveId', limit: 1)).first;
  final items = await client.select(
    'live_items',
    filter: 'live_id=eq.$_liveId',
    limit: 20,
  );

  Map<String, dynamic>? findReq(String id) {
    for (final r in reqs) {
      if (r['id']?.toString() == id) return r;
    }
    return null;
  }

  final a = findReq(_reqA);
  final b = findReq(_reqB);

  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'live': {
      'id': live['id'],
      'status': live['status'],
      'is_active': live['is_active'],
    },
    'app253_expired': {
      'id': a?['id'],
      'status': a?['status'],
      'live_item_id': a?['live_item_id'],
    },
    'app254_target': {
      'id': b?['id'],
      'status': b?['status'],
      'order_id': b?['order_id'],
      'live_item_id': b?['live_item_id'],
    },
    'items': items
        .map((i) => {
              'id': i['id'],
              'title': i['title'],
              'status': i['status'],
              'is_active': i['is_active'],
            })
        .toList(),
    'orders_recent': orders
        .map((o) => {
              'id': o['id'],
              'status': o['status'],
              'payment_method': o['payment_method'],
              'live_id': o['live_id'],
              'live_reservation_request_id': o['live_reservation_request_id'],
              'price_total': o['price_total'] ?? o['total_price'] ?? o['total'],
              'created_at': o['created_at'],
            })
        .toList(),
  };

  File(_out)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
}
