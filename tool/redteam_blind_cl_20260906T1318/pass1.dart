/// REDTEAM_BLIND_CL_LIVE_POS_CDCI_v1 — pass1 FOMO IT/DE/FR/extra + residual CDCI.
/// Staging only. No fixes.
import 'dart:io';

import '_rtcl.dart';

Future<void> main() async {
  final c = Rtcl.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final liveId = await c.createLive(title: '$prefix p1 fomo');
  final sku = await c.createProduct(title: '$prefix p1 sku', qty: 2, live: true);
  if (liveId == null || sku == null) {
    stderr.writeln('fixture live/sku fail');
    exit(4);
  }
  final itemId = await c.createLiveItem(
    liveId: liveId,
    title: '$prefix p1 item',
    ref: 'RTCL-P1A',
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
  c.note('p1.stock.before', 'stock antes FOMO', stockBefore, lens: 'CL3');

  Future<Map<String, dynamic>> tryFomo({
    required String id,
    required String body,
    required String? jwt,
    required String actor,
    bool residual = false,
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
    String verdict;
    if (ok) {
      verdict = residual ? 'FAIL_REGRESSION' : 'FAIL';
      if (residual) {
        c.hold(
          id: id,
          lens: 'CL2',
          severity: 'P2',
          title: 'REGRESSÃO CDCI FOMO persistiu: $body',
          actor: actor,
          pre: 'exacto CDCI deveria recusar',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok=false purchase_announce_via_broadcast_only',
          obtained: h.brief,
          evidence: {'body': body, 'rpc': h.map},
        );
      } else {
        c.hold(
          id: id,
          lens: 'CL2',
          severity: 'P2',
          title: 'FOMO anúncio persistiu: $body',
          actor: actor,
          pre: 'denylist CDCI sem IT/DE/FR/extra desta matriz',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok=false purchase_announce_via_broadcast_only',
          obtained: h.brief,
          evidence: {'body': body, 'rpc': h.map},
        );
      }
    } else {
      verdict = residual ? 'HOLD' : 'HOLD';
      c.block(
        id,
        'CL2',
        residual
            ? 'residual CDCI recusado (não contar)'
            : 'variante recusada',
        err,
      );
    }
    c.probe(
      id: id,
      lens: 'CL2',
      payload: body,
      http: h.brief,
      verdict: verdict,
      extra: {'ok': ok, 'actor': actor, 'residual': residual},
    );
    return {
      'id': id,
      'body': body,
      'ok': ok,
      'err': err,
      'residual': residual,
      'actor': actor,
    };
  }

  // Residual CDCI ≤3.
  final residual = <List<String>>[
    ['last_one', 'last one'],
    ['foi_embora', 'foi embora'],
  ];
  for (final row in residual) {
    await tryFomo(
      id: 'p1.fomo.residual.${row[0]}',
      body: row[1],
      jwt: c.sellerJwt,
      actor: 'seller JWT',
      residual: true,
    );
  }

  final matrix = <List<String>>[
    // IT (6)
    ['it_ultimo_pezzo', 'ultimo pezzo'],
    ['it_esaurito', 'esaurito'],
    ['it_gia_venduto', 'già venduto'],
    ['it_non_ce_piu', "non c'è più"],
    ['it_preso', 'preso'],
    ['it_esaurito_spaced', 'e s a u r i t o'],
    // DE (6)
    ['de_letztes_stuck', 'letztes Stück'],
    ['de_ausverkauft', 'ausverkauft'],
    ['de_schon_weg', 'schon weg'],
    ['de_kein_lager', 'kein Lager'],
    ['de_verkauft', 'verkauft'],
    ['de_ausverkauft_spaced', 'a u s v e r k a u f t'],
    // FR (6)
    ['fr_dernier_article', 'dernier article'],
    ['fr_epuise', 'épuisé'],
    ['fr_plus_de_stock', 'plus de stock'],
    ['fr_deja_pris', 'déjà pris'],
    ['fr_vendu', 'vendu'],
    ['fr_epuise_spaced', 'e p u i s e'],
    // Extra (6)
    ['ex_stop_1left', '🛑1 left'],
    ['ex_going_going_gone', 'going going gone'],
    ['ex_final_call', 'final call'],
    ['ex_quase_acabar', 'quase a acabar'],
    ['ex_ultimo_disponibile', 'ultimo disponibile'],
    ['ex_nur_noch_einer', 'nur noch einer'],
  ];

  final persisted = <Map<String, dynamic>>[];
  for (final row in matrix) {
    final r = await tryFomo(
      id: 'p1.fomo.matrix.${row[0]}',
      body: row[1],
      jwt: c.sellerJwt,
      actor: 'seller JWT',
    );
    if (r['ok'] == true) persisted.add(r);
  }

  final seen = await c.rest(
    'GET',
    'live_messages?live_id=eq.$liveId&kind=eq.system&select=id,kind,body,sender_label&order=created_at.desc&limit=80',
    jwt: c.buyerJwt,
  );
  final bodies = seen.list.whereType<Map>().map((m) {
    return {
      'kind': m['kind'],
      'body': m['body'],
      'label': m['sender_label'],
    };
  }).toList();
  c.note('p1.fomo.buyer.sees', 'buyer GET kind=system', bodies, lens: 'CL2');

  final seenBodies = bodies.map((m) => '${m['body']}').toSet();
  for (final row in persisted) {
    final body = '${row['body']}';
    final visible = seenBodies.contains(body);
    c.probe(
      id: 'p1.fomo.buyer.see.${row['id']}',
      lens: 'CL2',
      payload: body,
      http: visible ? 'buyer GET kind=system VISIBLE' : 'buyer GET MISSING',
      verdict: visible ? 'FAIL' : 'HOLD_NOT_VISIBLE',
    );
  }

  final stockAfter = await c.stock(itemId);
  c.note('p1.stock.after', 'stock depois FOMO', stockAfter, lens: 'CL3');
  final availB = stockBefore?['available_qty'];
  final availA = stockAfter?['available_qty'];
  if (availB != null && availA != null && availA != availB) {
    c.hold(
      id: 'p1.fomo.stock.delta',
      lens: 'CL3',
      severity: 'P1',
      title: 'FOMO system message alterou stock',
      actor: 'seller JWT',
      pre: 'só anúncio, sem accept/pagamento',
      repro: 'stock before/after system_message',
      expected: 'available_qty inalterado',
      obtained: {'before': stockBefore, 'after': stockAfter},
    );
  } else {
    c.block('p1.fomo.stock.delta', 'CL3', 'stock inalterado após FOMO', {
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
      lens: 'CL8',
      severity: 'P0',
      title: 'FOMO coincidiu com order paga nesta live de fixture',
      actor: 'n/a',
      pre: 'fixture sem checkout',
      repro: 'GET orders live_id',
      expected: 'zero pago',
      obtained: paid,
    );
  } else {
    c.block('p1.fomo.caixa.pago', 'CL8', 'FOMO não criou order paga',
        {'n': orders.list.length});
  }

  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_CL_LIVE_POS_CDCI_v1',
    'prefix': prefix,
    'liveId': liveId,
    'itemId': itemId,
    'persisted_new': persisted,
    'buyer_sees': bodies,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'probes': c.probes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'pass1 done findings=${c.findings.length} blocked=${c.blocked.length} '
      'persisted=${persisted.length} probes=${c.probes.length}');
}
