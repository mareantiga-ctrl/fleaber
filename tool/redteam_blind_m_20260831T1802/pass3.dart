import 'dart:io';

import '_rtm.dart';

/// Pass 3 — retract false P0 storage, Stripe events metadata, composition.
void main() async {
  final c = Rtm.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final out = <String, Object?>{'pass': 3};

  // M6-008 retract: buyer lists OWN uuid, not seller
  final sellerPrefix = c.sellerId!;
  final buyerPrefix = c.buyerId!;
  for (final folder in ['order_disputes', 'order_proofs']) {
    final own = await c.req(
      'POST',
      '/storage/v1/object/list/fleaber_private',
      jwt: c.buyerJwt,
      body: {'prefix': '$folder/$buyerPrefix', 'limit': 20},
    );
    final alien = await c.req(
      'POST',
      '/storage/v1/object/list/fleaber_private',
      jwt: c.buyerJwt,
      body: {'prefix': '$folder/$sellerPrefix', 'limit': 20},
    );
    final alienB2 = await c.req(
      'POST',
      '/storage/v1/object/list/fleaber_private',
      jwt: c.buyer2Jwt,
      body: {'prefix': '$folder/$sellerPrefix', 'limit': 20},
    );
    c.note('p3.m6.own', '$folder own', '${own.status} n=${own.list.length}',
        lens: 'M6');
    c.note('p3.m6.alien', '$folder seller as buyer',
        '${alien.status} n=${alien.list.length} ${alien.snippet}',
        lens: 'M6');
    c.note('p3.m6.alien.b2', '$folder seller as B2',
        '${alienB2.status} n=${alienB2.list.length}',
        lens: 'M6');
    out['list_${folder}_own_n'] = own.list.length;
    out['list_${folder}_alien_n'] = alien.list.length;
    out['list_${folder}_b2_n'] = alienB2.list.length;
    if (alien.ok && alien.list.isNotEmpty) {
      c.hold(
        id: 'RTM-M6-010',
        lens: 'M6',
        severity: 'P0',
        title: 'buyer lista ficheiros fleaber_private/$folder/<sellerId>',
        actor: 'buyer JWT',
        pre: 'prefix seller',
        repro: 'POST object/list/fleaber_private prefix=$folder/$sellerPrefix',
        expected: '[]',
        obtained: alien.snippet,
      );
    }
  }

  // chat_uploads files at bucket root as buyer2
  final svcFiles = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    service: true,
    body: {'prefix': 'chat_uploads', 'limit': 5},
  );
  if (svcFiles.list.isNotEmpty) {
    final name = (svcFiles.list.first as Map)['name']?.toString() ?? '';
    if (name.contains('.')) {
      final path = 'chat_uploads/$name';
      final b2 = await c.req(
        'GET',
        '/storage/v1/object/authenticated/fleaber_private/${Uri.encodeComponent(path)}',
        jwt: c.buyer2Jwt,
      );
      final b2b = await c.req(
        'GET',
        '/storage/v1/object/fleaber_private/$path',
        jwt: c.buyer2Jwt,
      );
      c.note('p3.m6.chatfile.b2', path, 'auth=${b2.status} obj=${b2b.status}',
          lens: 'M6');
      out['b2_private_file'] = {
        'path': path,
        'authenticated': b2.brief,
        'object': b2b.brief,
      };
      if (b2b.ok &&
          (int.tryParse(b2b.headers['x-rtm-bytes']?.first ?? '0') ?? 0) > 100) {
        c.hold(
          id: 'RTM-M6-011',
          lens: 'M6',
          severity: 'P0',
          title: 'B2 descarrega fleaber_private/chat_uploads alheio',
          actor: 'buyer2 JWT',
          pre: path,
          repro: 'GET /storage/v1/object/fleaber_private/$path',
          expected: '403',
          obtained: b2b.brief,
        );
      }
    }
  }

  // Enumerate public product_photos user UUIDs
  final users = await c.req(
    'POST',
    '/storage/v1/object/list/chat_media',
    body: {'prefix': 'product_photos', 'limit': 100},
  );
  final ids = users.list
      .whereType<Map>()
      .map((e) => e['name']?.toString() ?? '')
      .where((s) => s.length > 20)
      .toList();
  c.note('p3.m6.enum.users', 'product_photos UUID count', '${ids.length}',
      lens: 'M6');
  out['product_photo_user_ids'] = ids;

  // stripe_checkout_events for attacker origin tip
  final ev = await c.rest(
    'GET',
    'stripe_checkout_events?select=event,session_id,detail,created_at&order=created_at.desc&limit=8',
    service: true,
  );
  c.note('p3.m2.events', 'checkout events', '${ev.status} n=${ev.list.length}',
      lens: 'M2');
  out['events'] = ev.list.take(6).map((e) {
    if (e is! Map) return e;
    return {
      'event': e['event'],
      'session_id': e['session_id'],
      'detail': clip(e['detail'], 280),
    };
  }).toList();
  final hasAttacker = ev.body.contains('attacker.fleaber.pt');
  final hasEvil = ev.body.contains('evil.com');
  out['events_has_attacker'] = hasAttacker;
  out['events_has_evil'] = hasEvil;
  if (hasAttacker) {
    c.hold(
      id: 'RTM-M2-005',
      lens: 'M2',
      severity: 'P1',
      title: 'web_return_origin attacker.fleaber.pt persistido em stripe_checkout_events / Session metadata',
      actor: 'buyer JWT → Edge tip',
      pre: 'POST create-live-tip-checkout web_return_origin=https://attacker.fleaber.pt',
      repro: 'ler stripe_checkout_events.detail',
      expected: 'sanitize rejeita subdomínio; não gravar origin hostil',
      obtained: 'eventos contêm attacker.fleaber.pt',
    );
  }

  // Cross-edge settle: unpaid tip cs on payment-intent GET
  const tipCs = 'cs_test_a1uRjdlJsnutJ0FyUbp8v2cnD4V2a7FdozMUgLlGxygAVaDAZArHEmRbBD';
  const tipCs499 = 'cs_test_a1nl4JwatVZauQ34h8d5Sv6X1S8jKK3GBtcjYqwCGUqSU9MXneGu8Znixp';
  final cross = await c.req(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=$tipCs',
    jwt: c.buyer2Jwt,
  );
  c.note('p3.m3.cross.pi_tip', 'PI settle of unpaid tip Session', cross.brief,
      lens: 'M3');
  out['cross_pi_tip'] = cross.brief;
  final tipSettle499 = await c.edge(
    'create-live-tip-checkout',
    method: 'GET',
    qs: '?checkout_return=success&session_id=$tipCs499',
    extra: {'Origin': 'https://attacker.fleaber.pt'},
  );
  c.note('p3.m3.tip499.settle', 'settle 499 unpaid + CORS origin',
      '${tipSettle499.brief} acao=${tipSettle499.acao}',
      lens: 'M7');
  out['tip499_settle'] = {
    'brief': tipSettle499.brief,
    'acao': tipSettle499.acao,
    'loc': tipSettle499.location,
  };

  // live_tips rows for those sessions
  final tips = await c.rest(
    'GET',
    'live_tips?select=id,status,amount,buyer_id,seller_id,stripe_session_id,live_id&or=(stripe_session_id.eq.$tipCs,stripe_session_id.eq.$tipCs499)',
    service: true,
  );
  c.note('p3.m7.tips', 'tip rows unpaid', tips.brief, lens: 'M7');
  out['tip_rows'] = tips.snippet;
  final paidAnyway = tips.list.any((e) =>
      e is Map && '${e['status']}'.toLowerCase().contains('paid') ||
      (e is Map && '${e['status']}' == 'settled'));
  if (paidAnyway) {
    c.hold(
      id: 'RTM-M7-002',
      lens: 'M7',
      severity: 'P0',
      title: 'gorjeta marcada paga sem captura Stripe',
      actor: 'GET settle unpaid',
      pre: 'Session unpaid',
      repro: 'GET create-live-tip-checkout checkout_return=success',
      expected: 'status pending',
      obtained: tips.snippet,
    );
  }

  // hub messages columns
  final msgs = await c.rest(
    'GET',
    'hub_live_messages_public?select=*&limit=3',
  );
  c.note('p3.m1.msgs', 'hub messages cols', msgs.brief, lens: 'M1');
  out['msgs'] = msgs.snippet;

  // meta-data-deletion
  final meta = await c.edge(
    'meta-data-deletion',
    body: {'user_id': c.sellerId, 'confirmation_code': 'x'},
  );
  c.note('p3.m4.meta', 'meta-data-deletion spoof user_id', meta.brief, lens: 'M4');

  // Connect GET localhost already 303 — document as P2 only if Location is open
  final loc = await c.edge(
    'create-connect-account',
    method: 'GET',
    qs: '?web_return_origin=${Uri.encodeQueryComponent('https://fleaber.pt')}&wallet_return=1',
    extra: {'Origin': 'https://attacker.fleaber.pt'},
  );
  c.note('p3.m2.connect.acao', 'GET connect allow origin + attacker CORS',
      'status=${loc.status} loc=${loc.location} acao=${loc.acao}',
      lens: 'M2');
  out['connect_get'] = {
    'status': loc.status,
    'location': loc.location,
    'acao': loc.acao,
  };

  out['findings'] = c.findings;
  out['notes'] = c.notes;
  await dumpJson('${repoRoot()}/tool/redteam_blind_m_$stamp/pass3.json', out);
  stdout.writeln('FINDINGS ${c.findings.length}');
}
