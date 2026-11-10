/// Passagem 4 — disputa authority + PII colunas live + reserva qty após accept.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

typedef Json = Map<String, dynamic>;
final findings = <Json>[];
final probes = <Json>[];
void rec(String n, Object? d) => probes.add({'name': n, 'data': d});
String clip(Object? o, [int n = 300]) {
  final s = o is String ? o : jsonEncode(o);
  return s.length <= n ? s : '${s.substring(0, n)}…';
}
Json? rowOf(Object? b) {
  if (b is List && b.isNotEmpty && b.first is Map) return Map<String, dynamic>.from(b.first as Map);
  if (b is Map && (b['id'] != null || b['user_type'] != null)) return Map<String, dynamic>.from(b);
  return null;
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final BH = await sb.signIn(email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'), password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'));
  final SH = await sb.signIn(email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'), password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'));
  final bUid = await sb.userIdForAccessToken(BH);
  final sUid = await sb.userIdForAccessToken(SH);
  Future<Json> r(String method, String path, {String? tok, Object? body}) async {
    final t = tok ?? anon;
    final headers = {
      'apikey': t == svc ? svc : anon,
      'Authorization': 'Bearer $t',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
    final uri = Uri.parse(path.startsWith('http') ? path : '$url$path');
    final c = http.Client();
    try {
      final res = switch (method) {
        'GET' => await c.get(uri, headers: headers).timeout(const Duration(seconds: 20)),
        'POST' => await c.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 25)),
        'PATCH' => await c.patch(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20)),
        'DELETE' => await c.delete(uri, headers: headers).timeout(const Duration(seconds: 20)),
        _ => throw StateError(method),
      };
      Object? parsed = res.body;
      try { parsed = res.body.isEmpty ? null : jsonDecode(res.body); } catch (_) {}
      return {'http': res.statusCode, 'body': parsed};
    } finally { c.close(); }
  }

  void hit(String id, String sev, String surface, String impact, Object? after, String variant) {
    findings.add({
      'id': id, 'severity': sev, 'surface': surface, 'impact': impact, 'after': after,
      'variant': variant, 'confidence': 'alta', 'identity': 'jwt', 'request': id,
      'response': after, 'before': null, 'preconditions': variant,
      'false_positive_considered': '200 [] = fechado',
    });
  }

  // profile columns live
  final cols = await r('GET', '$url/rest/v1/profiles?select=*&id=eq.$sUid&limit=1', tok: svc);
  rec('seller_profile_star', {'http': cols['http'], 'keys': rowOf(cols['body'])?.keys.toList(), 'row': clip(cols['body'], 400)});
  final keys = (rowOf(cols['body'])?.keys.toList() ?? []).join(',');
  if (keys.isNotEmpty) {
    final anonP = await r('GET', '$url/rest/v1/profiles?select=$keys&limit=5');
    rec('anon_star', {'http': anonP['http'], 'n': anonP['body'] is List ? (anonP['body'] as List).length : clip(anonP['body'], 120)});
    final bSell = await r('GET', '$url/rest/v1/profiles?select=$keys&id=eq.$sUid', tok: BH);
    rec('buyer_star_seller', {'http': bSell['http'], 'row': clip(bSell['body'], 400)});
  }

  final p = await r('POST', '$url/rest/v1/products', tok: SH, body: {
    'seller_id': sUid, 'title': 'SAT27C4 d', 'price': 7.0, 'quantity': 2,
    'ref_code': 'C4-${DateTime.now().millisecondsSinceEpoch}', 'list_on_marketplace': true,
    'available_for_live': false, 'is_sold': false, 'image_urls': <String>[], 'category': 'Outros', 'state': 'Bom',
  });
  final pid = rowOf(p['body'])?['id'];
  final o = await r('POST', '$url/rest/v1/orders', tok: BH, body: {
    'product_id': pid, 'buyer_id': bUid, 'seller_id': sUid, 'price_total': 7, 'quantity': 1,
    'status': 'reserva_pendente', 'payment_method': 'Pagamento direto ao vendedor (MB WAY/transf)',
  });
  final oid = rowOf(o['body'])?['id'];
  rec('order', {'oid': oid, 'http': o['http']});
  if (oid != null) {
    await r('PATCH', '$url/rest/v1/orders?id=eq.$oid', tok: SH, body: {'status': 'pago'});
    await r('PATCH', '$url/rest/v1/orders?id=eq.$oid', tok: SH, body: {'status': 'enviado'});
    await r('PATCH', '$url/rest/v1/orders?id=eq.$oid', tok: BH, body: {'status': 'concluido'});
    final d = await r('POST', '$url/rest/v1/order_disputes', tok: BH, body: {
      'order_id': oid, 'buyer_id': bUid, 'reason': 'outro', 'description': 'C4',
    });
    final did = rowOf(d['body'])?['id'];
    rec('dispute', {'http': d['http'], 'id': did, 'st': rowOf(d['body'])?['status']});
    if (did != null) {
      for (final patch in [
        {'status': 'resolvida'},
        {'status': 'recusada'},
        {'seller_refund_percent': 100},
        {'current_turn': 'administracao'},
        {'buyer_decision': 'aceitar'},
      ]) {
        final u = await r('PATCH', '$url/rest/v1/order_disputes?id=eq.$did', tok: BH, body: patch);
        rec('buyer_d_${patch.keys.first}', {'http': u['http'], 'body': clip(u['body'], 180)});
        final live = rowOf((await r('GET', '$url/rest/v1/order_disputes?id=eq.$did&select=status,seller_refund_percent,current_turn,buyer_decision', tok: svc))['body']);
        rec('live_d_${patch.keys.first}', live);
        if (patch.containsKey('status') && '${live?['status']}' == patch['status']) {
          hit('SAT27C4-DSP-ST-${patch['status']}', 'P1', 'DISPUTE', 'Buyer definiu status=${patch['status']}', live, '${patch['status']}');
        }
        if (patch.containsKey('seller_refund_percent') && live?['seller_refund_percent'] != null && (live!['seller_refund_percent'] as num) >= 100) {
          hit('SAT27C4-DSP-PCT', 'P1', 'DISPUTE', 'Buyer definiu seller_refund_percent=100', live, 'percent');
        }
        if (patch.containsKey('current_turn') && '${live?['current_turn']}' == 'administracao') {
          hit('SAT27C4-DSP-TURN', 'P1', 'DISPUTE', 'Buyer pôs current_turn=administracao', live, 'turn');
        }
      }
      // seller patches
      final sU = await r('PATCH', '$url/rest/v1/order_disputes?id=eq.$did', tok: SH, body: {'status': 'recusada'});
      rec('seller_refuse', {'http': sU['http'], 'body': clip(sU['body'])});
      await r('DELETE', '$url/rest/v1/order_disputes?id=eq.$did', tok: svc);
    }
    await r('DELETE', '$url/rest/v1/orders?id=eq.$oid', tok: svc);
  }
  if (pid != null) await r('DELETE', '$url/rest/v1/products?id=eq.$pid', tok: svc);

  // leftover res from pass3
  await r('DELETE', '$url/rest/v1/live_reservation_requests?buyer_id=eq.$bUid&requested_qty=eq.9&status=eq.accepted', tok: svc);

  File('tool/reports/SAT_CEGA_PASS4_RAW_20260827.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'meta': {'when': DateTime.now().toUtc().toIso8601String()},
      'findings': findings,
      'probes': probes,
    }),
  );
  stdout.writeln('PASS4 FINDINGS=${findings.length}');
  for (final f in findings) {
    stdout.writeln('  ${f['severity']} ${f['id']} — ${f['impact']}');
  }
}
