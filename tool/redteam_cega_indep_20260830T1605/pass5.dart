// ignore_for_file: avoid_print
/// Pass 5 — RPCs OpenAPI perigosas com args certos + impacto do INSERT events + cleanup live.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../live_ops_staging_client.dart';

const stamp = '20260830T1605';
const projectMust = 'fxdknzrqjenzqcvnwqqq';
final findings = <Map<String, dynamic>>[];
final matrix = <Map<String, dynamic>>[];

void find({
  required String id,
  required String sev,
  required String title,
  required String actor,
  required String pre,
  required String repro,
  required String impact,
  required String state,
  Object? evidence,
}) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'preconditions': pre,
    'reproduction': repro,
    'impact': impact,
    'state': state,
    'evidence': evidence,
  });
}

void row(String surface, String attack, String identity, String result, String impact, String severity, [Object? evidence]) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': identity,
    'result': result,
    'impact': impact,
    'severity': severity,
    'evidence': evidence,
  });
}

String clip(Object? v, [int n = 400]) {
  final s = v is String ? v : jsonEncode(v);
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

Future<Map<String, dynamic>> req(String method, String u, Map<String, String> h, [Object? body]) async {
  late http.Response r;
  switch (method) {
    case 'POST':
      r = await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
      break;
    case 'PATCH':
      r = await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
      break;
    case 'GET':
      r = await http.get(Uri.parse(u), headers: h);
      break;
    default:
      r = await http.delete(Uri.parse(u), headers: h);
  }
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

Map<String, String> hdr(String k, String b) => {
      'apikey': k,
      'Authorization': 'Bearer $b',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) exit(2);
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final c = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerJwt = await c.signIn(email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'), password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'));
  final sellerJwt = await c.signIn(email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'), password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'));
  final bUid = await c.userIdForAccessToken(buyerJwt);
  final sUid = await c.userIdForAccessToken(sellerJwt);
  final buyH = hdr(anon, buyerJwt);
  final selH = hdr(anon, sellerJwt);
  final anonH = hdr(anon, anon);
  final svcH = hdr(svc, svc);
  String? b2Jwt;
  try {
    b2Jwt = await c.signIn(email: 'rt1605-b2-$stamp@staging.fleaber.invalid', password: 'Rt1605!pass');
  } catch (_) {}
  final b2H = b2Jwt == null ? null : hdr(anon, b2Jwt);
  final outDir = Directory('tool/redteam_cega_indep_20260830T1605/out');

  // Cleanup live created in pass4
  final endLive = await req('PATCH', '$url/rest/v1/lives?id=eq.336d37ad-23b5-4f19-8545-7b1a1805b9eb', svcH, {
    'status': 'ended',
    'is_active': false,
  });
  row('LIVE', 'cleanup live pass4', 'service_cleanup', 'http=${endLive['http']} ${clip(endLive['text'], 120)}', 'fechar directo', 'info');

  final oid = '6c4e2d3c-eb97-474c-94ea-cd22cd48cc03';

  // Event insert variants
  final evRefund = await req('POST', '$url/rest/v1/stripe_checkout_events', buyH, {
    'order_id': oid,
    'buyer_id': bUid,
    'event': 'refund_created',
    'detail': {'hostile': true, 'stamp': stamp},
  });
  row('STRIPE SESSION', 'INSERT refund_created own order', 'buyer', 'http=${evRefund['http']} ${clip(evRefund['text'], 160)}', 'grief release?', evRefund['http'] == 201 ? 'P2' : 'info');

  if (b2H != null) {
    final evX = await req('POST', '$url/rest/v1/stripe_checkout_events', b2H, {
      'order_id': oid,
      'buyer_id': bUid,
      'event': 'refund_created',
      'detail': {'hostile_b2': true},
    });
    row('STRIPE SESSION', 'B2 INSERT event on buyer1 order', 'buyer2', 'http=${evX['http']} ${clip(evX['text'], 160)}', 'cross-user event', evX['http'] == 201 ? 'P1' : 'info');
    if (evX['http'] == 201) {
      find(id: 'P1-EVENT-INSERT-FOREIGN', sev: 'P1', title: 'Buyer2 inseriu stripe_checkout_events em order alheia', actor: 'buyer2', pre: 'order do buyer1', repro: 'POST stripe_checkout_events order_id alheio event=refund_created', impact: 'integridade financeira / DoS release', state: 'ABERTO', evidence: evX['body']);
    }
  }

  // Dangerous RPCs with {} then with likely args
  final rpcs = <Map<String, dynamic>>[
    {'fn': 'batata_admin_list_profiles', 'p': <String, dynamic>{}},
    {'fn': 'batata_admin_resolve_dispute', 'p': {'p_dispute_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_lab_clear_fm_pending', 'p': <String, dynamic>{}},
    {'fn': 'batata_lab_clear_all_fm_pending', 'p': <String, dynamic>{}},
    {'fn': 'staging_nuke_user_data', 'p': <String, dynamic>{}},
    {'fn': 'staging_restore_stock_before_nuke', 'p': <String, dynamic>{}},
    {'fn': 'batata_finalize_stripe_order_refund', 'p': {'p_order_id': oid}},
    {'fn': 'batata_process_partial_refund_dispute', 'p': {'p_order_id': oid, 'p_amount_cents': 1}},
    {'fn': 'batata_refund_buyer_wallet_for_order', 'p': {'p_order_id': oid}},
    {'fn': 'batata_record_buyer_purchase_ledger', 'p': {'p_order_id': oid}},
    {'fn': 'batata_record_buyer_refund_ledger', 'p': {'p_order_id': oid}},
    {'fn': 'batata_wallet_apply_tip_once', 'p': {'p_tip_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_ingest_ocr_reservation', 'p': {'p_live_id': '00000000-0000-0000-0000-000000000001', 'p_ocr_line_hash': 'abcdefghijkl'}},
    {'fn': 'batata_claim_external_reservations', 'p': {'p_live_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_live_reservation_accept_available', 'p': {'p_live_item_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_draw_live_raffle_winners', 'p': {'p_raffle_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_create_raffle_prize_order', 'p': {'p_raffle_id': '00000000-0000-0000-0000-000000000001', 'p_winner_id': bUid}},
    {'fn': 'batata_award_live_raffle_tickets', 'p': {'p_raffle_id': '00000000-0000-0000-0000-000000000001', 'p_user_id': bUid}},
    {'fn': 'set_active_live_item', 'p': {'p_live_item_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'get_seller_stats', 'p': {'p_seller_id': sUid}},
    {'fn': 'batata_staging_set_fleahub_test_state', 'p': <String, dynamic>{}},
    {'fn': 'batata_generate_auto_feedback', 'p': <String, dynamic>{}},
    {'fn': 'batata_is_admin', 'p': <String, dynamic>{}},
    {'fn': 'batata_ps_create_pairing', 'p': {'p_live_id': '336d37ad-23b5-4f19-8545-7b1a1805b9eb'}},
    {'fn': 'batata_create_seller_device_token', 'p': <String, dynamic>{}},
    {'fn': 'batata_live_bag_update_qty', 'p': {'p_request_id': '00000000-0000-0000-0000-000000000001', 'p_qty': 99}},
    {'fn': 'batata_process_live_reservation_request', 'p': {'p_request_id': '00000000-0000-0000-0000-000000000001', 'p_accept': true}},
    {'fn': 'batata_confirm_ps_reservation', 'p': {'p_reservation_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_mark_live_item_sold', 'p': {'p_live_item_id': 'bd1fe033-927d-449b-b9fc-b231f73114f9'}},
    {'fn': 'batata_live_reconcile_stripe_order', 'p': {'p_order_id': oid}},
    {'fn': 'batata_send_live_tip_from_wallet', 'p': {'p_live_id': '5dd5cfd2-63b1-4cd8-82b1-c888e9dc5234', 'p_seller_id': sUid, 'p_amount': 1}},
    {'fn': 'batata_create_live_tip_pending', 'p': {'p_live_id': '5dd5cfd2-63b1-4cd8-82b1-c888e9dc5234', 'p_seller_id': sUid, 'p_amount': 1}},
    {'fn': 'batata_settle_live_tip_from_stripe', 'p': {'p_tip_id': '00000000-0000-0000-0000-000000000001', 'p_stripe_session_id': 'cs_x', 'p_paid_amount_cents': 500}},
    {'fn': 'batata_invoke_livekit_egress_cleanup', 'p': <String, dynamic>{}},
    {'fn': 'batata_anon_rate_check', 'p': {'p_rate_key': 'x', 'p_rpc': 'x', 'p_max_hits': 1}},
  ];

  for (final ident in [
    {'n': 'anon', 'h': anonH},
    {'n': 'buyer', 'h': buyH},
    {'n': 'seller', 'h': selH},
  ]) {
    for (final rdef in rpcs) {
      final r = await req('POST', '$url/rest/v1/rpc/${rdef['fn']}', ident['h'] as Map<String, String>, rdef['p']);
      final httpCode = r['http'] as int;
      final interesting = httpCode == 200 || httpCode == 201;
      row('RPC', '${rdef['fn']}', ident['n'] as String, 'http=$httpCode ${clip(r['text'], 120)}', interesting ? 'EXECUTE 200' : 'negado/erro', interesting ? 'P2' : 'info');
      if (interesting) {
        final fn = '${rdef['fn']}';
        final money = fn.contains('wallet') ||
            fn.contains('refund') ||
            fn.contains('nuke') ||
            fn.contains('admin') ||
            fn.contains('lab_clear') ||
            fn.contains('prize') ||
            fn.contains('settle') ||
            fn.contains('credit') ||
            fn.contains('ledger') ||
            fn.contains('tip');
        if (money) {
          find(
            id: 'P1-RPC-$fn-${ident['n']}',
            sev: fn.contains('nuke') || fn.contains('admin') || fn.contains('wallet') || fn.contains('refund') || fn.contains('settle') ? 'P1' : 'P2',
            title: 'RPC $fn HTTP 200 como ${ident['n']}',
            actor: ident['n'] as String,
            pre: 'OpenAPI GRANT',
            repro: 'POST /rpc/$fn ${rdef['p']}',
            impact: 'efeito privilegiado',
            state: 'ABERTO',
            evidence: clip(r['body'], 250),
          );
        }
      }
    }
  }

  // Remaining tables
  for (final t in [
    'app_logs',
    'batata_anon_rate_limits',
    'reviews_gerais',
    'order_dispute_replies',
    'product_bundles',
    'live_private_messages',
    'live_messages',
    'notifications_view',
    'hub_profiles_public',
    'chats',
    'wallet_payout_ledger',
    'fleaber_commissions',
  ]) {
    final g = await req('GET', '$url/rest/v1/$t?select=*&limit=5', buyH);
    final a = await req('GET', '$url/rest/v1/$t?select=*&limit=5', anonH);
    final g2 = b2H == null ? null : await req('GET', '$url/rest/v1/$t?select=*&limit=5', b2H);
    row(t, 'SELECT', 'buyer', 'http=${g['http']} ${clip(g['text'], 100)}', 'rls', 'info');
    row(t, 'SELECT', 'anon', 'http=${a['http']} ${clip(a['text'], 80)}', 'rls', 'info');
    if (g2 != null) row(t, 'SELECT', 'buyer2', 'http=${g2['http']} n=${g2['body'] is List ? (g2['body'] as List).length : g2['http']}', 'rls', 'info');
  }

  // reviews_gerais insert
  final rg = await req('POST', '$url/rest/v1/reviews_gerais', buyH, {
    'stars': 5,
    'comment': 'hostile $stamp',
    'target_id': sUid,
  });
  row('REVIEWS', 'INSERT reviews_gerais', 'buyer', 'http=${rg['http']} ${clip(rg['text'], 140)}', 'review sem compra', rg['http'] == 201 ? 'P2' : 'info');

  // Reservation with seller_id
  final res = await req('POST', '$url/rest/v1/live_reservation_requests', buyH, {
    'live_item_id': 'bd1fe033-927d-449b-b9fc-b231f73114f9',
    'live_id': 'f1d48e20-c59e-4519-8c43-36f6fdf2df698d',
    'buyer_id': bUid,
    'seller_id': sUid,
    'requested_qty': 99,
    'status': 'accepted',
  });
  row('WAITLIST / QUEUE', 'INSERT reservation seller_id qty=99 accepted', 'buyer', 'http=${res['http']} ${clip(res['text'], 180)}', 'fila', 'info');

  final frozen = {
    'FROZEN_AT': DateTime.now().toUtc().toIso8601String(),
    'pass': 5,
    'project': projectMust,
    'findings': findings,
    'matrix': matrix,
  };
  File('${outDir.path}/pass5.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(frozen));
  stdout.writeln('PASS5 findings=${findings.length}');
  for (final f in findings) {
    stdout.writeln('${f['severity']} ${f['id']} ${f['title']} http-ev');
  }
}
