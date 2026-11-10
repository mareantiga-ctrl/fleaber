/// Pass 1 — mapa da órbita + lentes E1–E9 (sem captura Stripe ainda).
import 'dart:convert';
import 'dart:io';
import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();

  final findings = <Map<String, dynamic>>[];
  final map = <String, dynamic>{};
  var n = 0;
  String nid(String s) => 'E1930-${s.toUpperCase()}-${++n}';

  void add(Map<String, dynamic> f) => findings.add(f);

  // ---------------------------------------------------------------------------
  // FASE 1 — mapa
  // ---------------------------------------------------------------------------
  final openapi = await c.req(
    'GET',
    '/rest/v1/',
    extra: {'Accept': 'application/openapi+json'},
  );
  final paths = <String>[];
  final rpcs = <String>[];
  if (openapi.json is Map) {
    final p = (openapi.json as Map)['paths'];
    if (p is Map) {
      for (final k in p.keys) {
        final s = k.toString();
        paths.add(s);
        if (s.startsWith('/rpc/')) rpcs.add(s.substring(5));
      }
    }
  }
  paths.sort();
  rpcs.sort();
  final hubPaths = paths.where((p) => p.contains('hub_')).toList();
  final cronRpcs = rpcs
      .where((r) =>
          r.contains('expire') ||
          r.contains('auto_feedback') ||
          r.contains('cron') ||
          r.contains('release_seller_wallet') ||
          r.contains('cleanup') ||
          r.contains('generate_auto'))
      .toList();
  final notifPaths = paths
      .where((p) =>
          p.contains('notif') ||
          p.contains('device_token') ||
          p.contains('push') ||
          p.contains('fcm'))
      .toList();
  final socialPaths = paths
      .where((p) =>
          p.contains('follow') ||
          p.contains('favorite') ||
          p.contains('block') ||
          p.contains('bundle'))
      .toList();
  map['openapi_http'] = openapi.status;
  map['path_count'] = paths.length;
  map['rpc_count'] = rpcs.length;
  map['hub_paths'] = hubPaths;
  map['cron_rpcs'] = cronRpcs;
  map['notif_paths'] = notifPaths;
  map['social_paths'] = socialPaths;
  map['rpcs_sample'] = rpcs.take(80).toList();

  // ---------------------------------------------------------------------------
  // E1 — vitrine pública (anon)
  // ---------------------------------------------------------------------------
  final hubViews = [
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
  final hubAnon = <String, dynamic>{};
  for (final v in hubViews) {
    final h = await c.rest('GET', '$v?select=*&limit=3');
    hubAnon[v] = {'http': h.status, 'n': h.ok && h.json is List ? (h.json as List).length : -1, 'snip': h.snippet};
    if (h.ok && h.json is List && (h.json as List).isNotEmpty) {
      final row = (h.json as List).first;
      if (row is Map) {
        final keys = row.keys.map((e) => e.toString().toLowerCase()).toSet();
        const pii = {
          'email', 'phone', 'iban', 'mb_way', 'legal_full_name',
          'shipping_line1', 'stream_key', 'mux_stream_key', 'user_id',
          'buyer_id', 'tip_id', 'order_id',
        };
        final hit = keys.intersection(pii);
        if (hit.isNotEmpty) {
          add(finding(
            id: nid('e1-pii'),
            lens: 'E1',
            severity: 'P1',
            title: 'Anon lê PII em $v: $hit',
            pre: 'grant anon SELECT hub_*',
            repro: 'GET $v?select=*&limit=3 as anon',
            proven: true,
            evidence: {'view': v, 'cols': hit.toList(), 'snip': h.snippet},
          ));
        }
      }
    } else if (!h.ok && h.status != 404) {
      map['hub_anon_fail_$v'] = {'http': h.status, 'snip': h.snippet};
    }
  }
  map['hub_anon'] = hubAnon;

  final unpub = await c.rest(
    'GET',
    'hub_profiles_discovery_public?hub_published=eq.false&is_live=eq.false&select=id,handle,full_name,location,hub_published,phone_verified&limit=8',
  );
  final unpubN = unpub.ok && unpub.json is List ? (unpub.json as List).length : -1;
  add(finding(
    id: nid('e1-unpub'),
    lens: 'E1',
    severity: unpubN > 0 ? 'P3' : 'INFO',
    title: unpubN > 0
        ? 'Anon enumera perfis hub_published=false e is_live=false'
        : 'Anon NÃO enumera discovery unpublished (filtro LIVE)',
    pre: 'hub_profiles_discovery_public grant anon',
    repro: 'GET hub_profiles_discovery_public?hub_published=eq.false&is_live=eq.false',
    proven: unpubN > 0,
    evidence: {'http': unpub.status, 'n': unpubN, 'snip': unpub.snippet},
  ));

  final soldHub = await c.rest(
    'GET',
    'hub_products_public?is_sold=eq.true&select=id,title,is_sold,price,seller_handle&limit=5',
  );
  map['hub_sold'] = {'http': soldHub.status, 'snip': soldHub.snippet};

  final rhMiss = await c.rpc('batata_resolve_handle', {'p_handle': 'nao-existe-$prefix'});
  map['resolve_miss'] = {'http': rhMiss.status, 'snip': rhMiss.snippet};

  final sellerProf = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=handle,hub_published,is_live',
    service: true,
  );
  String? sellerHandle;
  if (sellerProf.ok && sellerProf.json is List && (sellerProf.json as List).isNotEmpty) {
    sellerHandle = ((sellerProf.json as List).first as Map)['handle']?.toString();
  }
  if (sellerHandle != null && sellerHandle.isNotEmpty) {
    final rh = await c.rpc('batata_resolve_handle', {'p_handle': sellerHandle});
    map['resolve_seller'] = {'http': rh.status, 'snip': rh.snippet};
  }
  final rhB2 = await c.rpc('batata_resolve_handle', {'p_handle': 'rte1930b2'});
  add(finding(
    id: nid('e1-ghost-handle'),
    lens: 'E1',
    severity: (rhB2.ok && rhB2.body.contains('"found":true')) ? 'P3' : 'INFO',
    title: rhB2.body.contains('"found":true')
        ? 'resolve_handle revela UUID de handle claimado sem hub_published'
        : 'resolve_handle não revela ghost unpublished',
    pre: 'buyer2 handle rte1930b2 hub_published=false',
    repro: 'rpc batata_resolve_handle rte1930b2 as anon',
    proven: rhB2.body.contains('"found":true'),
    evidence: {'http': rhB2.status, 'snip': rhB2.snippet},
  ));

  final livesPub = await c.rest('GET', 'hub_lives_public?select=id,status,seller_handle&limit=3');
  if (livesPub.ok && livesPub.json is List && (livesPub.json as List).isNotEmpty) {
    final lid = ((livesPub.json as List).first as Map)['id'];
    final fomo = await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': lid});
    map['fomo'] = {'http': fomo.status, 'snip': fomo.snippet};
    if (fomo.ok && fomo.body.contains('available_qty')) {
      add(finding(
        id: nid('e1-fomo-qty'),
        lens: 'E1',
        severity: 'P3',
        title: 'Anon FOMO devolve available_qty exacto',
        pre: 'live pública',
        repro: 'rpc batata_hub_live_fomo_snapshot as anon',
        proven: true,
        evidence: {'snip': fomo.snippet},
        note: 'stock intel, não PII; não é oversell sozinho.',
      ));
    }
  }

  final baseTables = [
    'profiles', 'products', 'orders', 'wallets', 'lives', 'live_items',
    'user_notifications', 'favorites', 'follows', 'product_bundles',
  ];
  final anonBase = <String, dynamic>{};
  for (final t in baseTables) {
    final h = await c.rest('GET', '$t?select=id&limit=2');
    anonBase[t] = {'http': h.status, 'snip': h.snippet};
    if (h.ok && h.json is List && (h.json as List).isNotEmpty && t != 'products') {
      add(finding(
        id: nid('e1-base-$t'),
        lens: 'E1',
        severity: t == 'orders' || t == 'wallets' || t == 'user_notifications' ? 'P1' : 'P2',
        title: 'Anon SELECT em tabela base $t',
        pre: 'grant/RLS LIVE',
        repro: 'GET $t?select=id&limit=2 as anon',
        proven: true,
        evidence: {'http': h.status, 'snip': h.snippet},
      ));
    }
  }
  map['anon_base'] = anonBase;

  // ---------------------------------------------------------------------------
  // E2 — cron mentiroso (JWT / anon)
  // ---------------------------------------------------------------------------
  final cronTries = <String, dynamic>{};
  Future<void> tryCron(String fn, Object args, String who, String? jwt) async {
    final h = await c.rpc(fn, args, jwt: jwt);
    cronTries['$fn|$who'] = {'http': h.status, 'snip': h.snippet};
    final opened = h.ok && !h.body.toLowerCase().contains('permission') &&
        !h.body.contains('42501') &&
        h.status != 401 &&
        h.status != 403 &&
        !(h.status == 404);
    if (opened && jwt != c.svc) {
      add(finding(
        id: nid('e2-$fn'),
        lens: 'E2',
        severity: fn.contains('feedback') || fn.contains('wallet') ? 'P1' : 'P2',
        title: '$who executou job $fn',
        pre: 'EXECUTE grant LIVE',
        repro: 'POST /rpc/$fn as $who args=$args',
        proven: true,
        evidence: {'http': h.status, 'snip': h.snippet},
        note: 'efeito económico ainda não encadeado neste passo',
      ));
    }
  }

  final future = DateTime.now().toUtc().add(const Duration(days: 60)).toIso8601String();
  await tryCron('batata_generate_auto_feedback', {'p_now': future}, 'anon', null);
  await tryCron('batata_generate_auto_feedback', {'p_now': future}, 'buyer', c.buyerJwt);
  await tryCron('batata_expire_product_offers', {}, 'anon', null);
  await tryCron('batata_expire_product_offers', {}, 'buyer', c.buyerJwt);
  await tryCron('batata_release_seller_wallet_for_order', {
    'p_order_id': '00000000-0000-0000-0000-000000000001',
  }, 'buyer', c.buyerJwt);
  for (final fn in cronRpcs) {
    if (fn == 'batata_generate_auto_feedback' ||
        fn == 'batata_expire_product_offers' ||
        fn == 'batata_release_seller_wallet_for_order') {
      continue;
    }
    await tryCron(fn, {}, 'buyer', c.buyerJwt);
  }
  final egress = await c.edge('livekit-egress-cleanup', {}, jwt: c.buyerJwt);
  cronTries['edge_egress'] = {'http': egress.status, 'snip': egress.snippet};
  map['cron_tries'] = cronTries;

  // ---------------------------------------------------------------------------
  // E3 — push / notifications
  // ---------------------------------------------------------------------------
  final notifIns = await c.rest(
    'POST',
    'user_notifications',
    jwt: c.buyerJwt,
    prefer: 'return=representation',
    body: {
      'user_id': c.sellerId,
      'kind': 'rte',
      'title': '$prefix push',
      'body': 'cross-user',
    },
  );
  add(finding(
    id: nid('e3-notif-ins'),
    lens: 'E3',
    severity: notifIns.ok ? 'P1' : 'INFO',
    title: notifIns.ok
        ? 'Buyer INSERT user_notifications no UID do seller'
        : 'Buyer NÃO insere notificação alheia',
    pre: 'RLS user_notifications',
    repro: 'POST user_notifications user_id=seller as buyer',
    proven: notifIns.ok,
    evidence: {'http': notifIns.status, 'snip': notifIns.snippet},
  ));

  final notifRead = await c.rest(
    'GET',
    'user_notifications?user_id=eq.${c.sellerId}&select=id,user_id,title&limit=5',
    jwt: c.buyerJwt,
  );
  final notifN = notifRead.ok && notifRead.json is List ? (notifRead.json as List).length : 0;
  add(finding(
    id: nid('e3-notif-read'),
    lens: 'E3',
    severity: notifN > 0 ? 'P1' : 'INFO',
    title: notifN > 0 ? 'Buyer lê notificações do seller' : 'Buyer não lê notif alheias',
    pre: 'RLS select',
    repro: 'GET user_notifications?user_id=eq.seller',
    proven: notifN > 0,
    evidence: {'http': notifRead.status, 'n': notifN, 'snip': notifRead.snippet},
  ));

  final nv = await c.rest('GET', 'notifications_view?select=*&limit=5');
  map['notifications_view_anon'] = {'http': nv.status, 'snip': nv.snippet};
  if (nv.ok && nv.json is List && (nv.json as List).isNotEmpty) {
    add(finding(
      id: nid('e3-nv-anon'),
      lens: 'E3',
      severity: 'P1',
      title: 'Anon lê notifications_view (favoritos alheios)',
      pre: 'grant view',
      repro: 'GET notifications_view as anon',
      proven: true,
      evidence: {'snip': nv.snippet},
    ));
  }

  for (final t in ['seller_device_tokens', 'device_tokens', 'push_tokens', 'fcm_tokens']) {
    final h = await c.rest('GET', '$t?select=*&limit=5', jwt: c.buyer2Jwt);
    map['token_table_$t'] = {'http': h.status, 'snip': h.snippet};
    if (h.ok && h.json is List && (h.json as List).isNotEmpty) {
      add(finding(
        id: nid('e3-$t'),
        lens: 'E3',
        severity: 'P1',
        title: 'Buyer2 leu $t (tokens alheios)',
        pre: 'RLS tokens',
        repro: 'GET $t JWT buyer2',
        proven: true,
        evidence: {'http': h.status, 'snip': h.snippet},
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // E5 — Connect / banco
  // ---------------------------------------------------------------------------
  final connCross = await c.edge('create-connect-account', {
    'user_id': c.sellerId,
  }, jwt: c.buyer2Jwt);
  add(finding(
    id: nid('e5-connect-uid'),
    lens: 'E5',
    severity: connCross.ok ? 'P1' : 'INFO',
    title: connCross.ok
        ? 'Buyer2 onboarding Connect com user_id do seller'
        : 'Connect recusa user_id cruzado',
    pre: 'POST create-connect-account',
    repro: 'POST create-connect-account user_id=seller JWT buyer2',
    proven: connCross.ok,
    evidence: {'http': connCross.status, 'snip': connCross.snippet},
  ));

  for (final o in [
    'https://evil.example/phish',
    'https://fleaber.pt.evil.com/',
    'http://169.254.169.254/',
    'https://attacker.fleaber.pt/',
    '//evil.com',
    'https://fleaber.pt@evil.com/',
  ]) {
    final h = await c.req(
      'GET',
      '/functions/v1/create-connect-account?web_return_origin=${Uri.encodeQueryComponent(o)}',
      jwt: c.buyerJwt,
    );
    final loc = '${h.location ?? ''} ${h.body}';
    map['connect_origin_${o.hashCode}'] = {
      'o': o,
      'http': h.status,
      'location': h.location,
      'snip': h.snippet,
    };
    final bounced = loc.toLowerCase().contains('evil') ||
        loc.contains('169.254') ||
        loc.contains('attacker.fleaber');
    if (bounced && h.status >= 300 && h.status < 400) {
      add(finding(
        id: nid('e7-connect-redirect'),
        lens: 'E7',
        severity: 'P1',
        title: 'create-connect-account open redirect: $o',
        pre: 'web_return_origin',
        repro: 'GET create-connect-account?web_return_origin=$o',
        proven: true,
        evidence: {'http': h.status, 'location': h.location, 'snip': h.snippet},
      ));
    }
  }

  final iban = await c.rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': c.sellerId},
    jwt: c.buyer2Jwt,
  );
  final ibanLeak = iban.ok &&
      iban.body.contains('iban') &&
      !iban.body.contains('[]') &&
      iban.body.length > 8;
  add(finding(
    id: nid('e5-iban'),
    lens: 'E5',
    severity: ibanLeak ? 'P1' : 'INFO',
    title: ibanLeak
        ? 'Buyer2 obteve IBAN/MB WAY sem relação off-platform'
        : 'IBAN oracle fechado para buyer2 sem order aceite',
    pre: 'rpc batata_seller_direct_payment_details',
    repro: 'rpc p_seller_id=seller JWT buyer2',
    proven: ibanLeak,
    evidence: {'http': iban.status, 'snip': iban.snippet},
  ));

  final ibanCols = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=id,iban,mb_way,legal_full_name,phone',
    jwt: c.buyer2Jwt,
  );
  add(finding(
    id: nid('e5-profile-iban'),
    lens: 'E5',
    severity: (ibanCols.ok &&
            ibanCols.body.contains('"iban"') &&
            !ibanCols.body.contains('"iban":null') &&
            ibanCols.json is List &&
            (ibanCols.json as List).isNotEmpty)
        ? 'P1'
        : 'INFO',
    title: 'Buyer2 SELECT iban/mb_way em profiles.seller',
    pre: 'RLS profiles',
    repro: 'GET profiles?select=iban,mb_way JWT buyer2',
    proven: ibanCols.ok && ibanCols.json is List && (ibanCols.json as List).isNotEmpty &&
        ibanCols.body.contains('"iban"') &&
        !ibanCols.body.contains('"iban":null'),
    evidence: {'http': ibanCols.status, 'snip': ibanCols.snippet},
  ));

  // ---------------------------------------------------------------------------
  // E7 — return URL payment
  // ---------------------------------------------------------------------------
  for (final o in [
    'https://evil.example/x',
    'https://fleaber.pt.evil.com',
    'https://fleaber.pt%00.evil.com',
  ]) {
    final h = await c.edge('create-payment-intent', {
      'web_return_origin': o,
      'order_id': '00000000-0000-0000-0000-000000000001',
    }, jwt: c.buyerJwt);
    map['pay_origin_${o.hashCode}'] = {'o': o, 'http': h.status, 'snip': h.snippet};
  }

  // ---------------------------------------------------------------------------
  // E8 — grafo social
  // ---------------------------------------------------------------------------
  final folOther = await c.rest('POST', 'follows', jwt: c.buyer2Jwt, prefer: 'return=representation', body: {
    'follower_id': c.buyerId,
    'following_id': c.sellerId,
  });
  add(finding(
    id: nid('e8-follow-forge'),
    lens: 'E8',
    severity: folOther.ok ? 'P2' : 'INFO',
    title: folOther.ok ? 'Buyer2 forja follow como buyer1' : 'Follow exige follower_id=auth.uid()',
    pre: 'RLS follows',
    repro: 'POST follows follower_id=buyer1 JWT buyer2',
    proven: folOther.ok,
    evidence: {'http': folOther.status, 'snip': folOther.snippet},
  ));

  final folEnum = await c.rest(
    'GET',
    'follows?select=follower_id,following_id&limit=20',
    jwt: c.buyer2Jwt,
  );
  int folN = 0;
  if (folEnum.ok && folEnum.json is List) {
    for (final row in folEnum.json as List) {
      if (row is Map) {
        final a = row['follower_id']?.toString();
        final b = row['following_id']?.toString();
        if (a != c.buyer2Id && b != c.buyer2Id) folN++;
      }
    }
  }
  add(finding(
    id: nid('e8-follow-enum'),
    lens: 'E8',
    severity: folN > 0 ? 'P2' : 'INFO',
    title: folN > 0 ? 'Buyer2 enumera follows alheios' : 'Follows scoped às partes',
    pre: 'RLS follows select',
    repro: 'GET follows JWT buyer2',
    proven: folN > 0,
    evidence: {'http': folEnum.status, 'foreign': folN, 'snip': folEnum.snippet},
  ));

  // favorite flood (DoS) — 8 inserts same product if exists
  final prod = await c.rest(
    'GET',
    'products?seller_id=eq.${c.sellerId}&list_on_marketplace=eq.true&is_sold=eq.false&select=id&limit=1',
    jwt: c.sellerJwt,
  );
  String? listedPid;
  if (prod.ok && prod.json is List && (prod.json as List).isNotEmpty) {
    listedPid = ((prod.json as List).first as Map)['id']?.toString();
  }
  if (listedPid != null) {
    var favOk = 0;
    for (var i = 0; i < 8; i++) {
      final h = await c.rest('POST', 'favorites', jwt: c.buyer2Jwt, body: {
        'user_id': c.buyer2Id,
        'product_id': listedPid,
      });
      if (h.ok) favOk++;
    }
    map['fav_flood'] = {'ok': favOk, 'pid': listedPid};
  }

  // ---------------------------------------------------------------------------
  // E9 — invite / sms
  // ---------------------------------------------------------------------------
  final sms = await c.edge('send-sms-bulkgate', {
    'phone': '+351912345678',
    'text': '$prefix',
  }, jwt: c.buyerJwt);
  map['sms'] = {'http': sms.status, 'snip': sms.snippet};
  if (sms.ok && sms.body.toLowerCase().contains('ok')) {
    add(finding(
      id: nid('e9-sms'),
      lens: 'E9',
      severity: 'P1',
      title: 'JWT dispara send-sms-bulkgate',
      pre: 'edge SMS hook',
      repro: 'POST send-sms-bulkgate JWT buyer',
      proven: true,
      evidence: {'http': sms.status, 'snip': sms.snippet},
    ));
  }

  // ---------------------------------------------------------------------------
  // E4 prep — bundle hostile insert
  // ---------------------------------------------------------------------------
  if (listedPid != null) {
    final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, prefer: 'return=representation', body: {
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'product_ids': [listedPid],
      'subtotal_eur': 99.0,
      'discount_pct': 50,
      'discount_eur': 49.5,
      'total_eur': 0.50,
      'status': 'accepted',
    });
    map['bundle_hostile_insert'] = {'http': bun.status, 'snip': bun.snippet};
    final accepted = bun.ok && bun.body.contains('accepted');
    final cheap = bun.ok && bun.body.contains('0.5');
    add(finding(
      id: nid('e4-bundle-ins'),
      lens: 'E4',
      severity: (accepted || (cheap && bun.body.contains('"status":"pending"'))) ? 'P2' : 'INFO',
      title: accepted
          ? 'Buyer INSERT bundle já accepted com total 0.50'
          : (cheap
              ? 'Buyer INSERT bundle pending com total hostil 0.50 (seller ainda tem de aceitar)'
              : 'Bundle INSERT rejeitou desconto/status hostil'),
      pre: 'product_bundles guard',
      repro: 'POST product_bundles discount 50% total 0.50 status=accepted',
      proven: bun.ok,
      evidence: {'http': bun.status, 'snip': bun.snippet},
    ));
  }

  final disc = await c.rest('GET', 'seller_bundle_discounts?select=*&limit=20', jwt: c.buyer2Jwt);
  map['bundle_discounts'] = {'http': disc.status, 'snip': disc.snippet};
  if (disc.ok && disc.json is List && (disc.json as List).length > 1) {
    add(finding(
      id: nid('e4-disc-enum'),
      lens: 'E4',
      severity: 'P3',
      title: 'Buyer2 lê seller_bundle_discounts globais (using true)',
      pre: 'policy select using true',
      repro: 'GET seller_bundle_discounts JWT buyer2',
      proven: true,
      evidence: {'n': (disc.json as List).length, 'snip': disc.snippet},
    ));
  }

  final out = {
    'auditor': 'REDTEAM_BLIND_E_ORBITA_v1',
    'stamp': stamp,
    'project': projectMust,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'actors': {
      'buyer': c.buyerId,
      'seller': c.sellerId,
      'buyer2': c.buyer2Id,
    },
    'map': map,
    'findings': findings,
  };
  final dir = Directory('tool/redteam_blind_e_orbita_$stamp/out');
  if (!dir.existsSync()) {
    // run from repo root or from folder
  }
  final here = Directory.current.path;
  final outPath = here.endsWith('20260830T1930')
      ? 'out/pass1.json'
      : 'tool/redteam_blind_e_orbita_$stamp/out/pass1.json';
  await dumpJson(outPath, out);
  stdout.writeln('pass1 findings=${findings.length} proven=${findings.where((f) => f['proven'] == true).length}');
  stdout.writeln(outPath);
}
