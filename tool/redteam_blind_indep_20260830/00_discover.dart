// ignore_for_file: avoid_print
/// Auditoria cega independente 2026-08-30 — PASS 1 descoberta LIVE.
/// Não usa service_role como atacante. service_role só para observação no 99_observe.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

void main() async {
  final outDir = Directory('tool/redteam_blind_indep_20260830/out');
  outDir.createSync(recursive: true);

  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: not staging');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final buyerEmail = envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPass = envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final sellerEmail = envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPass = envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');

  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  print('signin...');
  final buyerTok = await sb.signIn(email: buyerEmail, password: buyerPass);
  final sellerTok = await sb.signIn(email: sellerEmail, password: sellerPass);
  final buyerUid = await sb.userIdForAccessToken(buyerTok);
  final sellerUid = await sb.userIdForAccessToken(sellerTok);
  print('buyer=$buyerUid seller=$sellerUid');
  if (buyerUid != buyerId || sellerUid != sellerId) {
    print('WARN id mismatch env vs jwt');
  }

  Future<Map<String, dynamic>> rest({
    required String method,
    required String path,
    String? token,
    Object? body,
    Map<String, String>? extraHeaders,
  }) async {
    final headers = <String, String>{
      'apikey': anon,
      'Authorization': 'Bearer ${token ?? anon}',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
      ...?extraHeaders,
    };
    final uri = Uri.parse('$url$path');
    late http.Response r;
    switch (method) {
      case 'GET':
        r = await http.get(uri, headers: headers);
        break;
      case 'POST':
        r = await http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
        break;
      case 'PATCH':
        r = await http.patch(uri, headers: headers, body: body == null ? null : jsonEncode(body));
        break;
      case 'DELETE':
        r = await http.delete(uri, headers: headers);
        break;
      case 'HEAD':
        r = await http.head(uri, headers: headers);
        break;
      default:
        throw StateError(method);
    }
    return {
      'method': method,
      'path': path,
      'status': r.statusCode,
      'body': r.body.length > 2500 ? '${r.body.substring(0, 2500)}…' : r.body,
      'content_range': r.headers['content-range'],
    };
  }

  Future<Map<String, dynamic>> openApi(String? token) async {
    final r = await http.get(
      Uri.parse('$url/rest/v1/'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer ${token ?? anon}',
        'Accept': 'application/openapi+json',
      },
    );
    final tables = <String>[];
    final rpcs = <String>[];
    if (r.statusCode == 200 && r.body.isNotEmpty) {
      try {
        final spec = jsonDecode(r.body);
        if (spec is Map && spec['paths'] is Map) {
          for (final key in (spec['paths'] as Map).keys) {
            final p = key.toString();
            if (!p.startsWith('/')) continue;
            if (p.startsWith('/rpc/')) {
              rpcs.add(p.substring(5));
            } else if (!p.contains('{')) {
              tables.add(p.substring(1));
            }
          }
        }
      } catch (e) {
        return {'status': r.statusCode, 'parse_error': e.toString()};
      }
    }
    tables.sort();
    rpcs.sort();
    return {
      'status': r.statusCode,
      'tables': tables,
      'rpcs': rpcs,
      'table_count': tables.length,
      'rpc_count': rpcs.length,
    };
  }

  print('openapi...');
  final anonSpec = await openApi(null);
  final buyerSpec = await openApi(buyerTok);
  File('tool/redteam_blind_indep_20260830/out/openapi_anon.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(anonSpec));
  File('tool/redteam_blind_indep_20260830/out/openapi_buyer.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(buyerSpec));
  print('anon tables=${anonSpec['table_count']} rpcs=${anonSpec['rpc_count']}');
  print('buyer tables=${buyerSpec['table_count']} rpcs=${buyerSpec['rpc_count']}');

  final tables = <String>{
    ...((anonSpec['tables'] as List?)?.cast<String>() ?? const []),
    ...((buyerSpec['tables'] as List?)?.cast<String>() ?? const []),
  }.toList()
    ..sort();
  final rpcs = <String>{
    ...((anonSpec['rpcs'] as List?)?.cast<String>() ?? const []),
    ...((buyerSpec['rpcs'] as List?)?.cast<String>() ?? const []),
  }.toList()
    ..sort();

  const sensitiveColsHint = [
    'wallets',
    'wallet_transactions',
    'wallet_payout_ledger',
    'orders',
    'products',
    'lives',
    'live_items',
    'live_reservation_requests',
    'live_raffles',
    'live_raffle_winners',
    'live_tips',
    'reviews',
    'chats',
    'chat_messages',
    'messages',
    'disputes',
    'order_disputes',
    'storage_objects',
    'profiles',
    'product_offers',
    'seller_bundle_discounts',
    'stripe_checkout_events',
    'ps_device_tokens',
    'ps_pairing_codes',
    'fleaber_commissions',
    'live_messages',
    'notifications',
    'follows',
    'favorites',
    'banking_details',
    'seller_banking',
    'iban',
  ];

  final matrix = <Map<String, dynamic>>[];

  Future<void> probeTable(String table, String who, String? tok) async {
    final get = await rest(
      method: 'GET',
      path: '/rest/v1/$table?select=*&limit=3',
      token: tok,
    );
    final head = await rest(
      method: 'GET',
      path: '/rest/v1/$table?select=id&limit=1',
      token: tok,
      extraHeaders: {'Prefer': 'count=exact', 'Range': '0-0'},
    );
    matrix.add({
      'surface': table,
      'attack': 'SELECT * limit 3',
      'identity': who,
      'result': get['status'],
      'body_len': (get['body'] as String).length,
      'preview': (get['body'] as String).length > 400
          ? (get['body'] as String).substring(0, 400)
          : get['body'],
      'count_hint': head['content_range'] ?? head['status'],
    });
  }

  print('select sweep...');
  final probeTables = <String>{
    ...tables.where((t) => sensitiveColsHint.any((s) => t.contains(s) || s.contains(t))),
    ...sensitiveColsHint.where(tables.contains),
    'wallets',
    'orders',
    'products',
    'lives',
    'profiles',
  };
  for (final t in probeTables) {
    await probeTable(t, 'anon', null);
    await probeTable(t, 'buyer', buyerTok);
    await probeTable(t, 'seller', sellerTok);
  }

  File('tool/redteam_blind_indep_20260830/out/select_matrix.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(matrix));

  print('rpc sweep (empty body)...');
  final rpcHits = <Map<String, dynamic>>[];
  final interesting = rpcs.where((n) {
    final l = n.toLowerCase();
    return l.contains('wallet') ||
        l.contains('payout') ||
        l.contains('refund') ||
        l.contains('credit') ||
        l.contains('debit') ||
        l.contains('settle') ||
        l.contains('order') ||
        l.contains('stock') ||
        l.contains('raffle') ||
        l.contains('admin') ||
        l.contains('stripe') ||
        l.contains('release') ||
        l.contains('clawback') ||
        l.contains('review') ||
        l.contains('offer') ||
        l.contains('bundle') ||
        l.contains('pairing') ||
        l.contains('ocr') ||
        l.contains('mux') ||
        l.contains('livekit') ||
        l.contains('ensure') ||
        l.contains('convert') ||
        l.contains('ship') ||
        l.contains('accept') ||
        l.contains('mark');
  }).toList();
  print('interesting rpcs=${interesting.length} / ${rpcs.length}');
  File('tool/redteam_blind_indep_20260830/out/rpc_list.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'all': rpcs, 'interesting': interesting}),
  );

  for (final fn in interesting) {
    for (final who in ['anon', 'buyer', 'seller']) {
      final tok = who == 'anon' ? null : (who == 'buyer' ? buyerTok : sellerTok);
      final r = await rest(
        method: 'POST',
        path: '/rest/v1/rpc/$fn',
        token: tok,
        body: <String, dynamic>{},
      );
      final st = r['status'] as int;
      if (st != 404 && st != 400 && st != 401 && st != 403) {
        rpcHits.add({'fn': fn, 'identity': who, ...r});
      } else if (st == 200 || st == 201 || st == 204) {
        rpcHits.add({'fn': fn, 'identity': who, ...r});
      }
      // always record 2xx / 5xx / unexpected 401-on-authenticated
      if (st < 400 || st >= 500 || (st == 200)) {
        if (!rpcHits.any((h) => h['fn'] == fn && h['identity'] == who)) {
          rpcHits.add({'fn': fn, 'identity': who, ...r});
        }
      }
    }
  }
  File('tool/redteam_blind_indep_20260830/out/rpc_empty_hits.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rpcHits));
  print('rpc notable hits=${rpcHits.length}');

  print('edge anon/buyer...');
  final edges = [
    'create-payment-intent',
    'refund-order',
    'create-connect-account',
    'create-live-tip-checkout',
    'create-mux-live',
    'complete-mux-live',
    'livekit-mux-publish',
    'resolve-mux-playback',
    'stripe-webhook',
    'ingest-ocr-reservation',
    'ps-pairing-claim',
    'ps-heartbeat',
    'ps-panel-log',
    'delete-test-account',
    'send-sms-bulkgate',
    'meta-data-deletion',
    'sec-fase2-e2e-oversell',
    'livekit-egress-cleanup',
  ];
  final edgeHits = <Map<String, dynamic>>[];
  for (final fn in edges) {
    for (final who in ['anon', 'buyer']) {
      final tok = who == 'anon' ? anon : buyerTok;
      final r = await http.post(
        Uri.parse('$url/functions/v1/$fn'),
        headers: {
          'apikey': anon,
          'Authorization': 'Bearer $tok',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'probe': true, 'amount': 1, 'order_id': buyerId}),
      );
      edgeHits.add({
        'fn': fn,
        'identity': who,
        'status': r.statusCode,
        'body': r.body.length > 800 ? '${r.body.substring(0, 800)}…' : r.body,
      });
    }
  }
  File('tool/redteam_blind_indep_20260830/out/edge_unauth_matrix.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(edgeHits));

  print('done discover');
}
