/// REDTEAM_BLIND_CR_LIVE_POS_ALLOW_v1 — pass1 welcome + FOMO stem bypass.
/// Staging only. No fixes.
import 'dart:io';

import '_rtcr.dart';

Future<void> main() async {
  final c = Rtcr.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureHelperNone();

  final liveId = await c.createLive(title: '$prefix p1 fomo');
  final sku = await c.createProduct(title: '$prefix p1 sku', qty: 2, live: true);
  if (liveId == null || sku == null) {
    stderr.writeln('fixture live/sku fail');
    exit(4);
  }
  final itemId = await c.createLiveItem(
    liveId: liveId,
    title: '$prefix p1 item',
    ref: 'RTCR-P1A',
    kind: 'live_only',
    checkoutProductId: sku,
    quantity: 2,
  );
  if (itemId == null) {
    stderr.writeln('fixture item fail ${c.notes}');
    await c.endAllCreatedLives();
    exit(4);
  }

  final stockBefore = await c.stock(itemId);
  c.note('p1.stock.before', 'stock antes FOMO', stockBefore, lens: 'CR3');

  Future<Map<String, dynamic>> visibility(String body) async {
    final rest = await c.rest(
      'GET',
      'live_messages?live_id=eq.$liveId&kind=eq.system&body=eq.${Uri.encodeQueryComponent(body)}&select=id,kind,body,sender_label&limit=5',
      jwt: c.buyerJwt,
    );
    final hubB = await c.rest(
      'GET',
      'hub_live_messages_public?live_id=eq.$liveId&kind=eq.system&body=eq.${Uri.encodeQueryComponent(body)}&select=id,kind,body,sender_label&limit=5',
      jwt: c.buyerJwt,
    );
    final hubA = await c.rest(
      'GET',
      'hub_live_messages_public?live_id=eq.$liveId&kind=eq.system&body=eq.${Uri.encodeQueryComponent(body)}&select=id,kind,body,sender_label&limit=5',
    );
    final restHit = rest.list.any((r) => r is Map && '${r['body']}' == body);
    final hubBHit = hubB.list.any((r) => r is Map && '${r['body']}' == body);
    final hubAHit = hubA.list.any((r) => r is Map && '${r['body']}' == body);
    return {
      'rest_buyer': restHit,
      'hub_buyer': hubBHit,
      'hub_anon': hubAHit,
      'rest_n': rest.list.length,
      'hub_buyer_n': hubB.list.length,
      'hub_anon_n': hubA.list.length,
      'rest_http': rest.status,
      'hub_buyer_http': hubB.status,
      'hub_anon_http': hubA.status,
      'visible_buyer': restHit || hubBHit,
    };
  }

  Future<Map<String, dynamic>> trySys({
    required String id,
    required String body,
    required String? jwt,
    required String actor,
    required String family,
    bool residual = false,
    bool positive = false,
    String lens = 'CR2',
  }) async {
    final h = await c.rpc(
      'batata_live_system_message',
      {
        'p_live_id': liveId,
        'p_body': body,
        'p_sender_label': 'Sistema',
      },
      jwt: jwt,
    );
    final ok = h.map?['ok'] == true;
    final err = h.map?['error']?.toString() ?? h.brief;
    final vis = ok ? await visibility(body) : <String, dynamic>{};
    final buyerSees = vis['visible_buyer'] == true;
    String verdict;
    if (positive) {
      if (ok && buyerSees) {
        verdict = 'HOLD';
        c.block(id, 'CR1', 'controlo positivo OK (welcome/neutra visível)', {
          'rpc': h.brief,
          'vis': vis,
        });
      } else if (ok && !buyerSees) {
        verdict = 'HOLD';
        c.note(id, 'positivo ok:true mas buyer GET vazio (Hub?)', vis,
            lens: 'CR1');
        c.block(id, 'CR1', 'positivo persistiu; visibilidade parcial', vis);
      } else {
        verdict = 'FAIL';
        c.hold(
          id: id,
          lens: 'CR1',
          severity: 'P2',
          title: 'System msg legítima bloqueada: $body',
          actor: actor,
          pre: 'allowlist deve deixar welcome / neutra passar',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok=true + row visível a buyer',
          obtained: h.brief,
        );
      }
    } else if (ok && buyerSees) {
      verdict = residual ? 'FAIL' : 'FAIL';
      c.hold(
        id: id,
        lens: lens,
        severity: 'P2',
        title: residual
            ? 'REGRESSÃO stem residual persistiu: $body'
            : 'FOMO fora da stem list persistiu: $body',
        actor: actor,
        pre: residual
            ? 'esaurito/ZWJ deveria recusar'
            : 'frase nova fora stems compactos allowlist',
        repro: 'rpc batata_live_system_message p_body=$body',
        expected: 'ok=false purchase_announce_via_broadcast_only',
        obtained: {'rpc': h.brief, 'vis': vis},
        evidence: {'body': body, 'family': family, 'vis': vis},
      );
    } else if (ok && !buyerSees) {
      verdict = 'FAIL';
      c.hold(
        id: id,
        lens: lens,
        severity: 'P2',
        title: 'FOMO persistiu (buyer GET não viu; service row?) $body',
        actor: actor,
        pre: 'ok:true sem convert pago',
        repro: 'rpc + GET live_messages/hub',
        expected: 'ok=false',
        obtained: {'rpc': h.brief, 'vis': vis},
        evidence: {'body': body, 'vis': vis},
      );
    } else {
      verdict = 'HOLD';
      c.block(
        id,
        lens,
        residual
            ? 'residual recusado (não contar)'
            : 'variante recusada',
        err,
      );
    }
    final visHttp = vis.isEmpty
        ? 'n/a'
        : 'rest=${vis['rest_http']} hubB=${vis['hub_buyer_http']} '
            'seen=${vis['visible_buyer']}';
    c.probe(
      id: id,
      lens: lens,
      payload: body,
      http: '${h.brief} | buyer GET $visHttp',
      verdict: verdict,
      extra: {
        'ok': ok,
        'actor': actor,
        'family': family,
        'residual': residual,
        'positive': positive,
        'vis': vis,
      },
    );
    return {
      'id': id,
      'body': body,
      'ok': ok,
      'err': err,
      'verdict': verdict,
      'family': family,
      'vis': vis,
    };
  }

  // CR-A positive controls
  await trySys(
    id: 'A1.welcome',
    body: 'Bem-vindos ao directo!',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'A-positive',
    positive: true,
    lens: 'CR1',
  );
  await trySys(
    id: 'A2.neutra.comecar',
    body: 'O directo está a começar',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'A-positive',
    positive: true,
    lens: 'CR1',
  );

  // Residual CDCI/allowlist ≤2
  await trySys(
    id: 'R1.esaurito',
    body: 'esaurito',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'residual',
    residual: true,
    lens: 'CR3',
  );

  // CR-B1 ES/PT-BR new
  await trySys(
    id: 'B1.es.ultimo_disponible',
    body: 'último disponible',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'B1-es-ptbr',
    lens: 'CR2',
  );
  await trySys(
    id: 'B1.ptbr.ja_foi',
    body: 'já foi',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'B1-es-ptbr',
    lens: 'CR2',
  );
  await trySys(
    id: 'B1.es.queda_poco',
    body: 'queda poco',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'B1-es-ptbr',
    lens: 'CR2',
  );

  // CR-B2 NL/PL/RO
  await trySys(
    id: 'B2.nl.uitverkocht',
    body: 'uitverkocht',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'B2-nl-pl-ro',
    lens: 'CR2',
  );
  await trySys(
    id: 'B2.pl.ostatni',
    body: 'ostatni',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'B2-nl-pl-ro',
    lens: 'CR2',
  );
  await trySys(
    id: 'B2.ro.nu_mai_e',
    body: 'nu mai e',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'B2-nl-pl-ro',
    lens: 'CR2',
  );

  // CR-B3 emoji-only
  await trySys(
    id: 'B3.emoji.fire_one',
    body: '🔥1️⃣',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'B3-emoji',
    lens: 'CR2',
  );

  // CR-B4 ZWJ control + 2 new phrases
  await trySys(
    id: 'B4.zwj.esaurito',
    body: 'e\u200bsaurito',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'B4-zwj',
    residual: true,
    lens: 'CR2',
  );
  await trySys(
    id: 'B4.new.fica_pouco',
    body: 'fica pouco',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'B4-new',
    lens: 'CR2',
  );
  await trySys(
    id: 'B4.new.correu_tudo',
    body: 'correu tudo',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    family: 'B4-new',
    lens: 'CR2',
  );

  // CR-B5 buyer INSERT kind=system FOMO
  final b5 = await c.rest('POST', 'live_messages', jwt: c.buyerJwt, body: {
    'live_id': liveId,
    'user_id': c.buyerId,
    'kind': 'system',
    'body': 'já foi',
    'sender_label': 'Sistema',
  });
  final b5ok = b5.ok && b5.firstId != null;
  if (b5ok) {
    c.hold(
      id: 'B5.buyer.insert.system',
      lens: 'CR3',
      severity: 'P1',
      title: 'Buyer INSERT live_messages kind=system FOMO',
      actor: 'buyer JWT',
      pre: 'RLS insert só kind=chat user_id=self',
      repro: 'POST live_messages kind=system body=já foi',
      expected: '403 RLS / check',
      obtained: b5.brief,
    );
    c.probe(
      id: 'B5.buyer.insert.system',
      lens: 'CR3',
      payload: 'POST live_messages kind=system já foi',
      http: b5.brief,
      verdict: 'FAIL',
    );
  } else {
    c.block('B5.buyer.insert.system', 'CR3',
        'buyer INSERT system recusado (HOLD)', b5.brief);
    c.probe(
      id: 'B5.buyer.insert.system',
      lens: 'CR3',
      payload: 'POST live_messages kind=system já foi',
      http: b5.brief,
      verdict: 'HOLD',
    );
  }

  // CR-B6 helper zero-perms anuncia scarcity nova
  await trySys(
    id: 'B6.helper0.ja_foi',
    body: 'já foi',
    jwt: c.helperNoneJwt,
    actor: 'helper zero JWT',
    family: 'B6-helper0',
    lens: 'CR2',
  );

  final stockAfter = await c.stock(itemId);
  c.note('p1.stock.after', 'stock depois FOMO', stockAfter, lens: 'CR3');
  final availB = stockBefore?['available_qty'];
  final availA = stockAfter?['available_qty'];
  if (availB != null && availA != null && availA != availB) {
    c.hold(
      id: 'p1.fomo.stock.delta',
      lens: 'CR3',
      severity: 'P1',
      title: 'FOMO system message alterou stock',
      actor: 'seller JWT',
      pre: 'só anúncio, sem accept/pagamento',
      repro: 'stock before/after system_message',
      expected: 'available_qty inalterado',
      obtained: {'before': stockBefore, 'after': stockAfter},
    );
  } else {
    c.block('p1.fomo.stock.delta', 'CR3', 'stock inalterado após FOMO', {
      'before': stockBefore,
      'after': stockAfter,
    });
  }

  final orders = await c.rest(
    'GET',
    'orders?live_id=eq.$liveId&select=id,status,amount_paid_cents',
    service: true,
  );
  final paid = orders.list.whereType<Map>().where((o) {
    final st = '${o['status']}'.toLowerCase();
    final cents = o['amount_paid_cents'];
    return st.contains('pago') || (cents is num && cents > 0);
  }).toList();
  if (paid.isNotEmpty) {
    c.hold(
      id: 'p1.fomo.caixa.pago',
      lens: 'CR5',
      severity: 'P0',
      title: 'FOMO coincidiu com order paga nesta live de fixture',
      actor: 'n/a',
      pre: 'fixture sem checkout',
      repro: 'GET orders live_id',
      expected: 'zero pago',
      obtained: paid,
    );
  } else {
    c.block('p1.fomo.caixa.pago', 'CR5', 'FOMO não criou order paga',
        {'n': orders.list.length});
  }

  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_CR_LIVE_POS_ALLOW_v1',
    'prefix': prefix,
    'liveId': liveId,
    'itemId': itemId,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'probes': c.probes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  await c.endAllCreatedLives();
  stdout.writeln(
      'pass1 done findings=${c.findings.length} blocked=${c.blocked.length} '
      'probes=${c.probes.length}');
}
