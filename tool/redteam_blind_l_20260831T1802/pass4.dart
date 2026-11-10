/// PASS 4 — L4 Hold TTL / offer TTL (relógio, não «offer morto» de Pass 1) · wrap.
import 'dart:convert';
import 'dart:io';

import '_rtl.dart';

Future<Map<String, dynamic>> loadPass(String name) async {
  final f = File('${outDir()}/$name.json');
  if (!f.existsSync()) return {};
  return jsonDecodeSafe(await f.readAsString());
}

Map<String, dynamic> jsonDecodeSafe(String s) {
  try {
    final v = jsonDecode(s);
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
  } catch (_) {}
  return {};
}

void main() async {
  final env = loadEnv();
  final c = Rtl.fromEnv(env);
  await c.loginActors();

  // ---- L4 hold: reservation_expires_at no passado, stock ainda preso ----
  final pid = await c.createProduct(title: '$prefix-hold-ttl', qty: 2);
  if (pid == null) {
    stderr.writeln('FAIL product');
    exit(4);
  }
  final holdIns = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pid,
    'price_total': 8.5,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
    'reservation_expires_at': isoPast(const Duration(hours: 2)),
  });
  c.note('p4.l4.hold.insert', 'INSERT hold TTL passado', holdIns.brief,
      lens: 'L4');
  final hid = holdIns.firstId;
  if (hid != null) c.createdOrderIds.add(hid);

  final expHold = await c.rpc('batata_expire_product_offers', {}, jwt: c.buyerJwt);
  c.note('p4.l4.expire_offers.jwt', 'expire offers JWT (não é expire hold)',
      expHold.brief, lens: 'L1');

  // Tentar RPCs de expire hold (nomes descobertos / guessed).
  for (final fn in [
    'batata_expire_pending_orders',
    'batata_release_expired_reservations',
    'batata_claim_expired_reservations',
    'batata_expire_reservations',
    'batata_expire_holds',
  ]) {
    final h = await c.rpc(fn, {}, service: true);
    c.note('p4.l4.rpc.$fn', 'service $fn', h.brief, lens: 'L4');
  }

  Map<String, dynamic>? holdRow;
  if (hid != null) {
    holdRow = await c.orderRow(hid);
    final prod = await c.rest(
      'GET',
      'products?id=eq.$pid&select=id,quantity,is_sold',
      service: true,
    );
    c.note('p4.l4.hold.after', 'hold após TTL + crons guessed', {
      'order': holdRow,
      'product': prod.map,
    }, lens: 'L4');

    final stillPending =
        (holdRow?['status'] ?? '').toString().contains('reserva');
    final expAt = holdRow?['reservation_expires_at']?.toString() ?? '';
    if (stillPending && expAt.isNotEmpty) {
      c.hold(
        id: 'RTL-L4-hold-no-cron',
        lens: 'L4',
        severity: 'P2',
        title: 'Hold com reservation_expires_at no passado não é expirado por job',
        actor: 'observação service',
        pre: 'order reserva_pendente expires_at -2h',
        repro: 'INSERT hold TTL passado; chamar crons de expire; ler status',
        expected: 'job marca cancelado/expirado e liberta stock',
        obtained: {'status': holdRow?['status'], 'expires': expAt, 'qty': prod.map},
      );
    }

    // JWT PATCH reservation_expires_at para o futuro (ressuscitar hold).
    final rez = await c.rest(
      'PATCH',
      'orders?id=eq.$hid',
      jwt: c.buyerJwt,
      body: {'reservation_expires_at': isoFuture(const Duration(days: 7))},
    );
    final afterRez = await c.orderRow(hid);
    c.note('p4.l4.hold.resurrect', 'JWT PATCH reservation_expires_at futuro', {
      'http': rez.brief,
      'expires': afterRez?['reservation_expires_at'],
    }, lens: 'L4');
    if (rez.ok &&
        (afterRez?['reservation_expires_at'] ?? '')
            .toString()
            .compareTo(DateTime.now().toUtc().toIso8601String()) >
            0) {
      c.hold(
        id: 'RTL-L4-hold-ttl-resurrect',
        lens: 'L4',
        severity: 'P1',
        title: 'JWT estende reservation_expires_at de hold já caducado',
        actor: 'buyer JWT',
        pre: 'expires_at no passado',
        repro: 'PATCH reservation_expires_at = +7d',
        expected: 'TTL imutável após caducar / só seller',
        obtained: afterRez?['reservation_expires_at'],
      );
    }
  }

  // ---- L4 offer TTL: relógio vs aceitar (não Pass-1 «offer morto») ----
  final pidO = await c.createProduct(title: '$prefix-offer-ttl', qty: 2);
  final chatId = pidO == null ? null : await c.ensureChat(pidO);
  String? offerId;
  if (pidO != null && chatId != null) {
    final ins = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': pidO,
      'chat_id': chatId,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': 7.0,
      'list_price': 8.5,
      'offered_by': 'buyer',
      'status': 'pending',
      'expires_at': isoFuture(const Duration(hours: 48)),
    });
    c.note('p4.l4.offer.insert', 'INSERT offer pending', ins.brief, lens: 'L4');
    offerId = ins.firstId;
  }

  if (offerId != null) {
    // JWT recua o relógio.
    final back = await c.rest(
      'PATCH',
      'product_offers?id=eq.$offerId',
      jwt: c.buyerJwt,
      body: {'expires_at': isoPast(const Duration(minutes: 5))},
    );
    c.note('p4.l4.offer.backdate', 'JWT PATCH expires_at passado', back.brief,
        lens: 'L4');

    final cron = await c.rpc('batata_expire_product_offers', {}, service: true);
    final afterCron = await c.rest(
      'GET',
      'product_offers?id=eq.$offerId&select=id,status,expires_at,responded_at',
      service: true,
    );
    c.note('p4.l4.offer.cron', 'expire cron service', {
      'rpc': cron.brief,
      'row': afterCron.map,
    }, lens: 'L4');

    // Aceitar DEPOIS do cron (status deveria ser expired) — TTL vs accept.
    final acc = await c.rest(
      'PATCH',
      'product_offers?id=eq.$offerId',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    final afterAcc = await c.rest(
      'GET',
      'product_offers?id=eq.$offerId&select=id,status,expires_at',
      service: true,
    );
    c.note('p4.l4.offer.accept_after_ttl', 'seller accept após expire cron', {
      'http': acc.brief,
      'row': afterAcc.map,
    }, lens: 'L4');
    if ((afterAcc.map?['status'] ?? '') == 'accepted') {
      c.hold(
        id: 'RTL-L4-accept-after-expire-cron',
        lens: 'L4',
        severity: 'P1',
        title: 'Seller aceita proposta depois do cron a marcar expired',
        actor: 'seller JWT PATCH status=accepted',
        pre: 'expire cron correu',
        repro: 'service batata_expire_product_offers; PATCH accepted',
        expected: 'status permanece expired',
        obtained: afterAcc.map,
      );
    }

    // Ressuscitar TTL: PATCH expires_at futuro + pending após expired.
    final rez = await c.rest(
      'PATCH',
      'product_offers?id=eq.$offerId',
      jwt: c.buyerJwt,
      body: {
        'status': 'pending',
        'expires_at': isoFuture(const Duration(days: 2)),
        'responded_at': null,
      },
    );
    final afterRez = await c.rest(
      'GET',
      'product_offers?id=eq.$offerId&select=id,status,expires_at',
      service: true,
    );
    c.note('p4.l4.offer.resurrect', 'JWT pending+expires futuro pós-expired', {
      'http': rez.brief,
      'row': afterRez.map,
    }, lens: 'L4');
    if ((afterRez.map?['status'] ?? '') == 'pending') {
      c.hold(
        id: 'RTL-L4-offer-ttl-resurrect',
        lens: 'L4',
        severity: 'P1',
        title: 'JWT ressuscita offer expired → pending com TTL novo',
        actor: 'buyer JWT',
        pre: 'offer expired pelo cron',
        repro: 'PATCH status=pending, expires_at=+2d',
        expected: 'status expired imutável',
        obtained: afterRez.map,
      );
    }
  }

  // L6 extra: apagar review automática (buyer_id = comprador no par auto).
  final autoBuyer = await c.rest(
    'GET',
    'reviews?comment=like.*Avaliação automática*&author_role=eq.comprador&select=id,stars,is_automatic,buyer_id,order_id&order=created_at.desc&limit=3',
    service: true,
  );
  c.note('p4.l6.auto_list', 'reviews auto comprador recentes', autoBuyer.list, lens: 'L6');
  if (autoBuyer.list.isNotEmpty) {
    final row = Map<String, dynamic>.from(autoBuyer.list.first as Map);
    final rid = row['id']?.toString();
    if (rid != null) {
      final delAuto = await c.rest('DELETE', 'reviews?id=eq.$rid', jwt: c.buyerJwt);
      final still = await c.rest(
        'GET',
        'reviews?id=eq.$rid&select=id,stars,is_automatic',
        service: true,
      );
      c.note('p4.l6.del_auto', 'JWT DELETE review automática 5★', {
        'http': delAuto.brief,
        'still': still.list,
      }, lens: 'L6');
      if (delAuto.ok && still.list.isEmpty) {
        c.hold(
          id: 'RTL-L6-delete-auto-feedback',
          lens: 'L6',
          severity: 'P1',
          title: 'JWT apaga a review automática de 5★ gerada pelo cron',
          actor: 'buyer JWT DELETE reviews',
          pre: 'review is_automatic=true author_role=comprador',
          repro: 'DELETE reviews?id=eq.<auto>',
          expected: 'reviews automáticas imutáveis / sem DELETE',
          obtained: {'deleted': rid, 'remaining': still.list},
        );
      }
    }
  }

  // ---- Wrap report ----
  final p1 = await loadPass('pass1');
  final p2 = await loadPass('pass2');
  final p3 = await loadPass('pass3');
  final allFindings = <Map<String, dynamic>>[
    ...((p1['findings'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    ...((p2['findings'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    ...((p3['findings'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    ...c.findings,
  ];

  final p0 = allFindings.where((f) => f['severity'] == 'P0').length;
  final p1n = allFindings.where((f) => f['severity'] == 'P1').length;
  final p2n = allFindings.where((f) => f['severity'] == 'P2').length;
  final verdict = p0 > 0
      ? 'FAIL_P0'
      : p1n > 0
          ? 'FAIL_P1'
          : p2n > 0
              ? 'FAIL_P2'
              : 'PASS_CEGO_SATURADO';

  await dumpJson('${outDir()}/pass4.json', {
    'stamp': stamp,
    'notes': c.notes,
    'findings': c.findings,
    'all_findings': allFindings,
    'verdict': verdict,
  });

  final buf = StringBuffer()
    ..writeln('AUDITOR: REDTEAM_BLIND_L_CRON_AUTO_v1')
    ..writeln('FROZEN_AT: ${DateTime.now().toUtc().toIso8601String()}')
    ..writeln('production_touched: false')
    ..writeln('fase4: false')
    ..writeln('corrections_applied: false')
    ..writeln('VEREDICTO: $verdict')
    ..writeln()
    ..writeln('Prefixo: $prefix')
    ..writeln('Staging: $projectMust · Stripe TEST · sem produção · sem Fase 4.')
    ..writeln()
    ..writeln('## Missão')
    ..writeln()
    ..writeln(
        'Jobs e estados automáticos ainda dão dinheiro, stock, feedback forjado ou libertação indevida?')
    ..writeln()
    ..writeln('## Anti-atrofia')
    ..writeln()
    ..writeln(
        'Pass 1 = catálogo OpenAPI + EXECUTE de jobs (auto_feedback, expire, cleanup, vault/cron schema).')
    ..writeln(
        'Não se repetiu dual Session, bag unlist, plain→JSON, mint pós-payout, cancel hold, Hub paused, pairing ended, offer morto, helper escalate.')
    ..writeln()
    ..writeln('## Lentes')
    ..writeln()
    ..writeln('| Lente | O que se fez |')
    ..writeln('|-------|----------------|')
    ..writeln('| L1 | JWT/anon vs rpc de cron + edge cleanup + schemas cron/vault |')
    ..writeln('| L2 | Stripe TEST → concluido (mão); p_now; now() cedo; sem concluido; duplo |')
    ..writeln('| L3 | Review humana 5★/1★ vs cron auto-feedback + wallet |')
    ..writeln('| L4 | Hold reservation_expires_at; offer expire cron + resurrect TTL |')
    ..writeln('| L5 | Future.wait humana∥cron; refund-order∥cron |')
    ..writeln('| L6 | PATCH completed_at / flags; DELETE review; is_automatic JWT |')
    ..writeln('| L7 | Contabilidade wallets antes/depois de cada cron |')
    ..writeln()
    ..writeln('## Contagens')
    ..writeln()
    ..writeln('- P0: $p0')
    ..writeln('- P1: $p1n')
    ..writeln('- P2: $p2n')
    ..writeln('- Findings totais: ${allFindings.length}')
    ..writeln()
    ..writeln('## Findings')
    ..writeln();

  if (allFindings.isEmpty) {
    buf.writeln('_Nenhum finding provado. Jobs recusaram JWT; 48h respeitada; races idempotentes._');
  }
  for (final f in allFindings) {
    buf
      ..writeln('### ${f['id']} · ${f['severity']} · ${f['lens']}')
      ..writeln()
      ..writeln('**Título:** ${f['title']}')
      ..writeln()
      ..writeln('**Actor:** ${f['actor']}')
      ..writeln()
      ..writeln('**Pré:** ${f['pre']}')
      ..writeln()
      ..writeln('**Passos / repro:** ${f['repro']}')
      ..writeln()
      ..writeln('**Esperado:** ${f['expected']}')
      ..writeln()
      ..writeln('**Obtido:** ${clip(f['obtained'], 800)}')
      ..writeln()
      ..writeln('**Prova:** `${clip(f['evidence'], 800)}`')
      ..writeln();
  }

  buf
    ..writeln('## Notas de saturação')
    ..writeln()
    ..writeln('- Fixture: `sec-fase2-e2e-oversell` setup_paid_order (Stripe TEST pm_card_visa) → vendedor enviado → comprador concluido (mão).')
    ..writeln('- Cron legítimo invocado com service_role só como oráculo de job (p_now para não esperar 48h reais).')
    ..writeln('- Atacante = JWT/anon.')
    ..writeln('- Confirmação de receção em mão não foi partida (caminho buyer PATCH concluido usado).')
    ..writeln()
    ..writeln('**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**')
    ..writeln();

  await File('${outDir()}/FROZEN_REPORT.md').writeAsString(buf.toString());
  stdout.writeln('PASS4 wrap VEREDICTO=$verdict findings=${allFindings.length}');
}
