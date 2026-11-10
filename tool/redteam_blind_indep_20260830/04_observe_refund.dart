// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../live_ops_staging_client.dart';

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  Future<http.Response> get(String path, {bool service = true, String? token}) =>
      http.get(Uri.parse('$url$path'), headers: {
        'apikey': service ? svc : anon,
        'Authorization': 'Bearer ${service ? svc : token}',
      });
  final paid = await get(
      '/rest/v1/orders?id=eq.6a3268c5-44ea-4a9e-b87e-b4ca13887131&select=id,status,stripe_refund_id,amount_paid_cents,stock_units_applied,wallet_refund_processed_at');
  final wb = await get('/rest/v1/wallets?id=eq.$buyerId&select=balance');
  final ws = await get('/rest/v1/wallets?id=eq.$sellerId&select=balance');
  final retry = await http.post(
    Uri.parse('$url/functions/v1/refund-order'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $sellerTok',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'order_id': '6a3268c5-44ea-4a9e-b87e-b4ca13887131'}),
  );
  final v0 = await get(
      '/rest/v1/products?id=eq.f85ded7d-c00a-4e70-8931-77a81d309bd7&select=id,price,quantity');
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'order': jsonDecode(paid.body),
    'wallet_buyer': jsonDecode(wb.body),
    'wallet_seller': jsonDecode(ws.body),
    'refund_retry': {'status': retry.statusCode, 'body': retry.body},
    'v0_product': jsonDecode(v0.body),
  }));
}
