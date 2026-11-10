// ignore_for_file: avoid_print
/// Block B1 — prove CHECK accepts/rejects `aguarda_pagamento` on staging.
/// dart run tool/block_b1_aguarda_check_probe.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String url,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'POST'
      ? await http.post(Uri.parse(url), headers: h, body: jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(url), headers: h, body: jsonEncode(body))
          : method == 'DELETE'
              ? await http.delete(Uri.parse(url), headers: h)
              : await http.get(Uri.parse(url), headers: h);
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

Map<String, dynamic>? row(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  return null;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT staging');
    exit(2);
  }
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'B1 check ${DateTime.now().toUtc().toIso8601String()}',
    'price': 1,
    'quantity': 1,
    'list_on_marketplace': false,
    'image_urls': <String>[],
  });
  final productId = row(prod['body'])?['id']?.toString();
  if (productId == null) {
    stderr.writeln('product fail ${prod['body']}');
    exit(1);
  }

  // Insert as reserva_pendente then PATCH to aguarda_pagamento (service_role).
  final ins = await req('POST', '$url/rest/v1/orders', SVC, {
    'product_id': productId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'price_total': 1,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    'shipping_method': 'Entrega em Mão (€0.00)',
    'is_reservation': true,
  });
  final orderId = row(ins['body'])?['id']?.toString();
  if (orderId == null) {
    stderr.writeln('order insert fail ${ins['body']}');
    exit(1);
  }

  final patch = await req(
    'PATCH',
    '$url/rest/v1/orders?id=eq.$orderId',
    SVC,
    {'status': 'aguarda_pagamento'},
  );
  final after = await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$orderId&select=id,status',
    SVC,
  );
  final st = row(after['body'])?['status']?.toString();
  final accepted = st == 'aguarda_pagamento';
  final checkViolation = msgContains(patch['body'], '23514') ||
      msgContains(patch['body'], 'orders_status_batata_check') ||
      msgContains(patch['body'], 'check constraint');

  final out = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'order_id': orderId,
    'product_id': productId,
    'patch_http': patch['http'],
    'patch_body': patch['body'],
    'status_after': st,
    'aguarda_pagamento_accepted': accepted,
    'check_violation_detected': checkViolation,
    'verdict': accepted
        ? 'CHECK_ALLOWS_aguarda_pagamento'
        : (checkViolation
            ? 'CHECK_REJECTS_aguarda_pagamento'
            : 'UNKNOWN_REJECT'),
  };

  final dir = Directory('tool/reports/block_b_fix_2026-09-27/evidence');
  await dir.create(recursive: true);
  final path = '${dir.path}/b1_aguarda_check_probe.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(const JsonEncoder.withIndent('  ').convert(out));
  print('evidence -> $path');

  // Cleanup: cancel order so it doesn't pollute.
  await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', SVC, {
    'status': 'cancelado',
  });

  exit(0);
}

bool msgContains(dynamic body, String needle) {
  return jsonEncode(body).toLowerCase().contains(needle.toLowerCase());
}
