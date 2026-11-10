// ignore_for_file: avoid_print
/// Última encomenda comprador C27 + eventos Stripe recentes.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

void main() async {
  const buyer = '7848848c-92df-4341-ad2a-7a5c24f1c250';
  const seller = '980f4fa1-0004-42f9-abca-69f1a9c29588';

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$seller&order=created_at.desc',
    limit: 5,
  );
  final orders = await client.select(
    'orders',
    filter: 'buyer_id=eq.$buyer&order=created_at.desc',
    limit: 8,
  );
  final latest = orders.isEmpty ? null : orders.first;
  final oid = latest?['id']?.toString() ?? '';

  Map<String, dynamic> wallet = const {};
  List<Map<String, dynamic>> events = const [];
  List<Map<String, dynamic>> reservations = const [];
  List<Map<String, dynamic>> liveItems = const [];

  if (oid.isNotEmpty) {
    final w = await client.select(
      'wallet_transactions',
      filter: 'order_id=eq.$oid&type=eq.compra',
      limit: 3,
    );
    if (w.isNotEmpty) wallet = w.first;
    events = await client.select(
      'stripe_checkout_events',
      filter: 'order_id=eq.$oid&order=created_at.desc',
      limit: 15,
    );
  }

  final liveId = latest?['live_id']?.toString() ?? '';
  if (liveId.isNotEmpty) {
    reservations = await client.select(
      'live_reservation_requests',
      filter: 'live_id=eq.$liveId&order=created_at.desc',
      limit: 15,
    );
    liveItems = await client.select(
      'live_items',
      filter: 'live_id=eq.$liveId&order=created_at.asc',
      limit: 80,
    );
  }

  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'lives': lives
        .map((l) => {
              'id': l['id'],
              'status': l['status'],
              'is_active': l['is_active'],
              'title': l['title'],
            })
        .toList(),
    'latest_order': latest,
    'wallet_compra': wallet,
    'stripe_events': events,
    'reservations': reservations,
    'live_items_count': liveItems.length,
    'live_items_titles': liveItems
        .map((i) => {
              'title': i['title'],
              'active': i['is_active'],
              'status': i['status'],
            })
        .toList(),
  };

  const path = 'tool/reports/battery_c27_2026-08-23/bd/c27_post_user_pay.json';
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
}
