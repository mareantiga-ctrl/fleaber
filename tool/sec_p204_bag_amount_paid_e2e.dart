// ignore_for_file: avoid_print
/// P2-04 E2E — bag multi-line amount_paid_cents proporcional (Stripe TEST).
/// Staging only. Secret Stripe nunca no Dart — harness Edge + sk_test_.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> _probe(
  String url,
  String svc,
  String e2e,
  Map<String, dynamic> body,
) async {
  final r = await http.post(
    Uri.parse('$url/functions/v1/sec-fase2-e2e-oversell'),
    headers: {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
      if (e2e.length >= 16) 'x-fleaber-e2e-secret': e2e,
    },
    body: jsonEncode(body),
  );
  Map<String, dynamic> parsed = {};
  try {
    parsed = jsonDecode(r.body) as Map<String, dynamic>;
  } catch (_) {
    parsed = {'raw': r.body};
  }
  return {
    'http': r.statusCode,
    ...parsed,
  };
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: só staging');
    exit(2);
  }
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final e2e = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final buyer = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final seller = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');

  stdout.writeln('=== P2-04 bag amount_paid E2E (Stripe TEST) ===');
  final res = await _probe(url, svc, e2e, {
    'probe': 'setup_paid_bag',
    'buyer_id': buyer,
    'seller_id': seller,
  });
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(res));

  final ok = res['http'] == 200 && res['ok'] == true;
  final checks = (res['checks'] as Map?) ?? {};
  final paidA = (res['paid_a'] as num?)?.toInt() ?? 0;
  final paidB = (res['paid_b'] as num?)?.toInt() ?? 0;
  final piAmt = (res['pi_amount_cents'] as num?)?.toInt() ?? 0;

  final evidence = <String, dynamic>{
    'test': 'P2-04_bag_amount_paid_proportional',
    'at': DateTime.now().toUtc().toIso8601String(),
    'staging_ref': 'fxdknzrqjenzqcvnwqqq',
    'ok': ok,
    'payment_intent_id': res['payment_intent_id'],
    'pi_amount_cents': piAmt,
    'share_a_cents': res['share_a_cents'],
    'share_b_cents': res['share_b_cents'],
    'expected_paid_a': res['expected_paid_a'],
    'expected_paid_b': res['expected_paid_b'],
    'paid_a': paidA,
    'paid_b': paidB,
    'order_a_id': res['order_a_id'],
    'order_b_id': res['order_b_id'],
    'product_a_id': res['product_a_id'],
    'product_b_id': res['product_b_id'],
    'checks': checks,
    'settle_http': res['settle_http'],
    'invariant_before_bug':
        'cada linha recebia amount_paid_cents = PI completo ($piAmt)',
    'invariant_after_fix':
        'linha A=$paidA + linha B=$paidB == PI=$piAmt; nenhuma linha = PI completo',
  };

  final outPath = 'tool/reports/HARDENING_P2_04_BAG_AMOUNT_PAID_E2E.json';
  await File(outPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );
  stdout.writeln('evidence -> $outPath');

  // Cleanup best-effort (não falha o teste se cleanup falhar)
  final pa = (res['product_a_id'] ?? '').toString();
  final pb = (res['product_b_id'] ?? '').toString();
  if (pa.isNotEmpty || pb.isNotEmpty) {
    final clean = await _probe(url, svc, e2e, {
      'probe': 'cleanup_bag_fixture',
      'product_a_id': pa,
      'product_b_id': pb,
    });
    stdout.writeln('cleanup http=${clean['http']} ok=${clean['ok']}');
  }

  if (!ok) {
    stderr.writeln('FAIL P2-04: checks=$checks');
    exit(1);
  }
  stdout.writeln('PASS P2-04 bag multi-line amount_paid_cents');
  exit(0);
}
