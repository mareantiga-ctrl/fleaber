/// REDTEAM_BLIND_S_IDENTIDADE_STAFF_v1 — pass1
/// dart run tool/redteam_blind_s_20260901T0657/pass1.dart
/// Staging only. No production. No SQL/Edge/Flutter patches.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '_rts.dart';

bool looksUuid(String? s) =>
    s != null &&
    RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(s);

String piiKeys(Map<String, dynamic>? m) {
  if (m == null) return 'null';
  final keys = [
    'phone',
    'iban',
    'mb_way',
    'legal_full_name',
    'email',
    'nif',
    'shipping_address',
    'address',
  ];
  final out = <String, String>{};
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v'.trim().isNotEmpty && '$v' != 'null') {
      out[k] = clip('$v', 40);
    }
  }
  return jsonEncode(out);
}

void main() async {
  final env = loadEnv();
  final c = Rts.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final b = c.buyerJwt!;
  final s = c.sellerJwt!;
  final b2 = c.buyer2Jwt!;
  final s2 = c.seller2Jwt!;
  final bid = c.buyerId!;
  final sid = c.sellerId!;
  final b2id = c.buyer2Id!;
  final s2id = c.seller2Id!;

  c.note('actors', 'two real UUIDs', {
    'buyer': bid,
    'seller': sid,
    'buyer2': b2id,
    'seller2': s2id,
  }, lens: 'S1');

  // Seed PII on seller via service_role (fixture only) so we can detect leaks.
  await c.rest('PATCH', 'profiles?id=eq.$sid', service: true, body: {
    'phone': '910000657',
    'legal_full_name': 'RTS Seller Legal',
    'iban': 'PT50000201231234567890154',
    'mb_way': '910000657',
  }, prefer: 'return=minimal');

  // =====================================================================
  // S1 — Profiles PII
  // =====================================================================
  final own = await c.rest(
    'GET',
    'profiles?id=eq.$bid&select=id,full_name,user_type,phone,legal_full_name,iban,mb_way,email,handle',
    jwt: b,
  );
  c.note('s1.own', 'buyer lê o próprio perfil', {
    'http': own.brief,
    'pii': piiKeys(own.map),
    'user_type': own.map?['user_type'],
  }, lens: 'S1');

  final other = await c.rest(
    'GET',
    'profiles?id=eq.$sid&select=id,full_name,user_type,phone,legal_full_name,iban,mb_way,email,handle',
    jwt: b,
  );
  c.note('s1.other.rest', 'buyer GET profiles seller', other.brief, lens: 'S1');
  if (other.ok && other.rowCount > 0) {
    final pii = piiKeys(other.map);
    final sev = (other.map?['phone'] != null ||
            other.map?['iban'] != null ||
            other.map?['mb_way'] != null ||
            other.map?['legal_full_name'] != null ||
            other.map?['email'] != null)
        ? 'P0'
        : 'P2';
    c.hold(
      id: 'RTS-S1-001',
      lens: 'S1',
      severity: sev,
      title: 'JWT buyer lê linha profiles de outro UUID',
      actor: 'buyer JWT GET profiles?id=eq.seller',
      pre: 'RLS own-row; PII fixture no seller',
      repro: 'GET /rest/v1/profiles?id=eq.$sid',
      expected: '[] / 0 rows',
      obtained: other.brief,
      evidence: {'pii': pii, 'rows': other.rowCount},
    );
  }

  final otherStar = await c.rest('GET', 'profiles?id=eq.$sid&select=*', jwt: b);
  c.note('s1.other.star', 'buyer GET profiles * seller', otherStar.brief,
      lens: 'S1');
  if (otherStar.ok && otherStar.rowCount > 0 && other.map == null) {
    c.hold(
      id: 'RTS-S1-002',
      lens: 'S1',
      severity: 'P1',
      title: 'select=* devolve linha alheia (select explícito não)',
      actor: 'buyer JWT',
      pre: 'mesmo UUID seller',
      repro: 'GET profiles?id=eq.$sid&select=*',
      expected: '[]',
      obtained: otherStar.brief,
    );
  }

  final anonProf = await c.rest(
    'GET',
    'profiles?id=eq.$sid&select=id,phone,iban,email,legal_full_name',
  );
  c.note('s1.anon', 'anon GET profiles seller', anonProf.brief, lens: 'S1');
  if (anonProf.ok && anonProf.rowCount > 0) {
    c.hold(
      id: 'RTS-S1-003',
      lens: 'S1',
      severity: 'P0',
      title: 'anon SELECT profiles de outro user',
      actor: 'anon',
      pre: 'revoke anon profiles',
      repro: 'GET profiles?id=eq.$sid',
      expected: '401/403/[]',
      obtained: anonProf.brief,
    );
  }

  final dirAll = await c.rest(
    'GET',
    'profiles_directory_public?select=id,full_name,user_type,handle&limit=20',
    jwt: b,
  );
  c.note('s1.dir', 'directory autenticada', {
    'http': dirAll.status,
    'n': dirAll.rowCount,
    'has_seller': dirAll.body.contains(sid),
    'has_buyer2_unpub': dirAll.body.contains(b2id),
  }, lens: 'S1');
  if (dirAll.ok && dirAll.body.contains(b2id)) {
    c.hold(
      id: 'RTS-S1-004',
      lens: 'S1',
      severity: 'P2',
      title: 'directory lista perfil hub_published=false de outro UUID',
      actor: 'buyer JWT',
      pre: 'buyer2 hub_published=false',
      repro: 'GET profiles_directory_public',
      expected: 'sem buyer2',
      obtained: 'buyer2 visível n=${dirAll.rowCount}',
    );
  }

  final findEmail = await c.rpc(
    'batata_find_user_id_by_email',
    {'p_email': env['LIVE_OPS_TEST_SELLER_EMAIL']},
    jwt: b,
  );
  c.note('s1.find_email', 'find_user_id_by_email seller', findEmail.brief,
      lens: 'S1');
  if (findEmail.ok && looksUuid(findEmail.body.replaceAll('"', '').trim())) {
    c.hold(
      id: 'RTS-S1-005',
      lens: 'S1',
      severity: 'P1',
      title: 'JWT recebe UUID por email (oracle clássico)',
      actor: 'buyer JWT',
      pre: 'email do seller conhecido',
      repro: 'rpc batata_find_user_id_by_email',
      expected: 'null',
      obtained: findEmail.brief,
    );
  }

  final payDet = await c.rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': sid},
    jwt: b2,
  );
  c.note('s1.paydet', 'IBAN/MB WAY sem order (buyer2→seller)', payDet.brief,
      lens: 'S1');
  final payBody = payDet.body.toLowerCase();
  if (payDet.ok &&
      (payBody.contains('pt50') ||
          payBody.contains('910000657') ||
          payBody.contains('iban'))) {
    c.hold(
      id: 'RTS-S1-006',
      lens: 'S1',
      severity: 'P0',
      title: 'buyer2 lê IBAN/MB WAY do seller sem order off-platform',
      actor: 'buyer2 JWT',
      pre: 'sem encomenda entre buyer2 e seller',
      repro: 'rpc batata_seller_direct_payment_details p_seller_id=seller',
      expected: '[] vazio',
      obtained: payDet.brief,
    );
  }

  final adminList = await c.rpc(
    'batata_admin_list_profiles',
    {'p_limit': 5},
    jwt: b,
  );
  c.note('s1.admin_list', 'admin_list_profiles buyer', adminList.brief,
      lens: 'S1');
  if (adminList.ok && adminList.rowCount > 0) {
    c.hold(
      id: 'RTS-S1-007',
      lens: 'S2',
      severity: 'P0',
      title: 'JWT não-admin executa batata_admin_list_profiles',
      actor: 'buyer JWT',
      pre: 'buyer não é admin',
      repro: 'rpc batata_admin_list_profiles',
      expected: 'Acesso negado',
      obtained: adminList.brief,
    );
  }

  final embed = await c.rest(
    'GET',
    'products?seller_id=eq.$sid&select=id,title,seller:profiles(id,phone,iban,email,legal_full_name)&limit=1',
    jwt: b,
  );
  c.note('s1.embed', 'embed profiles via products', embed.brief, lens: 'S1');
  if (embed.ok &&
      (embed.body.contains('910000657') ||
          embed.body.toLowerCase().contains('pt50') ||
          embed.body.contains('RTS Seller Legal'))) {
    c.hold(
      id: 'RTS-S1-008',
      lens: 'S1',
      severity: 'P0',
      title: 'embed PostgREST profiles(*) vaza PII do seller',
      actor: 'buyer JWT',
      pre: 'products.seller_id = seller',
      repro: 'GET products?select=seller:profiles(phone,iban,…)',
      expected: 'embed vazio / sem PII',
      obtained: embed.brief,
    );
  }

  final authAdmin = await c.req('GET', '/auth/v1/admin/users?page=1&per_page=2',
      jwt: b);
  c.note('s1.auth.admin', 'Auth admin users com JWT', authAdmin.brief,
      lens: 'S1');
  if (authAdmin.ok && authAdmin.body.contains('@')) {
    c.hold(
      id: 'RTS-S1-009',
      lens: 'S1',
      severity: 'P0',
      title: 'JWT lista auth.users (emails)',
      actor: 'buyer JWT',
      pre: 'GoTrue admin exige service_role',
      repro: 'GET /auth/v1/admin/users',
      expected: '401/403',
      obtained: authAdmin.brief,
    );
  }

  // =====================================================================
  // S2 — Admin boundary
  // =====================================================================
  final isAdmB = await c.rpc('batata_is_admin', <String, dynamic>{}, jwt: b);
  final isAdmS = await c.rpc('batata_is_admin', <String, dynamic>{}, jwt: s);
  final isAdmAnon =
      await c.rpc('batata_is_admin', <String, dynamic>{});
  c.note('s2.is_admin', 'batata_is_admin', {
    'buyer': isAdmB.brief,
    'seller': isAdmS.brief,
    'anon': isAdmAnon.brief,
  }, lens: 'S2');
  for (final row in [
    ['buyer', isAdmB],
    ['seller', isAdmS],
    ['anon', isAdmAnon],
  ]) {
    final hit = row[1] as HttpHit;
    if (hit.ok && hit.body.trim() == 'true') {
      c.hold(
        id: 'RTS-S2-001',
        lens: 'S2',
        severity: 'P0',
        title: '${row[0]} batata_is_admin() = true',
        actor: '${row[0]}',
        pre: 'contas QA não são admin',
        repro: 'rpc batata_is_admin',
        expected: 'false',
        obtained: hit.brief,
      );
    }
  }

  final patchAdmin = await c.rest(
    'PATCH',
    'profiles?id=eq.$bid',
    jwt: b,
    body: {'user_type': 'admin'},
  );
  final afterPatch = await c.profileRow(bid, service: true);
  c.note('s2.patch.admin', 'buyer PATCH user_type=admin', {
    'http': patchAdmin.brief,
    'user_type_after': afterPatch?['user_type'],
  }, lens: 'S2');
  final tAfter = (afterPatch?['user_type'] ?? '').toString().toLowerCase();
  if (const {'admin', 'admim', 'administrador', 'administracao'}
      .contains(tAfter)) {
    c.hold(
      id: 'RTS-S2-002',
      lens: 'S2',
      severity: 'P0',
      title: 'JWT promoveu-se a admin via PATCH profiles.user_type',
      actor: 'buyer JWT',
      pre: 'trigger guard user_type',
      repro: 'PATCH profiles user_type=admin',
      expected: 'user_type inalterado / 403',
      obtained: afterPatch,
    );
  }

  final patchOtherType = await c.rest(
    'PATCH',
    'profiles?id=eq.$sid',
    jwt: b,
    body: {'user_type': 'admin', 'full_name': 'Hacked'},
  );
  c.note('s2.patch.other', 'buyer PATCH perfil seller', patchOtherType.brief,
      lens: 'S2');
  if (patchOtherType.ok && patchOtherType.rowCount > 0) {
    c.hold(
      id: 'RTS-S2-003',
      lens: 'S2',
      severity: 'P0',
      title: 'JWT altera perfil de outro UUID',
      actor: 'buyer JWT',
      pre: 'RLS update own',
      repro: 'PATCH profiles?id=eq.$sid',
      expected: '[] / 403',
      obtained: patchOtherType.brief,
    );
  }

  final insertAlien = await c.rest('POST', 'profiles', jwt: b, body: {
    'id': s2id,
    'full_name': 'hijack',
    'user_type': 'admin',
  });
  c.note('s2.insert.alien', 'buyer INSERT profile id=seller2', insertAlien.brief,
      lens: 'S2');
  if (insertAlien.ok) {
    c.hold(
      id: 'RTS-S2-004',
      lens: 'S2',
      severity: 'P0',
      title: 'JWT INSERT profiles com user_id alheio',
      actor: 'buyer JWT',
      pre: 'insert own-row',
      repro: 'POST profiles id=seller2 user_type=admin',
      expected: '403',
      obtained: insertAlien.brief,
    );
  }

  // New signup: metadata admin + INSERT if no row.
  final newEmail = '${prefix.toLowerCase()}-new@fleaber.test';
  const newPass = 'Rts0657new!xK';
  final signup = await c.req('POST', '/auth/v1/signup', body: {
    'email': newEmail,
    'password': newPass,
    'data': {'user_type': 'admin', 'full_name': '$prefix-NEW'},
  });
  c.note('s2.signup', 'signup metadata user_type=admin', signup.status,
      lens: 'S2');
  String? newJwt;
  String? newId;
  try {
    newJwt = await c.signIn(newEmail, newPass);
    final me = await c.req('GET', '/auth/v1/user', jwt: newJwt);
    newId = (me.json is Map) ? (me.json as Map)['id']?.toString() : null;
  } catch (e) {
    c.note('s2.signup.login', 'login new', '$e', lens: 'S2');
  }
  if (newId != null && newJwt != null) {
    c.createdUserIds.add(newId);
    final np = await c.rest(
      'GET',
      'profiles?id=eq.$newId&select=id,user_type,full_name',
      jwt: newJwt,
    );
    c.note('s2.signup.profile', 'perfil após signup', np.brief, lens: 'S2');
    var ut = (np.map?['user_type'] ?? '').toString().toLowerCase();
    if (np.rowCount == 0) {
      final ins = await c.rest('POST', 'profiles', jwt: newJwt, body: {
        'id': newId,
        'full_name': '$prefix-NEW',
        'user_type': 'admin',
      });
      c.note('s2.signup.insert', 'INSERT admin (sem linha)', ins.brief,
          lens: 'S2');
      final np2 = await c.profileRow(newId, service: true);
      ut = (np2?['user_type'] ?? '').toString().toLowerCase();
    }
    if (const {'admin', 'admim', 'administrador', 'administracao'}
        .contains(ut)) {
      c.hold(
        id: 'RTS-S2-005',
        lens: 'S2',
        severity: 'P0',
        title: 'Conta nova nasceu / inseriu-se como admin',
        actor: 'signup JWT',
        pre: 'trigger handle_new_user + guard INSERT',
        repro: 'signup data.user_type=admin ou INSERT profiles',
        expected: 'vendedor/comprador',
        obtained: ut,
      );
    }
    final del = await c.rest('DELETE', 'profiles?id=eq.$newId', jwt: newJwt);
    c.note('s2.del.own', 'DELETE próprio perfil', del.brief, lens: 'S2');
    if (del.ok && (del.rowCount > 0 || del.body.contains(newId))) {
      final reins = await c.rest('POST', 'profiles', jwt: newJwt, body: {
        'id': newId,
        'full_name': '$prefix-RE',
        'user_type': 'admin',
      });
      final afterRe = await c.profileRow(newId, service: true);
      c.note('s2.reinsert', 'DELETE+INSERT admin', {
        'del': del.brief,
        'ins': reins.brief,
        'type': afterRe?['user_type'],
      }, lens: 'S2');
      final rt = (afterRe?['user_type'] ?? '').toString().toLowerCase();
      if (const {'admin', 'admim', 'administrador', 'administracao'}
          .contains(rt)) {
        c.hold(
          id: 'RTS-S2-006',
          lens: 'S2',
          severity: 'P0',
          title: 'DELETE perfil próprio + INSERT user_type=admin',
          actor: 'signup JWT',
          pre: 'guard só em UPDATE',
          repro: 'DELETE profiles; POST user_type=admin',
          expected: 'DELETE 403 ou INSERT demote',
          obtained: afterRe,
        );
      }
    }

    final mintTok = await c.rpc(
      'batata_create_seller_device_token',
      {'p_device_id': 'rts-new-device', 'p_label': 'rts'},
      jwt: newJwt,
    );
    c.note('s2.new.device', 'new user mint OCR token', mintTok.brief,
        lens: 'S6');
    if (mintTok.ok && (mintTok.map?['ok'] == true ||
        (mintTok.map?['token']?.toString().length ?? 0) > 10)) {
      c.hold(
        id: 'RTS-S6-001',
        lens: 'S6',
        severity: 'P1',
        title: 'Conta nova (não loja) emite seller device_token OCR',
        actor: 'signup JWT',
        pre: 'trigger força user_type=vendedor; token amarra a auth.uid()',
        repro: 'rpc batata_create_seller_device_token',
        expected: 'not_seller',
        obtained: mintTok.brief,
      );
    }
  }

  final resolve = await c.rpc(
    'batata_admin_resolve_dispute',
    {
      'p_dispute_id': '00000000-0000-0000-0000-000000000001',
      'p_resolution': 'favor_buyer_refund',
      'p_note': 'rts',
    },
    jwt: b,
  );
  c.note('s2.resolve', 'admin_resolve_dispute buyer', resolve.brief, lens: 'S2');
  if (resolve.ok && resolve.body.trim() == 'true') {
    c.hold(
      id: 'RTS-S2-007',
      lens: 'S2',
      severity: 'P0',
      title: 'JWT não-admin resolve disputa (true)',
      actor: 'buyer JWT',
      pre: 'batata_is_admin gate',
      repro: 'rpc batata_admin_resolve_dispute',
      expected: 'exception admin',
      obtained: resolve.brief,
    );
  }

  final kill = await c.rpc(
    'batata_director_activate_kill_switch',
    {'p_scope': 'global', 'p_reason': 'rts'},
    jwt: b,
  );
  c.note('s2.kill', 'director kill switch buyer', kill.brief, lens: 'S2');
  if (kill.ok && (kill.map?['ok'] == true || kill.body.contains('activated'))) {
    c.hold(
      id: 'RTS-S2-008',
      lens: 'S2',
      severity: 'P0',
      title: 'JWT não-admin activa kill switch Live Director',
      actor: 'buyer JWT',
      pre: 'admin_required',
      repro: 'rpc batata_director_activate_kill_switch',
      expected: 'admin_required',
      obtained: kill.brief,
    );
  }

  final dirIns = await c.rest('POST', 'live_director_scripts', jwt: b, body: {
    'name': prefix,
    'body': '{}',
  });
  c.note('s2.director.insert', 'INSERT live_director_scripts', dirIns.brief,
      lens: 'S6');
  if (dirIns.ok) {
    c.hold(
      id: 'RTS-S6-002',
      lens: 'S6',
      severity: 'P1',
      title: 'JWT não-admin INSERT live_director_scripts',
      actor: 'buyer JWT',
      pre: 'policy batata_is_admin',
      repro: 'POST live_director_scripts',
      expected: '403',
      obtained: dirIns.brief,
    );
  }

  // Staff: helper INSERT as non-owner onto seller shop
  final helperIns = await c.rest('POST', 'seller_helpers', jwt: b2, body: {
    'seller_id': sid,
    'helper_user_id': b2id,
    'invited_by': sid,
    'display_name': 'RTS hijack',
    'invitation_status': 'accepted',
    'active': true,
    'permissions': {
      'can_manage_reservations': true,
      'can_manage_products': true,
    },
  });
  c.note('s2.helper.insert', 'buyer2 INSERT helper na loja seller',
      helperIns.brief, lens: 'S2');
  if (helperIns.ok) {
    c.hold(
      id: 'RTS-S2-009',
      lens: 'S2',
      severity: 'P0',
      title: 'JWT insere-se como staff accepted na loja de outro',
      actor: 'buyer2 JWT',
      pre: 'INSERT seller_id=auth.uid()',
      repro: 'POST seller_helpers seller_id=seller accepted',
      expected: '403',
      obtained: helperIns.brief,
    );
  }

  // Seller invites buyer2 with narrow perms; buyer2 tries to escalate
  final invite = await c.rpc(
    'batata_staff_invite_helper_by_email',
    {
      'p_email': c.buyer2Email,
      'p_display_name': 'RTS-B2',
      'p_permissions': {'can_view_analytics': true},
    },
    jwt: s,
  );
  c.note('s2.invite', 'seller convite buyer2 analytics-only', invite.brief,
      lens: 'S2');
  final helperRow = await c.rest(
    'GET',
    'seller_helpers?seller_id=eq.$sid&helper_user_id=eq.$b2id&select=id,invitation_status,active,permissions',
    jwt: s,
  );
  c.note('s2.helper.row', 'linha convite', helperRow.brief, lens: 'S2');
  final hid = helperRow.firstId;
  if (hid != null) {
    final esc = await c.rest('PATCH', 'seller_helpers?id=eq.$hid', jwt: b2, body: {
      'invitation_status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
      'active': true,
      'permissions': {
        'can_manage_reservations': true,
        'can_manage_products': true,
        'can_view_analytics': true,
      },
    });
    final afterEsc = await c.rest(
      'GET',
      'seller_helpers?id=eq.$hid&select=id,invitation_status,active,permissions',
      service: true,
    );
    c.note('s2.helper.esc', 'buyer2 aceita + alarga perms', {
      'patch': esc.brief,
      'after': afterEsc.brief,
    }, lens: 'S2');
    final perms = afterEsc.map?['permissions'];
    final widened = perms is Map && perms['can_manage_reservations'] == true;
    if (esc.ok && widened) {
      c.hold(
        id: 'RTS-S2-010',
        lens: 'S2',
        severity: 'P1',
        title: 'Helper alarga permissions ao aceitar convite',
        actor: 'buyer2 JWT PATCH seller_helpers',
        pre: 'convite só can_view_analytics; SEC-014',
        repro: 'PATCH id=$hid permissions=reservations',
        expected: 'permissions ficam analytics-only',
        obtained: afterEsc.map,
      );
    }
    final staffCheck = await c.rpc(
      'batata_staff_has_permission',
      {'p_seller_id': sid, 'p_permission': 'can_manage_reservations'},
      jwt: b2,
    );
    c.note('s2.staff.has', 'buyer2 can_manage_reservations na loja seller',
        staffCheck.brief, lens: 'S2');
    if (staffCheck.ok && staffCheck.body.trim() == 'true' && !widened) {
      c.hold(
        id: 'RTS-S2-011',
        lens: 'S2',
        severity: 'P1',
        title: 'staff_has_permission reservations=true sem permissão no convite',
        actor: 'buyer2 JWT',
        pre: 'perms analytics-only',
        repro: 'rpc batata_staff_has_permission',
        expected: 'false',
        obtained: staffCheck.brief,
      );
    }
  }

  final staffOther = await c.rpc(
    'batata_staff_has_permission',
    {'p_seller_id': sid, 'p_permission': 'can_manage_reservations'},
    jwt: b,
  );
  c.note('s2.staff.stranger', 'buyer1 staff na loja seller?', staffOther.brief,
      lens: 'S2');
  if (staffOther.ok && staffOther.body.trim() == 'true') {
    c.hold(
      id: 'RTS-S2-012',
      lens: 'S2',
      severity: 'P0',
      title: 'JWT alheio tem staff_has_permission na loja',
      actor: 'buyer JWT',
      pre: 'buyer não é helper',
      repro: 'rpc batata_staff_has_permission seller',
      expected: 'false',
      obtained: staffOther.brief,
    );
  }

  // Invite oracle variant: existing vs missing vs pending
  final invGhost = await c.rpc(
    'batata_staff_invite_helper_by_email',
    {
      'p_email': 'nobody-rts-${Random().nextInt(99999)}@nope.invalid',
      'p_display_name': 'ghost',
      'p_permissions': <String, dynamic>{},
    },
    jwt: s,
  );
  final invKnown = await c.rpc(
    'batata_staff_invite_helper_by_email',
    {
      'p_email': c.buyer2Email,
      'p_display_name': 'again',
      'p_permissions': <String, dynamic>{},
    },
    jwt: s,
  );
  c.note('s2.invite.oracle', 'anti-oracle invite', {
    'ghost': invGhost.brief,
    'known_again': invKnown.brief,
  }, lens: 'S1');
  if (invGhost.ok &&
      invKnown.status != invGhost.status &&
      invKnown.body.contains('invite_pending')) {
    // differential is expected for already-invited; not a general enum
    c.note('s2.invite.diff', 'diff só para já-convidado (não enum global)',
        invKnown.brief, lens: 'S1');
  }

  // =====================================================================
  // S3 — Storage paths
  // =====================================================================
  final buckets = ['chat_media', 'fleaber_private', 'proof_photos'];
  for (final bucket in buckets) {
    final lstAnon = await c.storageList(bucket);
    final lstB = await c.storageList(bucket, jwt: b);
    final lstB2 = await c.storageList(bucket, prefix: 'chat_uploads/$sid/', jwt: b2);
    c.note('s3.list.$bucket', 'list bucket', {
      'anon': lstAnon.brief,
      'buyer': lstB.brief,
      'buyer2_prefix_seller': lstB2.brief,
    }, lens: 'S3');
    bool listedOther(HttpHit h) {
      if (!h.ok) return false;
      final t = h.body;
      return t.contains(sid) && t.contains(bid) == false && t.length > 8;
    }

    if (listedOther(lstAnon) || listedOther(lstB2)) {
      c.hold(
        id: 'RTS-S3-001-$bucket',
        lens: 'S3',
        severity: 'P1',
        title: 'Listagem storage $bucket revela paths de outro user',
        actor: 'anon/buyer2',
        pre: 'policies owner/counterparty',
        repro: 'POST /storage/v1/object/list/$bucket',
        expected: '[] / 400',
        obtained: {'anon': lstAnon.brief, 'b2': lstB2.brief},
      );
    }
  }

  // Fixture: observe real objects of seller (service_role observation).
  final obs = await c.req(
    'GET',
    '/rest/v1/objects?bucket_id=eq.fleaber_private&select=name,bucket_id&limit=15',
    service: true,
    extra: {'Accept-Profile': 'storage', 'Content-Profile': 'storage'},
  );
  if (obs.status == 406 || obs.status == 404 || !obs.ok) {
    // try storage schema via Host header alternative
    c.note('s3.objects.rest', 'storage.objects via rest', obs.brief, lens: 'S3');
  } else {
    c.note('s3.objects.rest', 'storage.objects via rest', {
      'n': obs.rowCount,
      'snip': clip(obs.body, 200),
    }, lens: 'S3');
  }

  final svcListPriv = await c.storageList('fleaber_private',
      prefix: '', service: true, limit: 40);
  c.note('s3.svc.priv', 'service_role list fleaber_private (observação)',
      {'http': svcListPriv.status, 'n': svcListPriv.rowCount}, lens: 'S3');

  String? victimPath;
  String? victimBucket;
  for (final item in svcListPriv.list) {
    if (item is Map) {
      final name = item['name']?.toString() ?? '';
      if (name.contains(sid) && !name.contains(bid) && name.contains('/')) {
        victimPath = name;
        victimBucket = 'fleaber_private';
        break;
      }
    }
  }
  if (victimPath == null) {
    final svcChat = await c.storageList('chat_media',
        prefix: 'profile_photos/$sid/', service: true, limit: 10);
    c.note('s3.svc.chat.profile', 'profile_photos seller', svcChat.brief,
        lens: 'S3');
    for (final item in svcChat.list) {
      if (item is Map) {
        final name = item['name']?.toString() ?? '';
        if (name.isNotEmpty) {
          victimPath = name.startsWith('profile_photos/')
              ? name
              : 'profile_photos/$sid/$name';
          victimBucket = 'chat_media';
          break;
        }
      }
    }
  }
  if (victimPath == null) {
    // Upload as seller then try to read as buyer2 (own path control).
    final up = await c.storageUpload(
      'fleaber_private',
      'chat_uploads/$sid/rts-s3.txt',
      jwt: s,
      content: 'SECRET-RTS-SELLER-MEDIA',
    );
    c.note('s3.up.seller', 'seller upload fleaber_private', up.brief, lens: 'S3');
    if (up.ok || up.status == 200) {
      victimPath = 'chat_uploads/$sid/rts-s3.txt';
      victimBucket = 'fleaber_private';
    }
  }

  if (victimPath != null && victimBucket != null) {
    final getB2 = await c.storageGet(victimBucket, victimPath, jwt: b2);
    final getAnon = await c.storageGet(victimBucket, victimPath);
    final getPub = await c.storageGet(victimBucket, victimPath, publicBucket: true);
    final signB2 = await c.storageSign(victimBucket, victimPath, jwt: b2);
    c.note('s3.read.victim', 'ler path de outro user', {
      'bucket': victimBucket,
      'path': victimPath,
      'b2': getB2.brief,
      'anon': getAnon.brief,
      'public': getPub.brief,
      'sign_b2': signB2.brief,
    }, lens: 'S3');
    bool leaked(HttpHit h) =>
        h.ok &&
        (h.body.contains('SECRET-RTS') ||
            h.body.contains('PNG') ||
            h.body.length > 80 && h.status == 200);
    if (leaked(getB2) || leaked(getAnon) || leaked(getPub)) {
      c.hold(
        id: 'RTS-S3-002',
        lens: 'S3',
        severity: 'P0',
        title: 'Leitura de objecto storage de outro utilizador',
        actor: leaked(getAnon) || leaked(getPub) ? 'anon' : 'buyer2 JWT',
        pre: 'path $victimBucket/$victimPath',
        repro: 'GET /storage/v1/object[/public]/$victimBucket/$victimPath',
        expected: '400/403',
        obtained: {
          'b2': getB2.brief,
          'anon': getAnon.brief,
          'public': getPub.brief,
        },
      );
    }
    if (signB2.ok && (signB2.map?['signedURL'] != null ||
        signB2.body.contains('token='))) {
      c.hold(
        id: 'RTS-S3-003',
        lens: 'S3',
        severity: 'P1',
        title: 'JWT alheio emite signed URL para path de outro',
        actor: 'buyer2 JWT',
        pre: victimPath,
        repro: 'POST /storage/v1/object/sign/$victimBucket/$victimPath',
        expected: '403',
        obtained: signB2.brief,
      );
    }
  } else {
    c.note('s3.no.victim.path', 'sem objecto alheio observável nesta ronda',
        'will retry pass2', lens: 'S3');
  }

  // Upload into someone else's prefix
  final upAlien = await c.storageUpload(
    'fleaber_private',
    'chat_uploads/$sid/rts-alien.txt',
    jwt: b2,
    content: 'ALIEN',
  );
  c.note('s3.up.alien', 'buyer2 upload prefixo seller', upAlien.brief, lens: 'S3');
  if (upAlien.ok) {
    c.hold(
      id: 'RTS-S3-004',
      lens: 'S3',
      severity: 'P1',
      title: 'JWT escreve no prefixo storage de outro UUID',
      actor: 'buyer2 JWT',
      pre: 'insert own prefix only',
      repro: 'POST fleaber_private/chat_uploads/$sid/rts-alien.txt',
      expected: '403',
      obtained: upAlien.brief,
    );
  }

  // REST storage.objects as JWT
  final objJwt = await c.req(
    'GET',
    '/rest/v1/objects?select=name,bucket_id&limit=10',
    jwt: b2,
    extra: {'Accept-Profile': 'storage'},
  );
  c.note('s3.rest.objects', 'JWT GET storage.objects', objJwt.brief, lens: 'S3');
  if (objJwt.ok && objJwt.rowCount > 0 && objJwt.body.contains(sid)) {
    c.hold(
      id: 'RTS-S3-005',
      lens: 'S3',
      severity: 'P1',
      title: 'JWT lista storage.objects (schema storage) com paths alheios',
      actor: 'buyer2 JWT',
      pre: 'Accept-Profile: storage',
      repro: 'GET /rest/v1/objects',
      expected: '406/[] sem paths alheios',
      obtained: objJwt.brief,
    );
  }

  // =====================================================================
  // S5 — Reviews
  // =====================================================================
  final revOther = await c.rest(
    'GET',
    'reviews?target_id=eq.$sid&select=id,stars,buyer_id,target_id,comment,order_id&limit=5',
    jwt: b2,
  );
  c.note('s5.sel.other', 'buyer2 SELECT reviews do seller (não target)',
      {'http': revOther.status, 'n': revOther.rowCount}, lens: 'S5');

  final pubRat = await c.rest(
    'GET',
    'reviews_public_ratings?target_id=eq.$sid&select=id,stars,comment,buyer_id&limit=5',
    jwt: b2,
  );
  c.note('s5.public', 'reviews_public_ratings', {
    'http': pubRat.status,
    'n': pubRat.rowCount,
    'has_buyer_id': pubRat.body.contains('buyer_id'),
  }, lens: 'S5');

  String? reviewId;
  if (revOther.rowCount > 0) {
    reviewId = revOther.firstId;
  } else if (pubRat.rowCount > 0) {
    reviewId = pubRat.firstId;
  }
  if (reviewId != null) {
    final upd = await c.rest(
      'PATCH',
      'reviews?id=eq.$reviewId',
      jwt: b2,
      body: {'stars': 5, 'comment': 'RTS hijack'},
    );
    c.note('s5.patch.tbl', 'PATCH reviews alheia', upd.brief, lens: 'S5');
    if (upd.ok && upd.rowCount > 0) {
      c.hold(
        id: 'RTS-S5-001',
        lens: 'S5',
        severity: 'P1',
        title: 'JWT UPDATE review alheia',
        actor: 'buyer2 JWT',
        pre: 'review $reviewId não é do buyer2',
        repro: 'PATCH reviews?id=eq.$reviewId stars=5',
        expected: '[] / 403',
        obtained: upd.brief,
      );
    }
    final updV = await c.rest(
      'PATCH',
      'reviews_public_ratings?id=eq.$reviewId',
      jwt: b2,
      body: {'stars': 5, 'comment': 'RTS view hijack'},
    );
    c.note('s5.patch.view', 'PATCH reviews_public_ratings', updV.brief,
        lens: 'S5');
    if (updV.ok && (updV.rowCount > 0 || updV.body.contains('RTS view'))) {
      c.hold(
        id: 'RTS-S5-002',
        lens: 'S5',
        severity: 'P0',
        title: 'JWT UPDATE reputação via view security_invoker=false',
        actor: 'buyer2 JWT',
        pre: 'reviews_public_ratings GRANT SELECT; view updatable?',
        repro: 'PATCH reviews_public_ratings?id=eq.$reviewId',
        expected: '401/403',
        obtained: updV.brief,
      );
    }
    final del = await c.rest('DELETE', 'reviews?id=eq.$reviewId', jwt: b2);
    c.note('s5.del.other', 'DELETE review alheia', del.brief, lens: 'S5');
    if (del.ok && del.rowCount > 0) {
      c.hold(
        id: 'RTS-S5-003',
        lens: 'S5',
        severity: 'P1',
        title: 'JWT DELETE review alheia',
        actor: 'buyer2 JWT',
        pre: 'trigger review_delete_forbidden',
        repro: 'DELETE reviews?id=eq.$reviewId',
        expected: 'review_delete_forbidden / []',
        obtained: del.brief,
      );
    }
  }

  final insRev = await c.rest('POST', 'reviews', jwt: b2, body: {
    'buyer_id': bid,
    'target_id': sid,
    'stars': 5,
    'comment': 'RTS fake',
    'author_role': 'comprador',
    'order_id': '00000000-0000-0000-0000-000000000001',
  });
  c.note('s5.ins.spoof', 'INSERT review buyer_id alheio', insRev.brief,
      lens: 'S5');
  if (insRev.ok) {
    c.hold(
      id: 'RTS-S5-004',
      lens: 'S5',
      severity: 'P1',
      title: 'JWT INSERT review com buyer_id de outro',
      actor: 'buyer2 JWT',
      pre: 'WITH CHECK buyer_id=auth.uid() + trigger',
      repro: 'POST reviews buyer_id=buyer1',
      expected: '403 / review_order_not_yours',
      obtained: insRev.brief,
    );
  }

  // Seller DELETE of reviews targeting them (policy allows attempt)
  if (reviewId != null) {
    final delS = await c.rest('DELETE', 'reviews?id=eq.$reviewId', jwt: s);
    c.note('s5.del.target', 'seller DELETE review onde é target', delS.brief,
        lens: 'S5');
    if (delS.ok && delS.rowCount > 0) {
      c.hold(
        id: 'RTS-S5-005',
        lens: 'S5',
        severity: 'P1',
        title: 'Vendedor apaga review em que é target (release 5★ / silêncio)',
        actor: 'seller JWT',
        pre: 'policy target_id=auth.uid(); trigger deve falhar',
        repro: 'DELETE reviews?id=eq.$reviewId',
        expected: 'review_delete_forbidden',
        obtained: delS.brief,
      );
    }
  }

  // =====================================================================
  // S7 — Orders / chat cross-user
  // =====================================================================
  final ordsB2 = await c.rest(
    'GET',
    'orders?buyer_id=eq.$bid&select=id,status,buyer_id,seller_id,price_total,proof_url&limit=5',
    jwt: b2,
  );
  c.note('s7.orders.other', 'buyer2 GET orders do buyer1', {
    'http': ordsB2.status,
    'n': ordsB2.rowCount,
  }, lens: 'S7');
  if (ordsB2.ok && ordsB2.rowCount > 0) {
    c.hold(
      id: 'RTS-S7-001',
      lens: 'S7',
      severity: 'P0',
      title: 'JWT lê encomendas de outro buyer',
      actor: 'buyer2 JWT',
      pre: 'orders_select_parties',
      repro: 'GET orders?buyer_id=eq.$bid',
      expected: '[]',
      obtained: ordsB2.brief,
    );
  }

  final existingOrd = await c.rest(
    'GET',
    'orders?buyer_id=eq.$bid&seller_id=eq.$sid&select=id,status,buyer_id,seller_id&limit=1',
    service: true,
  );
  final oidLeak = existingOrd.firstId;
  if (oidLeak != null) {
    final byId = await c.rest(
      'GET',
      'orders?id=eq.$oidLeak&select=id,status,buyer_id,seller_id,price_total,proof_url',
      jwt: b2,
    );
    c.note('s7.order.byid', 'buyer2 GET order por ID leak', byId.brief,
        lens: 'S7');
    if (byId.ok && byId.rowCount > 0) {
      c.hold(
        id: 'RTS-S7-002',
        lens: 'S7',
        severity: 'P0',
        title: 'IDOR encomenda por UUID',
        actor: 'buyer2 JWT',
        pre: 'order $oidLeak de buyer1',
        repro: 'GET orders?id=eq.$oidLeak',
        expected: '[]',
        obtained: byId.brief,
      );
    }
    final patchOrd = await c.rest(
      'PATCH',
      'orders?id=eq.$oidLeak',
      jwt: b2,
      body: {'status': 'concluido'},
    );
    c.note('s7.order.patch', 'buyer2 PATCH order alheia', patchOrd.brief,
        lens: 'S7');
    if (patchOrd.ok && patchOrd.rowCount > 0) {
      c.hold(
        id: 'RTS-S7-003',
        lens: 'S7',
        severity: 'P0',
        title: 'JWT PATCH encomenda de outro',
        actor: 'buyer2 JWT',
        pre: oidLeak,
        repro: 'PATCH orders?id=eq.$oidLeak status=concluido',
        expected: '[] / 403',
        obtained: patchOrd.brief,
      );
    }
  }

  final chatsOther = await c.rest(
    'GET',
    'chats?or=(user_a.eq.$bid,user_b.eq.$bid)&select=id,user_a,user_b&limit=5',
    jwt: b2,
  );
  c.note('s7.chats', 'buyer2 GET chats do buyer1', {
    'http': chatsOther.status,
    'n': chatsOther.rowCount,
  }, lens: 'S7');
  if (chatsOther.ok && chatsOther.rowCount > 0) {
    c.hold(
      id: 'RTS-S7-004',
      lens: 'S7',
      severity: 'P1',
      title: 'JWT lista chats de outro utilizador',
      actor: 'buyer2 JWT',
      pre: 'chats_select_participants',
      repro: 'GET chats?user_a=eq.buyer1',
      expected: '[]',
      obtained: chatsOther.brief,
    );
  }

  final chatSvc = await c.rest(
    'GET',
    'chats?or=(and(user_a.eq.$bid,user_b.eq.$sid),and(user_a.eq.$sid,user_b.eq.$bid))&select=id&limit=1',
    service: true,
  );
  final chatId = chatSvc.firstId;
  if (chatId != null) {
    final msgs = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$chatId&select=id,content,sender_id,media_url&limit=5',
      jwt: b2,
    );
    c.note('s7.msgs', 'buyer2 GET messages de thread alheia', {
      'http': msgs.status,
      'n': msgs.rowCount,
    }, lens: 'S7');
    if (msgs.ok && msgs.rowCount > 0) {
      c.hold(
        id: 'RTS-S7-005',
        lens: 'S7',
        severity: 'P0',
        title: 'JWT lê mensagens de chat alheio por chat_id',
        actor: 'buyer2 JWT',
        pre: 'chat $chatId buyer1↔seller',
        repro: 'GET chat_messages?chat_id=eq.$chatId',
        expected: '[]',
        obtained: msgs.brief,
      );
    }
    final join = await c.rest(
      'PATCH',
      'chats?id=eq.$chatId',
      jwt: b2,
      body: {'user_b': b2id},
    );
    c.note('s7.chat.join', 'buyer2 PATCH participantes', join.brief, lens: 'S7');
    if (join.ok && join.rowCount > 0) {
      c.hold(
        id: 'RTS-S7-006',
        lens: 'S7',
        severity: 'P0',
        title: 'JWT entra em chat alheio via PATCH user_b',
        actor: 'buyer2 JWT',
        pre: 'guard parties imutáveis',
        repro: 'PATCH chats?id=eq.$chatId user_b=buyer2',
        expected: '[] / 403 / parties frozen',
        obtained: join.brief,
      );
    }
  }

  final wal = await c.rest(
    'GET',
    'wallets?id=eq.$sid&select=id,balance',
    jwt: b2,
  );
  c.note('s7.wallet', 'buyer2 GET wallet seller', wal.brief, lens: 'S7');
  if (wal.ok && wal.rowCount > 0) {
    c.hold(
      id: 'RTS-S7-007',
      lens: 'S7',
      severity: 'P0',
      title: 'JWT lê saldo wallet de outro',
      actor: 'buyer2 JWT',
      pre: 'wallets_select_own',
      repro: 'GET wallets?id=eq.$sid',
      expected: '[]',
      obtained: wal.brief,
    );
  }

  final disp = await c.rest(
    'GET',
    'order_disputes?select=id,order_id,proof_photos,status&limit=5',
    jwt: b2,
  );
  c.note('s7.disp', 'buyer2 GET disputes', {
    'http': disp.status,
    'n': disp.rowCount,
  }, lens: 'S7');
  if (disp.ok && disp.rowCount > 0) {
    final alien = disp.list.where((e) {
      if (e is! Map) return false;
      // cannot easily know owner; any row while buyer2 is new ≈ leak
      return true;
    }).length;
    if (alien > 0) {
      c.hold(
        id: 'RTS-S7-008',
        lens: 'S7',
        severity: 'P1',
        title: 'Conta nova lê order_disputes (possíveis proof_photos alheias)',
        actor: 'buyer2 JWT',
        pre: 'buyer2 sem disputas próprias',
        repro: 'GET order_disputes',
        expected: '[]',
        obtained: disp.brief,
      );
    }
  }

  // =====================================================================
  // S6 — Pairing / director tokens
  // =====================================================================
  final pairTbl = await c.rest(
    'GET',
    'ps_pairing_sessions?select=id,code,device_token_plain,seller_id,live_id,expires_at&limit=5',
    jwt: b2,
  );
  c.note('s6.pair.tbl', 'buyer2 GET ps_pairing_sessions', {
    'http': pairTbl.status,
    'n': pairTbl.rowCount,
  }, lens: 'S6');
  if (pairTbl.ok && pairTbl.rowCount > 0) {
    c.hold(
      id: 'RTS-S6-003',
      lens: 'S6',
      severity: 'P1',
      title: 'JWT lê sessões pairing (código/token) de outros',
      actor: 'buyer2 JWT',
      pre: 'RLS pairing own',
      repro: 'GET ps_pairing_sessions',
      expected: '[]',
      obtained: pairTbl.brief,
    );
  }

  final lives = await c.rest(
    'GET',
    'lives?seller_id=eq.$sid&select=id,status,is_active&limit=3',
    service: true,
  );
  final liveId = lives.firstId;
  if (liveId != null) {
    final createP = await c.rpc(
      'batata_ps_create_pairing',
      {'p_live_id': liveId, 'p_role': 'helper'},
      jwt: b2,
    );
    c.note('s6.pair.create', 'buyer2 cria pairing na live do seller',
        createP.brief, lens: 'S6');
    if (createP.ok &&
        (createP.map?['code'] != null || createP.body.contains('code'))) {
      c.hold(
        id: 'RTS-S6-004',
        lens: 'S6',
        severity: 'P1',
        title: 'JWT alheio cria código pairing na live de outro seller',
        actor: 'buyer2 JWT',
        pre: 'live $liveId do seller; buyer2 não é helper',
        repro: 'rpc batata_ps_create_pairing',
        expected: 'not_allowed',
        obtained: createP.brief,
      );
    }
  }

  final tokB2 = await c.rpc(
    'batata_create_seller_device_token',
    {'p_device_id': 'rts-b2-dev', 'p_label': 'rts'},
    jwt: b2,
  );
  c.note('s6.tok.b2', 'buyer2 mint device token', tokB2.brief, lens: 'S6');
  if (tokB2.ok && tokB2.map?['ok'] == true) {
    c.hold(
      id: 'RTS-S6-005',
      lens: 'S6',
      severity: 'P1',
      title: 'buyer2 (não vendedor de loja) emite device_token OCR',
      actor: 'buyer2 JWT',
      pre: 'user_type após fixture',
      repro: 'rpc batata_create_seller_device_token',
      expected: 'not_seller',
      obtained: tokB2.brief,
    );
  }

  final sim = await c.rest(
    'GET',
    'live_director_sim_profiles?select=*&limit=5',
    jwt: b2,
  );
  c.note('s6.sim', 'buyer2 GET live_director_sim_profiles', sim.brief,
      lens: 'S6');
  if (sim.ok && sim.rowCount > 0) {
    c.hold(
      id: 'RTS-S6-006',
      lens: 'S6',
      severity: 'P2',
      title: 'JWT não-admin lê perfis SIM do Live Director',
      actor: 'buyer2 JWT',
      pre: 'policy admin',
      repro: 'GET live_director_sim_profiles',
      expected: '[] / 403',
      obtained: sim.brief,
    );
  }

  // =====================================================================
  // S4 — Multi-conta (review/disputa/rifa) — fixture + tentativa
  // =====================================================================
  final pid = await c.createProduct(title: '$prefix selfdeal', qty: 2, price: 5);
  final holdOrd = await c.rest('POST', 'orders', jwt: b2, body: {
    'buyer_id': b2id,
    'seller_id': sid,
    'product_id': pid,
    'price_total': 5,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  c.note('s4.hold', 'buyer2 hold no seller (mesma pessoa hipotética)',
      holdOrd.brief, lens: 'S4');

  final selfRev = await c.rest('POST', 'reviews', jwt: s, body: {
    'buyer_id': sid,
    'target_id': sid,
    'stars': 5,
    'comment': 'self',
    'author_role': 'comprador',
    'order_id': holdOrd.firstId,
  });
  c.note('s4.self.review', 'seller review a si próprio', selfRev.brief,
      lens: 'S4');
  if (selfRev.ok) {
    c.hold(
      id: 'RTS-S4-001',
      lens: 'S4',
      severity: 'P1',
      title: 'Vendedor insere review 5★ a si próprio',
      actor: 'seller JWT',
      pre: 'target_id=seller_id; sem order concluída própria',
      repro: 'POST reviews target=self',
      expected: '403 / review_order_not_yours',
      obtained: selfRev.brief,
    );
  }

  final raffle = await c.rest(
    'GET',
    'live_raffles?seller_id=eq.$sid&select=id,status,live_id&limit=1',
    service: true,
  );
  final raffleId = raffle.firstId;
  if (raffleId != null) {
    final t1 = await c.rpc(
      'batata_claim_live_raffle_share_intent',
      {'p_raffle_id': raffleId},
      jwt: b,
    );
    final t2 = await c.rpc(
      'batata_claim_live_raffle_share_intent',
      {'p_raffle_id': raffleId},
      jwt: b2,
    );
    c.note('s4.raffle', 'dois UUIDs claim tickets', {
      'b1': t1.brief,
      'b2': t2.brief,
    }, lens: 'S4');
  }

  // =====================================================================
  // S8 — composição identidade → dinheiro (só se algum elo abriu)
  // =====================================================================
  final credit = await c.rpc(
    'batata_credit_wallet_once',
    {
      'p_wallet_id': b2id,
      'p_amount': 50,
      'p_type': 'ajuste',
      'p_idempotency_key': '$prefix-mint',
    },
    jwt: b2,
  );
  c.note('s8.credit', 'JWT credit wallet', credit.brief, lens: 'S8');
  if (credit.ok && credit.body.contains('true')) {
    c.hold(
      id: 'RTS-S8-001',
      lens: 'S8',
      severity: 'P0',
      title: 'JWT chama batata_credit_wallet_once (mint)',
      actor: 'buyer2 JWT',
      pre: 'GRANT só service_role',
      repro: 'rpc batata_credit_wallet_once',
      expected: '403/42501',
      obtained: credit.brief,
    );
  }

  final wB2 = await c.walletBal(b2id);
  final wS = await c.walletBal(sid);
  c.note('s8.wallets', 'saldos observação', {'buyer2': wB2, 'seller': wS},
      lens: 'S8');

  // OpenAPI map (RPCs admin)
  final oa = await c.req(
    'GET',
    '/rest/v1/',
    jwt: b,
    extra: {'Accept': 'application/openapi+json'},
  );
  final rpcNames = <String>[];
  if (oa.json is Map) {
    final paths = (oa.json as Map)['paths'];
    if (paths is Map) {
      for (final k in paths.keys) {
        final ks = k.toString();
        if (ks.contains('/rpc/')) {
          rpcNames.add(ks.split('/rpc/').last);
        }
      }
    }
  }
  final adminRpcs = rpcNames
      .where((n) =>
          n.contains('admin') ||
          n.contains('staff') ||
          n.contains('director') ||
          n.contains('is_admin'))
      .toList();
  c.note('s2.openapi.admin', 'RPCs admin/staff no OpenAPI JWT', adminRpcs,
      lens: 'S2');

  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_S_IDENTIDADE_STAFF_v1',
    'stamp': stamp,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'actors': {
      'buyer': bid,
      'seller': sid,
      'buyer2': b2id,
      'seller2': s2id,
    },
    'findings': c.findings,
    'notes': c.notes,
    'admin_rpcs_visible': adminRpcs,
    'victim_storage': {'bucket': victimBucket, 'path': victimPath},
  });
  stdout.writeln('FINDINGS ${c.findings.length}');
  stdout.writeln('NOTES ${c.notes.length}');
}
