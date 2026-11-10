/// REDTEAM_BLIND_S_IDENTIDADE_STAFF_v1 — pass2
/// dart run tool/redteam_blind_s_20260901T0657/pass2.dart
import 'dart:convert';
import 'dart:io';

import '_rts.dart';

void main() async {
  final env = loadEnv();
  final c = Rts.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final b = c.buyerJwt!;
  final s = c.sellerJwt!;
  final b2 = c.buyer2Jwt!;
  final bid = c.buyerId!;
  final sid = c.sellerId!;
  final b2id = c.buyer2Id!;

  // Reuse device token minted in pass1 if still valid — mint again.
  final tokB2 = await c.rpc(
    'batata_create_seller_device_token',
    {'p_device_id': 'rts-b2-dev', 'p_label': 'rts'},
    jwt: b2,
  );
  final tokenB2 = tokB2.map?['token']?.toString();
  c.note('p2.tok.b2', 'buyer2 device token', tokB2.map?['ok'], lens: 'S6');

  final tokBuyer = await c.rpc(
    'batata_create_seller_device_token',
    {'p_device_id': 'rts-buyer-dev', 'p_label': 'rts'},
    jwt: b,
  );
  c.note('p2.tok.comprador', 'buyer comprador mint token', tokBuyer.brief,
      lens: 'S6');
  if (tokBuyer.ok && tokBuyer.map?['ok'] == true) {
    c.hold(
      id: 'RTS-S6-007',
      lens: 'S6',
      severity: 'P1',
      title: 'Conta comprador (user_type=comprador) emite device_token OCR',
      actor: 'buyer JWT',
      pre: 'user_type=comprador (não vendedor)',
      repro: 'rpc batata_create_seller_device_token',
      expected: 'not_seller',
      obtained: tokBuyer.brief,
    );
  }

  // =====================================================================
  // S1 — retry PII without email column
  // =====================================================================
  final own = await c.rest(
    'GET',
    'profiles?id=eq.$bid&select=id,full_name,user_type,phone,legal_full_name,iban,mb_way,handle',
    jwt: b,
  );
  c.note('p2.s1.own', 'próprio perfil (sem email)', {
    'http': own.status,
    'user_type': own.map?['user_type'],
    'pii': own.map?.keys.where((k) => [
          'phone',
          'iban',
          'mb_way',
          'legal_full_name',
        ].contains(k)).map((k) => '$k=${own.map?[k]}').join(','),
  }, lens: 'S1');

  final other = await c.rest(
    'GET',
    'profiles?id=eq.$sid&select=id,full_name,user_type,phone,legal_full_name,iban,mb_way,handle',
    jwt: b,
  );
  c.note('p2.s1.other', 'buyer GET PII seller', {
    'http': other.status,
    'n': other.rowCount,
    'body': other.brief,
  }, lens: 'S1');
  if (other.ok && other.rowCount > 0) {
    final m = other.map ?? {};
    final pii = m['phone'] != null ||
        m['iban'] != null ||
        m['mb_way'] != null ||
        (m['legal_full_name']?.toString().isNotEmpty ?? false);
    c.hold(
      id: 'RTS-S1-010',
      lens: 'S1',
      severity: pii ? 'P0' : 'P2',
      title: 'JWT lê profiles de outro UUID (retry sem coluna email)',
      actor: 'buyer JWT',
      pre: 'select id,phone,iban,…',
      repro: 'GET profiles?id=eq.$sid',
      expected: '[]',
      obtained: other.brief,
    );
  }

  final dump = await c.rest(
    'GET',
    'profiles?select=id,phone,iban,mb_way,legal_full_name&limit=20',
    jwt: b,
  );
  c.note('p2.s1.dump', 'GET profiles sem filtro', {
    'http': dump.status,
    'n': dump.rowCount,
  }, lens: 'S1');
  if (dump.ok && dump.rowCount > 1) {
    c.hold(
      id: 'RTS-S1-011',
      lens: 'S1',
      severity: 'P0',
      title: 'JWT lista várias linhas profiles (PII dump)',
      actor: 'buyer JWT',
      pre: 'own-row RLS',
      repro: 'GET profiles?select=phone,iban&limit=20',
      expected: '0–1 (próprio)',
      obtained: 'n=${dump.rowCount}',
    );
  }

  final dirPii = await c.rest(
    'GET',
    'profiles_directory_public?id=eq.$sid&select=*',
    jwt: b2,
  );
  c.note('p2.s1.dir.star', 'directory select * seller', {
    'http': dirPii.status,
    'keys': dirPii.map?.keys.toList(),
    'has_phone': dirPii.body.contains('910000657'),
    'has_iban': dirPii.body.toLowerCase().contains('pt50'),
  }, lens: 'S1');
  if (dirPii.ok &&
      (dirPii.body.contains('910000657') ||
          dirPii.body.toLowerCase().contains('pt50'))) {
    c.hold(
      id: 'RTS-S1-012',
      lens: 'S1',
      severity: 'P0',
      title: 'profiles_directory_public vaza telefone/IBAN',
      actor: 'buyer2 JWT',
      pre: 'view whitelist',
      repro: 'GET profiles_directory_public?id=eq.seller&select=*',
      expected: 'sem phone/iban',
      obtained: dirPii.brief,
    );
  }

  final gql = await c.req(
    'POST',
    '/graphql/v1',
    jwt: b2,
    body: {
      'query':
          '{ profilesCollection(filter: { id: { eq: "$sid" } }, first: 1) { edges { node { id phone iban mbWay legalFullName fullName } } } }',
    },
  );
  c.note('p2.s1.gql', 'GraphQL profiles seller', gql.brief, lens: 'S1');
  if (gql.ok &&
      (gql.body.contains('910000657') ||
          gql.body.toLowerCase().contains('pt50') ||
          (gql.body.contains(sid) && gql.body.contains('phone')))) {
    final hasPii = gql.body.contains('910000657') ||
        gql.body.toLowerCase().contains('pt50');
    if (hasPii) {
      c.hold(
        id: 'RTS-S1-013',
        lens: 'S1',
        severity: 'P0',
        title: 'GraphQL lê PII de outro profile',
        actor: 'buyer2 JWT',
        pre: 'RLS REST own-row',
        repro: 'POST /graphql/v1 profilesCollection',
        expected: 'edges vazios / sem PII',
        obtained: gql.brief,
      );
    }
  }

  final payout = await c.rpc('batata_get_my_payout_details', <String, dynamic>{},
      jwt: b2);
  c.note('p2.s1.payout', 'get_my_payout_details buyer2', payout.brief, lens: 'S1');

  // =====================================================================
  // S3 — storage list recursion + public CDN + alien JPEG
  // =====================================================================
  Future<void> listPref(String bucket, String prefix, String actor, String? jwt) async {
    final h = await c.storageList(bucket, prefix: prefix, jwt: jwt);
    c.note('p2.s3.list.$actor', '$bucket prefix="$prefix"', {
      'http': h.status,
      'n': h.rowCount,
      'snip': clip(h.body, 180),
    }, lens: 'S3');
    final names = <String>[];
    for (final item in h.list) {
      if (item is Map) {
        final n = item['name']?.toString() ?? '';
        if (n.isNotEmpty) names.add(n);
      }
    }
    final alien = names.where((n) => n.contains(sid) && !n.contains(b2id)).toList();
    if (h.ok && alien.isNotEmpty) {
      c.hold(
        id: 'RTS-S3-010',
        lens: 'S3',
        severity: 'P1',
        title: 'Listagem $bucket/$prefix revela UUID de outro user',
        actor: actor,
        pre: 'prefix $prefix',
        repro: 'POST /storage/v1/object/list/$bucket prefix=$prefix',
        expected: '[] ou só próprio UUID',
        obtained: alien.take(8).toList(),
      );
    }
  }

  await listPref('chat_media', 'product_photos/', 'buyer2', b2);
  await listPref('chat_media', 'product_photos/$sid/', 'buyer2', b2);
  await listPref('chat_media', 'profile_photos/', 'buyer2', b2);
  await listPref('chat_media', 'profile_photos/$sid/', 'anon', null);
  await listPref('fleaber_private', 'chat_uploads/', 'buyer2', b2);
  await listPref('fleaber_private', 'chat_uploads/$sid/', 'buyer2', b2);
  await listPref('fleaber_private', 'order_proofs/', 'buyer2', b2);
  await listPref('fleaber_private', 'order_disputes/', 'buyer2', b2);

  // Seller uploads JPEG to own prefix; buyer2 tries read/sign/public.
  final spath = 'chat_uploads/$sid/$prefix-s3.jpg';
  final upS = await c.storageUpload('fleaber_private', spath, jwt: s);
  c.note('p2.s3.up.seller', 'seller JPEG fleaber_private', upS.brief, lens: 'S3');

  final getB2 = await c.storageGet('fleaber_private', spath, jwt: b2);
  final getAnon = await c.storageGet('fleaber_private', spath);
  final getPub = await c.storageGet('fleaber_private', spath, publicBucket: true);
  final signB2 = await c.storageSign('fleaber_private', spath, jwt: b2);
  final getOwner = await c.storageGet('fleaber_private', spath, jwt: s);
  c.note('p2.s3.read', 'ler JPEG seller como outros', {
    'up': upS.status,
    'owner': getOwner.status,
    'b2': getB2.brief,
    'anon': getAnon.brief,
    'public': getPub.brief,
    'sign': signB2.brief,
  }, lens: 'S3');
  bool gotFile(HttpHit h) =>
      h.ok &&
      (h.body.contains('JFIF') ||
          h.body.startsWith('<<binary') ||
          (h.body.length > 40 && !h.body.contains('"error"')));
  if (upS.ok && (gotFile(getB2) || gotFile(getAnon) || gotFile(getPub))) {
    c.hold(
      id: 'RTS-S3-011',
      lens: 'S3',
      severity: 'P0',
      title: 'Objecto fleaber_private de outro UUID é legível',
      actor: gotFile(getAnon) || gotFile(getPub) ? 'anon' : 'buyer2 JWT',
      pre: 'seller upload $spath',
      repro: 'GET /storage/v1/object/fleaber_private/$spath',
      expected: '400/403',
      obtained: {
        'b2': getB2.brief,
        'anon': getAnon.brief,
        'public': getPub.brief,
      },
    );
  }
  if (signB2.ok &&
      (signB2.map?['signedURL'] != null || signB2.body.contains('token='))) {
    c.hold(
      id: 'RTS-S3-012',
      lens: 'S3',
      severity: 'P1',
      title: 'JWT alheio assina URL de objecto de outro',
      actor: 'buyer2 JWT',
      pre: spath,
      repro: 'POST object/sign/fleaber_private/$spath',
      expected: '403',
      obtained: signB2.brief,
    );
  }

  final upAlien = await c.storageUpload(
    'fleaber_private',
    'chat_uploads/$sid/$prefix-alien.jpg',
    jwt: b2,
  );
  c.note('p2.s3.up.alien', 'buyer2 JPEG no prefixo seller', upAlien.brief,
      lens: 'S3');
  if (upAlien.ok) {
    c.hold(
      id: 'RTS-S3-013',
      lens: 'S3',
      severity: 'P1',
      title: 'JWT escreve JPEG no prefixo storage de outro UUID',
      actor: 'buyer2 JWT',
      pre: 'insert own prefix',
      repro: 'POST fleaber_private/chat_uploads/$sid/…',
      expected: '403',
      obtained: upAlien.brief,
    );
  }

  final upCatalog = await c.storageUpload(
    'chat_media',
    'product_photos/$sid/$prefix-cat.jpg',
    jwt: b2,
  );
  c.note('p2.s3.up.cat', 'buyer2 upload catálogo seller', upCatalog.brief,
      lens: 'S3');
  if (upCatalog.ok) {
    c.hold(
      id: 'RTS-S3-014',
      lens: 'S3',
      severity: 'P1',
      title: 'JWT escreve em product_photos/{outro}/',
      actor: 'buyer2 JWT',
      pre: 'insert own uid prefix',
      repro: 'POST chat_media/product_photos/$sid/…',
      expected: '403',
      obtained: upCatalog.brief,
    );
  }

  // Public catalog of seller via known product image_urls
  final prodImg = await c.rest(
    'GET',
    'products?seller_id=eq.$sid&select=id,image_urls&limit=3',
    service: true,
  );
  String? publicUrl;
  for (final row in prodImg.list) {
    if (row is Map && row['image_urls'] is List && (row['image_urls'] as List).isNotEmpty) {
      publicUrl = (row['image_urls'] as List).first.toString();
      break;
    }
  }
  if (publicUrl != null) {
    final pubHit = await c.req('GET', publicUrl, jwt: b2);
    c.note('p2.s3.cdn', 'CDN image_urls produto', {
      'url': clip(publicUrl, 120),
      'http': pubHit.status,
      'len': pubHit.body.length,
    }, lens: 'S3');
  }

  // Chat: buyer2 cria chat com seller e tenta ler media de OUTRO chat
  final mkChat = await c.rest('POST', 'chats', jwt: b2, body: {
    'user_a': b2id,
    'user_b': sid,
  });
  c.note('p2.s3.chat.create', 'buyer2 abre chat com seller', mkChat.brief,
      lens: 'S3');
  final newChatId = mkChat.firstId;
  if (newChatId != null) {
    final listOtherChat = await c.storageList(
      'fleaber_private',
      prefix: 'chat_uploads/$sid/',
      jwt: b2,
    );
    c.note('p2.s3.chat.list', 'após abrir chat, list chat_uploads/seller', {
      'http': listOtherChat.status,
      'n': listOtherChat.rowCount,
      'snip': clip(listOtherChat.body, 160),
    }, lens: 'S3');
    final getViaChat = await c.storageGet(
      'fleaber_private',
      spath,
      jwt: b2,
    );
    c.note('p2.s3.chat.get', 'ler ficheiro seller após ser counterparty',
        getViaChat.brief, lens: 'S3');
    if (gotFile(getViaChat) && !gotFile(getB2)) {
      c.hold(
        id: 'RTS-S3-015',
        lens: 'S3',
        severity: 'P1',
        title: 'Abrir chat com vendedor desbloqueia TODO o prefixo chat_uploads dele',
        actor: 'buyer2 JWT',
        pre: 'counterparty policy deveria ser só {uid}/{chat_id}/',
        repro: 'POST chats; GET fleaber_private/$spath',
        expected: '403 (ficheiro não é deste chat_id)',
        obtained: getViaChat.brief,
      );
    }
  }

  // Disputes proof_photos URLs
  final dispSvc = await c.rest(
    'GET',
    'order_disputes?select=id,order_id,proof_photos&limit=5',
    service: true,
  );
  c.note('p2.s3.disp.svc', 'disputas (observação)', {
    'n': dispSvc.rowCount,
    'snip': clip(dispSvc.body, 160),
  }, lens: 'S3');
  for (final row in dispSvc.list) {
    if (row is! Map) continue;
    final photos = row['proof_photos'];
    if (photos is List && photos.isNotEmpty) {
      final url = photos.first.toString();
      if (url.contains('http')) {
        final g = await c.req('GET', url, jwt: b2);
        c.note('p2.s3.proof.url', 'buyer2 GET proof_photos URL', {
          'http': g.status,
          'len': g.body.length,
        }, lens: 'S3');
        if (g.ok && g.body.length > 80) {
          c.hold(
            id: 'RTS-S3-016',
            lens: 'S3',
            severity: 'P1',
            title: 'JWT alheio descarrega proof_photos por URL',
            actor: 'buyer2 JWT',
            pre: 'URL de disputa de terceiros',
            repro: 'GET $url',
            expected: '403',
            obtained: g.brief,
          );
        }
      }
      break;
    }
  }

  // =====================================================================
  // S6 — OCR token vs live alheia + pairing + device_tokens RLS
  // =====================================================================
  final lives = await c.rest(
    'GET',
    'lives?or=(seller_id.eq.$sid,vendedor_id.eq.$sid)&select=id,status,is_active,seller_id&order=created_at.desc&limit=5',
    service: true,
  );
  c.note('p2.s6.lives', 'lives do seller', {
    'n': lives.rowCount,
    'snip': clip(lives.body, 180),
  }, lens: 'S6');
  final liveId = lives.firstId;
  if (liveId != null && tokenB2 != null) {
    final ingest = await c.edge(
      'ingest-ocr-reservation',
      {
        'live_id': liveId,
        'ocr_line_hash': 'rts${stamp}hashxx',
        'detected_at': DateTime.now().toUtc().toIso8601String(),
        'ref_number': 1,
        'external_display_name': 'RTS',
        'ocr_raw_line': 'RTS ingest',
      },
      extra: {'x-device-token': tokenB2},
    );
    c.note('p2.s6.ingest', 'OCR com token buyer2 na live do seller',
        ingest.brief, lens: 'S6');
    final err = '${ingest.map?['error'] ?? ingest.body}';
    if (ingest.ok && ingest.map?['ok'] == true) {
      c.hold(
        id: 'RTS-S6-010',
        lens: 'S6',
        severity: 'P0',
        title: 'Token OCR de outra conta ingere reserva na live do seller',
        actor: 'anon + x-device-token buyer2',
        pre: 'token seller_id=buyer2; live seller=$sid',
        repro: 'POST ingest-ocr-reservation live_id=$liveId',
        expected: 'not_allowed',
        obtained: ingest.brief,
      );
    } else {
      c.note('p2.s6.ingest.hold', 'recusa OCR cruzado', err, lens: 'S6');
    }
  }

  final pairCreate = await c.rpc(
    'batata_ps_create_pairing',
    {'p_live_id': liveId, 'p_device_id_hint': 'rts-b2'},
    jwt: b2,
  );
  c.note('p2.s6.pair', 'helper analytics cria pairing', pairCreate.brief,
      lens: 'S6');
  if (pairCreate.ok && pairCreate.map?['ok'] == true) {
    c.hold(
      id: 'RTS-S6-011',
      lens: 'S2',
      severity: 'P1',
      title: 'Helper só-analytics cria código pairing (staff OCR)',
      actor: 'buyer2 JWT (can_view_analytics)',
      pre: 'perms sem can_manage_reservations',
      repro: 'rpc batata_ps_create_pairing',
      expected: 'not_allowed',
      obtained: pairCreate.brief,
    );
  }

  final tokTbl = await c.rest(
    'GET',
    'seller_device_tokens?seller_id=eq.$sid&select=id,seller_id,device_id,token_hash,label&limit=10',
    jwt: b2,
  );
  c.note('p2.s6.tok.tbl', 'buyer2 lê tokens do seller', {
    'http': tokTbl.status,
    'n': tokTbl.rowCount,
  }, lens: 'S6');
  if (tokTbl.ok && tokTbl.rowCount > 0) {
    c.hold(
      id: 'RTS-S6-012',
      lens: 'S6',
      severity: 'P1',
      title: 'JWT lê seller_device_tokens de outro vendedor',
      actor: 'buyer2 JWT',
      pre: 'policy seller_id=auth.uid()',
      repro: 'GET seller_device_tokens?seller_id=eq.$sid',
      expected: '[]',
      obtained: tokTbl.brief,
    );
  }

  final tokStar = await c.rest(
    'GET',
    'seller_device_tokens?select=*&limit=20',
    jwt: b2,
  );
  c.note('p2.s6.tok.star', 'buyer2 GET seller_device_tokens *', {
    'http': tokStar.status,
    'n': tokStar.rowCount,
  }, lens: 'S6');

  // Flutter lab tokens: only anon key in lib (observed in code review).
  c.note('p2.s6.binario', 'tokens no binário Flutter',
      'anon key staging em lib/backend/supabase/supabase.dart; sem service_role; device_token não hardcoded',
      lens: 'S6');

  // =====================================================================
  // S7 — chat_messages columns + graphql orders
  // =====================================================================
  final chatSvc = await c.rest(
    'GET',
    'chats?or=(and(user_a.eq.$bid,user_b.eq.$sid),and(user_a.eq.$sid,user_b.eq.$bid))&select=id&limit=1',
    service: true,
  );
  final chatId = chatSvc.firstId;
  if (chatId != null) {
    for (final cols in [
      'id,sender_id,body,created_at',
      'id,user_id,text,created_at',
      'id,author_id,message,created_at',
      'id,content,created_at',
    ]) {
      final msgs = await c.rest(
        'GET',
        'chat_messages?chat_id=eq.$chatId&select=$cols&limit=3',
        jwt: b2,
      );
      c.note('p2.s7.msgs', 'buyer2 msgs cols=$cols', {
        'http': msgs.status,
        'n': msgs.rowCount,
        'snip': clip(msgs.body, 120),
      }, lens: 'S7');
      if (msgs.ok && msgs.rowCount > 0) {
        c.hold(
          id: 'RTS-S7-010',
          lens: 'S7',
          severity: 'P0',
          title: 'JWT lê chat_messages de thread alheia',
          actor: 'buyer2 JWT',
          pre: 'chat $chatId buyer1↔seller',
          repro: 'GET chat_messages?chat_id=eq.$chatId',
          expected: '[]',
          obtained: msgs.brief,
        );
        break;
      }
    }
  }

  final gqlOrd = await c.req('POST', '/graphql/v1', jwt: b2, body: {
    'query':
        '{ ordersCollection(filter: { buyerId: { eq: "$bid" } }, first: 3) { edges { node { id status buyerId sellerId priceTotal } } } }',
  });
  c.note('p2.s7.gql.orders', 'GraphQL orders do buyer1', gqlOrd.brief,
      lens: 'S7');
  if (gqlOrd.ok && gqlOrd.body.contains(bid) && gqlOrd.body.contains('"id"')) {
    final edges = gqlOrd.body.contains('"edges":[]') ||
        gqlOrd.body.contains('"edges": []');
    if (!edges && gqlOrd.body.contains('ordersCollection')) {
      c.hold(
        id: 'RTS-S7-011',
        lens: 'S7',
        severity: 'P0',
        title: 'GraphQL IDOR encomendas de outro buyer',
        actor: 'buyer2 JWT',
        pre: 'filter buyerId=buyer1',
        repro: 'POST /graphql/v1 ordersCollection',
        expected: 'edges vazios',
        obtained: gqlOrd.brief,
      );
    }
  }

  // Helper analytics: vê encomendas da loja?
  final ordsStaff = await c.rest(
    'GET',
    'orders?seller_id=eq.$sid&select=id,buyer_id,status,price_total&limit=5',
    jwt: b2,
  );
  c.note('p2.s7.staff.orders', 'helper analytics GET orders da loja', {
    'http': ordsStaff.status,
    'n': ordsStaff.rowCount,
  }, lens: 'S7');
  if (ordsStaff.ok && ordsStaff.rowCount > 0) {
    c.hold(
      id: 'RTS-S7-012',
      lens: 'S7',
      severity: 'P1',
      title: 'Helper só-analytics lê encomendas (PII compradores) da loja',
      actor: 'buyer2 JWT staff analytics',
      pre: 'orders RLS parties; sem permissão de encomendas',
      repro: 'GET orders?seller_id=eq.$sid',
      expected: '[] (não é seller nem buyer)',
      obtained: 'n=${ordsStaff.rowCount} ${ordsStaff.brief}',
    );
  }

  // =====================================================================
  // S5 — reviews_public_ratings + DELETE próprio após ciclo
  // =====================================================================
  final pub = await c.rest(
    'GET',
    'reviews_public_ratings?target_id=eq.$sid&select=id,stars,comment,purchase_verified,author_role&limit=5',
    jwt: b2,
  );
  c.note('p2.s5.pub', 'reviews_public_ratings', {
    'http': pub.status,
    'n': pub.rowCount,
  }, lens: 'S5');
  final rid = pub.firstId;
  if (rid != null) {
    final patchV = await c.rest(
      'PATCH',
      'reviews_public_ratings?id=eq.$rid',
      jwt: b2,
      body: {'stars': 5},
    );
    c.note('p2.s5.patch.view', 'PATCH view ratings', patchV.brief, lens: 'S5');
    if (patchV.ok && patchV.rowCount > 0) {
      c.hold(
        id: 'RTS-S5-010',
        lens: 'S5',
        severity: 'P0',
        title: 'PATCH reviews_public_ratings altera estrelas alheias',
        actor: 'buyer2 JWT',
        pre: 'view security_invoker=false GRANT SELECT',
        repro: 'PATCH reviews_public_ratings?id=eq.$rid',
        expected: '401/403',
        obtained: patchV.brief,
      );
    }
    final delV = await c.rest(
      'DELETE',
      'reviews_public_ratings?id=eq.$rid',
      jwt: b2,
    );
    c.note('p2.s5.del.view', 'DELETE view ratings', delV.brief, lens: 'S5');
    if (delV.ok && delV.rowCount > 0) {
      c.hold(
        id: 'RTS-S5-011',
        lens: 'S5',
        severity: 'P0',
        title: 'DELETE via reviews_public_ratings remove review alheia',
        actor: 'buyer2 JWT',
        pre: rid,
        repro: 'DELETE reviews_public_ratings',
        expected: '401/403',
        obtained: delV.brief,
      );
    }
  }

  // Own review DELETE → reinsert 5★ (S5) using e2e completed order of buyer1
  final paid = await c.e2e('setup_paid_order', {'initial_qty': 1});
  c.note('p2.s5.e2e', 'setup_paid_order', paid.brief, lens: 'S5');
  final oid = c.parseE2eOrderId(paid);
  if (oid != null) {
    c.createdOrderIds.add(oid);
    await c.rest('PATCH', 'orders?id=eq.$oid', jwt: s, body: {
      'shipping_method': 'entrega em mão',
    });
    await c.rest('PATCH', 'orders?id=eq.$oid', jwt: s, body: {'status': 'enviado'});
    final conc = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: b,
      body: {'status': 'concluido'},
    );
    c.note('p2.s5.conc', 'concluido', conc.brief, lens: 'S5');
    final ins1 = await c.rest('POST', 'reviews', jwt: b, body: {
      'buyer_id': bid,
      'target_id': sid,
      'stars': 1,
      'comment': '$prefix-1star',
      'author_role': 'comprador',
      'order_id': oid,
    });
    c.note('p2.s5.ins1', 'buyer review 1★', ins1.brief, lens: 'S5');
    final myRid = ins1.firstId;
    if (myRid != null) {
      final delOwn = await c.rest('DELETE', 'reviews?id=eq.$myRid', jwt: b);
      c.note('p2.s5.del.own', 'buyer DELETE própria review', delOwn.brief,
          lens: 'S5');
      final still = await c.rest(
        'GET',
        'reviews?id=eq.$myRid&select=id,stars',
        service: true,
      );
      if (delOwn.ok && still.rowCount == 0) {
        final ins5 = await c.rest('POST', 'reviews', jwt: b, body: {
          'buyer_id': bid,
          'target_id': sid,
          'stars': 5,
          'comment': '$prefix-5star',
          'author_role': 'comprador',
          'order_id': oid,
        });
        c.note('p2.s5.reins', 'reinsert 5★ após DELETE', ins5.brief, lens: 'S5');
        if (ins5.ok) {
          c.hold(
            id: 'RTS-S5-012',
            lens: 'S5',
            severity: 'P1',
            title: 'DELETE review própria + INSERT 5★ na mesma order (release)',
            actor: 'buyer JWT',
            pre: 'trigger review_delete_forbidden deveria impedir DELETE',
            repro: 'DELETE reviews; POST stars=5 order=$oid',
            expected: 'DELETE review_delete_forbidden',
            obtained: {'del': delOwn.brief, 'ins5': ins5.brief},
          );
        }
      } else {
        c.note('p2.s5.del.blocked', 'DELETE próprio bloqueado', {
          'del': delOwn.brief,
          'still': still.brief,
        }, lens: 'S5');
      }
    }
  }

  // =====================================================================
  // S4 — multi-conta: review 5★ de buyer2 após ciclo no seller
  // =====================================================================
  final paid2 = await c.req(
    'POST',
    '/functions/v1/sec-fase2-e2e-oversell',
    service: true,
    body: {
      'probe': 'setup_paid_order',
      'buyer_id': b2id,
      'seller_id': sid,
      'initial_qty': 1,
    },
    extra: c.e2eSecret.isEmpty
        ? null
        : {'x-fleaber-e2e-secret': c.e2eSecret},
  );
  c.note('p2.s4.e2e', 'setup_paid_order buyer2→seller', paid2.brief, lens: 'S4');
  final oid2 = c.parseE2eOrderId(paid2);
  if (oid2 != null) {
    await c.rest('PATCH', 'orders?id=eq.$oid2', jwt: s, body: {
      'shipping_method': 'entrega em mão',
    });
    await c.rest(
      'PATCH',
      'orders?id=eq.$oid2',
      jwt: s,
      body: {'status': 'enviado'},
    );
    await c.rest(
      'PATCH',
      'orders?id=eq.$oid2',
      jwt: b2,
      body: {'status': 'concluido'},
    );
    final rev2 = await c.rest('POST', 'reviews', jwt: b2, body: {
      'buyer_id': b2id,
      'target_id': sid,
      'stars': 5,
      'comment': '$prefix-alt-5',
      'author_role': 'comprador',
      'order_id': oid2,
    });
    c.note('p2.s4.rev', 'alt-account 5★ no seller', rev2.brief, lens: 'S4');
    if (rev2.ok) {
      c.note(
        'p2.s4.rev.arch',
        'sem ligação de contas: 2 UUIDs podem 5★ após compra real (arquitectura, não RLS)',
        rev2.firstId,
        lens: 'S4',
      );
    }
    final dispIns = await c.rest('POST', 'order_disputes', jwt: b2, body: {
      'order_id': oid2,
      'reason': 'nao_corresponde',
      'description': prefix,
    });
    c.note('p2.s4.disp', 'alt-account abre disputa', dispIns.brief, lens: 'S4');
  }

  // user_type freeze: comprador → vendedor
  final toSeller = await c.rest(
    'PATCH',
    'profiles?id=eq.$bid',
    jwt: b,
    body: {'user_type': 'vendedor'},
  );
  final afterType = await c.rest(
    'GET',
    'profiles?id=eq.$bid&select=id,user_type',
    jwt: b,
  );
  c.note('p2.s2.type.flip', 'comprador tenta vendedor', {
    'patch': toSeller.brief,
    'after': afterType.map?['user_type'],
  }, lens: 'S2');

  // =====================================================================
  // S8 — credit variants + admin resolve with real dispute
  // =====================================================================
  for (final fn in [
    'batata_credit_wallet_once',
    'batata_debit_wallet_once',
    'batata_refund_buyer_wallet_for_order',
    'batata_release_seller_wallet_for_order',
  ]) {
    final hit = await c.rpc(fn, {
      'p_order_id': oid ?? oid2 ?? '00000000-0000-0000-0000-000000000001',
    }, jwt: b2);
    c.note('p2.s8.$fn', 'JWT wallet rpc', hit.brief, lens: 'S8');
    if (hit.ok &&
        (hit.body.trim() == 'true' || hit.map?['ok'] == true)) {
      c.hold(
        id: 'RTS-S8-010',
        lens: 'S8',
        severity: 'P0',
        title: 'JWT executa $fn com sucesso',
        actor: 'buyer2 JWT',
        pre: 'GRANT service_role / party checks',
        repro: 'rpc $fn',
        expected: '403 / false',
        obtained: hit.brief,
      );
    }
  }

  await dumpJson('${outDir()}/pass2.json', {
    'auditor': 'REDTEAM_BLIND_S_IDENTIDADE_STAFF_v1',
    'stamp': stamp,
    'pass': 2,
    'production_touched': false,
    'fase4': false,
    'findings': c.findings,
    'notes': c.notes,
  });
  stdout.writeln('FINDINGS ${c.findings.length}');
}
