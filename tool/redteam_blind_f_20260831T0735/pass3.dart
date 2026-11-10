/// Pass 3 — F5 pairing claim correcto; F2 draft item status=available; chats; admin RPCs.
/// Último ciclo com tentativa de classe nova P0/P1. Não corrige.
import 'dart:io';
import '_rtf.dart';

void main() async {
  final env = loadEnv();
  final c = Rtf.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final findings = <Map<String, dynamic>>[];
  final map = <String, dynamic>{};
  var n = 200;
  String nid(String s) => 'RTF0735-${s.toUpperCase()}-${++n}';
  void add(Map<String, dynamic> f) => findings.add(f);

  Future<HttpHit> note(String label, Future<HttpHit> fut, {String idn = ''}) async {
    final h = await fut;
    map[label] = {'http': h.status, 'snip': h.snippet, 'identity': idn, 'n': h.list.length};
    stderr.writeln('${h.status} $label ${h.snippet}');
    return h;
  }

  const endedLive = 'a61fd280-edd1-4efa-b203-c79bffeb6b1b';
  const draftLive = 'bdd782c8-f2c4-49c4-9579-d197b2d479c9';

  // ---------------------------------------------------------------------------
  // F5 pairing: create (ended live) → claim JWT / anon → expire → claim
  // ---------------------------------------------------------------------------
  final created = await note(
    'F5-create',
    c.rpc('batata_ps_create_pairing', {'p_live_id': endedLive}, jwt: c.sellerJwt),
    idn: 'seller',
  );
  String? code;
  String? expiresAt;
  if (created.json is Map) {
    final m = Map<String, dynamic>.from(created.json as Map);
    code = m['code']?.toString();
    expiresAt = m['expires_at']?.toString();
  }
  map['code'] = code;
  map['expires_at'] = expiresAt;

  if (code != null && code.isNotEmpty) {
    final claimB2 = await note(
      'F5-claim-b2-ended-live',
      c.rpc('batata_ps_claim_pairing', {
        'p_code': code,
        'p_device_id': 'rtf-b2-device',
        'p_app_version': 'rtf',
      }, jwt: c.buyer2Jwt),
      idn: 'buyer2',
    );
    final claimed =
        claimB2.ok && (claimB2.body.contains('"ok":true') || claimB2.body.contains('device_token'));
    if (claimed) {
      add(finding(
        id: nid('f5-claim-ended'),
        lens: 'F5',
        severity: 'P1',
        title: 'JWT buyer2 reivindicou pairing de live ended e recebeu device_token',
        pre: 'seller criou code em live status=ended is_active=false',
        repro: 'rpc batata_ps_claim_pairing p_code p_device_id p_app_version',
        proven: true,
        evidence: {'snip': claimB2.snippet},
      ));
    } else {
      // código ainda válido? expirar na BD e tentar de novo com código fresco
      final created2 = await note(
        'F5-create2',
        c.rpc('batata_ps_create_pairing', {'p_live_id': endedLive}, jwt: c.sellerJwt),
        idn: 'seller',
      );
      String? code2;
      if (created2.json is Map) {
        code2 = (created2.json as Map)['code']?.toString();
      }
      if (code2 != null) {
        final exp = await note(
          'F5-expire-row',
          c.rest('PATCH', 'ps_pairing_sessions?code=eq.$code2', service: true, body: {
            'expires_at':
                DateTime.now().toUtc().subtract(const Duration(minutes: 2)).toIso8601String(),
          }),
          idn: 'svc',
        );
        map['expire_n'] = exp.list.length;
        final claimExp = await note(
          'F5-claim-after-expire-jwt',
          c.rpc('batata_ps_claim_pairing', {
            'p_code': code2,
            'p_device_id': 'rtf-exp',
            'p_app_version': 'rtf',
          }, jwt: c.buyer2Jwt),
          idn: 'buyer2',
        );
        final claimAnon = await note(
          'F5-claim-after-expire-anon',
          c.rpc('batata_ps_claim_pairing', {
            'p_code': code2,
            'p_device_id': 'rtf-anon',
            'p_app_version': 'rtf',
          }),
          idn: 'anon',
        );
        final claimSvc = await note(
          'F5-claim-after-expire-svc',
          c.rpc('batata_ps_claim_pairing', {
            'p_code': code2,
            'p_device_id': 'rtf-svc',
            'p_app_version': 'rtf',
          }, service: true),
          idn: 'svc',
        );
        if (claimExp.ok && claimExp.body.contains('"ok":true')) {
          add(finding(
            id: nid('f5-ttl-jwt'),
            lens: 'F5',
            severity: 'P1',
            title: 'JWT claim pairing após expires_at na BD',
            pre: 'ps_pairing_sessions.expires_at passado',
            repro: 'rpc claim as buyer2',
            proven: true,
            evidence: {'snip': claimExp.snippet},
          ));
        }
        if (claimSvc.ok && claimSvc.body.contains('"ok":true')) {
          add(finding(
            id: nid('f5-ttl-svc'),
            lens: 'F5',
            severity: 'P2',
            title: 'service_role claim após expires_at (actor ≠ atacante)',
            pre: 'svc não conta como exploit JWT',
            repro: 'rpc claim service_role',
            proven: true,
            evidence: {'snip': claimSvc.snippet},
            note: 'não P0/P1 — service_role não é actor',
          ));
        }
        map['claim_anon'] = claimAnon.snippet;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // F2 draft item com status available
  // ---------------------------------------------------------------------------
  final di = await note(
    'F2-draft-item-available',
    c.rest('POST', 'live_items', service: true, body: {
      'live_id': draftLive,
      'title': '$prefix draft-avail',
      'price': 55,
      'quantity': 2,
      'ref_code': 'RTF-DA',
      'seller_id': c.sellerId,
      'is_active': true,
      'status': 'available',
      'item_kind': 'live_only',
    }),
    idn: 'svc',
  );
  if (di.firstId != null) {
    final hub = await note(
      'F2-hub-da',
      c.rest('GET', 'hub_live_items_public?id=eq.${di.firstId}&select=id,title,price'),
      idn: 'anon',
    );
    final base = await note(
      'F2-base-da-b2',
      c.rest(
        'GET',
        'live_items?id=eq.${di.firstId}&select=id,title,price,quantity,status',
        jwt: c.buyer2Jwt,
      ),
      idn: 'buyer2',
    );
    final anon = await note(
      'F2-base-da-anon',
      c.rest('GET', 'live_items?id=eq.${di.firstId}&select=id,title,price,quantity'),
      idn: 'anon',
    );
    if ((hub.list.isEmpty) && (base.list.isNotEmpty || anon.list.isNotEmpty)) {
      add(finding(
        id: nid('f2-draft-item'),
        lens: 'F2',
        severity: 'P2',
        title: 'live_item em live draft visível na base, ausente no Hub',
        pre: 'live draft + item ${di.firstId}',
        repro: 'GET live_items vs hub_live_items_public',
        proven: true,
        evidence: {'hub': hub.snippet, 'b2': base.snippet, 'anon': anon.snippet},
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // chats / device tokens / admin RPCs
  // ---------------------------------------------------------------------------
  await note('F2-chats-star', c.rest('GET', 'chats?select=*&limit=5', jwt: c.buyer2Jwt),
      idn: 'buyer2');
  await note(
    'F2-chat-messages',
    c.rest('GET', 'chat_messages?select=id,chat_id,sender_id,text&limit=5', jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note(
    'F7-admin-list',
    c.rpc('batata_admin_list_profiles', {'p_limit': 3}, jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note(
    'F7-admin-resolve',
    c.rpc('batata_admin_resolve_dispute', {
      'p_dispute_id': '00000000-0000-0000-0000-000000000001',
    }, jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note(
    'F4-expire-offers-jwt',
    c.rpc('batata_expire_product_offers', {}, jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );

  // F1: leftover wide SELECT on orders as seller of others
  await note(
    'F1-orders-as-s2',
    c.rest(
      'GET',
      'orders?buyer_id=eq.${c.buyerId}&select=id,status,price_total&limit=5',
      jwt: c.seller2Jwt ?? c.buyer2Jwt,
    ),
    idn: 'seller2',
  );

  await note(
    'F2-hub-lives-draft',
    c.rest('GET', 'hub_lives_public?id=eq.$draftLive&select=id,status,title'),
    idn: 'anon',
  );

  await c.rest('PATCH', 'lives?id=eq.$endedLive', service: true, body: {
    'is_active': false,
    'status': 'ended',
  }, prefer: 'return=minimal');
  await c.rest('PATCH', 'lives?id=eq.$draftLive', service: true, body: {
    'is_active': false,
    'status': 'draft',
  }, prefer: 'return=minimal');

  final proven = findings.where((f) => f['proven'] == true).toList();
  final dirPath = Directory.current.path.contains('redteam_blind_f_')
      ? Directory.current.path
      : '${Directory.current.path}/tool/redteam_blind_f_$stamp';
  await dumpJson('$dirPath/out/pass3.json', {
    'auditor': 'REDTEAM_BLIND_F_POLITICAS_FINAS_v1',
    'pass': 3,
    'map': map,
    'findings': findings,
    'proven_n': proven.length,
  });
  stderr.writeln('PASS3 proven=${proven.length}');
}
