/// Passagem 5b — máquina de estados + regressões históricas (SAT-RT-01, empty PM, phone).
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

typedef Json = Map<String, dynamic>;
final findings = <Json>[];
final probes = <Json>[];
void rec(String n, Object? d) => probes.add({'name': n, 'data': d});
String clip(Object? o, [int n = 280]) {
  final s = o is String ? o : jsonEncode(o);
  return s.length <= n ? s : '${s.substring(0, n)}…';
}
Json? rowOf(Object? b) {
  if (b is List && b.isNotEmpty && b.first is Map) return Map<String, dynamic>.from(b.first as Map);
  if (b is Map && (b['id'] != null || b['status'] != null)) return Map<String, dynamic>.from(b);
  return null;
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final BH = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final SH = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
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
      try {
        parsed = res.body.isEmpty ? null : jsonDecode(res.body);
      } catch (_) {}
      return {'http': res.statusCode, 'body': parsed};
    } finally {
      c.close();
    }
  }

  final p = await r('POST', '$url/rest/v1/products', tok: SH, body: {
    'seller_id': sUid,
    'title': 'SAT27C5 state',
    'price': 6.0,
    'quantity': 8,
    'ref_code': 'C5-${DateTime.now().millisecondsSinceEpoch}',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
    'category': 'Outros',
    'state': 'Bom',
  });
  final pid = rowOf(p['body'])?['id'];
  rec('product', {'http': p['http'], 'id': pid});

  Future<Json?> mkOrder(String pm) async {
    final o = await r('POST', '$url/rest/v1/orders', tok: BH, body: {
      'product_id': pid,
      'buyer_id': bUid,
      'seller_id': sUid,
      'price_total': 6,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': pm,
    });
    return rowOf(o['body']);
  }

  Future<String?> liveStatus(String oid) async {
    final g = await r(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=status,amount_paid_cents,stock_units_applied,payment_method',
      tok: svc,
    );
    final row = rowOf(g['body']);
    rec('live_$oid', row);
    return row?['status']?.toString();
  }

  // SAT-RT-01: buyer jumps reserva_pendente → entregue → concluido (MB WAY)
  final oRt = await mkOrder('Pagamento direto ao vendedor (MB WAY/transf)');
  rec('rt_insert', {'id': oRt?['id'], 'st': oRt?['status']});
  if (oRt?['id'] != null) {
    final oid = '${oRt!['id']}';
    await r('PATCH', '$url/rest/v1/orders?id=eq.$oid', tok: BH, body: {'status': 'entregue'});
    rec('rt_entregue', await liveStatus(oid));
    await r('PATCH', '$url/rest/v1/orders?id=eq.$oid', tok: BH, body: {'status': 'concluido'});
    rec('rt_concluido', await liveStatus(oid));
    await r('PATCH', '$url/rest/v1/orders?id=eq.$oid', tok: BH, body: {'status': 'pago'});
    rec('rt_buyer_pago', await liveStatus(oid));
    final st = await liveStatus(oid);
    if (st == 'entregue' || st == 'concluido' || st == 'pago') {
      findings.add({
        'id': 'SAT27C5-RT01',
        'severity': 'P1',
        'surface': 'ORDERS',
        'impact': 'Buyer saltou reserva_pendente → $st sem seller/captura',
        'after': st,
        'variant': 'SAT-RT-01',
      });
    }
    await r('DELETE', '$url/rest/v1/orders?id=eq.$oid', tok: svc);
  }

  // empty / whitespace PM → seller pago
  for (final pm in ['', ' ', '   ']) {
    final o = await mkOrder(pm);
    if (o?['id'] == null) {
      rec('empty_pm_insert_$pm', {'http': 'fail', 'body': clip(o)});
      continue;
    }
    final oid = '${o!['id']}';
    await r('PATCH', '$url/rest/v1/orders?id=eq.$oid', tok: SH, body: {'status': 'pago'});
    final st = await liveStatus(oid);
    rec('empty_pm_pago_${pm.length}', st);
    if (st == 'pago') {
      findings.add({
        'id': 'SAT27C5-EMPTY-PM',
        'severity': 'P1',
        'surface': 'ORDERS',
        'impact': 'PM vazio/whitespace permitiu seller→pago',
        'after': st,
        'variant': 'len=${pm.length}',
      });
    }
    await r('DELETE', '$url/rest/v1/orders?id=eq.$oid', tok: svc);
  }

  // Seguro canónico: buyer entregue from reserva
  final oSeg = await mkOrder('Pagamento na app (Seguro Fleaber)');
  if (oSeg?['id'] != null) {
    final oid = '${oSeg!['id']}';
    await r('PATCH', '$url/rest/v1/orders?id=eq.$oid', tok: BH, body: {'status': 'entregue'});
    rec('seguro_buyer_entregue', await liveStatus(oid));
    await r('PATCH', '$url/rest/v1/orders?id=eq.$oid', tok: SH, body: {'status': 'concluido'});
    rec('seguro_seller_concluido', await liveStatus(oid));
    await r('DELETE', '$url/rest/v1/orders?id=eq.$oid', tok: svc);
  }

  // phone_verified_at
  final ph = await r('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: BH, body: {
    'phone_verified_at': DateTime.now().toUtc().toIso8601String(),
  });
  rec('phone_patch', {'http': ph['http'], 'body': clip(ph['body'])});
  final phLive = rowOf((await r(
    'GET',
    '$url/rest/v1/profiles?id=eq.$bUid&select=phone_verified_at,user_type',
    tok: svc,
  ))['body']);
  rec('phone_live', phLive);
  if (phLive?['phone_verified_at'] != null) {
    findings.add({
      'id': 'SAT27C5-PHONE',
      'severity': 'P1',
      'surface': 'AUTH',
      'impact': 'Buyer forjou phone_verified_at',
      'after': phLive,
      'variant': 'phone_verified_at',
    });
    await r('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: svc, body: {'phone_verified_at': null});
  }

  // chat user_b hijack
  final chats = await r('GET', '$url/rest/v1/chats?select=id,user_a,user_b&or=(user_a.eq.$bUid,user_b.eq.$bUid)&limit=1', tok: BH);
  rec('chat_sample', clip(chats['body']));
  if (chats['body'] is List && (chats['body'] as List).isNotEmpty) {
    final ch = Map<String, dynamic>.from((chats['body'] as List).first as Map);
    final cid = ch['id'];
    final hij = await r('PATCH', '$url/rest/v1/chats?id=eq.$cid', tok: BH, body: {'user_b': sUid});
    rec('chat_hijack', {'http': hij['http'], 'body': clip(hij['body'])});
  }

  if (pid != null) await r('DELETE', '$url/rest/v1/products?id=eq.$pid', tok: svc);

  File('tool/reports/SAT_CEGA_PASS5_RAW_20260827.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'meta': {'when': DateTime.now().toUtc().toIso8601String()},
      'findings': findings,
      'probes': probes,
    }),
  );
  stdout.writeln('PASS5 FINDINGS=${findings.length}');
  for (final f in findings) {
    stdout.writeln('  ${f['severity']} ${f['id']} — ${f['impact']}');
  }
}
