/// REDTEAM_BLIND_S_IDENTIDADE_STAFF_v1 — pass3 (confirmar S5/S7)
/// dart run tool/redteam_blind_s_20260901T0657/pass3.dart
import 'dart:io';

import '_rts.dart';

void main() async {
  final env = loadEnv();
  final c = Rts.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();

  final b = c.buyerJwt!;
  final b2 = c.buyer2Jwt!;
  final bid = c.buyerId!;
  final sid = c.sellerId!;
  final b2id = c.buyer2Id!;

  // ---- S5: mutate via reviews_public_ratings ----
  final pub = await c.rest(
    'GET',
    'reviews_public_ratings?target_id=eq.$sid&select=id,stars,comment,author_role,is_automatic&order=created_at.desc&limit=8',
    jwt: b2,
  );
  c.note('p3.s5.list', 'ratings visíveis a buyer2', {
    'n': pub.rowCount,
    'snip': clip(pub.body, 240),
  }, lens: 'S5');

  Map<String, dynamic>? target;
  for (final row in pub.list) {
    if (row is Map) {
      final stars = row['stars'];
      final auto = row['is_automatic'] == true;
      if (stars is num && stars >= 4) {
        target = Map<String, dynamic>.from(row);
        if (auto) break;
      }
    }
  }
  target ??= pub.map;
  final rid = target?['id']?.toString();
  final starsBefore = target?['stars'];
  final commentBefore = target?['comment']?.toString();
  c.note('p3.s5.target', 'review alvo', {
    'id': rid,
    'stars_before': starsBefore,
    'auto': target?['is_automatic'],
  }, lens: 'S5');

  if (rid != null) {
    final patch1 = await c.rest(
      'PATCH',
      'reviews_public_ratings?id=eq.$rid',
      jwt: b2,
      body: {
        'stars': 1,
        'comment': '$prefix-HIJACK',
        'is_automatic': false,
      },
    );
    final afterSvc = await c.rest(
      'GET',
      'reviews?id=eq.$rid&select=id,stars,comment,is_automatic,buyer_id,target_id',
      service: true,
    );
    c.note('p3.s5.patch1', 'PATCH view → 1★ + comment', {
      'http': patch1.brief,
      'svc': afterSvc.brief,
    }, lens: 'S5');
    final starsAfter = afterSvc.map?['stars'];
    final commentAfter = afterSvc.map?['comment']?.toString();
    final mutatedStars = starsAfter != null &&
        starsBefore != null &&
        starsAfter.toString() != starsBefore.toString();
    final mutatedComment = commentAfter != null &&
        commentBefore != null &&
        commentAfter != commentBefore &&
        commentAfter.contains('HIJACK');
    if (mutatedStars || mutatedComment) {
      c.hold(
        id: 'RTS-S5-020',
        lens: 'S5',
        severity: 'P0',
        title: 'JWT altera review alheia via reviews_public_ratings (mutação real)',
        actor: 'buyer2 JWT',
        pre: 'review $rid target=seller; buyer2 não é autor',
        repro: 'PATCH reviews_public_ratings?id=eq.$rid stars=1 comment=HIJACK',
        expected: '403 / valores congelados pelo trigger',
        obtained: {
          'stars_before': starsBefore,
          'stars_after': starsAfter,
          'comment_before': clip(commentBefore, 80),
          'comment_after': clip(commentAfter, 80),
        },
        evidence: {
          'review_id': rid,
          'mutated_stars': mutatedStars,
          'mutated_comment': mutatedComment,
        },
      );
      // Fixture rollback (não é correcção de segurança).
      await c.rest('PATCH', 'reviews?id=eq.$rid', service: true, body: {
        'stars': starsBefore,
        'comment': commentBefore,
      }, prefer: 'return=minimal');
    } else {
      c.note('p3.s5.frozen', 'PATCH 200 mas trigger congelou stars/comment', {
        'stars': starsAfter,
        'comment': clip(commentAfter, 80),
        'patch_http': patch1.status,
      }, lens: 'S5');
    }

    // Also PATCH base table as buyer2
    final patchTbl = await c.rest(
      'PATCH',
      'reviews?id=eq.$rid',
      jwt: b2,
      body: {'stars': 1, 'comment': '$prefix-TBL'},
    );
    c.note('p3.s5.patch.tbl', 'PATCH tabela reviews', patchTbl.brief, lens: 'S5');
  }

  // Own 1★ from pass2 — try PATCH via view as owner AND as other
  final own1 = await c.rest(
    'GET',
    'reviews?buyer_id=eq.$bid&comment=like.$prefix*&select=id,stars,comment&limit=3',
    service: true,
  );
  c.note('p3.s5.own1', 'review 1★ do buyer1 (pass2)', own1.brief, lens: 'S5');
  final ownRid = own1.firstId;
  if (ownRid != null) {
    final asOwner = await c.rest(
      'PATCH',
      'reviews_public_ratings?id=eq.$ownRid',
      jwt: b,
      body: {'stars': 5, 'comment': '$prefix-up'},
    );
    final afterOwn = await c.rest(
      'GET',
      'reviews?id=eq.$ownRid&select=id,stars,comment',
      service: true,
    );
    c.note('p3.s5.own.patch', 'autor PATCH view 1★→5★', {
      'http': asOwner.brief,
      'after': afterOwn.brief,
    }, lens: 'S5');
    if (afterOwn.map?['stars'] == 5) {
      c.hold(
        id: 'RTS-S5-021',
        lens: 'S5',
        severity: 'P1',
        title: 'Autor muda 1★ para 5★ via reviews_public_ratings (release)',
        actor: 'buyer JWT (autor)',
        pre: 'trigger deveria congelar stars',
        repro: 'PATCH reviews_public_ratings?id=eq.$ownRid stars=5',
        expected: 'stars=1 congelado',
        obtained: afterOwn.map,
      );
    }
  }

  // ---- S7: helper analytics vs others' orders ----
  final ordsAll = await c.rest(
    'GET',
    'orders?seller_id=eq.$sid&select=id,buyer_id,status,price_total&limit=20',
    jwt: b2,
  );
  final foreign = ordsAll.list.where((e) {
    if (e is! Map) return false;
    return e['buyer_id']?.toString() != b2id;
  }).toList();
  c.note('p3.s7.orders', 'helper GET orders loja', {
    'n': ordsAll.rowCount,
    'foreign_n': foreign.length,
    'own_only': foreign.isEmpty,
    'snip': clip(ordsAll.body, 200),
  }, lens: 'S7');
  if (foreign.isNotEmpty) {
    c.hold(
      id: 'RTS-S7-020',
      lens: 'S7',
      severity: 'P1',
      title: 'Helper analytics lê encomendas de outros compradores da loja',
      actor: 'buyer2 JWT',
      pre: 'can_view_analytics only; não é seller',
      repro: 'GET orders?seller_id=eq.$sid',
      expected: 'só as suas (buyer_id=buyer2)',
      obtained: {
        'n': ordsAll.rowCount,
        'foreign': foreign.take(5).toList(),
      },
    );
  }

  final ordB1 = await c.rest(
    'GET',
    'orders?id=eq.39ffbfa1-2e8c-4ebb-bd6b-25d18961514f&select=id,buyer_id,status,price_total',
    jwt: b2,
  );
  c.note('p3.s7.b1.byid', 'buyer2 GET order do buyer1 (ID conhecido)',
      ordB1.brief, lens: 'S7');
  if (ordB1.ok && ordB1.rowCount > 0) {
    c.hold(
      id: 'RTS-S7-021',
      lens: 'S7',
      severity: 'P0',
      title: 'IDOR order do outro buyer por UUID conhecido',
      actor: 'buyer2 JWT',
      pre: 'order 39ffbfa1… é do buyer1',
      repro: 'GET orders?id=eq.39ffbfa1-…',
      expected: '[]',
      obtained: ordB1.brief,
    );
  }

  // ---- S7 chat_messages select=* ----
  final chat = await c.rest(
    'GET',
    'chats?or=(and(user_a.eq.$bid,user_b.eq.$sid),and(user_a.eq.$sid,user_b.eq.$bid))&select=id&limit=1',
    service: true,
  );
  final chatId = chat.firstId;
  if (chatId != null) {
    final msgsB2 = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$chatId&select=*&limit=5',
      jwt: b2,
    );
    final msgsB = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$chatId&select=*&limit=1',
      jwt: b,
    );
    c.note('p3.s7.msgs', 'chat_messages select=*', {
      'b2': {'http': msgsB2.status, 'n': msgsB2.rowCount, 'snip': clip(msgsB2.body, 140)},
      'owner': {'http': msgsB.status, 'n': msgsB.rowCount, 'keys': msgsB.map?.keys.toList()},
    }, lens: 'S7');
    if (msgsB2.ok && msgsB2.rowCount > 0) {
      c.hold(
        id: 'RTS-S7-022',
        lens: 'S7',
        severity: 'P0',
        title: 'JWT lê mensagens de chat alheio (select=*)',
        actor: 'buyer2 JWT',
        pre: 'chat $chatId',
        repro: 'GET chat_messages?chat_id=eq.$chatId&select=*',
        expected: '[]',
        obtained: msgsB2.brief,
      );
    }
  }

  // ---- S3: buyer2 GET after knowing exact Key (404 vs 403) ----
  final path = 'chat_uploads/$sid/$prefix-s3.jpg';
  final g = await c.storageGet('fleaber_private', path, jwt: b2);
  final owner = await c.storageGet('fleaber_private', path, jwt: c.sellerJwt);
  c.note('p3.s3.get', 'path conhecido', {
    'b2': g.brief,
    'owner': owner.status,
  }, lens: 'S3');

  // ---- S1: auth user email of other via admin ----
  final userB2 = await c.req('GET', '/auth/v1/user', jwt: b2);
  c.note('p3.s1.me', 'auth.user próprio', {
    'email': (userB2.map?['email']),
    'id': (userB2.map?['id']),
  }, lens: 'S1');

  // ---- S8 composition: if S5 mutated, does it unlock wallet? ----
  final rel = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': '39ffbfa1-2e8c-4ebb-bd6b-25d18961514f'},
    jwt: b2,
  );
  c.note('p3.s8.release', 'buyer2 release order alheia', rel.brief, lens: 'S8');

  await dumpJson('${outDir()}/pass3.json', {
    'auditor': 'REDTEAM_BLIND_S_IDENTIDADE_STAFF_v1',
    'stamp': stamp,
    'pass': 3,
    'production_touched': false,
    'fase4': false,
    'findings': c.findings,
    'notes': c.notes,
  });
  stdout.writeln('FINDINGS ${c.findings.length}');
}
