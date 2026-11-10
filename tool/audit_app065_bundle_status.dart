// ignore_for_file: avoid_print
/// APP-065 — verifica frase agregada «Artigo Enviado» para conjuntos enviados na BD.
library;

import 'dart:convert';
import 'dart:io';

import 'package:fleaber/backend/supabase/supabase.dart';
import 'package:fleaber/bundle_order_status_util.dart';
import 'package:fleaber/order_cancel_eligibility.dart';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  const buyerEmail = 'axinoqua@axinoquaa.pt';
  final token = await client.signIn(
    email: buyerEmail,
    password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final buyerId = await client.userIdForAccessToken(token);

  final raw = await client.select(
    'orders',
    filter: 'buyer_id=eq.$buyerId&order=created_at.desc',
    limit: 200,
  );

  final byBundle = <String, List<Map<String, dynamic>>>{};
  for (final o in raw) {
    final bid = o['bundle_id']?.toString().trim() ?? '';
    if (bid.isEmpty) continue;
    final st = normalizeOrderStatusKey(o['status']?.toString());
    if (st != 'enviado' && st != 'concluido') continue;
    byBundle.putIfAbsent(bid, () => []).add(o);
  }

  var pass = 0;
  var fail = 0;
  final samples = <Map<String, dynamic>>[];

  for (final entry in byBundle.entries) {
    if (entry.value.length < 2) continue;
    final orders = entry.value.map((m) => OrdersRow(m)).toList();
    final allShipped = orders.every((o) {
      final st = normalizeOrderStatusKey(o.status);
      return st == 'enviado' || st == 'concluido';
    });
    if (!allShipped) continue;

    final phrase = bundleGroupAggregatedStatusPhrase(orders);
    final ok = phrase == 'Artigo Enviado' || phrase == 'Concluída';
    if (ok) {
      pass++;
    } else {
      fail++;
    }
    if (samples.length < 5) {
      samples.add({
        'bundle_id': entry.key,
        'count': orders.length,
        'phrase': phrase,
        'ok': ok,
        'statuses': orders.map((o) => o.status).toList(),
      });
    }
  }

  final out = {
    'buyer_id': buyerId,
    'bundles_shipped_checked': pass + fail,
    'pass': pass,
    'fail': fail,
    'result': fail == 0 && pass > 0 ? 'PASS' : (pass == 0 ? 'SKIP' : 'FAIL'),
    'samples': samples,
  };
  print(const JsonEncoder.withIndent('  ').convert(out));
  if (out['result'] == 'FAIL') exit(1);
}
