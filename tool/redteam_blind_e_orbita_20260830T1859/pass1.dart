/// Blind E órbita — Pass 1 mapa + lentes E1–E9.
/// Staging fxdknzrqjenzqcvnwqqq. Stripe TEST. Sem produção. Sem Fase 4. Sem fixes.
import 'dart:convert';
import 'dart:io';

import '_http.dart';

final findings = <Map<String, dynamic>>[];
final notes = <String>[];

void add({
  required String id,
  required String lens,
  required String title,
  required String sev,
  required bool hit,
  required String pre,
  required String repro,
  required Object evidence,
  String impact = '',
}) {
  findings.add({
    'id': id,
    'lens': lens,
    'title': title,
    'sev': sev,
    'hit': hit,
    'pre': pre,
    'repro': repro,
    'evidence': evidence,
    'impact': impact,
  });
  stdout.writeln('${hit ? "HIT" : "ok "} $id $lens $sev $title');
}

bool looksPii(dynamic row) {
  if (row is! Map) return false;
  for (final k in [
    'phone',
    'iban',
    'mb_way',
    'email',
    'legal_full_name',
    'shipping_line1',
    'mux_stream_key',
    'stream_key',
    'user_id',
    'buyer_id',
  ]) {
    if (row.containsKey(k) && row[k] != null && '${row[k]}'.trim().isNotEmpty) {
      return true;
    }
  }
  return false;
}

Future<void> main() async {
  final c = await boot();
  notes.add('buyer=${c.buyerId} seller=${c.sellerId}');

  // ---- mapa OpenAPI ----
  final oa = await c.rest(
    'GET',
    '/rest/v1/',
    extra: {'Accept': 'application/openapi+json'},
  );
  final paths = <String>[];
  final hubPaths = <String>[];
  final cronish = <String>[];
  try {
    final spec = oa.json;
    if (spec is Map && spec['paths'] is Map) {
      for (final k in (spec['paths'] as Map).keys) {
        final p = k.toString();
        paths.add(p);
        if (p.contains('hub_') ||
            p.contains('notif') ||
            p.contains('follow') ||
            p.contains('favorit') ||
            p.contains('bundle') ||
            p.contains('wallet') ||
            p.contains('device_token')) {
          hubPaths.add(p);
        }
        final low = p.toLowerCase();
        if (p.contains('/rpc/') &&
            (low.contains('expire') ||
                low.contains('release') ||
                low.contains('tick') ||
                low.contains('auto_feedback') ||
                low.contains('cleanup') ||
                low.contains('generate') ||
                low.contains('sweep') ||
                low.contains('cron'))) {
          cronish.add(p);
        }
      }
    }
  } catch (e) {
    notes.add('openapi parse: $e');
  }
  await writeOut('pass1_map.json', {
    'openapi_http': oa.status,
    'path_count': paths.length,
    'hub_paths': hubPaths.take(80).toList(),
    'cronish': cronish,
  });

  // ---- E1 vitrine ----
  const hubViews = [
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
    final r = await c.select(v, limit: 5);
    hubAnon[v] = {'http': r.status, 'n': r.ok && r.json is List ? (r.json as List).length : 0, 'snip': r.snippet};
    final rows = r.ok && r.json is List ? r.json as List : [];
    final pii = rows.where(looksPii).toList();
    add(
      id: 'E1-ANON-$v',
      lens: 'E1',
      title: 'Anon lê $v',
      sev: pii.isNotEmpty ? 'P1' : 'info',
      hit: pii.isNotEmpty,
      pre: 'views hub_* grant anon',
      repro: 'GET /rest/v1/$v',
      evidence: {'http': r.status, 'pii_rows': pii.length, 'snip': r.snippet},
      impact: pii.isNotEmpty ? 'PII na vitrine anónima' : '',
    );
  }

  for (final t in ['profiles', 'products', 'lives', 'live_items', 'orders', 'wallets']) {
    final r = await c.select(t, limit: 3);
    final n = r.ok && r.json is List ? (r.json as List).length : 0;
    add(
      id: 'E1-BASE-$t',
      lens: 'E1',
      title: 'Anon lê tabela base $t',
      sev: n > 0 ? 'P2' : 'info',
      hit: n > 0 && t != 'products',
      pre: 'revoke anon em tabelas base',
      repro: 'GET /rest/v1/$t',
      evidence: {'http': r.status, 'n': n, 'snip': r.snippet},
      impact: n > 0 ? 'anon vê linhas privadas' : '',
    );
  }

  final unpub = await c.select(
    'hub_profiles_discovery_public',
    filter: 'hub_published=eq.false',
    select: 'id,handle,full_name,location,hub_published,phone_verified',
    limit: 8,
  );
  final unpubRows = unpub.ok && unpub.json is List ? unpub.json as List : [];
  add(
    id: 'E1-DISCOVERY-UNPUB',
    lens: 'E1',
    title: 'Anon enumera perfis hub_published=false',
    sev: unpubRows.isNotEmpty ? 'P3' : 'info',
    hit: unpubRows.isNotEmpty,
    pre: 'discovery não deve listar vitrines fechadas',
    repro: 'GET hub_profiles_discovery_public?hub_published=eq.false',
    evidence: {'http': unpub.status, 'n': unpubRows.length, 'snip': unpub.snippet},
    impact: unpubRows.isNotEmpty ? 'enum de contas não publicadas' : '',
  );

  final soldHub = await c.select(
    'hub_products_public',
    filter: 'is_sold=eq.true',
    select: 'id,title,price,is_sold,seller_handle',
    limit: 5,
  );
  final soldRows = soldHub.ok && soldHub.json is List ? soldHub.json as List : [];
  add(
    id: 'E1-HUB-SOLD',
    lens: 'E1',
    title: 'Hub lista produtos is_sold=true',
    sev: soldRows.isNotEmpty ? 'P3' : 'info',
    hit: soldRows.isNotEmpty,
    pre: 'vitrine não deve promover mortos',
    repro: 'GET hub_products_public?is_sold=eq.true',
    evidence: {'http': soldHub.status, 'n': soldRows.length, 'snip': soldHub.snippet},
  );

  final rh = await c.rpc('batata_resolve_handle', {'p_handle': 'nao-existe-rte-1859'});
  add(
    id: 'E1-RESOLVE-MISS',
    lens: 'E1',
    title: 'Anon resolve_handle handle inexistente',
    sev: 'info',
    hit: false,
    pre: 'RPC pública',
    repro: 'rpc batata_resolve_handle',
    evidence: {'http': rh.status, 'snip': rh.snippet},
  );

  final sellerProf = await c.select(
    'profiles',
    service: true,
    select: 'id,handle,hub_published,is_live,full_name',
    filter: 'id=eq.${c.sellerId}',
    limit: 1,
  );
  String? sellerHandle;
  if (sellerProf.ok && sellerProf.json is List && (sellerProf.json as List).isNotEmpty) {
    sellerHandle = (sellerProf.json.first as Map)['handle']?.toString();
  }
  if (sellerHandle != null && sellerHandle.isNotEmpty) {
    final rh2 = await c.rpc('batata_resolve_handle', {'p_handle': sellerHandle});
    final body = rh2.json;
    final found = body is Map && body['found'] == true;
    add(
      id: 'E1-RESOLVE-SELLER',
      lens: 'E1',
      title: 'Anon resolve handle do vendedor (profile_id)',
      sev: 'info',
      hit: false,
      pre: 'handle público vs unpublished',
      repro: 'rpc batata_resolve_handle ${clip(sellerHandle, 40)}',
      evidence: {'http': rh2.status, 'found': found, 'hub_published': body is Map ? body['hub_published'] : null, 'snip': rh2.snippet},
    );
  }

  final liveAnon = await c.select('hub_lives_public', select: 'id,status,seller_handle', limit: 1);
  if (liveAnon.ok && liveAnon.json is List && (liveAnon.json as List).isNotEmpty) {
    final lid = (liveAnon.json.first as Map)['id']?.toString();
    if (lid != null) {
      final fomo = await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': lid});
      add(
        id: 'E1-FOMO',
        lens: 'E1',
        title: 'Anon FOMO snapshot (qty exacta?)',
        sev: 'info',
        hit: false,
        pre: 'agregados sem PII',
        repro: 'rpc batata_hub_live_fomo_snapshot',
        evidence: {'http': fomo.status, 'snip': fomo.snippet},
      );
    }
  }

  // ---- fixture buyer2 + unpublished profile ----
  final b2email = '${prefix.toLowerCase()}-b2@fleaber.invalid';
  const b2pass = 'Rte-b2-Pass-1859!x';
  try {
    c.buyer2Id = await c.admin.createAdminUser(
      email: b2email,
      password: b2pass,
      userMetadata: {'full_name': '$prefix Buyer2'},
    );
    c.buyer2Jwt = await c.admin.signIn(email: b2email, password: b2pass);
    await c.rest('PATCH', '/rest/v1/profiles?id=eq.${c.buyer2Id}', service: true, body: {
      'full_name': '$prefix Buyer2',
      'handle': 'rte1859b2',
      'hub_published': false,
      'is_live': false,
    });
    notes.add('buyer2=${c.buyer2Id}');
  } catch (e) {
    notes.add('buyer2 setup: ${clip(e)}');
    // reuse if exists
    try {
      c.buyer2Jwt = await c.admin.signIn(email: b2email, password: b2pass);
      c.buyer2Id = await c.admin.userIdForAccessToken(c.buyer2Jwt!);
    } catch (e2) {
      notes.add('buyer2 signin: ${clip(e2)}');
    }
  }

  if (c.buyer2Id != null) {
    final discB2 = await c.select(
      'hub_profiles_discovery_public',
      filter: 'id=eq.${c.buyer2Id}',
      select: 'id,handle,full_name,hub_published,location',
      limit: 3,
    );
    final n = discB2.ok && discB2.json is List ? (discB2.json as List).length : 0;
    add(
      id: 'E1-UNPUB-FIXTURE',
      lens: 'E1',
      title: 'Anon vê fixture unpublished via discovery',
      sev: n > 0 ? 'P3' : 'info',
      hit: n > 0,
      pre: 'hub_published=false is_live=false',
      repro: 'GET hub_profiles_discovery_public?id=eq.buyer2',
      evidence: {'http': discB2.status, 'n': n, 'snip': discB2.snippet},
    );
    final rhU = await c.rpc('batata_resolve_handle', {'p_handle': 'rte1859b2'});
    final foundU = rhU.json is Map && (rhU.json as Map)['found'] == true;
    add(
      id: 'E1-RESOLVE-UNPUB',
      lens: 'E1',
      title: 'Anon resolve_handle de vitrine não publicada',
      sev: foundU ? 'P3' : 'info',
      hit: foundU,
      pre: 'handle claimado sem hub_published',
      repro: 'rpc batata_resolve_handle rte1859b2',
      evidence: {'http': rhU.status, 'snip': rhU.snippet},
      impact: foundU ? 'UUID de conta não publicada' : '',
    );
  }

  // ---- E2 crons ----
  final jobs = <String, Map<String, dynamic>>{
    'batata_generate_auto_feedback': {'p_now': DateTime.now().toUtc().add(const Duration(days: 400)).toIso8601String()},
    'batata_expire_product_offers': <String, dynamic>{},
    'batata_invoke_livekit_egress_cleanup': <String, dynamic>{},
    'batata_release_seller_wallet_for_order': {'p_order_id': c.buyerId},
    'batata_tick_live_raffle': {'p_raffle_id': c.buyerId},
  };
  for (final e in jobs.entries) {
    for (final who in ['anon', 'buyer', 'seller']) {
      final jwt = who == 'anon'
          ? null
          : (who == 'buyer' ? c.buyerJwt : c.sellerJwt);
      final r = await c.rpc(e.key, e.value, jwt: jwt);
      final bodyTxt = r.snippet.toLowerCase();
      final executed = r.status == 200 &&
          !bodyTxt.contains('false') &&
          !bodyTxt.contains('not_allowed') &&
          !bodyTxt.contains('raffle_not_found') &&
          !bodyTxt.contains('permission') &&
          bodyTxt != 'false';
      add(
        id: 'E2-${e.key}-$who',
        lens: 'E2',
        title: 'Job ${e.key} invocável por $who (efeito)',
        sev: executed ? 'P2' : 'info',
        hit: executed && who != 'seller',
        pre: 'jobs devem ser service_role/cron; HTTP 200 com false não conta',
        repro: 'POST /rest/v1/rpc/${e.key} as $who',
        evidence: {'http': r.status, 'snip': r.snippet},
        impact: executed ? 'JWT dispara job de órbita' : '',
      );
    }
  }

  // expire: criar proposta pending e tentar expire como buyer2
  String? offerId;
  try {
    final prodOffer = await c.rest('POST', '/rest/v1/products', jwt: c.sellerJwt, body: {
      'seller_id': c.sellerId,
      'title': '$prefix offer bait 9.90',
      'price': 9.90,
      'quantity': 3,
      'is_sold': false,
      'list_on_marketplace': true,
    });
    String? pid;
    if (prodOffer.ok) {
      final d = prodOffer.json;
      if (d is List && d.isNotEmpty) pid = (d.first as Map)['id']?.toString();
      if (d is Map) pid = d['id']?.toString();
    }
    if (pid != null) {
      final off = await c.rest('POST', '/rest/v1/product_offers', jwt: c.buyerJwt, body: {
        'product_id': pid,
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'amount': 5.00,
        'status': 'pending',
        'offered_by': 'buyer',
        'expires_at': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
      });
      if (off.ok) {
        final d = off.json;
        if (d is List && d.isNotEmpty) offerId = (d.first as Map)['id']?.toString();
        if (d is Map) offerId = d['id']?.toString();
      }
      notes.add('offer_insert ${off.status} ${off.snippet}');
    }
  } catch (e) {
    notes.add('offer setup ${clip(e)}');
  }
  if (offerId != null) {
    final before = await c.select('product_offers', service: true, filter: 'id=eq.$offerId', select: 'id,status', limit: 1);
    final exp = await c.rpc('batata_expire_product_offers', {}, jwt: c.buyer2Jwt ?? c.buyerJwt);
    final after = await c.select('product_offers', service: true, filter: 'id=eq.$offerId', select: 'id,status', limit: 1);
    final st = after.ok && after.json is List && (after.json as List).isNotEmpty
        ? (after.json.first as Map)['status']
        : null;
    add(
      id: 'E2-EXPIRE-EFFECT',
      lens: 'E2',
      title: 'JWT dispara expire de propostas (efeito real)',
      sev: st == 'expired' ? 'P2' : 'info',
      hit: st == 'expired',
      pre: 'expire só cron/service',
      repro: 'criar offer expired_at passado; rpc batata_expire_product_offers JWT',
      evidence: {
        'offer_id': offerId,
        'expire_http': exp.status,
        'before': before.snippet,
        'after_status': st,
        'expire_snip': exp.snippet,
      },
      impact: st == 'expired' ? 'qualquer JWT mata propostas globais' : '',
    );
  }

  // auto_feedback p_now futuro — se 200, contar reviews inseridas? só se grant
  final af = await c.rpc(
    'batata_generate_auto_feedback',
    {'p_now': '2099-01-01T00:00:00Z'},
    jwt: c.buyerJwt,
  );
  add(
    id: 'E2-AUTOFEEDBACK-FUTURE',
    lens: 'E2',
    title: 'JWT auto_feedback com p_now futuro',
    sev: af.status == 200 ? 'P2' : 'info',
    hit: af.status == 200,
    pre: 'só service_role; p_now não deve saltar 48h via JWT',
    repro: 'rpc batata_generate_auto_feedback p_now=2099',
    evidence: {'http': af.status, 'snip': af.snippet},
  );

  // ---- E3 push / notifications ----
  for (final t in [
    'user_notifications',
    'notifications',
    'notifications_view',
    'seller_device_tokens',
    'device_tokens',
    'push_tokens',
  ]) {
    final r = await c.select(t, jwt: c.buyerJwt, limit: 5);
    final rows = r.ok && r.json is List ? r.json as List : [];
    final cross = rows.where((e) {
      if (e is! Map) return false;
      final uid = '${e['user_id'] ?? e['seller_id'] ?? e['target_user_id'] ?? ''}';
      return uid.isNotEmpty && uid != c.buyerId;
    }).toList();
    add(
      id: 'E3-READ-$t',
      lens: 'E3',
      title: 'Buyer lê $t (cross-user?)',
      sev: cross.isNotEmpty ? 'P1' : 'info',
      hit: cross.isNotEmpty,
      pre: 'só rows do próprio UID',
      repro: 'GET $t as buyer',
      evidence: {'http': r.status, 'n': rows.length, 'cross': cross.length, 'snip': r.snippet},
      impact: cross.isNotEmpty ? 'token/notif alheio' : '',
    );
  }

  final injNotif = await c.rest('POST', '/rest/v1/user_notifications', jwt: c.buyerJwt, body: {
    'user_id': c.sellerId,
    'kind': 'rte_probe',
    'title': '$prefix',
    'body': 'cross',
  });
  add(
    id: 'E3-INSERT-NOTIF-CROSS',
    lens: 'E3',
    title: 'Buyer INSERT user_notifications para UID vendedor',
    sev: injNotif.ok ? 'P1' : 'info',
    hit: injNotif.ok,
    pre: 'sem INSERT policy / só trigger',
    repro: 'POST user_notifications user_id=seller',
    evidence: {'http': injNotif.status, 'snip': injNotif.snippet},
    impact: injNotif.ok ? 'push/in-app a UID alheio' : '',
  );

  if (c.buyer2Jwt != null) {
    final nv = await c.select('notifications_view', jwt: c.buyer2Jwt, limit: 10);
    final rows = nv.ok && nv.json is List ? nv.json as List : [];
    add(
      id: 'E3-NV-B2',
      lens: 'E3',
      title: 'Buyer2 lê notifications_view (favoritos alheios)',
      sev: rows.isNotEmpty ? 'P2' : 'info',
      hit: rows.isNotEmpty,
      pre: 'view filtrada a seller_id=auth.uid()',
      repro: 'GET notifications_view as buyer2',
      evidence: {'http': nv.status, 'n': rows.length, 'snip': nv.snippet},
    );
  }

  final tok = await c.rpc('batata_create_seller_device_token', {
    'p_device_id': 'rte-1859-phone',
    'p_label': prefix,
  }, jwt: c.buyerJwt);
  add(
    id: 'E3-DEVICE-TOKEN-BUYER',
    lens: 'E3',
    title: 'Buyer cria seller_device_token (OCR)',
    sev: tok.ok && tok.json is Map && (tok.json as Map)['ok'] == true ? 'P2' : 'info',
    hit: tok.ok && tok.json is Map && (tok.json as Map)['ok'] == true,
    pre: 'só seller',
    repro: 'rpc batata_create_seller_device_token as buyer',
    evidence: {'http': tok.status, 'snip': tok.snippet},
  );

  // ---- E4 bundle / discounts ----
  final discRead = await c.select('seller_bundle_discounts', jwt: c.buyerJwt, limit: 8);
  add(
    id: 'E4-DISCOUNT-READ',
    lens: 'E4',
    title: 'Buyer lê seller_bundle_discounts globais',
    sev: 'info',
    hit: false,
    pre: 'SELECT auth aberto de propósito (produto)',
    repro: 'GET seller_bundle_discounts as buyer',
    evidence: {'http': discRead.status, 'snip': discRead.snippet},
  );
  final discWrite = await c.rest('POST', '/rest/v1/seller_bundle_discounts', jwt: c.buyerJwt, body: {
    'seller_id': c.sellerId,
    'min_items': 2,
    'percent': 90,
  });
  add(
    id: 'E4-DISCOUNT-WRITE-HOSTILE',
    lens: 'E4',
    title: 'Buyer INSERT desconto 90% na loja alheia',
    sev: discWrite.ok ? 'P1' : 'info',
    hit: discWrite.ok,
    pre: 'escrita só own',
    repro: 'POST seller_bundle_discounts seller_id=seller percent=90',
    evidence: {'http': discWrite.status, 'snip': discWrite.snippet},
    impact: discWrite.ok ? 'desconto hostil no saco' : '',
  );

  final bun = await c.rest('POST', '/rest/v1/product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'status': 'accepted',
    'total_eur': 0.50,
    'discount_eur': 99,
  });
  add(
    id: 'E4-BUNDLE-SELF-ACCEPT',
    lens: 'E4',
    title: 'Buyer cria bundle já accepted com total hostil',
    sev: bun.ok ? 'P2' : 'info',
    hit: bun.ok,
    pre: 'accepted só seller; totais selados',
    repro: 'POST product_bundles status=accepted total_eur=0.50',
    evidence: {'http': bun.status, 'snip': bun.snippet},
  );

  // ---- E5 Connect / banco ----
  final iban = await c.select(
    'profiles',
    jwt: c.buyerJwt,
    select: 'id,iban,mb_way,phone,email',
    filter: 'id=eq.${c.sellerId}',
    limit: 1,
  );
  final ibanHit = iban.ok && iban.json is List && (iban.json as List).isNotEmpty && looksPii(iban.json.first);
  add(
    id: 'E5-IBAN-ORACLE',
    lens: 'E5',
    title: 'Buyer lê IBAN/telefone do vendedor',
    sev: ibanHit ? 'P1' : 'info',
    hit: ibanHit,
    pre: 'colunas bancárias revogadas a JWT alheio',
    repro: 'GET profiles?id=seller&select=iban,mb_way,phone',
    evidence: {'http': iban.status, 'snip': iban.snippet},
  );

  final wBefore = await c.select(
    'wallets',
    service: true,
    select: 'id,stripe_account_id,balance',
    filter: 'id=eq.${c.sellerId}',
    limit: 1,
  );
  final beforeAcct = wBefore.ok && wBefore.json is List && (wBefore.json as List).isNotEmpty
      ? (wBefore.json.first as Map)['stripe_account_id']
      : null;
  final wpatch = await c.rest('PATCH', '/rest/v1/wallets?id=eq.${c.sellerId}', jwt: c.buyerJwt, body: {
    'stripe_account_id': 'acct_RTE1859',
  });
  final wAfter = await c.select(
    'wallets',
    service: true,
    select: 'id,stripe_account_id,balance',
    filter: 'id=eq.${c.sellerId}',
    limit: 1,
  );
  final afterAcct = wAfter.ok && wAfter.json is List && (wAfter.json is List && (wAfter.json as List).isNotEmpty)
      ? (wAfter.json.first as Map)['stripe_account_id']
      : null;
  final mutated = afterAcct == 'acct_RTE1859' && afterAcct != beforeAcct;
  add(
    id: 'E5-WALLET-STRIPE-CROSS',
    lens: 'E5',
    title: 'Buyer PATCH stripe_account_id da wallet do vendedor',
    sev: mutated ? 'P0' : 'info',
    hit: mutated,
    pre: 'wallet só own; 200 [] sem mutação não conta',
    repro: 'PATCH wallets id=seller stripe_account_id',
    evidence: {
      'http': wpatch.status,
      'snip': wpatch.snippet,
      'before': beforeAcct,
      'after': afterAcct,
      'rows_returned': wpatch.snippet,
    },
    impact: mutated ? 'payout para conta Connect alheia' : '',
  );
  if (mutated) {
    await c.rest('PATCH', '/rest/v1/wallets?id=eq.${c.sellerId}', service: true, body: {
      'stripe_account_id': beforeAcct,
    });
    notes.add('restored seller stripe_account_id');
  }

  final conn = await c.edge('create-connect-account', {
    'user_id': c.sellerId,
    'amount': 100,
    'idempotency_key': '${prefix}-x',
  }, jwt: c.buyerJwt);
  add(
    id: 'E5-CONNECT-USER-SPOOF',
    lens: 'E5',
    title: 'Buyer onboarding Connect com user_id do vendedor',
    sev: conn.ok ? 'P1' : 'info',
    hit: conn.ok && !conn.snippet.toLowerCase().contains('cannot create'),
    pre: 'user_id tem de coincidir com JWT',
    repro: 'POST create-connect-account user_id=seller',
    evidence: {'http': conn.status, 'snip': conn.snippet},
  );

  final origins = [
    'https://evil.example/steal',
    'https://fleaber.pt.evil.com',
    'http://evil.com',
    'https://127.0.0.1',
    'https://fleaber.pt',
    'http://localhost:9999',
    'https://notfleaber.pt',
    r'https://fleaber.pt%2F%2Fevil.com',
  ];
  for (final o in origins) {
    try {
      final g = await c.edge(
        'create-connect-account',
        null,
        method: 'GET',
        query: 'web_return_origin=${Uri.encodeQueryComponent(o)}',
      );
      final loc = g.headers['location'] ?? g.headers['Location'] ?? '';
      final locLow = loc.toLowerCase();
      final allowed = locLow.contains('fleaber.pt') ||
          locLow.contains('fleaber.app') ||
          locLow.startsWith('fleaber:') ||
          locLow.contains('intent://');
      final hostile = loc.isNotEmpty && !allowed;
      add(
        id: 'E7-CONNECT-REDIR-${o.hashCode.abs()}',
        lens: 'E7',
        title: 'Connect GET redirect origin=$o',
        sev: hostile ? 'P1' : 'info',
        hit: hostile,
        pre: 'allowlist web_return',
        repro: 'GET create-connect-account?web_return_origin=$o',
        evidence: {'http': g.status, 'location': loc, 'snip': clip(g.snippet, 160)},
        impact: hostile ? 'open redirect' : '',
      );
    } catch (e) {
      notes.add('redir $o ${clip(e)}');
    }
  }

  // ---- E6 mortos + checkout ----
  Future<String?> makeProduct({
    required bool listed,
    required bool sold,
    required String tag,
    int qty = 2,
    double price = 12.5,
  }) async {
    final r = await c.rest('POST', '/rest/v1/products', jwt: c.sellerJwt, body: {
      'seller_id': c.sellerId,
      'title': '$prefix $tag',
      'price': price,
      'quantity': qty,
      'is_sold': sold,
      'list_on_marketplace': listed,
      'description': prefix,
    });
    if (!r.ok) {
      notes.add('product $tag ${r.status} ${r.snippet}');
      return null;
    }
    final d = r.json;
    if (d is List && d.isNotEmpty) return (d.first as Map)['id']?.toString();
    if (d is Map) return d['id']?.toString();
    return null;
  }

  Future<String?> makeOrder(String pid, {String ship = 'mao'}) async {
    final r = await c.rest('POST', '/rest/v1/orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 12.5,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app',
      'shipping_method': ship,
    });
    notes.add('order ${r.status} ${r.snippet}');
    if (!r.ok) return null;
    final d = r.json;
    if (d is List && d.isNotEmpty) return (d.first as Map)['id']?.toString();
    if (d is Map) return d['id']?.toString();
    return null;
  }

  Future<Hit> checkout({
    required String oid,
    required String pid,
    bool bag = false,
  }) {
    return c.edge('create-payment-intent', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'order_id': oid,
      'quantity': 1,
      'currency': 'eur',
      'shipping_method': 'mao',
      if (bag) 'bag_checkout': true,
      if (bag)
        'bag_lines': [
          {
            'order_id': oid,
            'product_id': pid,
            'seller_id': c.sellerId,
            'quantity': 1,
          }
        ],
    }, jwt: c.buyerJwt);
  }

  bool sessionOpened(Hit h) {
    if (!h.ok) return false;
    final j = h.json;
    if (j is Map) {
      final url = '${j['checkoutUrl'] ?? j['url'] ?? ''}';
      final sid = '${j['checkoutSessionId'] ?? j['session_id'] ?? ''}';
      return url.contains('checkout.stripe.com') || sid.startsWith('cs_');
    }
    return h.body.contains('checkout.stripe.com') || h.body.contains('cs_test_');
  }

  // sold product: JWT hold + checkout
  final deadId = await makeProduct(listed: true, sold: true, tag: 'sold');
  if (deadId != null) {
    final oid = await makeOrder(deadId);
    add(
      id: 'E6-HOLD-SOLD',
      lens: 'E6',
      title: 'JWT hold em produto is_sold',
      sev: oid != null ? 'P1' : 'info',
      hit: oid != null,
      pre: 'hold bloqueia is_sold',
      repro: 'POST orders product is_sold=true',
      evidence: {'product': deadId, 'order': oid},
    );
  }

  final unlistedId = await makeProduct(listed: false, sold: false, tag: 'unlist-new', qty: 2);
  if (unlistedId != null) {
    final oid = await makeOrder(unlistedId);
    add(
      id: 'E6-HOLD-UNLIST-NEW',
      lens: 'E6',
      title: 'JWT hold em produto já unlist',
      sev: oid != null ? 'P1' : 'info',
      hit: oid != null,
      pre: 'hold bloqueia unlist sem live',
      repro: 'POST orders list_on_marketplace=false',
      evidence: {'product': unlistedId, 'order': oid},
    );
  }

  // listed → hold → unlist → checkout single vs bag
  final livePid = await makeProduct(listed: true, sold: false, tag: 'then-unlist', qty: 3, price: 12.5);
  String? liveOid;
  if (livePid != null) {
    liveOid = await makeOrder(livePid);
    if (liveOid != null) {
      final ul = await c.rest(
        'PATCH',
        '/rest/v1/products?id=eq.$livePid',
        jwt: c.sellerJwt,
        body: {'list_on_marketplace': false},
      );
      notes.add('unlist ${ul.status} ${ul.snippet}');
      final single = await checkout(oid: liveOid, pid: livePid, bag: false);
      final bagH = await checkout(oid: liveOid, pid: livePid, bag: true);
      add(
        id: 'E6-SINGLE-AFTER-UNLIST',
        lens: 'E6',
        title: 'Checkout Session single após unlist',
        sev: sessionOpened(single) ? 'P1' : 'info',
        hit: sessionOpened(single),
        pre: 'Edge single bloqueia unlist',
        repro: 'hold listed; seller unlist; POST create-payment-intent',
        evidence: {'http': single.status, 'session': sessionOpened(single), 'snip': single.snippet},
        impact: sessionOpened(single) ? 'morto ainda vende (single)' : '',
      );
      add(
        id: 'E6-BAG-AFTER-UNLIST',
        lens: 'E6',
        title: 'Checkout Session saco após unlist (gap vs single)',
        sev: sessionOpened(bagH) ? 'P1' : 'info',
        hit: sessionOpened(bagH),
        pre: 'bag path pode não checar list_on_marketplace',
        repro: 'hold listed; unlist; bag_checkout=true',
        evidence: {'http': bagH.status, 'session': sessionOpened(bagH), 'snip': bagH.snippet},
        impact: sessionOpened(bagH) ? 'saco paga produto morto/unlist' : '',
      );
      if (sessionOpened(bagH)) {
        await writeOut('e6_bag_unlist_session.json', {
          'order_id': liveOid,
          'product_id': livePid,
          'http': bagH.status,
          'body': bagH.snippet,
        });
      }

      // sold after hold
      final soldPatch = await c.rest(
        'PATCH',
        '/rest/v1/products?id=eq.$livePid',
        jwt: c.sellerJwt,
        body: {'is_sold': true, 'list_on_marketplace': false},
      );
      notes.add('sold ${soldPatch.status}');
      final bagSold = await checkout(oid: liveOid, pid: livePid, bag: true);
      add(
        id: 'E6-BAG-AFTER-SOLD',
        lens: 'E6',
        title: 'Saco checkout após is_sold',
        sev: sessionOpened(bagSold) ? 'P1' : 'info',
        hit: sessionOpened(bagSold),
        pre: 'RPC checkout_available bloqueia is_sold',
        repro: 'is_sold=true; bag_checkout',
        evidence: {'http': bagSold.status, 'session': sessionOpened(bagSold), 'snip': bagSold.snippet},
      );
    }
  }

  // vacation_mode
  try {
    await c.rest('PATCH', '/rest/v1/profiles?id=eq.${c.sellerId}', service: true, body: {
      'vacation_mode': true,
    });
    final vacPid = await makeProduct(listed: true, sold: false, tag: 'vacation', price: 12.5);
    if (vacPid != null) {
      final oid = await makeOrder(vacPid);
      if (oid != null) {
        final ch = await checkout(oid: oid, pid: vacPid);
        add(
          id: 'E6-VACATION-CHECKOUT',
          lens: 'E6',
          title: 'Checkout com vendedor em vacation_mode',
          sev: sessionOpened(ch) ? 'P3' : 'info',
          hit: sessionOpened(ch),
          pre: 'férias não é P0; anotar se Session abre',
          repro: 'vacation_mode=true; checkout',
          evidence: {'http': ch.status, 'session': sessionOpened(ch), 'snip': ch.snippet},
        );
      }
    }
    await c.rest('PATCH', '/rest/v1/profiles?id=eq.${c.sellerId}', service: true, body: {
      'vacation_mode': false,
    });
  } catch (e) {
    notes.add('vacation ${clip(e)}');
  }

  // qty 0
  final zid = await makeProduct(listed: true, sold: false, tag: 'qty0', qty: 0);
  if (zid != null) {
    final oid = await makeOrder(zid);
    add(
      id: 'E6-HOLD-QTY0',
      lens: 'E6',
      title: 'JWT hold qty=0',
      sev: oid != null ? 'P2' : 'info',
      hit: oid != null,
      pre: 'stock 0 não hold',
      repro: 'product quantity=0; POST order',
      evidence: {'product': zid, 'order': oid},
    );
  }

  // ---- E7 session_id alheio ----
  final alien = await c.select(
    'orders',
    service: true,
    select: 'id,buyer_id,stripe_checkout_session_id,status',
    filter: 'stripe_checkout_session_id=not.is.null',
    limit: 3,
  );
  String? alienSid;
  if (alien.ok && alien.json is List) {
    for (final row in alien.json as List) {
      if (row is Map) {
        final sid = '${row['stripe_checkout_session_id'] ?? ''}';
        if (sid.startsWith('cs_') && row['buyer_id']?.toString() != c.buyerId) {
          alienSid = sid;
          break;
        }
      }
    }
  }
  if (alienSid != null) {
    final g = await c.edge(
      'create-payment-intent',
      null,
      method: 'GET',
      query: 'checkout_return=success&session_id=${Uri.encodeQueryComponent(alienSid)}',
    );
    add(
      id: 'E7-SESSION-ALIEN',
      lens: 'E7',
      title: 'GET settle com session_id de outro buyer',
      sev: g.body.contains(c.sellerId) || g.body.contains('price_total') ? 'P2' : 'info',
      hit: g.status == 200 && g.body.contains('€'),
      pre: 'return URL não deve vazar encomenda alheia',
      repro: 'GET create-payment-intent?session_id=cs_alheio',
      evidence: {'http': g.status, 'snip': clip(g.snippet, 280)},
    );
  } else {
    notes.add('no alien cs_ for E7');
    final fake = await c.edge(
      'create-payment-intent',
      null,
      method: 'GET',
      query: 'checkout_return=success&session_id=cs_test_rte1859fake',
    );
    add(
      id: 'E7-SESSION-FAKE',
      lens: 'E7',
      title: 'GET session_id fake (oráculo Stripe?)',
      sev: fake.snippet.contains('No such') ? 'P3' : 'info',
      hit: fake.snippet.contains('No such'),
      pre: 'não ecoar erro Stripe cru',
      repro: 'GET session_id=cs_test_fake',
      evidence: {'http': fake.status, 'snip': fake.snippet},
    );
  }

  final payOrigin = await c.edge('create-payment-intent', {
    'buyer_id': c.buyerId,
    'order_id': liveOid ?? c.buyerId,
    'web_return_origin': 'https://evil.example',
  }, jwt: c.buyerJwt);
  add(
    id: 'E7-PAY-WEB-RETURN',
    lens: 'E7',
    title: 'Checkout aceita web_return_origin hostil',
    sev: 'info',
    hit: payOrigin.ok && payOrigin.snippet.contains('evil'),
    pre: 'sanitizeWebReturnOrigin',
    repro: 'POST create-payment-intent web_return_origin=evil',
    evidence: {'http': payOrigin.status, 'snip': payOrigin.snippet},
  );

  // ---- E8 grafo ----
  final fol = await c.rest('POST', '/rest/v1/follows', jwt: c.buyerJwt, body: {
    'follower_id': c.sellerId,
    'following_id': c.buyerId,
  });
  add(
    id: 'E8-FOLLOW-AS-OTHER',
    lens: 'E8',
    title: 'Buyer INSERT follow como se fosse o vendedor',
    sev: fol.ok ? 'P2' : 'info',
    hit: fol.ok,
    pre: 'follower_id = auth.uid()',
    repro: 'POST follows follower_id=seller',
    evidence: {'http': fol.status, 'snip': fol.snippet},
  );

  final folSelf = await c.rest('POST', '/rest/v1/follows', jwt: c.buyerJwt, body: {
    'follower_id': c.buyerId,
    'following_id': c.sellerId,
  });
  notes.add('follow self ${folSelf.status}');

  if (c.buyer2Jwt != null) {
    final enumF = await c.select(
      'follows',
      jwt: c.buyer2Jwt,
      filter: 'following_id=eq.${c.sellerId}',
      limit: 20,
    );
    final n = enumF.ok && enumF.json is List ? (enumF.json as List).length : 0;
    add(
      id: 'E8-FOLLOW-ENUM',
      lens: 'E8',
      title: 'Buyer2 enumera followers do vendedor',
      sev: n > 0 ? 'P3' : 'info',
      hit: n > 0,
      pre: 'select só parties',
      repro: 'GET follows?following_id=seller as buyer2',
      evidence: {'http': enumF.status, 'n': n, 'snip': enumF.snippet},
    );
  }

  String? favPid = livePid ?? await makeProduct(listed: true, sold: false, tag: 'fav', qty: 1);
  if (favPid != null) {
    var favOk = 0;
    for (var i = 0; i < 25; i++) {
      final r = await c.rest('POST', '/rest/v1/favorites', jwt: c.buyerJwt, body: {
        'user_id': c.buyerId,
        'product_id': favPid,
      });
      if (r.ok) favOk++;
    }
    add(
      id: 'E8-FAV-BURST',
      lens: 'E8',
      title: 'Burst 25 favorites no mesmo produto',
      sev: favOk > 1 ? 'P3' : 'info',
      hit: favOk > 5,
      pre: 'unique (user,product) / rate',
      repro: 'POST favorites ×25',
      evidence: {'inserted_ok': favOk, 'product': favPid},
    );
    final favCross = await c.rest('POST', '/rest/v1/favorites', jwt: c.buyerJwt, body: {
      'user_id': c.sellerId,
      'product_id': favPid,
    });
    add(
      id: 'E8-FAV-AS-OTHER',
      lens: 'E8',
      title: 'Favorite em nome do vendedor',
      sev: favCross.ok ? 'P2' : 'info',
      hit: favCross.ok,
      pre: 'user_id = auth.uid()',
      repro: 'POST favorites user_id=seller',
      evidence: {'http': favCross.status, 'snip': favCross.snippet},
    );
  }

  for (final t in ['blocks', 'user_blocks', 'blocked_users', 'profile_blocks']) {
    final r = await c.select(t, jwt: c.buyerJwt, limit: 1);
    if (r.status != 404 && !r.snippet.contains('Could not find')) {
      notes.add('block table $t ${r.status} ${r.snippet}');
    }
  }

  // ---- E9 email ----
  final em = await c.rpc('batata_find_user_id_by_email', {
    'p_email': 'admin@fleaber.pt',
  }, jwt: c.buyerJwt);
  add(
    id: 'E9-EMAIL-LOOKUP',
    lens: 'E9',
    title: 'JWT find_user_id_by_email (além rate 2/h)',
    sev: em.ok && '${em.json}'.contains('-') ? 'P3' : 'info',
    hit: em.ok && em.json != null && '${em.json}'.length > 8,
    pre: 'rate 2/h conhecido; residual órbita',
    repro: 'rpc batata_find_user_id_by_email',
    evidence: {'http': em.status, 'snip': em.snippet},
  );

  final invite = await c.rpc('batata_invite_staff', {
    'p_email': b2email,
  }, jwt: c.buyerJwt);
  add(
    id: 'E9-STAFF-INVITE',
    lens: 'E9',
    title: 'Buyer convida staff',
    sev: invite.ok ? 'P2' : 'info',
    hit: invite.ok,
    pre: 'invite só dono',
    repro: 'rpc batata_invite_staff',
    evidence: {'http': invite.status, 'snip': invite.snippet},
  );

  // follow-up Hub products anon sold vs products table
  final prodAnonSold = await c.select(
    'products',
    filter: 'is_sold=eq.true',
    select: 'id,title,is_sold,list_on_marketplace',
    limit: 5,
  );
  final nSold = prodAnonSold.ok && prodAnonSold.json is List ? (prodAnonSold.json as List).length : 0;
  add(
    id: 'E1-ANON-PRODUCTS-SOLD',
    lens: 'E1',
    title: 'Anon lê products is_sold via tabela base',
    sev: nSold > 0 ? 'P2' : 'info',
    hit: nSold > 0,
    pre: 'RLS marketplace not sold',
    repro: 'GET products?is_sold=eq.true as anon',
    evidence: {'http': prodAnonSold.status, 'n': nSold, 'snip': prodAnonSold.snippet},
  );

  final hits = findings.where((f) => f['hit'] == true).toList();
  await writeOut('pass1.json', {
    'notes': notes,
    'hub_anon': hubAnon,
    'findings': findings,
    'hits': hits,
    'hit_count': hits.length,
  });

  stdout.writeln('--- hits ${hits.length}/${findings.length} ---');
  for (final h in hits) {
    stdout.writeln('${h['sev']} ${h['id']} ${h['title']}');
  }
}
