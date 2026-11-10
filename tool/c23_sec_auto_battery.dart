// ignore_for_file: avoid_print
/// Bateria SEC automatizada (ataque deve falhar) — staging.
/// Não cria directo Mux, não enfraquece defesa, não muda produto.
///
///   dart run tool/c23_sec_auto_battery.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

typedef Probe = Future<Map<String, dynamic>> Function();

void main() async {
  final outDir = Directory('tool/reports/battery_c23_sec_2026-08-20');
  outDir.createSync(recursive: true);
  final shots = Directory('${outDir.path}/screenshots')..createSync(recursive: true);
  final logFile = File('${outDir.path}/c23_sec_auto_battery.log');
  final sink = logFile.openWrite();

  void log(String m) {
    final line = '[${DateTime.now().toIso8601String()}] $m';
    print(line);
    sink.writeln(line);
  }

  final staging = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL'));
  final anon = envRequire(staging, 'SUPABASE_ANON_KEY');
  final service = envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY');
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: service,
  );

  log('sign_in buyer+seller…');
  final buyerTok = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = await client.userIdForAccessToken(buyerTok);
  final sellerId = await client.userIdForAccessToken(sellerTok);
  log('buyer=$buyerId seller=$sellerId');

  final results = <Map<String, dynamic>>[];

  Future<void> run(String id, String title, Probe probe) async {
    log('--- $id: $title');
    try {
      final r = await probe();
      final pass = r['pass'] == true;
      final aviso = r['aviso'] == true;
      final status = pass
          ? (aviso ? 'PASS_COM_AVISO' : 'PASS')
          : (r['skip'] == true ? 'SKIP' : 'FAIL');
      final row = {
        'id': id,
        'title': title,
        'status': status,
        ...r,
      };
      results.add(row);
      log('$id → $status ${r['summary'] ?? ''}');
    } catch (e, st) {
      results.add({
        'id': id,
        'title': title,
        'status': 'FAIL',
        'pass': false,
        'summary': 'exception: $e',
        'stack': st.toString().split('\n').take(6).join('\n'),
      });
      log('$id → FAIL exception=$e');
    }
  }

  Map<String, String> userH(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Map<String, String> anonH() => {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<http.Response> rpcRaw(
    String fn,
    Map<String, dynamic> body, {
    String? token,
    bool useAnon = false,
  }) {
    final headers = useAnon
        ? anonH()
        : (token == null
            ? {
                'apikey': service,
                'Authorization': 'Bearer $service',
                'Content-Type': 'application/json',
              }
            : userH(token));
    return http.post(
      Uri.parse('$url/rest/v1/rpc/$fn'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> restGet(
    String path, {
    required String token,
  }) {
    return http.get(Uri.parse('$url/rest/v1/$path'), headers: userH(token));
  }

  Future<http.Response> restPatch(
    String path,
    Object body, {
    required String token,
  }) {
    return http.patch(
      Uri.parse('$url/rest/v1/$path'),
      headers: userH(token),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> restPost(
    String path,
    Object body, {
    Map<String, String>? headers,
  }) {
    return http.post(
      Uri.parse('$url/rest/v1/$path'),
      headers: headers ?? anonH(),
      body: jsonEncode(body),
    );
  }

  bool rpcDenied(http.Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) return true;
    final b = r.body.toLowerCase();
    return b.contains('permission denied') ||
        b.contains('not accept') ||
        b.contains('42501') ||
        (r.statusCode == 404 && b.contains('could not find'));
  }

  // ─── SEC-001 ───────────────────────────────────────────────
  await run('APP-SEC-001', 'Bloquear auto-admin user_type', () async {
    final before = await client.selectAsUser(
      'profiles',
      accessToken: buyerTok,
      filter: 'id=eq.$buyerId',
      limit: 1,
    );
    final oldType = before.isEmpty ? null : before.first['user_type'];
    final patch = await restPatch(
      'profiles?id=eq.$buyerId',
      {'user_type': 'admin'},
      token: buyerTok,
    );
    final after = await client.selectAsUser(
      'profiles',
      accessToken: buyerTok,
      filter: 'id=eq.$buyerId',
      limit: 1,
    );
    final newType = after.isEmpty ? null : after.first['user_type'];
    final blocked = newType?.toString().toLowerCase() != 'admin';
    return {
      'pass': blocked,
      'summary':
          'patch_http=${patch.statusCode} user_type before=$oldType after=$newType',
      'evidence': {
        'patch_status': patch.statusCode,
        'patch_body_snip': patch.body.length > 200
            ? patch.body.substring(0, 200)
            : patch.body,
        'user_type_before': oldType,
        'user_type_after': newType,
      },
    };
  });

  // ─── SEC-002 ───────────────────────────────────────────────
  await run('APP-SEC-002', 'Guard estados encomenda (ataque comprador)', () async {
    final orders = await client.select(
      'orders',
      filter: 'buyer_id=eq.$buyerId&status=neq.pago&order=created_at.desc',
      limit: 5,
    );
    if (orders.isEmpty) {
      return {
        'pass': false,
        'skip': true,
        'summary': 'sem encomenda buyer para atacar',
      };
    }
    final o = orders.first;
    final oid = o['id'].toString();
    final oldStatus = o['status']?.toString() ?? '';
    final attacks = <String, dynamic>{};
    var allBlocked = true;
    for (final target in ['pago', 'enviado', 'concluido', 'devolvida']) {
      final p = await restPatch(
        'orders?id=eq.$oid',
        {'status': target},
        token: buyerTok,
      );
      final check = await client.select('orders', filter: 'id=eq.$oid', limit: 1);
      final now = check.isEmpty ? '?' : check.first['status']?.toString();
      final blocked = now == oldStatus ||
          (target == 'pago' && oldStatus == 'premio_rifa' && now == 'pago');
      // For premio_rifa→pago allowed; otherwise status must stay.
      final ok = target == 'pago' && oldStatus.toLowerCase() == 'premio_rifa'
          ? true
          : now == oldStatus;
      attacks[target] = {
        'http': p.statusCode,
        'status_after': now,
        'blocked_ok': ok,
      };
      if (!ok) allBlocked = false;
      // restore via service if somehow changed
      if (now != oldStatus) {
        await client.patch('orders', 'id=eq.$oid', {'status': oldStatus});
      }
    }
    return {
      'pass': allBlocked,
      'summary':
          'order=$oid old=$oldStatus attacks=${attacks.keys.join(",")}',
      'evidence': {'order_id': oid, 'old_status': oldStatus, 'attacks': attacks},
    };
  });

  // ─── SEC-003 ───────────────────────────────────────────────
  await run('APP-SEC-003', 'Lives sem stream keys no SELECT', () async {
    final liveRows = await client.select(
      'lives',
      filter: 'order=created_at.desc',
      limit: 3,
    );
    if (liveRows.isEmpty) {
      return {'pass': false, 'skip': true, 'summary': 'sem lives'};
    }
    final lid = liveRows.first['id'].toString();
    // Column grants: safe cols OK; secrets / select=* → 403 (esperado).
    final safe = await restGet(
      'lives?id=eq.$lid&select=id,title,status,mux_playback_id&limit=1',
      token: buyerTok,
    );
    final keys = await restGet(
      'lives?id=eq.$lid&select=stream_key,mux_stream_key&limit=1',
      token: buyerTok,
    );
    final star = await restGet(
      'lives?id=eq.$lid&select=*&limit=1',
      token: buyerTok,
    );
    final secretsBlocked = keys.statusCode >= 400;
    final starBlockedOrSafe = star.statusCode >= 400 ||
        !(star.body.contains('"stream_key":"') ||
            star.body.contains('"mux_stream_key":"'));
    final pass =
        safe.statusCode == 200 && secretsBlocked && starBlockedOrSafe;
    return {
      'pass': pass,
      'aviso': true, // UI Home/criar directo não retestado nesta corrida
      'summary':
          'safe_http=${safe.statusCode} keys_http=${keys.statusCode} star_http=${star.statusCode}',
      'evidence': {
        'live_id': lid,
        'safe_snip':
            safe.body.length > 220 ? safe.body.substring(0, 220) : safe.body,
        'keys_status': keys.statusCode,
        'keys_body_snip':
            keys.body.length > 160 ? keys.body.substring(0, 160) : keys.body,
        'star_status': star.statusCode,
      },
    };
  });

  // ─── SEC-004 ───────────────────────────────────────────────
  await run('APP-SEC-004', 'stripe_convert só servidor', () async {
    final fake = '00000000-0000-4000-8000-000000000001';
    final r = await rpcRaw(
      'batata_live_reservation_stripe_convert',
      {'p_reservation_id': fake, 'p_order_id': fake},
      token: buyerTok,
    );
    return {
      'pass': rpcDenied(r),
      'summary': 'http=${r.statusCode} denied=${rpcDenied(r)}',
      'evidence': {
        'status': r.statusCode,
        'body_snip': r.body.length > 240 ? r.body.substring(0, 240) : r.body,
      },
    };
  });

  // ─── SEC-009 / 010 ─────────────────────────────────────────
  await run('APP-SEC-009', 'Prémio rifa RPC directa revogada', () async {
    final fake = '00000000-0000-4000-8000-000000000001';
    final r = await rpcRaw(
      'batata_create_raffle_prize_order',
      {'p_raffle_id': fake, 'p_winner_id': buyerId, 'p_qty': 1},
      token: buyerTok,
    );
    return {
      'pass': rpcDenied(r),
      'summary': 'http=${r.statusCode}',
      'evidence': {
        'status': r.statusCode,
        'body_snip': r.body.length > 200 ? r.body.substring(0, 200) : r.body,
      },
    };
  });

  await run('APP-SEC-010', 'Tickets rifa RPC directa revogada', () async {
    final fake = '00000000-0000-4000-8000-000000000001';
    final r = await rpcRaw(
      'batata_award_live_raffle_tickets',
      {
        'p_live_id': fake,
        'p_user_id': buyerId,
        'p_source': 'hack',
        'p_qty': 99,
        'p_idempotency_key': 'sec-auto-c23',
        'p_meta': <String, dynamic>{},
      },
      token: buyerTok,
    );
    return {
      'pass': rpcDenied(r),
      'summary': 'http=${r.statusCode}',
      'evidence': {
        'status': r.statusCode,
        'body_snip': r.body.length > 200 ? r.body.substring(0, 200) : r.body,
      },
    };
  });

  // ─── SEC-012 ───────────────────────────────────────────────
  await run('APP-SEC-012', 'Lookup email: anon bloqueado + auth OK', () async {
    final sellerEmail = envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL');
    final anonTry = await rpcRaw(
      'batata_find_user_id_by_email',
      {'p_email': sellerEmail},
      useAnon: true,
    );
    final authTry = await rpcRaw(
      'batata_find_user_id_by_email',
      {'p_email': sellerEmail},
      token: sellerTok,
    );
    final anonBlocked = anonTry.statusCode >= 400 ||
        anonTry.body.toLowerCase().contains('not_authenticated') ||
        anonTry.body.contains('42501');
    final authOk = authTry.statusCode >= 200 && authTry.statusCode < 300;
    return {
      'pass': anonBlocked && authOk,
      'aviso': true, // rate-limit 30/h não esgotado nesta corrida
      'summary':
          'anon_http=${anonTry.statusCode} auth_http=${authTry.statusCode}',
      'evidence': {
        'anon_status': anonTry.statusCode,
        'anon_snip':
            anonTry.body.length > 160 ? anonTry.body.substring(0, 160) : anonTry.body,
        'auth_status': authTry.statusCode,
        'auth_found': authTry.body.contains(sellerId),
      },
    };
  });

  // ─── SEC-013 ───────────────────────────────────────────────
  await run('APP-SEC-013', 'Claim FB exige live_id', () async {
    final r = await rpcRaw(
      'batata_claim_external_reservations',
      <String, dynamic>{},
      token: buyerTok,
    );
    var ok = false;
    String detail = 'http=${r.statusCode} body=${r.body}';
    if (r.statusCode >= 200 && r.statusCode < 300) {
      try {
        final j = jsonDecode(r.body);
        if (j is Map) {
          ok = j['ok'] == false &&
              (j['error']?.toString() == 'live_id_required' ||
                  j['error']?.toString().contains('live_id') == true);
          detail = 'ok=${j['ok']} error=${j['error']}';
        }
      } catch (_) {}
    }
    return {
      'pass': ok,
      'aviso': true, // residual match-by-name documentado
      'summary': detail,
      'evidence': {'status': r.statusCode, 'body': r.body},
    };
  });

  // ─── SEC-014 ───────────────────────────────────────────────
  await run('APP-SEC-014', 'Helper não alarga permissions', () async {
    // Convite temporário: seller → buyer, depois buyer tenta permissions admin.
    final inserted = await client.insert('seller_helpers', {
      'seller_id': sellerId,
      'helper_user_id': buyerId,
      'invitation_status': 'pending',
      'active': false,
      'invited_email': envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      'permissions': {
        'can_manage_chat': false,
        'can_manage_reservations': false,
        'can_view_finances': false,
      },
    });
    final hid = inserted['id']?.toString() ?? '';
    try {
      final attack = await restPatch(
        'seller_helpers?id=eq.$hid',
        {
          'invitation_status': 'accepted',
          'permissions': {
            'can_manage_chat': true,
            'can_manage_reservations': true,
            'can_view_finances': true,
            'can_refund': true,
          },
        },
        token: buyerTok,
      );
      final after = await client.select(
        'seller_helpers',
        filter: 'id=eq.$hid',
        limit: 1,
      );
      final perms = after.isEmpty ? null : after.first['permissions'];
      final status = after.isEmpty ? null : after.first['invitation_status'];
      Map<String, dynamic> pmap = {};
      if (perms is Map) {
        pmap = Map<String, dynamic>.from(perms);
      } else if (perms is String) {
        try {
          pmap = Map<String, dynamic>.from(jsonDecode(perms) as Map);
        } catch (_) {}
      }
      final escalated = pmap['can_view_finances'] == true ||
          pmap['can_refund'] == true ||
          pmap['can_manage_reservations'] == true;
      return {
        'pass': !escalated,
        'summary':
            'patch_http=${attack.statusCode} status=$status finances=${pmap['can_view_finances']}',
        'evidence': {
          'helper_id': hid,
          'patch_status': attack.statusCode,
          'invitation_status': status,
          'permissions_after': pmap,
        },
      };
    } finally {
      if (hid.isNotEmpty) {
        try {
          await client.deleteWhere('seller_helpers', 'id=eq.$hid');
        } catch (e) {
          log('cleanup seller_helpers failed: $e');
        }
      }
    }
  });

  // ─── SEC-016 ───────────────────────────────────────────────
  await run('APP-SEC-016', 'anon_rate_check só service + resolve smoke', () async {
    final userRpc = await rpcRaw(
      'batata_anon_rate_check',
      {'p_rate_key': 'c23', 'p_rpc': 'probe', 'p_max_hits': 1},
      token: buyerTok,
    );
    final denied = rpcDenied(userRpc);
    // Smoke resolve (1 call) — não stressar rate
    final lives = await client.select(
      'lives',
      filter: 'mux_playback_id=not.is.null&order=created_at.desc',
      limit: 1,
    );
    Map<String, dynamic>? edgeEv;
    if (lives.isNotEmpty) {
      final lid = lives.first['id'].toString();
      final edge = await http.post(
        Uri.parse('$url/functions/v1/resolve-mux-playback'),
        headers: {
          'apikey': anon,
          'Authorization': 'Bearer $buyerTok',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'live_id': lid}),
      );
      edgeEv = {
        'live_id': lid,
        'status': edge.statusCode,
        'body_snip':
            edge.body.length > 180 ? edge.body.substring(0, 180) : edge.body,
      };
    }
    return {
      'pass': denied,
      'aviso': true, // rate-limit Mux não esgotado; VOD UI não testada
      'summary': 'user_rpc_denied=$denied edge=${edgeEv?['status']}',
      'evidence': {
        'rpc_status': userRpc.statusCode,
        'rpc_snip': userRpc.body.length > 160
            ? userRpc.body.substring(0, 160)
            : userRpc.body,
        'edge': edgeEv,
      },
    };
  });

  // ─── SEC-017 ───────────────────────────────────────────────
  await run('APP-SEC-017', 'create-mux-live exige auth (sem criar live)', () async {
    final noAuth = await http.post(
      Uri.parse('$url/functions/v1/create-mux-live'),
      headers: {
        'apikey': anon,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'title': 'SEC C23 probe — não criar'}),
    );
    var bodyOk = false;
    try {
      final j = jsonDecode(noAuth.body);
      if (j is Map) {
        bodyOk = (j['step']?.toString() == 'auth') ||
            (j['error']?.toString().toLowerCase().contains('auth') ?? false);
      }
    } catch (_) {}
    final pass = noAuth.statusCode == 401 || bodyOk;
    return {
      'pass': pass,
      'aviso': true, // quota 10/dia e 1.º directo UI não exercitados (BATATA: sem criar directo)
      'summary': 'no_auth_http=${noAuth.statusCode}',
      'evidence': {
        'status': noAuth.statusCode,
        'body': noAuth.body.length > 220
            ? noAuth.body.substring(0, 220)
            : noAuth.body,
      },
    };
  });

  // ─── SEC-019 ───────────────────────────────────────────────
  await run('APP-SEC-019', 'CORS allowlist (evil origin não espelhado)', () async {
    final evil = 'https://evil.example';
    final good = 'https://fleaber.pt';
    Future<http.Response> options(String origin) async {
      final req = http.Request(
        'OPTIONS',
        Uri.parse('$url/functions/v1/resolve-mux-playback'),
      );
      req.headers.addAll({
        'apikey': anon,
        'Origin': origin,
        'Access-Control-Request-Method': 'POST',
      });
      return http.Response.fromStream(await req.send());
    }

    final evilRes = await options(evil);
    final goodRes = await options(good);
    final evilAcao =
        evilRes.headers['access-control-allow-origin'] ?? '';
    final goodAcao =
        goodRes.headers['access-control-allow-origin'] ?? '';
    // Evil NÃO pode receber o próprio origin; good deve espelhar fleaber.pt.
    final pass = evilAcao != evil && goodAcao == good;
    return {
      'pass': pass,
      'aviso': true, // extensão PS não exercitada
      'summary': 'evil_acao=$evilAcao good_acao=$goodAcao',
      'evidence': {
        'method': 'OPTIONS',
        'evil_origin': evil,
        'evil_acao': evilAcao,
        'good_origin': good,
        'good_acao': goodAcao,
        'evil_status': evilRes.statusCode,
        'good_status': goodRes.statusCode,
      },
    };
  });

  // ─── SEC-020 ───────────────────────────────────────────────
  await run('APP-SEC-020', 'Broadcast rifa directo revogado', () async {
    final fake = '00000000-0000-4000-8000-000000000001';
    final r = await rpcRaw(
      'batata_live_raffle_social_broadcast',
      {'p_live_id': fake, 'p_kind': 'share'},
      token: buyerTok,
    );
    return {
      'pass': rpcDenied(r),
      'aviso': true, // FOMO/saco UI não nesta corrida
      'summary': 'http=${r.statusCode}',
      'evidence': {
        'status': r.statusCode,
        'body_snip': r.body.length > 200 ? r.body.substring(0, 200) : r.body,
      },
    };
  });

  // ─── SEC-021 ───────────────────────────────────────────────
  await run('APP-SEC-021', 'recompute ownership (outsider)', () async {
    final items = await client.select(
      'live_items',
      filter: 'order=created_at.desc',
      limit: 80,
    );
    // Outsider real: outro seller E sem reserva do buyer nesse item.
    String? target;
    String? targetSeller;
    for (final it in items) {
      final liveId = it['live_id']?.toString() ?? '';
      final iid = it['id']?.toString() ?? '';
      if (!isUuid(liveId) || !isUuid(iid)) continue;
      final lives =
          await client.select('lives', filter: 'id=eq.$liveId', limit: 1);
      if (lives.isEmpty) continue;
      final sid = (lives.first['seller_id'] ?? lives.first['vendedor_id'])
          ?.toString();
      if (sid == null || sid == buyerId) continue;
      final mine = await client.select(
        'live_reservation_requests',
        filter: 'live_item_id=eq.$iid&buyer_id=eq.$buyerId',
        limit: 1,
      );
      if (mine.isNotEmpty) continue;
      target = iid;
      targetSeller = sid;
      break;
    }
    if (target == null) {
      return {
        'pass': false,
        'skip': true,
        'summary': 'sem live_item outsider sem reserva do buyer',
      };
    }
    final r = await rpcRaw(
      'batata_recompute_live_item_status',
      {'p_live_item_id': target},
      token: buyerTok,
    );
    var denied = false;
    if (r.statusCode >= 200 && r.statusCode < 300) {
      try {
        final j = jsonDecode(r.body);
        if (j is Map) {
          denied = j['ok'] == false && j['error']?.toString() == 'not_allowed';
        }
      } catch (_) {}
    } else {
      denied = rpcDenied(r);
    }
    return {
      'pass': denied,
      'aviso': true, // saco/studio happy-path não retestado
      'summary':
          'item=$target seller=$targetSeller http=${r.statusCode} denied=$denied',
      'evidence': {
        'live_item_id': target,
        'seller_id': targetSeller,
        'status': r.statusCode,
        'body': r.body.length > 240 ? r.body.substring(0, 240) : r.body,
      },
    };
  });

  // ─── SEC-022 ───────────────────────────────────────────────
  await run('APP-SEC-022', 'app_logs sem INSERT anon', () async {
    final r = await restPost('app_logs', {
      'level': 'error',
      'message': 'c23-sec-022-anon-probe',
      'context': {'probe': true},
    });
    final blocked = r.statusCode >= 400;
    return {
      'pass': blocked,
      'summary': 'anon_insert_http=${r.statusCode}',
      'evidence': {
        'status': r.statusCode,
        'body_snip': r.body.length > 200 ? r.body.substring(0, 200) : r.body,
      },
    };
  });

  // ─── SEC-023 ───────────────────────────────────────────────
  await run('APP-SEC-023', 'studio logs sem spoof seller', () async {
    final r = await restPost(
      'live_vendor_studio_logs',
      {
        'seller_id': sellerId,
        'actor_id': buyerId,
        'event': 'c23_spoof_probe',
        'payload': {'probe': true},
      },
      headers: userH(buyerTok),
    );
    final blocked = r.statusCode >= 400;
    return {
      'pass': blocked,
      'aviso': true, // studio UI happy-path não retestado
      'summary': 'spoof_insert_http=${r.statusCode}',
      'evidence': {
        'status': r.statusCode,
        'body_snip': r.body.length > 200 ? r.body.substring(0, 200) : r.body,
      },
    };
  });

  // ─── SEC-024 ───────────────────────────────────────────────
  await run('APP-SEC-024', 'live_viewers SELECT scoped', () async {
    final lives = await client.select(
      'lives',
      filter: 'order=created_at.desc',
      limit: 5,
    );
    if (lives.isEmpty) {
      return {'pass': false, 'skip': true, 'summary': 'sem lives'};
    }
    // Pick a live owned by seller; as buyer, dump viewers should not list others.
    String? liveId;
    for (final l in lives) {
      final sid = (l['seller_id'] ?? l['vendedor_id'])?.toString();
      if (sid == sellerId) {
        liveId = l['id']?.toString();
        break;
      }
    }
    liveId ??= lives.first['id']?.toString();
    final r = await restGet(
      'live_viewers?live_id=eq.$liveId&select=*&limit=50',
      token: buyerTok,
    );
    var scoped = r.statusCode >= 400;
    var otherUsers = 0;
    if (r.statusCode >= 200 && r.statusCode < 300) {
      try {
        final list = jsonDecode(r.body);
        if (list is List) {
          for (final e in list) {
            if (e is Map) {
              final uid = e['user_id']?.toString();
              if (uid != null && uid.isNotEmpty && uid != buyerId) {
                otherUsers++;
              }
            }
          }
          scoped = otherUsers == 0;
        }
      } catch (_) {}
    }
    return {
      'pass': scoped,
      'aviso': true, // chat player UI não retestado
      'summary':
          'http=${r.statusCode} other_viewers_visible=$otherUsers scoped=$scoped',
      'evidence': {
        'live_id': liveId,
        'status': r.statusCode,
        'other_users': otherUsers,
        'body_snip': r.body.length > 220 ? r.body.substring(0, 220) : r.body,
      },
    };
  });

  // ─── SEC-025 ───────────────────────────────────────────────
  await run('APP-SEC-025', 'wallet/credit só participantes', () async {
    final ensureOther = await rpcRaw(
      'batata_ensure_wallet',
      {'p_user_id': sellerId},
      token: buyerTok,
    );
    final ensureBlocked = ensureOther.statusCode >= 400 ||
        ensureOther.body.toLowerCase().contains('not_allowed') ||
        ensureOther.body.contains('42501');
    final credit = await rpcRaw(
      'batata_credit_wallet_once',
      {
        'p_user_id': buyerId,
        'p_order_id': '00000000-0000-4000-8000-000000000001',
        'p_amount': 999,
        'p_reason': 'hack',
        'p_idempotency_key': 'c23-sec-025',
      },
      token: buyerTok,
    );
    final creditDenied = rpcDenied(credit);
    return {
      'pass': ensureBlocked && creditDenied,
      'aviso': true, // disputa parcial UI não nesta corrida
      'summary':
          'ensure_other_blocked=$ensureBlocked credit_denied=$creditDenied',
      'evidence': {
        'ensure_status': ensureOther.statusCode,
        'ensure_snip': ensureOther.body.length > 160
            ? ensureOther.body.substring(0, 160)
            : ensureOther.body,
        'credit_status': credit.statusCode,
        'credit_snip':
            credit.body.length > 160 ? credit.body.substring(0, 160) : credit.body,
      },
    };
  });

  // ─── SEC-027 ───────────────────────────────────────────────
  await run('APP-SEC-027', 'Storage chat_media: anon sem write', () async {
    final path =
        'c23_sec_probe/${DateTime.now().millisecondsSinceEpoch}_anon.txt';
    final r = await http.post(
      Uri.parse('$url/storage/v1/object/chat_media/$path'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'Content-Type': 'text/plain',
      },
      body: 'c23-anon-write-probe',
    );
    final blocked = r.statusCode >= 400;
    return {
      'pass': blocked,
      'aviso': true, // upload chat foto UI não nesta corrida
      'summary': 'anon_upload_http=${r.statusCode}',
      'evidence': {
        'path': path,
        'status': r.statusCode,
        'body_snip': r.body.length > 200 ? r.body.substring(0, 200) : r.body,
      },
    };
  });

  // ─── SEC-008 (parcial auto) ────────────────────────────────
  await run('APP-SEC-008', 'PS claim pairing RPC revogada ao cliente', () async {
    final r = await rpcRaw(
      'batata_ps_claim_pairing',
      {
        'p_code': '000000',
        'p_device_token': 'c23-probe',
        'p_device_label': 'c23',
      },
      token: buyerTok,
    );
    return {
      'pass': rpcDenied(r),
      'aviso': true, // pairing real PS Reader não testado
      'summary': 'http=${r.statusCode}',
      'evidence': {
        'status': r.statusCode,
        'body_snip': r.body.length > 200 ? r.body.substring(0, 200) : r.body,
      },
    };
  });

  final pass = results.where((r) => r['status'] == 'PASS').length;
  final aviso = results.where((r) => r['status'] == 'PASS_COM_AVISO').length;
  final fail = results.where((r) => r['status'] == 'FAIL').length;
  final skip = results.where((r) => r['status'] == 'SKIP').length;

  final summary = {
    'battery': 'C23_SEC_AUTO',
    'date': DateTime.now().toIso8601String(),
    'project_url': url,
    'counts': {
      'total': results.length,
      'PASS': pass,
      'PASS_COM_AVISO': aviso,
      'FAIL': fail,
      'SKIP': skip,
    },
    'note_batata':
        'Só prova de ataque bloqueado (API/SQL). Sem criar directo Mux. '
        'UI happy-path / PS Reader / rifa ao vivo = AVISO quando aplicável.',
    'results': results,
  };

  final jsonOut = File('${outDir.path}/c23_sec_auto_results.json');
  jsonOut.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(summary),
  );
  log('wrote ${jsonOut.path}');
  log('counts PASS=$pass AVISO=$aviso FAIL=$fail SKIP=$skip');

  // Screenshot Redmi (sessão app — evidência visual residual se device online)
  try {
    final adb =
        r'C:\Users\Casa\AppData\Local\Android\Sdk\platform-tools\adb.exe';
    final shot =
        '${shots.path}/c23_sec_redmi_session_${DateTime.now().millisecondsSinceEpoch}.png';
    final ps = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-File',
        'tool/fleaber_adb_screencap.ps1',
        '-Device',
        'd6pnqgz5jvnnbm9x',
        '-OutFile',
        shot,
      ],
      workingDirectory: Directory.current.path,
    );
    log('screencap exit=${ps.exitCode} ${ps.stdout}${ps.stderr}');
    summary['screenshot_redmi'] = {
      'path': shot,
      'exit': ps.exitCode,
    };
    jsonOut.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
    );
  } catch (e) {
    log('screencap skip: $e');
  }

  await sink.close();
  exit(fail > 0 ? 2 : 0);
}
