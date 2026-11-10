// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final orderId = args.isNotEmpty
      ? args[0]
      : 'a8ba0404-0d98-413e-8a6f-a9321b651640';
  final sessionId = args.length > 1
      ? args[1]
      : 'cs_test_a1ETewdv38Zn1YYMSQ1mw4WQYKmxK6wBqieoaDRlfGFeaBvYR30ktoco9D';

  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
  };
  final o1 = await http.get(
    Uri.parse(
      '$url/rest/v1/orders?select=id,status,stripe_refund_id,stock_units_applied,amount_paid_cents,stripe_checkout_session_id&id=eq.$orderId',
    ),
    headers: SVC,
  );
  print('ORDER_BEFORE_REPLAY: ${o1.body}');

  final settleUrl =
      '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=$sessionId';
  final h = {'apikey': anon, 'Authorization': 'Bearer $anon'};
  final r1 = await http.get(Uri.parse(settleUrl), headers: h);
  print('SETTLE1 ${r1.statusCode} ${r1.body.length > 300 ? r1.body.substring(0, 300) : r1.body}');
  final r2 = await http.get(Uri.parse(settleUrl), headers: h);
  print('SETTLE2 ${r2.statusCode} ${r2.body.length > 300 ? r2.body.substring(0, 300) : r2.body}');

  final o2 = await http.get(
    Uri.parse(
      '$url/rest/v1/orders?select=id,status,stripe_refund_id,stock_units_applied,amount_paid_cents&id=eq.$orderId',
    ),
    headers: SVC,
  );
  print('ORDER_AFTER_REPLAY: ${o2.body}');

  final list = jsonDecode(o2.body) as List;
  final row = list.isNotEmpty ? list.first as Map : {};
  final st = '${row['status'] ?? ''}'.toLowerCase();
  final ref = '${row['stripe_refund_id'] ?? ''}'.trim();
  final ok = st == 'pago' &&
      ref.isEmpty &&
      !r2.body.contains('reembolsado automaticamente') &&
      !r2.body.contains('Artigo esgotado');
  print(ok ? 'PASS P0_settle_replay' : 'FAIL P0_settle_replay');
  exit(ok ? 0 : 1);
}
