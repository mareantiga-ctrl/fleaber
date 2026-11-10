/// Pass 2 — W7 bundle card sem bundle real; proof_url em order paga; OCR.
import 'dart:convert';
import 'dart:io';
import '_rtw.dart';

Future<void> main() async {
  final c = Rtw.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  final b = c.buyerJwt!;
  final s = c.sellerJwt!;

  final probe = jsonDecode(
    File('${outDir()}/probe.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final paidOid = probe['paid_order']?.toString();
  final holdOid = probe['hold_order']?.toString();

  final holdRow = await c.orderRow(holdOid ?? '');
  final paidRow = paidOid == null ? null : await c.orderRow(paidOid);
  final holdPid = holdRow?['product_id']?.toString() ?? '';
  final paidPid = paidRow?['product_id']?.toString() ?? '';
  stdout.writeln('hold=$holdOid pid=$holdPid paid=$paidOid pid=$paidPid');

  final holdChat = holdPid.isEmpty ? null : await c.ensureChat(holdPid);
  final paidChat = paidPid.isEmpty ? null : await c.ensureChat(paidPid);
  stdout.writeln('chats hold=$holdChat paid=$paidChat');

  // W7 — card conjunto sem bundle BD, total inventado
  final fakeBun = '00000000-0000-4000-8000-000000000777';
  if (holdChat == null) {
    stderr.writeln('no hold chat');
    exit(4);
  }
  final card = await c.postMsg(
    holdChat,
    jsonCard('bundle_proposal', {
      'bundle_id': fakeBun,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'total_eur': 8888.0,
      'discount_eur': 0,
      'product_ids': [holdPid],
      'request_mode': 'discount',
    }),
    jwt: b,
  );
  c.note('p2.W7.card', 'bundle_proposal ghost', card.brief, lens: 'W7');
  if (card.ok) {
    c.hold(
      id: 'W7.P1.ghost_bundle_card',
      lens: 'W7',
      severity: 'P1',
      title:
          'INSERT bundle_proposal com bundle_id inexistente e total_eur=8888',
      actor: 'buyer JWT',
      pre: 'kind bundle_proposal sem validar bundle/orders',
      repro:
          'POST chat_messages kind=bundle_proposal bundle_id=ghost total_eur=8888',
      expected: 'bundle_id tem de existir e total = BD',
      obtained: card.brief,
      evidence: {
        'msg_id': card.firstId,
        'flutter':
            'pending + bundle null → total = payload total_eur (8888)',
      },
    );
  } else {
    c.closed('W7.ghost', 'ghost bundle_proposal blocked', card.brief, lens: 'W7');
  }

  // Two real products → real bundle, then lie on card
  final p2 = await c.insertProduct(title: '$prefix bun-b', price: 12);
  final bun = await c.rest('POST', 'product_bundles', jwt: b, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'status': 'pending',
    'product_ids': [holdPid, p2],
    'total_eur': 0.5,
    'chat_id': holdChat,
  });
  c.note('p2.W7.bun', 'bundle real', bun.brief, lens: 'W7');
  if (bun.ok) {
    final bdTotal = bun.map?['total_eur'];
    await c.rest(
      'PATCH',
      'product_bundles?id=eq.${bun.firstId}',
      service: true,
      body: {'status': 'accepted'},
      prefer: 'return=minimal',
    );
    final lie = await c.postMsg(
      holdChat,
      jsonCard('bundle_proposal', {
        'bundle_id': bun.firstId,
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'total_eur': 7777.0,
        'discount_eur': 0,
        'product_ids': [holdPid, p2],
        'request_mode': 'discount',
      }),
      jwt: b,
    );
    if (lie.ok) {
      c.hold(
        id: 'W7.P1.accepted_payload_override',
        lens: 'W7',
        severity: 'P1',
        title:
            'Card conjunto aceite: total_eur JSON 7777 vs bundle BD $bdTotal',
        actor: 'buyer JWT',
        pre: 'bundle accepted; Flutter frozen lê payload',
        repro: 'POST bundle_proposal total_eur=7777 bundle_id aceite',
        expected: 'totais só da BD',
        obtained: lie.brief,
        evidence: {'bundle_total': bdTotal, 'msg_id': lie.firstId},
      );
    } else {
      c.closed('W7.accepted_lie', 'card aceite blocked', lie.brief, lens: 'W7');
    }
  }

  // W1 — promote fake total: re-insert on hold chat (paid chat may have deleted)
  final fakeTot = await c.postMsg(
    holdChat,
    jsonCard('seguro_fleaber_paid', {
      'order_id': holdOid,
      'total': 9999.99,
      'label': 'iPhone 15 Pro Max',
    }),
    jwt: b,
  );
  c.note('p2.W1.seguro.hold', 'seguro fake total on hold', fakeTot.brief,
      lens: 'W1');

  // paid order still exists — try seguro fake total again if chat alive
  if (paidChat != null && paidOid != null) {
    final fakePaid = await c.postMsg(
      paidChat,
      jsonCard('seguro_fleaber_paid', {
        'order_id': paidOid,
        'total': 4321.0,
        'label': 'MacBook',
      }),
      jwt: b,
    );
    c.note('p2.W1.seguro.paid', 'seguro fake total on paid/cancelado',
        fakePaid.brief,
        lens: 'W1');
    if (fakePaid.ok) {
      final o = await c.orderRow(paidOid);
      c.hold(
        id: 'W1.P1.seguro_json_total',
        lens: 'W1',
        severity: 'P1',
        title:
            'INSERT seguro_fleaber_paid com total JSON sem amarrar a price_total/cents',
        actor: 'buyer JWT',
        pre:
            'order price_total=5.9 amount_paid_cents=590; UI usa payload[total]',
        repro:
            'POST chat_messages kind=seguro_fleaber_paid total=4321 order capturada',
        expected: 'total do card = amount_paid / price_total da order',
        obtained: fakePaid.brief,
        evidence: {
          'msg_id': fakePaid.firstId,
          'order_price': o?['price_total'],
          'paid_cents': o?['amount_paid_cents'],
          'json_total': 4321,
        },
      );
    }

    // paid proof_url javascript
    final js = await c.rest(
      'PATCH',
      'orders?id=eq.$paidOid',
      jwt: b,
      body: {'proof_url': 'javascript:alert(1)'},
    );
    final orow = await c.orderRow(paidOid);
    c.note('p2.W4.paid.js', 'paid PATCH javascript',
        '${js.brief} stored=${orow?['proof_url']}',
        lens: 'W4');
    if (js.ok && (orow?['proof_url']?.toString() ?? '').startsWith('javascript')) {
      c.hold(
        id: 'W4.P1.paid_proof_javascript',
        lens: 'W4',
        severity: 'P1',
        title: 'Order paga persiste proof_url javascript:',
        actor: 'buyer JWT',
        pre: 'status pós-refund/cancelado ou pago',
        repro: 'PATCH orders.proof_url=javascript:alert(1)',
        expected: 'denied em paid',
        obtained: orow?['proof_url'],
      );
    } else if (!js.ok) {
      c.closed('W4.paid_js', 'paid javascript blocked', js.brief, lens: 'W4');
    }
  }

  // W5 operational lies — hold as findings (already inserted in pass1)
  c.hold(
    id: 'W5.P1.ops_cards_without_status',
    lens: 'W5',
    severity: 'P1',
    title:
        'Cards shipped/completed/receipt inseríveis com order ainda pago',
    actor: 'buyer/seller JWT',
    pre: 'pass1 INSERT 201; BD status permaneceu pago',
    repro:
        'POST reservation_order_shipped | reservation_order_completed | reservation_seller_confirmed_receipt',
    expected: 'kind operacional só se status BD corresponder',
    obtained: '201 + status=pago (probe.json W5.bd.unchanged)',
    evidence: {'source': 'pass1 notes W5.shipped/completed/receipt'},
  );

  c.hold(
    id: 'W1.P2.regex_gap_plain',
    lens: 'W1',
    severity: 'P2',
    title:
        'Plain «Compra paga…» com NBSP ou espaço duplo fura o regex SQL',
    actor: 'buyer JWT',
    pre: 'batata_chat_is_forged_seguro_plain ^\\s*Compra( em conjunto)? paga',
    repro: 'POST text=Compra\\u00a0paga… e Compra  paga…',
    expected: 'mesmo bloqueio que o legado exact',
    obtained: '201 msgs 925 e 926 no chat hold',
    evidence: {
      'flutter':
          'startsWith exact falha — bolha de texto, não card; humano lê recibo',
    },
  );

  // W7 price_offer_outcome — check product_offers unchanged
  final offers = await c.rest(
    'GET',
    'product_offers?buyer_id=eq.${c.buyerId}&select=id,status,offer_price,product_id&order=created_at.desc&limit=5',
    service: true,
  );
  c.note('p2.W7.offers', 'product_offers após outcome fake', offers.brief,
      lens: 'W7');
  c.hold(
    id: 'W7.P2.price_offer_outcome_orphan',
    lens: 'W7',
    severity: 'P2',
    title: 'Seller INSERT price_offer_outcome accepted amount=0.01 sem oferta BD',
    actor: 'seller JWT',
    pre: 'kind seller-only + order_id; sem check product_offers',
    repro: 'POST chat_messages kind=price_offer_outcome outcome=accepted amount=0.01',
    expected: 'amarrar a product_offers accepted',
    obtained: '201 no pass1; product_offers ${clip(offers.body, 180)}',
  );

  // seller PATCH resolvida — observe only
  if (c.createdDisputeIds.isEmpty) {
    final d = await c.rest(
      'GET',
      'order_disputes?description=like.*RTW-20260901T1201*&select=id,status,buyer_decision&limit=3',
      service: true,
    );
    c.note('p2.dispute.status', 'disputa após PATCH seller', d.brief, lens: 'W4');
  }

  // OCR edge without device token
  final ocr = await c.edge('ingest-ocr-reservation', {
    'live_id': '00000000-0000-4000-8000-000000000001',
    'ocr_line_hash': 'abcdefgh',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
  }, jwt: b);
  c.note('p2.W4.ocr', 'OCR sem device token', ocr.brief, lens: 'W4');

  final out = {
    'findings': c.findings,
    'closed': c.blocked,
    'notes': c.notes,
  };
  await dumpJson('${outDir()}/pass2.json', out);
  stdout.writeln('PASS2 findings=${c.findings.length}');
}
