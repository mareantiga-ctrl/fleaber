/// REDTEAM_BLIND_E_ORBITA_v1 — PASS 1 mapa + lentes E1–E9.
/// Staging fxdknzrqjenzqcvnwqqq. Stripe TEST. No production. No Fase 4. No fixes.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '_http.dart';

Future<void> main() async {
  final c = await boot();
  stdout.writeln(
    'E PASS1 boot seller=${c.sellerId} buyer=${c.buyerId} b2=${c.buyer2Id}',
  );

  final rpcNames = await _openapi(c);
  Future<void> lens(String name, Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e, st) {
      rec(
        lens: name,
        surface: 'PROBE',
        attack: 'exception',
        identity: 'n/a',
        result: '$e',
      );
      gaps.add('$name exception: $e');
      stdout.writeln('LENS $name error: $e\n$st');
    }
  }

  await lens('E1', () => _e1Hub(c));
  await lens('E2', () => _e2Crons(c, rpcNames));
  await lens('E3', () => _e3Notif(c));
  await lens('E4', () => _e4Bundle(c));
  await lens('E5', () => _e5Connect(c));
  await lens('E6', () => _e6Soft(c));
  await lens('E7', () => _e7Return(c));
  await lens('E8', () => _e8Social(c));
  await lens('E9', () => _e9Invite(c));

  await dumpJson(
    'tool/redteam_blind_e_orbita_20260830T1810/out/pass1.json',
    {
      'auditor': 'REDTEAM_BLIND_E_ORBITA_v1',
      'project': projectMust,
      'prefix': prefix,
      'pass': 1,
      'production_touched': false,
      'fase4': false,
      'corrections_applied': false,
      'matrix': matrix,
      'findings': findings,
      'gaps': gaps,
    },
  );
  stdout.writeln(
    'PASS1 done matrix=${matrix.length} findings=${findings.length}',
  );
}

Future<List<String>> _openapi(Ctx c) async {
  final r = await http.get(
    Uri.parse('${c.url}/rest/v1/'),
    headers: {
      ...c.anonH,
      'Accept': 'application/openapi+json',
    },
  );
  final rpcNames = <String>[];
  final hubPaths = <String>[];
  try {
    final j = jsonDecode(r.body);
    if (j is Map && j['paths'] is Map) {
      for (final k in (j['paths'] as Map).keys) {
        final p = k.toString();
        if (p.startsWith('/rpc/')) {
          rpcNames.add(p.replaceFirst('/rpc/', ''));
        }
        if (p.contains('hub_') ||
            p.contains('follow') ||
            p.contains('favorite') ||
            p.contains('notif') ||
            p.contains('bundle') ||
            p.contains('device')) {
          hubPaths.add(p);
        }
      }
    }
  } catch (_) {}
  rec(
    lens: 'MAP',
    surface: 'POSTGREST',
    attack: 'openapi_orbit_inventory',
    identity: 'anon',
    result: 'rpcs=${rpcNames.length} orbit_paths=${hubPaths.length}',
    evidence: {
      'cronish': rpcNames
          .where(
            (n) =>
                n.contains('expire') ||
                n.contains('auto_feedback') ||
                n.contains('cron') ||
                n.contains('release') ||
                n.contains('tick') ||
                n.contains('cleanup') ||
                n.contains('generate'),
          )
          .toList(),
      'hub_paths': hubPaths.take(60).toList(),
    },
  );
  await dumpJson(
    'tool/redteam_blind_e_orbita_20260830T1810/out/openapi_orbit.json',
    {'rpc_count': rpcNames.length, 'rpcs': rpcNames, 'hub_paths': hubPaths},
  );
  return rpcNames;
}

Future<void> _e1Hub(Ctx c) async {
  const views = [
    'hub_profiles_public',
    'hub_lives_public',
    'hub_products_public',
    'hub_live_items_public',
    'hub_live_messages_public',
    'hub_reviews_public',
    'hub_lives_discovery_public',
    'hub_profiles_discovery_public',
    'hub_live_items_discovery_public',
  ];
  const sensitive = [
    'phone',
    'email',
    'iban',
    'mb_way',
    'shipping_line1',
    'legal_full_name',
    'mux_stream_key',
    'stream_key',
    'buyer_id',
    'user_id',
    'tip_id',
    'order_id',
  ];

  for (final v in views) {
    final r = await rest(
      c.url,
      'GET',
      v,
      headers: c.anonH,
      qs: 'select=*&limit=5',
    );
    rec(
      lens: 'E1',
      surface: v,
      attack: 'anon_select',
      identity: 'anon',
      result: brief(r, 350),
    );
    if (looksOk(r)) {
      final body = r.body.toLowerCase();
      final hits = sensitive.where((s) => body.contains('"$s"')).toList();
      if (hits.isNotEmpty) {
        finding(
          id: 'E1-$v-PII',
          severity: 'P1',
          title: 'View $v expoe colunas sensiveis a anon',
          actor: 'anon',
          pre: 'GET rest/v1/$v',
          repro: 'anon select * limit 5',
          impact: 'Leak PII/keys Hub publico: $hits',
          evidence: {'hits': hits, 'sample': brief(r, 600)},
        );
      }
    }
  }

  final baseTables = [
    'profiles',
    'products',
    'lives',
    'live_items',
    'live_messages',
    'reviews_gerais',
    'wallets',
    'orders',
  ];
  for (final t in baseTables) {
    final r = await rest(
      c.url,
      'GET',
      t,
      headers: c.anonH,
      qs: 'select=*&limit=3',
    );
    rec(
      lens: 'E1',
      surface: t,
      attack: 'anon_base_table',
      identity: 'anon',
      result: brief(r, 220),
    );
    if (looksOk(r) && r.body.trim() != '[]' && r.body.trim().isNotEmpty) {
      finding(
        id: 'E1-BASE-$t',
        severity: t == 'wallets' || t == 'orders' ? 'P0' : 'P1',
        title: 'Anon le tabela base $t (nao so hub_*)',
        actor: 'anon',
        pre: 'revoke anon em tabelas base esperado',
        repro: 'GET /rest/v1/$t',
        impact: 'Bypass da vitrine whitelist',
        evidence: brief(r, 500),
      );
    }
  }

  final unpublished = await rest(
    c.url,
    'GET',
    'hub_profiles_discovery_public',
    headers: c.anonH,
    qs: 'select=id,handle,full_name,location,hub_published,phone_verified,external_payments_enabled&hub_published=eq.false&limit=8',
  );
  rec(
    lens: 'E1',
    surface: 'hub_profiles_discovery_public',
    attack: 'anon_unpublished_enum',
    identity: 'anon',
    result: brief(unpublished, 400),
  );
  dynamic unpubJson = tryJson(unpublished);
  if (looksOk(unpublished) && unpubJson is List && unpubJson.isNotEmpty) {
    finding(
      id: 'E1-DISCOVERY-UNPUB',
      severity: 'P2',
      title: 'Anon enumera perfis com hub_published=false (nome, local, id)',
      actor: 'anon',
      pre: 'view discovery sem exigir hub_published',
      repro: 'GET hub_profiles_discovery_public?hub_published=eq.false',
      impact: 'Vitrine nao publicada ainda enumeravel; PII leve (nome/local/UUID)',
      evidence: unpubJson.take(3).toList(),
    );
  }

  // resolve_handle: published + unpublished + garbage
  for (final h in ['fleahub-demo-ux', 'nao-existe-rte-xyz', c.sellerId]) {
    final r = await rpc(
      c.url,
      'batata_resolve_handle',
      {'p_handle': h},
      headers: c.anonH,
    );
    rec(
      lens: 'E1',
      surface: 'batata_resolve_handle',
      attack: 'anon_resolve_$h',
      identity: 'anon',
      result: brief(r, 300),
    );
  }

  // seller unpublished handle if any
  final sellerProf = await rest(
    c.url,
    'GET',
    'profiles',
    headers: c.svcH,
    qs: 'id=eq.${c.sellerId}&select=id,handle,hub_published,full_name,location,phone,iban,mb_way,email',
  );
  rec(
    lens: 'E1',
    surface: 'profiles',
    attack: 'svc_seller_shape',
    identity: 'service_role_observe',
    result: brief(sellerProf, 280),
  );
  dynamic sp = tryJson(sellerProf);
  String? handle;
  if (sp is List && sp.isNotEmpty) {
    handle = sp.first['handle']?.toString();
  }
  if (handle != null && handle.isNotEmpty) {
    final r = await rpc(
      c.url,
      'batata_resolve_handle',
      {'p_handle': handle},
      headers: c.anonH,
    );
    rec(
      lens: 'E1',
      surface: 'batata_resolve_handle',
      attack: 'anon_seller_handle',
      identity: 'anon',
      result: brief(r, 350),
    );
  }

  // FOMO snapshot: pick a public live id
  final lives = await rest(
    c.url,
    'GET',
    'hub_lives_public',
    headers: c.anonH,
    qs: 'select=id,status,seller_id&limit=2',
  );
  dynamic livesJ = tryJson(lives);
  if (livesJ is List && livesJ.isNotEmpty) {
    final lid = livesJ.first['id']?.toString();
    if (lid != null) {
      final fomo = await rpc(
        c.url,
        'batata_hub_live_fomo_snapshot',
        {'p_live_id': lid},
        headers: c.anonH,
      );
      rec(
        lens: 'E1',
        surface: 'batata_hub_live_fomo_snapshot',
        attack: 'anon_fomo_exact_qty',
        identity: 'anon',
        result: brief(fomo, 400),
      );
    }
  }

  // follow / reserve without auth
  final fol = await rest(
    c.url,
    'POST',
    'follows',
    headers: c.anonH,
    body: {'follower_id': c.buyerId, 'following_id': c.sellerId},
  );
  rec(
    lens: 'E1',
    surface: 'follows',
    attack: 'anon_follow',
    identity: 'anon',
    result: brief(fol, 220),
  );
  if (looksOk(fol)) {
    finding(
      id: 'E1-ANON-FOLLOW',
      severity: 'P1',
      title: 'Anon consegue INSERT follows',
      actor: 'anon',
      pre: 'grant follows revogado a anon esperado',
      repro: 'POST /rest/v1/follows',
      impact: 'Grafo social sem login',
      evidence: brief(fol, 400),
    );
  }
}

Future<void> _e2Crons(Ctx c, List<String> rpcNames) async {
  final cronish = <String, Map<String, dynamic>>{
    'batata_generate_auto_feedback': {
      'p_now': DateTime.now().toUtc().add(const Duration(days: 400)).toIso8601String(),
    },
    'batata_expire_product_offers': {},
    'batata_release_seller_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_tick_live_raffle': {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
    },
  };
  for (final e in cronish.entries) {
    if (rpcNames.isNotEmpty && !rpcNames.contains(e.key)) {
      rec(
        lens: 'E2',
        surface: e.key,
        attack: 'rpc_missing_openapi',
        identity: 'n/a',
        result: 'not in openapi',
      );
    }
    for (final idn in [
      ['anon', c.anonH],
      ['buyer', c.buyerH],
      ['seller', c.sellerH],
    ]) {
      final r = await rpc(c.url, e.key, e.value, headers: idn[1] as Map<String, String>);
      rec(
        lens: 'E2',
        surface: e.key,
        attack: 'hostile_fire',
        identity: idn[0] as String,
        result: brief(r, 280),
      );
      if (looksOk(r) && (idn[0] as String) != 'n/a') {
        finding(
          id: 'E2-${e.key}-${idn[0]}',
          severity: e.key.contains('wallet') || e.key.contains('feedback')
              ? 'P1'
              : 'P2',
          title: 'Job ${e.key} invocavel por ${idn[0]} (nao so cron/service)',
          actor: idn[0] as String,
          pre: 'jobs devem ser service_role/cron',
          repro: 'POST /rpc/${e.key} as JWT',
          impact: 'Disparo cedo / duplicado de job economico ou de estado',
          evidence: brief(r, 500),
        );
      }
    }
  }

  final cleanupEdge = await edge(
    c.url,
    'livekit-egress-cleanup',
    anon: c.anon,
    jwt: c.buyerJwt,
    body: {},
  );
  rec(
    lens: 'E2',
    surface: 'livekit-egress-cleanup',
    attack: 'buyer_jwt_fire',
    identity: 'buyer',
    result: brief(cleanupEdge, 220),
  );
  if (looksOk(cleanupEdge)) {
    finding(
      id: 'E2-EGRESS-JWT',
      severity: 'P2',
      title: 'Edge livekit-egress-cleanup aceita JWT buyer',
      actor: 'buyer',
      pre: 'so cron secret / service_role',
      repro: 'POST functions/v1/livekit-egress-cleanup',
      impact: 'Stop egress alheio / DoS gravacao',
      evidence: brief(cleanupEdge, 400),
    );
  }
}

Future<void> _e3Notif(Ctx c) async {
  for (final t in [
    'user_notifications',
    'notifications_view',
    'seller_device_tokens',
  ]) {
    final anonR = await rest(
      c.url,
      'GET',
      t,
      headers: c.anonH,
      qs: 'select=*&limit=5',
    );
    rec(
      lens: 'E3',
      surface: t,
      attack: 'anon_select',
      identity: 'anon',
      result: brief(anonR, 220),
    );
    final cross = await rest(
      c.url,
      'GET',
      t,
      headers: c.buyerH,
      qs: 'select=*&limit=20',
    );
    rec(
      lens: 'E3',
      surface: t,
      attack: 'buyer_select_all',
      identity: 'buyer',
      result: brief(cross, 280),
    );
    if (looksOk(cross)) {
      final j = tryJson(cross);
      if (j is List) {
        final others = j.where((row) {
          if (row is! Map) return false;
          final uid = (row['user_id'] ??
                  row['target_user_id'] ??
                  row['seller_id'] ??
                  '')
              .toString();
          return uid.isNotEmpty && uid != c.buyerId;
        }).toList();
        if (others.isNotEmpty) {
          finding(
            id: 'E3-CROSS-$t',
            severity: t == 'seller_device_tokens' ? 'P1' : 'P2',
            title: 'Buyer le rows de $t de outro UID',
            actor: 'buyer',
            pre: 'RLS own-only',
            repro: 'GET $t as buyer',
            impact: 'Cross-user notif/token',
            evidence: others.take(2).toList(),
          );
        }
      }
    }
  }

  final ins = await rest(
    c.url,
    'POST',
    'user_notifications',
    headers: c.buyerH,
    body: {
      'user_id': c.sellerId,
      'kind': 'rte_e_probe',
      'title': '$prefix push alheio',
      'body': 'probe',
    },
  );
  rec(
    lens: 'E3',
    surface: 'user_notifications',
    attack: 'insert_to_other_uid',
    identity: 'buyer',
    result: brief(ins, 280),
  );
  if (looksOk(ins)) {
    finding(
      id: 'E3-INSERT-ALIEN',
      severity: 'P1',
      title: 'Buyer INSERT user_notifications para UID do vendedor',
      actor: 'buyer',
      pre: 'sem policy INSERT authenticated',
      repro: 'POST user_notifications user_id=seller',
      impact: 'Notificacao / push a conta alheia',
      evidence: brief(ins, 500),
    );
    try {
      final j = tryJson(ins);
      if (j is List && j.isNotEmpty) {
        final id = j.first['id']?.toString();
        if (id != null) {
          await rest(
            c.url,
            'DELETE',
            'user_notifications',
            headers: c.svcH,
            qs: 'id=eq.$id',
          );
        }
      }
    } catch (_) {}
  }

  final patchOther = await rest(
    c.url,
    'PATCH',
    'user_notifications',
    headers: c.buyerH,
    qs: 'user_id=eq.${c.sellerId}',
    body: {'is_read': true},
  );
  rec(
    lens: 'E3',
    surface: 'user_notifications',
    attack: 'patch_other_read',
    identity: 'buyer',
    result: brief(patchOther, 220),
  );
}

Future<void> _e4Bundle(Ctx c) async {
  // Fixture products
  final p1 = await rest(
    c.url,
    'POST',
    'products',
    headers: c.svcH,
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix-p1',
      'price': 12.0,
      'quantity': 3,
      'list_on_marketplace': true,
      'is_sold': false,
    },
  );
  final p2 = await rest(
    c.url,
    'POST',
    'products',
    headers: c.svcH,
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix-p2',
      'price': 18.0,
      'quantity': 3,
      'list_on_marketplace': true,
      'is_sold': false,
    },
  );
  rec(
    lens: 'E4',
    surface: 'products',
    attack: 'fixture_insert',
    identity: 'service_role_setup',
    result: '${brief(p1, 120)} | ${brief(p2, 120)}',
  );
  String? id1;
  String? id2;
  final j1 = tryJson(p1);
  final j2 = tryJson(p2);
  if (j1 is List && j1.isNotEmpty) id1 = j1.first['id']?.toString();
  if (j2 is List && j2.isNotEmpty) id2 = j2.first['id']?.toString();
  if (id1 == null || id2 == null) {
    gaps.add('E4 fixture products failed');
    return;
  }
  cleanup['products'] = [id1, id2];

  // Buyer write other seller discounts
  final disc = await rest(
    c.url,
    'POST',
    'seller_bundle_discounts',
    headers: c.buyerH,
    body: {
      'seller_id': c.sellerId,
      'enabled': true,
      'tier_2_pct': 50,
      'tier_3_pct': 50,
      'tier_5_pct': 50,
    },
  );
  rec(
    lens: 'E4',
    surface: 'seller_bundle_discounts',
    attack: 'buyer_write_seller_tiers',
    identity: 'buyer',
    result: brief(disc, 250),
  );
  if (looksOk(disc)) {
    finding(
      id: 'E4-DISC-CROSS',
      severity: 'P0',
      title: 'Buyer escreve seller_bundle_discounts de outro seller',
      actor: 'buyer',
      pre: 'write so own',
      repro: 'POST seller_bundle_discounts seller_id=vitima',
      impact: 'Desconto hostil no checkout de conjuntos (ate 50%)',
      evidence: brief(disc, 500),
    );
  }

  final discGet = await rest(
    c.url,
    'GET',
    'seller_bundle_discounts',
    headers: c.buyerH,
    qs: 'select=*&limit=20',
  );
  rec(
    lens: 'E4',
    surface: 'seller_bundle_discounts',
    attack: 'buyer_enum_all_tiers',
    identity: 'buyer',
    result: brief(discGet, 280),
  );

  // Nao PATCH custom_tiers no seller de QA (evita corromper config real).

  // Buyer INSERT bundle as purchased with hostile totals
  final bun = await rest(
    c.url,
    'POST',
    'product_bundles',
    headers: c.buyerH,
    body: {
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'product_ids': [id1, id2],
      'subtotal_eur': 30.0,
      'discount_pct': 50.0,
      'discount_eur': 15.0,
      'total_eur': 0.50,
      'status': 'purchased',
    },
  );
  rec(
    lens: 'E4',
    surface: 'product_bundles',
    attack: 'buyer_insert_purchased_050',
    identity: 'buyer',
    result: brief(bun, 350),
  );
  String? bid;
  dynamic bunJ = tryJson(bun);
  if (looksOk(bun) && bunJ is List && bunJ.isNotEmpty) {
    bid = bunJ.first['id']?.toString();
    final st = bunJ.first['status']?.toString();
    final tot = bunJ.first['total_eur'];
    if (st == 'purchased' || st == 'accepted') {
      finding(
        id: 'E4-BUNDLE-SELF-PURCHASE',
        severity: 'P1',
        title: 'Buyer INSERT product_bundles com status=$st (sem aceite do seller)',
        actor: 'buyer',
        pre: 'guard forca pending no INSERT buyer',
        repro: 'POST product_bundles status=purchased',
        impact: 'Conjunto marcado comprado/aceite sem o vendedor; holds/checkout',
        evidence: bunJ.first,
      );
    }
    if (tot is num && tot <= 1) {
      rec(
        lens: 'E4',
        surface: 'product_bundles',
        attack: 'hostile_total_persisted',
        identity: 'buyer',
        result: 'total_eur=$tot status=$st',
        impact: 'row aceita total hostil (Edge pode recomputar)',
      );
    }
  }
  if (bid != null) {
    cleanup['product_bundles'] = [bid];
    final patch = await rest(
      c.url,
      'PATCH',
      'product_bundles',
      headers: c.buyerH,
      qs: 'id=eq.$bid',
      body: {
        'status': 'accepted',
        'discount_pct': 50,
        'total_eur': 0.50,
      },
    );
    rec(
      lens: 'E4',
      surface: 'product_bundles',
      attack: 'buyer_self_accept_patch',
      identity: 'buyer',
      result: brief(patch, 350),
    );
    if (looksOk(patch)) {
      final pj = tryJson(patch);
      var st = '';
      if (pj is List && pj.isNotEmpty) st = pj.first['status']?.toString() ?? '';
      if (st == 'accepted' || st == 'purchased') {
        finding(
          id: 'E4-BUNDLE-SELF-ACCEPT',
          severity: 'P1',
          title: 'Buyer PATCH bundle para status=$st sem ser o vendedor',
          actor: 'buyer',
          pre: 'update parties; guard nao trava status',
          repro: 'PATCH product_bundles status=accepted',
          impact: 'Aceite falso → criar encomendas/reservas do conjunto',
          evidence: pj,
        );
      }
    }

    // Try create hold orders from fake-accepted bundle
    final ord = await rest(
      c.url,
      'POST',
      'orders',
      headers: c.buyerH,
      body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': id1,
        'price_total': 0.50,
        'status': 'reservado',
        'is_reservation': true,
        'payment_method': 'Compra em conjunto aceite',
        'bundle_id': bid,
        'quantity': 1,
      },
    );
    rec(
      lens: 'E4',
      surface: 'orders',
      attack: 'order_from_self_accepted_bundle',
      identity: 'buyer',
      result: brief(ord, 350),
    );
    if (looksOk(ord)) {
      finding(
        id: 'E4-HOLD-FROM-FAKE-ACCEPT',
        severity: 'P1',
        title: 'Buyer cria order reservado a partir de bundle auto-aceite',
        actor: 'buyer',
        pre: 'bundle PATCH accepted pelo proprio buyer',
        repro: 'POST orders bundle_id=... status=reservado',
        impact: 'Hold de stock sem o vendedor ter aceite o conjunto',
        evidence: brief(ord, 500),
      );
      final oj = tryJson(ord);
      if (oj is List && oj.isNotEmpty) {
        final oid = oj.first['id']?.toString();
        if (oid != null) {
          cleanup['orders'] = [...(cleanup['orders'] ?? []), oid];
        }
      }
    }
  }

  // Buyer2 cannot read buyer1 bundle
  if (bid != null) {
    final x = await rest(
      c.url,
      'GET',
      'product_bundles',
      headers: c.buyer2H,
      qs: 'id=eq.$bid&select=*',
    );
    rec(
      lens: 'E4',
      surface: 'product_bundles',
      attack: 'buyer2_read_other_bundle',
      identity: 'buyer2',
      result: brief(x, 220),
    );
    if (looksOk(x) && x.body.trim() != '[]') {
      finding(
        id: 'E4-BUNDLE-CROSS-READ',
        severity: 'P2',
        title: 'Segundo buyer le product_bundles alheio',
        actor: 'buyer2',
        pre: 'select parties',
        repro: 'GET product_bundles id=eq.victim',
        impact: 'Precos/ids de conjunto de outro par',
        evidence: brief(x, 400),
      );
    }
  }
}

Future<void> _e5Connect(Ctx c) async {
  final origins = [
    'https://evil.com',
    'https://fleaber.pt.evil.com',
    'https://evil.fleaber.pt',
    'https://fleaber.pt@evil.com',
    'http://localhost',
    'https://fleaber.pt',
    'https://www.fleaber.app/phishing',
  ];
  for (final o in origins) {
    final r = await edge(
      c.url,
      'create-connect-account',
      anon: c.anon,
      method: 'GET',
      qs: '?wallet_return=1&web_return_origin=${Uri.encodeQueryComponent(o)}',
    );
    final loc = r.headers['location'] ?? r.headers['Location'] ?? '';
    rec(
      lens: 'E5',
      surface: 'create-connect-account',
      attack: 'get_open_redirect',
      identity: 'anon',
      result: '${r.statusCode} loc=$loc',
      evidence: {'origin': o, 'location': loc, 'body': brief(r, 160)},
    );
    if (r.statusCode >= 300 && r.statusCode < 400) {
      final locL = loc.toLowerCase();
      final hostile = locL.contains('evil.com') ||
          (o.contains('evil.fleaber') && locL.contains('evil.fleaber'));
      if (hostile) {
        finding(
          id: 'E5-OPEN-REDIRECT',
          severity: 'P1',
          title: 'Connect GET redireciona para origem hostil',
          actor: 'anon',
          pre: 'sanitizeWebReturnOrigin allowlist',
          repro: 'GET create-connect-account?web_return_origin=$o',
          impact: 'Open redirect pos-onboarding / phishing wallet',
          evidence: {'origin': o, 'location': loc},
        );
      }
    }
  }

  final swap = await edge(
    c.url,
    'create-connect-account',
    anon: c.anon,
    jwt: c.buyerJwt,
    body: {'user_id': c.sellerId},
  );
  rec(
    lens: 'E5',
    surface: 'create-connect-account',
    attack: 'user_id_swap',
    identity: 'buyer',
    result: brief(swap, 280),
  );
  if (looksOk(swap)) {
    finding(
      id: 'E5-ACCOUNT-SWAP',
      severity: 'P0',
      title: 'Buyer cria/liga Connect account do seller via user_id',
      actor: 'buyer',
      pre: 'body.user_id deve == JWT',
      repro: 'POST create-connect-account user_id=seller',
      impact: 'Onboarding/payouts na conta Stripe alheia',
      evidence: brief(swap, 500),
    );
  }

  final iban = await rpc(
    c.url,
    'batata_seller_direct_payment_details',
    {'p_seller_id': c.sellerId},
    headers: c.buyer2H,
  );
  rec(
    lens: 'E5',
    surface: 'batata_seller_direct_payment_details',
    attack: 'buyer2_iban_no_order',
    identity: 'buyer2',
    result: brief(iban, 280),
  );
  final ibanJ = tryJson(iban);
  if (looksOk(iban) && ibanJ is List && ibanJ.isNotEmpty) {
    final row = ibanJ.first;
    if (row is Map &&
        ((row['iban'] ?? '').toString().isNotEmpty ||
            (row['mb_way'] ?? '').toString().isNotEmpty)) {
      finding(
        id: 'E5-IBAN-ORACLE',
        severity: 'P1',
        title: 'Buyer sem encomenda off-platform le IBAN/MB WAY do seller',
        actor: 'buyer2',
        pre: 'oracle so com order off-platform aceite',
        repro: 'rpc batata_seller_direct_payment_details',
        impact: 'Dados bancarios a estranho',
        evidence: {'keys': row.keys.toList()},
      );
    }
  }

  // Stripe webhook Connect-ish without sig
  final wh = await edge(
    c.url,
    'stripe-webhook',
    anon: c.anon,
    body: {
      'type': 'account.updated',
      'data': {
        'object': {'id': 'acct_RTE', 'metadata': {'fleaber_user_id': c.buyerId}},
      },
    },
  );
  rec(
    lens: 'E5',
    surface: 'stripe-webhook',
    attack: 'unsigned_account_updated',
    identity: 'anon',
    result: brief(wh, 250),
  );
}

Future<void> _e6Soft(Ctx c) async {
  final p = await rest(
    c.url,
    'POST',
    'products',
    headers: c.svcH,
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix-unlist',
      'price': 9.5,
      'quantity': 2,
      'list_on_marketplace': true,
      'is_sold': false,
    },
  );
  rec(
    lens: 'E6',
    surface: 'products',
    attack: 'fixture_unlist',
    identity: 'service_role_setup',
    result: brief(p, 180),
  );
  String? pid;
  final pj = tryJson(p);
  if (pj is List && pj.isNotEmpty) pid = pj.first['id']?.toString();
  if (pid == null) {
    gaps.add('E6 product fixture failed');
    return;
  }
  cleanup['products'] = [...(cleanup['products'] ?? []), pid];

  final listed = await rest(
    c.url,
    'GET',
    'hub_products_public',
    headers: c.anonH,
    qs: 'id=eq.$pid&select=id,title,price,is_sold,seller_id',
  );
  rec(
    lens: 'E6',
    surface: 'hub_products_public',
    attack: 'listed_visible',
    identity: 'anon',
    result: brief(listed, 220),
  );

  await rest(
    c.url,
    'PATCH',
    'products',
    headers: c.svcH,
    qs: 'id=eq.$pid',
    body: {'list_on_marketplace': false, 'is_sold': true},
  );

  final stillHub = await rest(
    c.url,
    'GET',
    'hub_products_public',
    headers: c.anonH,
    qs: 'id=eq.$pid&select=id,title,is_sold',
  );
  rec(
    lens: 'E6',
    surface: 'hub_products_public',
    attack: 'after_unlist_sold',
    identity: 'anon',
    result: brief(stillHub, 220),
  );

  final stillAuth = await rest(
    c.url,
    'GET',
    'products',
    headers: c.buyerH,
    qs: 'id=eq.$pid&select=id,title,list_on_marketplace,is_sold,quantity,price',
  );
  rec(
    lens: 'E6',
    surface: 'products',
    attack: 'buyer_read_unlisted_sold',
    identity: 'buyer',
    result: brief(stillAuth, 250),
  );

  final checkoutSold = await rest(
    c.url,
    'POST',
    'orders',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'price_total': 9.5,
      'status': 'reserva_pendente',
      'quantity': 1,
    },
  );
  rec(
    lens: 'E6',
    surface: 'orders',
    attack: 'order_unlisted_sold',
    identity: 'buyer',
    result: brief(checkoutSold, 320),
  );
  if (looksOk(checkoutSold)) {
    finding(
      id: 'E6-SOLD-STILL-ORDER',
      severity: 'P1',
      title: 'Buyer cria encomenda em produto is_sold + unlisted',
      actor: 'buyer',
      pre: 'produto morto nao deve criar hold novo',
      repro: 'POST orders product_id=unlist/sold',
      impact: 'Mortos que vendem — stock/hold apos unpublish',
      evidence: brief(checkoutSold, 500),
    );
    final oj = tryJson(checkoutSold);
    if (oj is List && oj.isNotEmpty) {
      final oid = oj.first['id']?.toString();
      if (oid != null) {
        cleanup['orders'] = [...(cleanup['orders'] ?? []), oid];
      }
    }
  }

  // Hard delete
  await rest(
    c.url,
    'DELETE',
    'products',
    headers: c.svcH,
    qs: 'id=eq.$pid',
  );
  final afterDel = await rest(
    c.url,
    'GET',
    'hub_products_public',
    headers: c.anonH,
    qs: 'id=eq.$pid&select=id',
  );
  rec(
    lens: 'E6',
    surface: 'hub_products_public',
    attack: 'after_hard_delete',
    identity: 'anon',
    result: brief(afterDel, 180),
  );
}

Future<void> _e7Return(Ctx c) async {
  final fake = await edge(
    c.url,
    'create-payment-intent',
    anon: c.anon,
    method: 'GET',
    qs: '?checkout_return=success&session_id=cs_test_rte_alien',
  );
  rec(
    lens: 'E7',
    surface: 'create-payment-intent',
    attack: 'alien_session_id',
    identity: 'anon',
    result: '${fake.statusCode} ${brief(fake, 200)} loc=${fake.headers['location'] ?? ''}',
  );

  final origins = [
    'https://evil.com',
    'https://sub.fleaber.pt',
    'javascript:alert(1)',
    'https://fleaber.pt/\\@evil.com',
  ];
  for (final o in origins) {
    final r = await edge(
      c.url,
      'create-payment-intent',
      anon: c.anon,
      jwt: c.buyerJwt,
      body: {
        'web_return_origin': o,
        'order_id': '00000000-0000-0000-0000-000000000001',
      },
    );
    rec(
      lens: 'E7',
      surface: 'create-payment-intent',
      attack: 'post_web_return_origin',
      identity: 'buyer',
      result: brief(r, 220),
      evidence: o,
    );
  }
}

Future<void> _e8Social(Ctx c) async {
  final fol = await rest(
    c.url,
    'POST',
    'follows',
    headers: c.buyerH,
    body: {
      'follower_id': c.sellerId,
      'following_id': c.buyer2Id,
    },
  );
  rec(
    lens: 'E8',
    surface: 'follows',
    attack: 'follow_as_other_uid',
    identity: 'buyer',
    result: brief(fol, 250),
  );
  if (looksOk(fol)) {
    finding(
      id: 'E8-FOLLOW-FORGE',
      severity: 'P1',
      title: 'Buyer INSERT follow com follower_id alheio',
      actor: 'buyer',
      pre: 'follower_id = auth.uid()',
      repro: 'POST follows follower_id=seller',
      impact: 'Forjar grafo / unfollow impossivel pela vitima se so delete own',
      evidence: brief(fol, 400),
    );
  }

  final own = await rest(
    c.url,
    'POST',
    'follows',
    headers: c.buyerH,
    body: {
      'follower_id': c.buyerId,
      'following_id': c.sellerId,
    },
  );
  rec(
    lens: 'E8',
    surface: 'follows',
    attack: 'follow_self_ok',
    identity: 'buyer',
    result: brief(own, 220),
  );
  if (looksOk(own)) {
    final j = tryJson(own);
    if (j is List && j.isNotEmpty) {
      final id = j.first['id']?.toString();
      if (id != null) {
        await rest(
          c.url,
          'DELETE',
          'follows',
          headers: c.buyerH,
          qs: 'id=eq.$id',
        );
      }
    }
  }

  // Favorite DoS: 30 inserts same product if unique missing
  final prods = cleanup['products'] ?? [];
  final pid = prods.isNotEmpty ? prods.first : null;
  if (pid != null) {
    var ok = 0;
    String? lastId;
    for (var i = 0; i < 12; i++) {
      final r = await rest(
        c.url,
        'POST',
        'favorites',
        headers: c.buyerH,
        body: {'user_id': c.buyerId, 'product_id': pid},
      );
      if (looksOk(r)) {
        ok++;
        final j = tryJson(r);
        if (j is List && j.isNotEmpty) lastId = j.first['id']?.toString();
      } else if (i == 0) {
        rec(
          lens: 'E8',
          surface: 'favorites',
          attack: 'first_insert',
          identity: 'buyer',
          result: brief(r, 180),
        );
      }
    }
    rec(
      lens: 'E8',
      surface: 'favorites',
      attack: 'dup_burst',
      identity: 'buyer',
      result: 'ok_inserts=$ok/12',
    );
    if (ok > 1) {
      finding(
        id: 'E8-FAV-DOS',
        severity: 'P3',
        title: 'favorites permite duplicados (burst ${ok}x mesmo par)',
        actor: 'buyer',
        pre: 'unique (user_id, product_id) esperado',
        repro: 'POST favorites 12x mesmo product',
        impact: 'DoS storage / notifications_view inflado',
        evidence: {'ok': ok},
      );
    }
    if (lastId != null) {
      await rest(
        c.url,
        'DELETE',
        'favorites',
        headers: c.svcH,
        qs: 'user_id=eq.${c.buyerId}&product_id=eq.$pid',
      );
    }
  }

  // Block tables?
  for (final t in ['blocks', 'user_blocks', 'blocked_users', 'profile_blocks']) {
    final r = await rest(
      c.url,
      'GET',
      t,
      headers: c.buyerH,
      qs: 'select=*&limit=1',
    );
    rec(
      lens: 'E8',
      surface: t,
      attack: 'table_exists',
      identity: 'buyer',
      result: brief(r, 160),
    );
  }
}

Future<void> _e9Invite(Ctx c) async {
  final r = await rpc(
    c.url,
    'batata_find_user_id_by_email',
    {'p_email': 'rte-missing@example.com'},
    headers: c.buyerH,
  );
  rec(
    lens: 'E9',
    surface: 'batata_find_user_id_by_email',
    attack: 'buyer_email_oracle',
    identity: 'buyer',
    result: brief(r, 250),
  );
  if (looksOk(r) && r.body.trim() != 'null' && r.body.trim().isNotEmpty) {
    finding(
      id: 'E9-EMAIL-ORACLE-BUYER',
      severity: 'P2',
      title: 'Nao-seller resolve email→UUID',
      actor: 'buyer',
      pre: 'so sellers + rate',
      repro: 'rpc batata_find_user_id_by_email',
      impact: 'Enum de contas por email alem do rate conhecido',
      evidence: brief(r, 300),
    );
  }

  final sellerEmail = await rpc(
    c.url,
    'batata_find_user_id_by_email',
    {'p_email': 'nao-existe-rte@fleaber.invalid'},
    headers: c.sellerH,
  );
  rec(
    lens: 'E9',
    surface: 'batata_find_user_id_by_email',
    attack: 'seller_unknown_email',
    identity: 'seller',
    result: brief(sellerEmail, 220),
  );
}
