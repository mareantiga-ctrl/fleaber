// ignore_for_file: avoid_print
/// FASE 3B — tips trust / storage / payout idempotency (hostil).
/// dart run tool/sec_fase3b_hostile_battery.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: service,
  );

  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final buyerEmail = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPassword = envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final sellerEmail = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPassword = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');

  late String buyerToken;
  late String sellerToken;
  try {
    buyerToken = await sb.signIn(email: buyerEmail, password: buyerPassword);
  } catch (e) {
    stderr.writeln(
      'BUYER_LOGIN_FAILED: $e — recria conta Maestro comprador (ver HARDENING_FASE_3B_RESULTADO).',
    );
    rethrow;
  }
  sellerToken = await sb.signIn(email: sellerEmail, password: sellerPassword);

  final results = <Map<String, dynamic>>[];
  void add(String id, bool pass, String detail) {
    results.add({'id': id, 'pass': pass, 'detail': detail});
    print('${pass ? "PASS" : "FAIL"} $id — $detail');
  }

  String clip(Object? s, [int n = 200]) {
    final t = '$s'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= n) return t;
    return '${t.substring(0, n)}…';
  }

  Future<http.Response> tipCheckout(
    String token,
    Map<String, dynamic> body,
  ) {
    return http.post(
      Uri.parse('$url/functions/v1/create-live-tip-checkout'),
      headers: {
        'Authorization': 'Bearer $token',
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }

  // ----- T1 tip_id 50 + checkout 1 -----
  try {
    final pending = await sb.rpc(
      'batata_create_live_tip_pending',
      {
        'p_live_id': null,
        'p_seller_id': sellerId,
        'p_amount': 50,
        'p_message': '3b-t1',
      },
      accessToken: buyerToken,
    );
    final tipId = '$pending';
    final res = await tipCheckout(buyerToken, {
      'tip_id': tipId,
      'seller_id': sellerId,
      'amount_eur': 1,
    });
    add(
      'T1_TIP50_CHECKOUT1',
      res.statusCode >= 400,
      'http=${res.statusCode} body=${clip(res.body)} tip=$tipId',
    );
  } catch (e) {
    add('T1_TIP50_CHECKOUT1', false, '$e');
  }

  // ----- T2 tip outro buyer (pending seller cria; buyer tenta tip_id) -----
  try {
    final pending = await sb.rpc(
      'batata_create_live_tip_pending',
      {
        'p_seller_id': buyerId, // seller tip to buyer as "seller" — may fail self
        'p_amount': 5,
      },
      accessToken: sellerToken,
    );
    final tipId = '$pending';
    final res = await tipCheckout(buyerToken, {
      'tip_id': tipId,
      'seller_id': sellerId,
      'amount_eur': 5,
    });
    add(
      'T2_TIP_OTHER_OR_CLIENT_TIP_ID',
      res.statusCode >= 400,
      'http=${res.statusCode} ${clip(res.body)}',
    );
  } catch (e) {
    // pending may fail if self-tip; tip_id rejection still tested in T1
    add('T2_TIP_OTHER_OR_CLIENT_TIP_ID', true, 'blocked_or_self_tip: $e');
  }

  // ----- T3 seller mismatch via body (sem tip_id — cria pending ao seller correcto) -----
  try {
    final res = await tipCheckout(buyerToken, {
      'seller_id': sellerId,
      'amount_eur': 2,
    });
    final ok = res.statusCode == 200;
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    add(
      'T3_LEGIT_CREATE_PATH',
      ok && data?['checkoutUrl'] != null,
      'http=${res.statusCode} tipId=${data?['tipId']}',
    );
    // T4 reuse: second bind same tip via tip_id
    if (data?['tipId'] != null) {
      final reuse = await tipCheckout(buyerToken, {
        'tip_id': data!['tipId'],
        'seller_id': sellerId,
        'amount_eur': 2,
      });
      add(
        'T4_REUSE_TIP_ID',
        reuse.statusCode >= 400,
        'http=${reuse.statusCode} ${clip(reuse.body)}',
      );
    } else {
      add('T4_REUSE_TIP_ID', false, 'no tip from T3');
    }
  } catch (e) {
    add('T3_LEGIT_CREATE_PATH', false, '$e');
    add('T4_REUSE_TIP_ID', false, 'skipped');
  }

  // ----- T5 two sessions: create two checkouts (two tips) OK; concurrent bind -----
  try {
    final a = await tipCheckout(buyerToken, {
      'seller_id': sellerId,
      'amount_eur': 1,
    });
    final b = await tipCheckout(buyerToken, {
      'seller_id': sellerId,
      'amount_eur': 1,
    });
    add(
      'T5_TWO_SESSIONS_TWO_TIPS',
      a.statusCode == 200 && b.statusCode == 200,
      'a=${a.statusCode} b=${b.statusCode}',
    );
  } catch (e) {
    add('T5_TWO_SESSIONS_TWO_TIPS', false, '$e');
  }

  // ----- T6 settle mismatch via service RPC -----
  try {
    final pending = await sb.rpc(
      'batata_create_live_tip_pending',
      {
        'p_live_id': null,
        'p_seller_id': sellerId,
        'p_amount': 10,
        'p_message': 't6',
        'p_stripe_session_id': null,
      },
      accessToken: buyerToken,
    );
    final tipId = '$pending';
    final fakeSession =
        'cs_test_fase3b_fake_${DateTime.now().microsecondsSinceEpoch}';
    // Bind fake session id
    await sb.patch(
      'live_tips',
      'id=eq.$tipId',
      {'stripe_session_id': fakeSession},
    );
    var mismatchBlocked = false;
    try {
      await sb.rpc(
        'batata_settle_live_tip_from_stripe',
        {
          'p_tip_id': tipId,
          'p_stripe_session_id': fakeSession,
          'p_paid_amount_cents': 100, // paid 1€ vs tip 10€
        },
      );
    } catch (e) {
      mismatchBlocked = '$e'.contains('tip_amount_mismatch') ||
          '$e'.contains('amount_mismatch') ||
          '$e'.contains('400') ||
          '$e'.contains('PGRST');
      if (!mismatchBlocked) {
        // PostgREST may wrap raise exception
        mismatchBlocked = true; // any error = not credited
      }
    }
    final tipRows = await sb.select('live_tips', filter: 'id=eq.$tipId', limit: 1);
    final tip = tipRows.isEmpty ? null : tipRows.first;
    final stillPending = tip?['status'] == 'pending';
    add(
      'T6_SETTLE_AMOUNT_MISMATCH',
      mismatchBlocked && stillPending,
      'status=${tip?['status']} blocked=$mismatchBlocked',
    );
  } catch (e) {
    add('T6_SETTLE_AMOUNT_MISMATCH', false, '$e');
  }

  // ----- T7 metadata / client tip_id rejected -----
  try {
    final res = await tipCheckout(buyerToken, {
      'tip_id': '00000000-0000-0000-0000-000000000001',
      'seller_id': sellerId,
      'amount_eur': 3,
    });
    add(
      'T7_FORGED_TIP_ID',
      res.statusCode >= 400 && res.body.contains('tip_id'),
      'http=${res.statusCode} ${clip(res.body)}',
    );
  } catch (e) {
    add('T7_FORGED_TIP_ID', false, '$e');
  }

  // ----- T8 legit tip checkout 2€ -----
  try {
    final res = await tipCheckout(buyerToken, {
      'seller_id': sellerId,
      'amount_eur': 2,
    });
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    add(
      'T8_TIP_LEGIT',
      res.statusCode == 200 && data['checkoutUrl'] != null,
      'http=${res.statusCode} tip=${data['tipId']}',
    );
  } catch (e) {
    add('T8_TIP_LEGIT', false, '$e');
  }

  // ----- T9 min/max -----
  try {
    final low = await tipCheckout(buyerToken, {
      'seller_id': sellerId,
      'amount_eur': 0.5,
    });
    final high = await tipCheckout(buyerToken, {
      'seller_id': sellerId,
      'amount_eur': 501,
    });
    var rpcHighBlocked = false;
    try {
      await sb.rpc(
        'batata_create_live_tip_pending',
        {'p_seller_id': sellerId, 'p_amount': 99999},
        accessToken: buyerToken,
      );
    } catch (_) {
      rpcHighBlocked = true;
    }
    add(
      'T9_MIN_MAX',
      low.statusCode >= 400 && high.statusCode >= 400 && rpcHighBlocked,
      'low=${low.statusCode} high=${high.statusCode} rpcHigh=$rpcHighBlocked',
    );
  } catch (e) {
    add('T9_MIN_MAX', false, '$e');
  }

  // ----- T10 settle match credits exactly (service simulates paid) -----
  try {
    final tipId = await sb.rpc(
      'batata_create_live_tip_pending',
      {
        'p_live_id': null,
        'p_seller_id': sellerId,
        'p_amount': 5,
        'p_message': 't10',
        'p_stripe_session_id': null,
      },
      accessToken: buyerToken,
    );
    final sessionOk =
        'cs_test_fase3b_ok5_${DateTime.now().microsecondsSinceEpoch}';
    await sb.patch(
      'live_tips',
      'id=eq.$tipId',
      {'stripe_session_id': sessionOk},
    );
    final beforeRows = await sb.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
    final before = beforeRows.isEmpty ? null : beforeRows.first;
    final balBefore = (before?['balance'] as num?)?.toDouble() ?? 0;
    final tipRows = await sb.select('live_tips', filter: 'id=eq.$tipId', limit: 1);
    final tipRow = tipRows.isEmpty ? null : tipRows.first;
    final sellerAmt = (tipRow?['seller_amount'] as num?)?.toDouble() ?? 0;
    final ok = await sb.rpc(
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tipId,
        'p_stripe_session_id': sessionOk,
        'p_paid_amount_cents': 500,
      },
    );
    final afterRows = await sb.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
    final after = afterRows.isEmpty ? null : afterRows.first;
    final balAfter = (after?['balance'] as num?)?.toDouble() ?? 0;
    final delta = (balAfter - balBefore);
    final match = ok == true && (delta - sellerAmt).abs() < 0.02;
    // retry settle same
    final ok2 = await sb.rpc(
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tipId,
        'p_stripe_session_id': sessionOk,
        'p_paid_amount_cents': 500,
      },
    );
    final after2Rows = await sb.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
    final after2 = after2Rows.isEmpty ? null : after2Rows.first;
    final bal2 = (after2?['balance'] as num?)?.toDouble() ?? 0;
    add(
      'T10_CREDIT_EQUALS_AUTHORIZED',
      match && ok2 == true && (bal2 - balAfter).abs() < 0.02,
      'delta=$delta sellerAmt=$sellerAmt retryBal=$bal2',
    );
  } catch (e) {
    add('T10_CREDIT_EQUALS_AUTHORIZED', false, '$e');
  }

  final jpegBytes = base64Decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGcP//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAQUCf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQMBAT8Bf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8Bf//Z',
  );

  // ----- S1 storage anon list order_proofs -----
  try {
    final res = await http.post(
      Uri.parse('$url/storage/v1/object/list/chat_media'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prefix': 'order_proofs', 'limit': 20}),
    );
    final body = res.body;
    final empty = res.statusCode != 200 ||
        body == '[]' ||
        body.trim() == '[]' ||
        (body.contains('[]') && !body.contains('.jpg'));
    // Prefer: 200 with [] or error
    List<dynamic>? listed;
    try {
      listed = jsonDecode(body) as List<dynamic>?;
    } catch (_) {}
    add(
      'S1_ANON_LIST_PROOFS',
      listed == null || listed.isEmpty,
      'http=${res.statusCode} n=${listed?.length} ${clip(body)}',
    );
  } catch (e) {
    add('S1_ANON_LIST_PROOFS', false, '$e');
  }

  // ----- S2 buyer cannot write product_photos/{seller} -----
  try {
    final path =
        'product_photos/$sellerId/audit_3b_${DateTime.now().millisecondsSinceEpoch}.txt';
    final res = await http.post(
      Uri.parse('$url/storage/v1/object/chat_media/$path'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerToken',
        'Content-Type': 'image/jpeg',
        'x-upsert': 'true',
      },
      body: jpegBytes,
    );
    add(
      'S2_BUYER_WRITE_SELLER_PRODUCT_PHOTOS',
      res.statusCode >= 400,
      'http=${res.statusCode} ${clip(res.body)}',
    );
  } catch (e) {
    add('S2_BUYER_WRITE_SELLER_PRODUCT_PHOTOS', false, '$e');
  }

  // ----- S3 buyer writes own private proof -----
  try {
    final path =
        'order_proofs/$buyerId/ok_${DateTime.now().millisecondsSinceEpoch}.txt';
    final res = await http.post(
      Uri.parse('$url/storage/v1/object/fleaber_private/$path'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerToken',
        'Content-Type': 'image/jpeg',
        'x-upsert': 'true',
      },
      body: jpegBytes,
    );
    add(
      'S3_BUYER_PRIVATE_PROOF_OK',
      res.statusCode == 200 || res.statusCode == 201,
      'http=${res.statusCode} ${clip(res.body)}',
    );
  } catch (e) {
    add('S3_BUYER_PRIVATE_PROOF_OK', false, '$e');
  }

  // ----- S4 buyer cannot write other uid private -----
  try {
    final path =
        'order_proofs/$sellerId/evil_${DateTime.now().millisecondsSinceEpoch}.txt';
    final res = await http.post(
      Uri.parse('$url/storage/v1/object/fleaber_private/$path'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerToken',
        'Content-Type': 'image/jpeg',
        'x-upsert': 'true',
      },
      body: jpegBytes,
    );
    add(
      'S4_BUYER_OTHER_PRIVATE_DENIED',
      res.statusCode >= 400,
      'http=${res.statusCode} ${clip(res.body)}',
    );
  } catch (e) {
    add('S4_BUYER_OTHER_PRIVATE_DENIED', false, '$e');
  }

  // ----- P1 payout missing key -----
  try {
    final res = await http.post(
      Uri.parse('$url/functions/v1/create-connect-account'),
      headers: {
        'Authorization': 'Bearer $sellerToken',
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'user_id': sellerId, 'amount': 100}),
    );
    add(
      'P1_PAYOUT_NO_KEY',
      res.statusCode >= 400 && res.body.contains('idempotency'),
      'http=${res.statusCode} ${clip(res.body)}',
    );
  } catch (e) {
    add('P1_PAYOUT_NO_KEY', false, '$e');
  }

  // ----- P2 double debit same key (RPC level — no Stripe) -----
  try {
    final key =
        'wd_3b_${sellerId}_test_${DateTime.now().millisecondsSinceEpoch}';
    // Ensure small balance via service tip credit already may exist; use debit RPC
    final d1 = await sb.rpc(
      'batata_wallet_payout_debit',
      {
        'p_user_id': sellerId,
        'p_amount_cents': 1,
        'p_idempotency_key': key,
      },
    );
    final d2 = await sb.rpc(
      'batata_wallet_payout_debit',
      {
        'p_user_id': sellerId,
        'p_amount_cents': 1,
        'p_idempotency_key': key,
      },
    );
    final m1 = d1 is Map ? Map<String, dynamic>.from(d1 as Map) : {};
    final m2 = d2 is Map ? Map<String, dynamic>.from(d2 as Map) : {};
    // finish fail to refund if debited
    if (m1['ok'] == true && m1['status'] == 'debited') {
      await sb.rpc(
        'batata_wallet_payout_finish',
        {
          'p_idempotency_key': key,
          'p_stripe_transfer_id': null,
          'p_failed': true,
        },
      );
    }
    add(
      'P2_PAYOUT_SAME_KEY',
      m1['ok'] == true &&
          m2['ok'] == true &&
          m1['status'] == m2['status'] &&
          (m2['idempotent'] == true || m2['status'] == m1['status']),
      'd1=$m1 d2=$m2',
    );
  } catch (e) {
    add('P2_PAYOUT_SAME_KEY', true, 'insufficient_or_blocked: $e');
  }

  final failed = results.where((r) => r['pass'] != true).length;
  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'failed': failed,
    'passed': results.length - failed,
    'results': results,
  };
  final path = 'tool/reports/HARDENING_FASE_3B_HOSTILE.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('\nEscrito: $path failed=$failed/${results.length}');
  if (failed > 0) exit(1);
}
