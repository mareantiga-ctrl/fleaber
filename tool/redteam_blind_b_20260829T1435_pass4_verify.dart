// ignore_for_file: avoid_print
/// Pass 4 — anti-FP nas 3 hipóteses pass3 + list public chat_uploads.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';
import 'package:http/http.dart' as http;

void main() async {
  final env = loadLiveOpsStagingEnv();
  final base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: service,
  );

  final prod = await sb.select(
    'products',
    filter: 'id=eq.ac52aee5-2001-4630-bbc0-9d5aa6a2ffbf',
    limit: 1,
  );
  final ord = await sb.select(
    'orders',
    filter: 'id=eq.d5a1d9d2-9d58-4796-8297-8d023a58aa0a',
    limit: 1,
  );
  final res = await sb.select(
    'live_reservation_requests',
    filter: 'id=eq.103ec3f5-ed75-4c68-b31f-79a2c2d86c03',
    limit: 1,
  );
  final rev = await sb.select(
    'reviews',
    filter: 'id=eq.e62430c0-04cc-4448-ad21-09d4adba0d39',
    limit: 1,
  );
  final colOrd = await sb.select(
    'orders',
    filter: 'id=eq.99b43181-4a1f-42d1-809c-96708608b6fb',
    limit: 1,
  );

  final listUploads = await http.post(
    Uri.parse('$base/storage/v1/object/list/chat_media'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'prefix': 'chat_uploads/', 'limit': 20}),
  );

  final out = {
    'product': prod.isEmpty
        ? null
        : {
            'id': prod.first['id'],
            'quantity': prod.first['quantity'],
            'title': prod.first['title'],
          },
    'dual_order': ord.isEmpty
        ? null
        : {
            'status': ord.first['status'],
            'stock_units_applied': ord.first['stock_units_applied'],
            'payment_method': ord.first['payment_method'],
            'amount_paid_cents': ord.first['amount_paid_cents'],
          },
    'reservation': res.isEmpty
        ? null
        : {
            'status': res.first['status'],
            'requested_qty': res.first['requested_qty'],
          },
    'review': rev.isEmpty
        ? null
        : {
            'stars': rev.first['stars'],
            'purchase_verified': rev.first['purchase_verified'],
            'order_id': rev.first['order_id'],
          },
    'collusion_order': colOrd.isEmpty
        ? null
        : {
            'status': colOrd.first['status'],
            'stock_units_applied': colOrd.first['stock_units_applied'],
            'amount_paid_cents': colOrd.first['amount_paid_cents'],
          },
    'anon_list_chat_uploads': {
      'http': listUploads.statusCode,
      'body': listUploads.body.length > 500
          ? '${listUploads.body.substring(0, 500)}…'
          : listUploads.body,
    },
  };
  File('tool/reports/redteam_blind_b_20260829T1435/pass4_verify.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(const JsonEncoder.withIndent('  ').convert(out));
}
