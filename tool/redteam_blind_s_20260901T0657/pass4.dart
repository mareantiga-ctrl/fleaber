/// REDTEAM_BLIND_S_IDENTIDADE_STAFF_v1 — pass4 (RPC admin sweep + resíduos)
/// dart run tool/redteam_blind_s_20260901T0657/pass4.dart
import 'dart:io';

import '_rts.dart';

void main() async {
  final env = loadEnv();
  final c = Rts.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();

  final b = c.buyerJwt!;
  final b2 = c.buyer2Jwt!;
  final s = c.sellerJwt!;
  final bid = c.buyerId!;
  final sid = c.sellerId!;
  final b2id = c.buyer2Id!;

  final oa = await c.req(
    'GET',
    '/rest/v1/',
    service: true,
    extra: {'Accept': 'application/openapi+json'},
  );
  final rpcNames = <String>[];
  if (oa.json is Map) {
    final paths = (oa.json as Map)['paths'];
    if (paths is Map) {
      for (final k in paths.keys) {
        final ks = k.toString();
        if (ks.contains('/rpc/')) rpcNames.add(ks.split('/rpc/').last);
      }
    }
  }
  rpcNames.sort();
  final interesting = rpcNames
      .where((n) =>
          n.contains('admin') ||
          n.contains('staff') ||
          n.contains('director') ||
          n.contains('is_admin') ||
          n.contains('payout') ||
          n.contains('wallet') ||
          n.contains('credit') ||
          n.contains('find_user') ||
          n.contains('pairing') ||
          n.contains('device_token') ||
          n.contains('review') ||
          n.contains('handle') ||
          n.contains('profile'))
      .toList();
  c.note('p4.rpc.map', 'RPCs identidade/staff (svc OpenAPI)', {
    'n_all': rpcNames.length,
    'n_int': interesting.length,
    'int': interesting,
  }, lens: 'S2');

  final probes = <String, Map<String, dynamic>>{
    'batata_is_admin': <String, dynamic>{},
    'batata_admin_list_profiles': {'p_limit': 3},
    'batata_admin_resolve_dispute': {
      'p_dispute_id': '00000000-0000-0000-0000-000000000001',
      'p_resolution': 'favor_buyer_refund',
    },
    'batata_staff_has_permission': {
      'p_seller_id': sid,
      'p_permission': 'can_manage_reservations',
    },
    'batata_staff_invite_helper_by_email': {
      'p_email': 'x@y.z',
      'p_display_name': 'x',
    },
    'batata_find_user_id_by_email': {
      'p_email': env['LIVE_OPS_TEST_SELLER_EMAIL'],
    },
    'batata_seller_direct_payment_details': {'p_seller_id': sid},
    'batata_get_my_payout_details': <String, dynamic>{},
    'batata_create_seller_device_token': {'p_device_id': 'rts-p4'},
    'batata_revoke_seller_device_token': {'p_device_id': 'rts-p4'},
    'batata_ps_create_pairing': {
      'p_live_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_ps_claim_pairing': {
      'p_code': '000000',
      'p_device_id': 'rts',
    },
    'batata_claim_handle': {'p_handle': 'axinoquaa'},
    'batata_change_handle': {'p_handle': 'rts-hijack'},
    'batata_resolve_handle': {'p_handle': 'axinoquaa'},
    'batata_notify_helper_invitation': {
      'p_helper_user_id': sid,
      'p_seller_helpers_id': '00000000-0000-0000-0000-000000000001',
    },
  };

  for (final e in probes.entries) {
    final hit = await c.rpc(e.key, e.value, jwt: b2);
    final okTrue = hit.ok &&
        (hit.body.trim() == 'true' ||
            hit.map?['ok'] == true ||
            (hit.rowCount > 0 &&
                e.key.contains('admin_list') &&
                hit.body.contains(sid)));
    c.note('p4.rpc.${e.key}', 'buyer2', hit.brief, lens: 'S2');
    if (okTrue &&
        e.key.contains('admin') &&
        e.key != 'batata_is_admin') {
      c.hold(
        id: 'RTS-S2-020',
        lens: 'S2',
        severity: 'P0',
        title: 'JWT não-admin sucesso em ${e.key}',
        actor: 'buyer2 JWT',
        pre: 'gate batata_is_admin / owner',
        repro: 'rpc ${e.key}',
        expected: 'denied',
        obtained: hit.brief,
      );
    }
  }

  // Handle claim of seller's handle
  final ch = await c.rpc('batata_claim_handle', {'p_handle': 'axinoquaa'}, jwt: b2);
  c.note('p4.handle.claim', 'buyer2 claim handle do seller', ch.brief, lens: 'S2');
  if (ch.ok && ch.map?['ok'] == true) {
    c.hold(
      id: 'RTS-S2-021',
      lens: 'S2',
      severity: 'P1',
      title: 'JWT reclama handle já usado por outro',
      actor: 'buyer2 JWT',
      pre: 'handle axinoquaa do seller',
      repro: 'rpc batata_claim_handle',
      expected: 'taken / not_allowed',
      obtained: ch.brief,
    );
  }

  // Notifications of others
  final ntf = await c.rest(
    'GET',
    'user_notifications?user_id=eq.$sid&select=id,title,body,user_id&limit=5',
    jwt: b2,
  );
  c.note('p4.ntf', 'buyer2 GET notifications seller', {
    'http': ntf.status,
    'n': ntf.rowCount,
  }, lens: 'S1');
  if (ntf.ok && ntf.rowCount > 0) {
    c.hold(
      id: 'RTS-S1-020',
      lens: 'S1',
      severity: 'P1',
      title: 'JWT lê notificações de outro user',
      actor: 'buyer2 JWT',
      pre: 'RLS own notifications',
      repro: 'GET user_notifications?user_id=eq.$sid',
      expected: '[]',
      obtained: ntf.brief,
    );
  }

  // INSERT message into others' chat
  final chat = await c.rest(
    'GET',
    'chats?or=(and(user_a.eq.$bid,user_b.eq.$sid),and(user_a.eq.$sid,user_b.eq.$bid))&select=id&limit=1',
    service: true,
  );
  final chatId = chat.firstId;
  if (chatId != null) {
    final insMsg = await c.rest('POST', 'chat_messages', jwt: b2, body: {
      'chat_id': chatId,
      'sender_id': b2id,
      'receiver_id': sid,
      'text': '$prefix inject',
    });
    c.note('p4.msg.inject', 'buyer2 INSERT msg em chat alheio', insMsg.brief,
        lens: 'S7');
    if (insMsg.ok) {
      c.hold(
        id: 'RTS-S7-030',
        lens: 'S7',
        severity: 'P1',
        title: 'JWT injeta mensagem em chat de outros',
        actor: 'buyer2 JWT',
        pre: 'chat buyer1↔seller',
        repro: 'POST chat_messages chat_id=$chatId',
        expected: '403',
        obtained: insMsg.brief,
      );
    }
  }

  // INSERT order as seller_id=victim buyer_id=self (already allowed as buyer)
  // INSERT order spoofing buyer_id
  final pid = await c.createProduct(title: '$prefix p4', qty: 1);
  final spoof = await c.rest('POST', 'orders', jwt: b2, body: {
    'buyer_id': bid,
    'seller_id': sid,
    'product_id': pid,
    'price_total': 1,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  c.note('p4.ord.spoof', 'INSERT order buyer_id alheio', spoof.brief, lens: 'S7');
  if (spoof.ok) {
    c.hold(
      id: 'RTS-S7-031',
      lens: 'S7',
      severity: 'P0',
      title: 'JWT cria encomenda no nome de outro buyer',
      actor: 'buyer2 JWT',
      pre: 'buyer_id=buyer1',
      repro: 'POST orders buyer_id=$bid',
      expected: '403',
      obtained: spoof.brief,
    );
  }

  // reviews_gerais
  final rg = await c.rest(
    'GET',
    'reviews_gerais?select=*&limit=5',
    jwt: b2,
  );
  c.note('p4.rev.gerais', 'reviews_gerais', {
    'http': rg.status,
    'n': rg.rowCount,
  }, lens: 'S5');

  // hub unpublished
  final hub = await c.rest(
    'GET',
    'hub_profiles_public?id=eq.$b2id&select=id,handle,full_name',
  );
  c.note('p4.hub.unpub', 'anon hub perfil unpublished buyer2', hub.brief,
      lens: 'S1');
  if (hub.ok && hub.rowCount > 0) {
    c.hold(
      id: 'RTS-S1-021',
      lens: 'S1',
      severity: 'P2',
      title: 'anon vê hub_profiles_public de perfil não publicado',
      actor: 'anon',
      pre: 'buyer2 hub_published=false',
      repro: 'GET hub_profiles_public?id=eq.buyer2',
      expected: '[]',
      obtained: hub.brief,
    );
  }

  // Realtime: not a full WS; REST rpc maybe
  final rt = await c.req(
    'GET',
    '/realtime/v1/api/tenants',
    jwt: b2,
  );
  c.note('p4.realtime', 'realtime tenants', rt.brief, lens: 'S2');

  // Seller helpers: buyer2 (accepted analytics) PATCH seller_id hijack
  final hrow = await c.rest(
    'GET',
    'seller_helpers?helper_user_id=eq.$b2id&select=id,seller_id,invitation_status,permissions,active',
    jwt: b2,
  );
  c.note('p4.helper.me', 'linhas helper de buyer2', hrow.brief, lens: 'S2');
  final hid = hrow.firstId;
  if (hid != null) {
    final hij = await c.rest('PATCH', 'seller_helpers?id=eq.$hid', jwt: b2, body: {
      'seller_id': b2id,
      'permissions': {'can_manage_reservations': true},
    });
    final after = await c.rest(
      'GET',
      'seller_helpers?id=eq.$hid&select=id,seller_id,permissions,invitation_status',
      service: true,
    );
    c.note('p4.helper.hijack', 'helper tenta seller_id=self', {
      'patch': hij.brief,
      'after': after.brief,
    }, lens: 'S2');
    if (after.map?['seller_id']?.toString() == b2id) {
      c.hold(
        id: 'RTS-S2-022',
        lens: 'S2',
        severity: 'P1',
        title: 'Helper muda seller_id da linha staff para si',
        actor: 'buyer2 JWT',
        pre: 'SEC-014 congela seller_id',
        repro: 'PATCH seller_helpers seller_id=self',
        expected: 'seller_id permanece a loja',
        obtained: after.map,
      );
    }
  }

  // Favorites embed / follows
  for (final t in [
    'favorites?select=*&limit=5',
    'follows?select=*&limit=5',
    'user_follows?select=*&limit=5',
    'shipping_addresses?select=*&limit=5',
    'addresses?select=*&limit=5',
  ]) {
    final h = await c.rest('GET', t, jwt: b2);
    c.note('p4.tbl.$t', 'buyer2', {'http': h.status, 'n': h.rowCount},
        lens: 'S1');
    if (h.ok &&
        h.rowCount > 0 &&
        (h.body.contains(sid) || h.body.contains(bid)) &&
        t.contains('address')) {
      c.hold(
        id: 'RTS-S1-022',
        lens: 'S1',
        severity: 'P0',
        title: 'JWT lê moradas de outros ($t)',
        actor: 'buyer2 JWT',
        pre: t,
        repro: 'GET $t',
        expected: '[] / só próprias',
        obtained: h.brief,
      );
    }
  }

  await dumpJson('${outDir()}/pass4.json', {
    'auditor': 'REDTEAM_BLIND_S_IDENTIDADE_STAFF_v1',
    'stamp': stamp,
    'pass': 4,
    'production_touched': false,
    'fase4': false,
    'rpc_interesting': interesting,
    'findings': c.findings,
    'notes': c.notes,
  });
  stdout.writeln('FINDINGS ${c.findings.length}');
}
