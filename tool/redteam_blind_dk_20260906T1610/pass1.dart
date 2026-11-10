/// RED TEAM CEGO DK — RLS / storage / FSM. Staging only. Não corrige.
/// Matriz A≥5 B≥4 C≥5 · lentes DK1–DK7 · quota ≥14.
import 'dart:convert';
import 'dart:io';
import '_rtdk.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

bool isHttpDenied(HttpHit h) {
  final raw = h.body.toLowerCase();
  return h.status == 400 ||
      h.status == 401 ||
      h.status == 403 ||
      h.status == 404 ||
      h.status == 409 ||
      h.status == 415 ||
      raw.contains('42501') ||
      raw.contains('23514') ||
      raw.contains('23505') ||
      raw.contains('denied') ||
      raw.contains('forbidden') ||
      raw.contains('sem permiss') ||
      raw.contains('jwt') && raw.contains('expired');
}

bool emptyOk(HttpHit h) {
  if (h.status == 204) return true;
  if (!h.ok) return false;
  if (h.list.isEmpty && h.map == null && (h.body.isEmpty || h.body == '[]')) {
    return true;
  }
  return false;
}

dynamic pick(Map? m, String k) => m == null ? null : m[k];

bool fieldChanged(Map? before, Map? after, String k, Object? want) {
  if (after == null) return false;
  final v = after[k];
  if (want != null && '$v' == '$want') return true;
  if (before == null) return v != null;
  return '${before[k]}' != '$v';
}

int? availOf(HttpHit h) {
  final m = h.map;
  if (m == null) return null;
  return numOf(m['available'] ?? m['available_qty'] ?? m['qty'])?.round();
}

int? stockOf(HttpHit h) {
  final m = h.map;
  if (m == null) return null;
  return numOf(m['stock'] ?? m['quantity'])?.round();
}

void main() async {
  final c = Rtdk.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.well('DK-A');
  c.well('DK-B');
  c.well('DK-C');

  Future<({String oid, String pid, String? pi})> mustPay(String lens,
      {int qty = 1}) async {
    final paid = await c.payToPago(lens: lens, initialQty: qty);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  void record({
    required String id,
    required String matrix,
    required String lens,
    required String payload,
    required HttpHit hit,
    String? bd,
    required bool held,
    String expectedDeny = 'deny JWT / RLS / trigger; BD inalterada',
    String severity = 'P1',
    String? title,
    bool controlNoCount = false,
    bool happy = false,
  }) {
    if (controlNoCount) {
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: held ? 'HOLD' : 'FAIL',
      );
      if (held) {
        c.note(id, 'controlo clássico — NÃO CONTAR', hit, lens: lens);
      } else {
        c.block(id, lens, title ?? id, hit);
      }
      return;
    }
    if (happy) {
      if (held) {
        c.block(id, lens, title ?? id, hit);
        c.probe(
          id: id,
          matrix: matrix,
          payload: payload,
          http: hit.brief,
          bd: bd,
          result: 'FAIL',
        );
      } else {
        c.hold(
          id: id,
          lens: lens,
          severity: severity,
          title: title ?? 'Happy path partido',
          actor: 'JWT',
          pre: payload,
          repro: id,
          expected: '200/201 happy',
          obtained: hit.brief,
        );
        c.probe(
          id: id,
          matrix: matrix,
          payload: payload,
          http: hit.brief,
          bd: bd,
          result: 'HOLD',
        );
      }
      return;
    }
    if (held) {
      c.hold(
        id: id,
        lens: lens,
        severity: severity,
        title: title ?? id,
        actor: 'JWT',
        pre: payload,
        repro: id,
        expected: expectedDeny,
        obtained: {'http': hit.brief, 'bd': bd},
      );
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: 'HOLD',
      );
    } else {
      c.block(id, lens, title ?? id, hit);
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: 'FAIL',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Fixtures
  // ---------------------------------------------------------------------------
  final paid = await mustPay('DK3', qty: 2);
  final paidRow = await c.orderRow(paid.oid);
  c.note('fixture.paid_row', 'Stripe TEST pago', {
    'oid': paid.oid,
    'pid': paid.pid,
    'pi': paid.pi,
    'status': paidRow?['status'],
    'amount': paidRow?['amount_paid_cents'],
    'pm': paidRow?['payment_method'],
    'qty': paidRow?['quantity'],
  }, lens: 'DK3');

  final skuIdor = await c.createProduct(qty: 3, title: '$prefix-idor');
  if (skuIdor == null) throw StateError('sku idor');
  final oidOwn = await c.insertOrder(
    productId: skuIdor,
    jwt: c.buyerJwt,
    payment: 'Pagamento na app',
  );
  if (oidOwn == null) throw StateError('order own');
  final chatOwn = await c.ensureChat(skuIdor);
  if (chatOwn == null) throw StateError('chat own');
  final msgOwn = await c.insertMsg(
    chatId: chatOwn,
    jwt: c.buyerJwt,
    sender: c.buyerId,
    text: 'RTDK hello own chat',
  );
  c.note('fixture.chat', 'chat B1-S1', {
    'chat': chatOwn,
    'msg': msgOwn.brief,
  }, lens: 'DK1');

  final proofName = 'order_proofs/${c.buyerId}/$oidOwn/rtdk-own.png';
  final upOwn = await c.storageUpload(
    objectName: proofName,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  c.note('fixture.proof_own', 'upload prova B1', upOwn.brief, lens: 'DK2');

  final skuOff = await c.createProduct(qty: 2, title: '$prefix-off');
  if (skuOff == null) throw StateError('sku off');
  final oidOff = await c.insertOrder(
    productId: skuOff,
    jwt: c.buyerJwt,
    payment: 'MB WAY',
  );
  if (oidOff == null) throw StateError('order off');

  final skuPlat = await c.createProduct(qty: 1, title: '$prefix-plat');
  if (skuPlat == null) throw StateError('sku plat');
  final oidPlat = await c.insertOrder(
    productId: skuPlat,
    jwt: c.buyerJwt,
    payment: 'Pagamento na app',
  );
  if (oidPlat == null) throw StateError('order plat');

  // =========================================================================
  // DK-A RLS / IDOR
  // =========================================================================

  // A1 PATCH order alheia status
  final a1Before = await c.orderRow(paid.oid);
  final a1 = await c.patchOrder(paid.oid, {'status': 'enviado'}, jwt: c.buyer2Jwt);
  final a1After = await c.orderRow(paid.oid);
  final a1Held = a1After?['status']?.toString() == 'enviado' &&
      a1Before?['status']?.toString() != 'enviado';
  record(
    id: 'DK-A1.patch_status_alheia',
    matrix: 'DK-A',
    lens: 'DK1',
    payload: 'B2 PATCH orders.status=enviado order B1 Stripe paga',
    hit: a1,
    bd: 'before=${a1Before?['status']} after=${a1After?['status']}',
    held: a1Held,
    title: 'IDOR PATCH status encomenda alheia',
    severity: 'P0',
  );

  // A1b money / shipping
  final a1bBefore = await c.orderRow(paid.oid);
  final a1b = await c.patchOrder(paid.oid, {
    'shipping_method': 'CTT Expresso',
    'amount_paid_cents': 1,
  }, jwt: c.buyer2Jwt);
  final a1bAfter = await c.orderRow(paid.oid);
  final a1bHeld = fieldChanged(a1bBefore, a1bAfter, 'shipping_method', 'CTT Expresso') ||
      fieldChanged(a1bBefore, a1bAfter, 'amount_paid_cents', 1);
  record(
    id: 'DK-A1b.patch_money_shipping_alheia',
    matrix: 'DK-A',
    lens: 'DK1',
    payload: 'B2 PATCH shipping+amount_paid_cents order B1',
    hit: a1b,
    bd: 'ship ${a1bBefore?['shipping_method']}→${a1bAfter?['shipping_method']} '
        'paid ${a1bBefore?['amount_paid_cents']}→${a1bAfter?['amount_paid_cents']}',
    held: a1bHeld,
    title: 'IDOR PATCH money/shipping encomenda alheia',
    severity: 'P0',
  );

  // A1c GET order alheia
  final a1c = await c.rest(
    'GET',
    'orders?id=eq.${paid.oid}&select=id,status,amount_paid_cents,buyer_id',
    jwt: c.buyer2Jwt,
  );
  final a1cSaw = a1c.ok && (a1c.firstId == paid.oid || a1c.map?['id'] == paid.oid);
  record(
    id: 'DK-A1c.select_order_alheia',
    matrix: 'DK-A',
    lens: 'DK1',
    payload: 'B2 GET orders?id=eq.B1pago',
    hit: a1c,
    bd: 'rows=${a1c.list.length} first=${a1c.firstId}',
    held: a1cSaw,
    title: 'IDOR SELECT encomenda alheia',
    severity: 'P1',
  );

  // A1d INSERT spoof buyer
  final a1d = await c.rest('POST', 'orders', jwt: c.buyer2Jwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': skuIdor,
    'price_total': 5.9,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  if (a1d.firstId != null) c.createdOrderIds.add(a1d.firstId!);
  final a1dRow = a1d.firstId == null ? null : await c.orderRow(a1d.firstId!);
  final a1dHeld = a1d.ok &&
      a1d.firstId != null &&
      a1dRow?['buyer_id']?.toString() == c.buyerId;
  record(
    id: 'DK-A1d.insert_spoof_buyer',
    matrix: 'DK-A',
    lens: 'DK1',
    payload: 'B2 POST orders buyer_id=B1',
    hit: a1d,
    bd: 'created=${a1d.firstId} buyer=${a1dRow?['buyer_id']}',
    held: a1dHeld,
    title: 'INSERT encomenda com buyer_id spoof',
    severity: 'P1',
  );

  // A2 GET storage object outro buyer
  final a2 = await c.storageGet(proofName, jwt: c.buyer2Jwt);
  final a2Held = a2.ok && a2.status == 200 && a2.body.contains('PNG');
  record(
    id: 'DK-A2.get_storage_alheio',
    matrix: 'DK-A',
    lens: 'DK2',
    payload: 'B2 GET authenticated order_proofs/{B1}/{oid}/rtdk-own.png',
    hit: a2,
    bd: 'status=${a2.status} len=${a2.body.length}',
    held: a2Held,
    title: 'GET storage objecto outro buyer',
    severity: 'P1',
  );

  // A2b LIST prefix outro
  final a2b = await c.storageList(
    prefix: 'order_proofs/${c.buyerId}/',
    jwt: c.buyer2Jwt,
  );
  final a2bNames = a2b.list
      .map((e) => e is Map ? '${e['name'] ?? e['id'] ?? ''}' : '$e')
      .where((s) => s.contains('${c.buyerId}'))
      .toList();
  record(
    id: 'DK-A2b.list_prefix_alheio',
    matrix: 'DK-A',
    lens: 'DK2',
    payload: 'B2 LIST fleaber_private prefix order_proofs/{B1}/',
    hit: a2b,
    bd: 'n=${a2b.list.length} names=${clip(a2bNames, 180)}',
    held: a2bNames.isNotEmpty,
    title: 'LIST storage prefix outro buyer',
    severity: 'P1',
  );

  // A2c sign URL outro
  final a2cSigned = await c.signObject(proofName, jwt: c.buyer2Jwt);
  final a2c = HttpHit(
    a2cSigned == null ? 403 : 200,
    a2cSigned ?? 'null',
    a2cSigned,
  );
  record(
    id: 'DK-A2c.sign_object_alheio',
    matrix: 'DK-A',
    lens: 'DK2',
    payload: 'B2 POST object/sign order_proofs/{B1}/…',
    hit: a2c,
    bd: 'signed=${a2cSigned != null}',
    held: a2cSigned != null && a2cSigned.contains('token='),
    title: 'signed URL objecto outro buyer',
    severity: 'P1',
  );

  // A3 upload path order_proofs/{outro}/ — clássico, NÃO CONTAR HOLD
  final a3Name = 'order_proofs/${c.buyerId}/$oidOwn/rtdk-b2-evil.png';
  final a3 = await c.storageUpload(
    objectName: a3Name,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  final a3Get = await c.storageGet(a3Name, jwt: c.buyerJwt);
  final a3Held = a3.ok || a3Get.ok;
  record(
    id: 'DK-A3.upload_proofs_outro',
    matrix: 'DK-A',
    lens: 'DK2',
    payload: 'B2 POST object order_proofs/{B1}/{oid}/evil.png',
    hit: a3,
    bd: 'upload=${a3.status} getB1=${a3Get.status}',
    held: a3Held,
    title: 'upload path order_proofs outro buyer',
    controlNoCount: true,
  );

  // A3b path traversal novo (não clássico exacto)
  final a3bName =
      'order_proofs/${c.buyer2Id}/../${c.buyerId}/$oidOwn/rtdk-dotdot.png';
  final a3b = await c.storageUpload(
    objectName: a3bName,
    bytes: pngBytes,
    jwt: c.buyer2Jwt,
  );
  final a3bCanon = 'order_proofs/${c.buyerId}/$oidOwn/rtdk-dotdot.png';
  final a3bGet = await c.storageGet(a3bCanon, jwt: c.buyerJwt);
  final a3bGetB2 = await c.storageGet(a3bName, jwt: c.buyer2Jwt);
  final a3bCross = a3b.ok && (a3bGet.ok || a3bGet.status == 200);
  record(
    id: 'DK-A3b.upload_dotdot_proofs',
    matrix: 'DK-A',
    lens: 'DK2',
    payload: 'B2 upload order_proofs/{B2}/../{B1}/{oid}/…',
    hit: a3b,
    bd: 'upload=${a3b.status} getCanonB1=${a3bGet.status} getRawB2=${a3bGetB2.status}',
    held: a3bCross,
    title: 'upload traversal .. para order_proofs alheio',
    severity: 'P1',
  );

  // A4 chat_messages noutro chat
  final a4 = await c.insertMsg(
    chatId: chatOwn,
    jwt: c.buyer2Jwt,
    sender: c.buyer2Id,
    text: 'RTDK B2 inject noutro chat',
  );
  final a4List = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatOwn&text=eq.${Uri.encodeQueryComponent('RTDK B2 inject noutro chat')}&select=id,sender_id,text',
    service: true,
  );
  final a4Held = a4.ok && a4.firstId != null;
  record(
    id: 'DK-A4.msg_noutro_chat',
    matrix: 'DK-A',
    lens: 'DK1',
    payload: 'B2 POST chat_messages chat B1-S1',
    hit: a4,
    bd: 'id=${a4.firstId} svcRows=${a4List.list.length}',
    held: a4Held,
    title: 'mensagem noutro chat',
    severity: 'P1',
  );

  // A4b PATCH mensagem alheia
  final a4b = await c.rest(
    'PATCH',
    'chat_messages?id=eq.${msgOwn.firstId}',
    jwt: c.buyer2Jwt,
    body: {'text': 'RTDK hijack'},
  );
  final a4bRow = await c.rest(
    'GET',
    'chat_messages?id=eq.${msgOwn.firstId}&select=id,text,sender_id',
    service: true,
  );
  final a4bHeld = '${a4bRow.map?['text']}' == 'RTDK hijack';
  record(
    id: 'DK-A4b.patch_msg_alheia',
    matrix: 'DK-A',
    lens: 'DK1',
    payload: 'B2 PATCH chat_messages B1',
    hit: a4b,
    bd: 'text=${a4bRow.map?['text']}',
    held: a4bHeld,
    title: 'PATCH mensagem alheia',
    severity: 'P2',
  );

  // A5 follows spoof follower_id
  final a5 = await c.rest('POST', 'follows', jwt: c.buyer2Jwt, body: {
    'follower_id': c.buyerId,
    'following_id': c.sellerId,
  });
  final a5Get = await c.rest(
    'GET',
    'follows?follower_id=eq.${c.buyerId}&following_id=eq.${c.sellerId}&select=follower_id,following_id',
    service: true,
  );
  final a5Held = a5.ok && a5Get.list.isNotEmpty;
  record(
    id: 'DK-A5.follow_spoof_follower',
    matrix: 'DK-A',
    lens: 'DK1',
    payload: 'B2 POST follows follower_id=B1 following=S1',
    hit: a5,
    bd: 'rows=${a5Get.list.length}',
    held: a5Held,
    title: 'spoof follower_id',
    severity: 'P2',
  );

  // A5b PATCH profile alheio
  final a5bBefore = await c.rest(
    'GET',
    'profiles?id=eq.${c.buyerId}&select=id,full_name,handle',
    service: true,
  );
  final a5b = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.buyerId}',
    jwt: c.buyer2Jwt,
    body: {'full_name': 'RTDK-HIJACK'},
  );
  final a5bAfter = await c.rest(
    'GET',
    'profiles?id=eq.${c.buyerId}&select=id,full_name,handle',
    service: true,
  );
  final a5bHeld = '${a5bAfter.map?['full_name']}' == 'RTDK-HIJACK';
  record(
    id: 'DK-A5b.patch_profile_alheio',
    matrix: 'DK-A',
    lens: 'DK1',
    payload: 'B2 PATCH profiles.full_name B1',
    hit: a5b,
    bd: 'before=${a5bBefore.map?['full_name']} after=${a5bAfter.map?['full_name']}',
    held: a5bHeld,
    title: 'PATCH perfil alheio',
    severity: 'P1',
  );

  // CTRL clássico buyer PATCH pago — NÃO CONTAR
  final ctrlPagoBefore = await c.orderRow(oidOwn);
  final ctrlPago = await c.patchOrder(oidOwn, {'status': 'pago'}, jwt: c.buyerJwt);
  final ctrlPagoAfter = await c.orderRow(oidOwn);
  record(
    id: 'DK-CTRL.buyer_patch_pago',
    matrix: 'DK-A',
    lens: 'DK7',
    payload: 'B1 PATCH própria order status=pago (clássico)',
    hit: ctrlPago,
    bd: 'before=${ctrlPagoBefore?['status']} after=${ctrlPagoAfter?['status']}',
    held: ctrlPagoAfter?['status']?.toString() == 'pago',
    controlNoCount: true,
    title: 'buyer PATCH pago clássico',
  );

  // =========================================================================
  // DK-B money / immutability
  // =========================================================================

  final b1Before = await c.orderRow(paid.oid);
  final b1 = await c.patchOrder(paid.oid, {'amount_paid_cents': 1}, jwt: c.buyerJwt);
  final b1After = await c.orderRow(paid.oid);
  record(
    id: 'DK-B1.patch_amount_paid',
    matrix: 'DK-B',
    lens: 'DK3',
    payload: 'B1 PATCH amount_paid_cents=1 order Stripe paga',
    hit: b1,
    bd: '${b1Before?['amount_paid_cents']}→${b1After?['amount_paid_cents']}',
    held: fieldChanged(b1Before, b1After, 'amount_paid_cents', 1),
    title: 'buyer PATCH amount_paid_cents',
    severity: 'P0',
  );

  final b1bBefore = await c.orderRow(paid.oid);
  final b1b = await c.patchOrder(paid.oid, {
    'stripe_payment_intent_id': 'pi_rtdk_forged',
    'stripe_checkout_session_id': 'cs_rtdk_forged',
  }, jwt: c.buyerJwt);
  final b1bAfter = await c.orderRow(paid.oid);
  record(
    id: 'DK-B1b.patch_stripe_ids',
    matrix: 'DK-B',
    lens: 'DK3',
    payload: 'B1 PATCH stripe_payment_intent_id + checkout_session_id',
    hit: b1b,
    bd: 'pi ${b1bBefore?['stripe_payment_intent_id']}→${b1bAfter?['stripe_payment_intent_id']}',
    held: fieldChanged(b1bBefore, b1bAfter, 'stripe_payment_intent_id', 'pi_rtdk_forged') ||
        fieldChanged(b1bBefore, b1bAfter, 'stripe_checkout_session_id', 'cs_rtdk_forged'),
    title: 'buyer PATCH stripe_*',
    severity: 'P0',
  );

  final b1cBefore = await c.orderRow(paid.oid);
  final b1c = await c.patchOrder(paid.oid, {'amount_paid_cents': 99999}, jwt: c.sellerJwt);
  final b1cAfter = await c.orderRow(paid.oid);
  record(
    id: 'DK-B1c.seller_patch_amount',
    matrix: 'DK-B',
    lens: 'DK3',
    payload: 'S1 PATCH amount_paid_cents=99999',
    hit: b1c,
    bd: '${b1cBefore?['amount_paid_cents']}→${b1cAfter?['amount_paid_cents']}',
    held: fieldChanged(b1cBefore, b1cAfter, 'amount_paid_cents', 99999),
    title: 'seller PATCH amount_paid_cents',
    severity: 'P0',
  );

  // B2 PATCH payment_method após Session
  final cs = await c.checkout(
    orderId: oidOwn,
    productId: skuIdor,
    amount: 590,
  );
  c.note('B2.checkout', 'create-payment-intent', cs.brief, lens: 'DK3');
  final b2Before = await c.orderRow(oidOwn);
  final b2 = await c.patchOrder(oidOwn, {'payment_method': 'MB WAY'}, jwt: c.buyerJwt);
  final b2After = await c.orderRow(oidOwn);
  record(
    id: 'DK-B2.patch_pm_after_session',
    matrix: 'DK-B',
    lens: 'DK3',
    payload: 'após create-payment-intent B1 PATCH payment_method=MB WAY',
    hit: b2,
    bd: 'cs=${cs.brief} pm ${b2Before?['payment_method']}→${b2After?['payment_method']} '
        'sid=${b2After?['stripe_checkout_session_id']}',
    held: fieldChanged(b2Before, b2After, 'payment_method', 'MB WAY'),
    title: 'PATCH payment_method após Session',
    severity: 'P1',
  );

  // B3 seller marca pago off-platform sem prova
  final b3Before = await c.orderRow(oidOff);
  final b3 = await c.patchOrder(oidOff, {'status': 'pago'}, jwt: c.sellerJwt);
  final b3After = await c.orderRow(oidOff);
  record(
    id: 'DK-B3.seller_pago_sem_prova',
    matrix: 'DK-B',
    lens: 'DK7',
    payload: 'S1 PATCH MB WAY order status=pago sem proof_url',
    hit: b3,
    bd: 'before=${b3Before?['status']} after=${b3After?['status']} proof=${b3After?['proof_url']}',
    held: b3After?['status']?.toString() == 'pago',
    title: 'seller pago off-platform sem prova',
    severity: 'P1',
  );

  // B3b com prova signed própria
  final offProof = 'order_proofs/${c.buyerId}/$oidOff/rtdk-mbway.png';
  final upOff = await c.storageUpload(
    objectName: offProof,
    bytes: pngBytes,
    jwt: c.buyerJwt,
  );
  final signedOff = await c.signObject(offProof, jwt: c.buyerJwt);
  c.note('B3b.upload', 'prova MB WAY', {
    'up': upOff.brief,
    'signed': signedOff != null,
  }, lens: 'DK7');
  HttpHit? b3bProof;
  if (signedOff != null) {
    b3bProof = await c.patchOrder(oidOff, {'proof_url': signedOff}, jwt: c.buyerJwt);
  }
  final b3b = await c.patchOrder(oidOff, {'status': 'pago'}, jwt: c.sellerJwt);
  final b3bAfter = await c.orderRow(oidOff);
  final b3bOk = b3bAfter?['status']?.toString() == 'pago';
  record(
    id: 'DK-B3b.seller_pago_com_prova',
    matrix: 'DK-B',
    lens: 'DK7',
    payload: 'S1 PATCH pago MB WAY com proof signed',
    hit: b3b,
    bd: 'proofPatch=${b3bProof?.brief} status=${b3bAfter?['status']} proof=${clip(b3bAfter?['proof_url'], 120)}',
    held: b3bOk,
    happy: true,
    title: 'seller pago off-platform com prova',
    severity: 'P2',
  );

  // B4 contract / qty
  final b4Before = await c.orderRow(paid.oid);
  final b4 = await c.patchOrder(paid.oid, {'quantity': 99}, jwt: c.buyerJwt);
  final b4After = await c.orderRow(paid.oid);
  record(
    id: 'DK-B4.patch_qty',
    matrix: 'DK-B',
    lens: 'DK3',
    payload: 'B1 PATCH quantity=99 order paga',
    hit: b4,
    bd: '${b4Before?['quantity']}→${b4After?['quantity']}',
    held: fieldChanged(b4Before, b4After, 'quantity', 99),
    title: 'qty immutability pós-pago',
    severity: 'P0',
  );

  final b4bBefore = await c.orderRow(paid.oid);
  final b4b = await c.patchOrder(paid.oid, {
    'contract_unit_cents': 1,
    'contract_qty': 99,
  }, jwt: c.buyerJwt);
  final b4bAfter = await c.orderRow(paid.oid);
  record(
    id: 'DK-B4b.patch_contract',
    matrix: 'DK-B',
    lens: 'DK3',
    payload: 'B1 PATCH contract_unit_cents=1 contract_qty=99',
    hit: b4b,
    bd: 'unit ${b4bBefore?['contract_unit_cents']}→${b4bAfter?['contract_unit_cents']} '
        'cq ${b4bBefore?['contract_qty']}→${b4bAfter?['contract_qty']}',
    held: fieldChanged(b4bBefore, b4bAfter, 'contract_unit_cents', 1) ||
        fieldChanged(b4bBefore, b4bAfter, 'contract_qty', 99),
    title: 'contract_unit/qty immutability',
    severity: 'P0',
  );

  // =========================================================================
  // DK-C FSM + stock
  // =========================================================================

  // C1 reserva_pendente → enviado saltar pago
  final c1Before = await c.orderRow(oidPlat);
  final c1 = await c.patchOrder(oidPlat, {'status': 'enviado'}, jwt: c.sellerJwt);
  final c1After = await c.orderRow(oidPlat);
  record(
    id: 'DK-C1.reserva_to_enviado',
    matrix: 'DK-C',
    lens: 'DK4',
    payload: 'S1 PATCH reserva_pendente → enviado (sem pago / sem captura)',
    hit: c1,
    bd: '${c1Before?['status']}→${c1After?['status']} captured=${c1After?['amount_paid_cents']}',
    held: c1After?['status']?.toString() == 'enviado',
    title: 'FSM saltar pago para enviado',
    severity: 'P1',
  );

  final c1bBefore = await c.orderRow(oidPlat);
  final c1b = await c.patchOrder(oidPlat, {'status': 'concluido'}, jwt: c.buyerJwt);
  final c1bAfter = await c.orderRow(oidPlat);
  record(
    id: 'DK-C1b.reserva_to_concluido',
    matrix: 'DK-C',
    lens: 'DK4',
    payload: 'B1 PATCH reserva_pendente → concluido',
    hit: c1b,
    bd: '${c1bBefore?['status']}→${c1bAfter?['status']}',
    held: c1bAfter?['status']?.toString() == 'concluido',
    title: 'buyer saltar pago para concluido',
    severity: 'P1',
  );

  // C2 cancel platform restaura stock
  final availBeforePlat = availOf(await c.stockCheck(skuPlat, exclude: oidPlat));
  final heldBeforePlat = await c.stockCheck(skuPlat);
  final c2 = await c.patchOrder(oidPlat, {'status': 'cancelado'}, jwt: c.sellerJwt);
  final c2After = await c.orderRow(oidPlat);
  final heldAfterPlat = await c.stockCheck(skuPlat);
  final availAfterPlat = availOf(heldAfterPlat);
  final stockRowPlat = await c.productRow(skuPlat);
  final cancelled = c2After?['status']?.toString() == 'cancelado';
  final restoredPlat = cancelled &&
      (availAfterPlat ?? 0) > (availOf(heldBeforePlat) ?? -1);
  final c2FailDefense = !cancelled;
  // Finding if cancel denied on unpaid (regression) OR cancel ok but stock not restored
  if (c2FailDefense) {
    c.hold(
      id: 'DK-C2.cancel_plat_stock',
      lens: 'DK5',
      severity: 'P2',
      title: 'cancelar reserva plataforma JWT negado',
      actor: 'seller JWT',
      pre: 'reserva_pendente Pagamento na app qty=1',
      repro: 'DK-C2.cancel_plat_stock',
      expected: 'cancelado + available sobe',
      obtained: c2.brief,
    );
    c.probe(
      id: 'DK-C2.cancel_plat_stock',
      matrix: 'DK-C',
      payload: 'S1 cancel reserva plataforma',
      http: c2.brief,
      bd: 'st=${c2After?['status']} avail ${availOf(heldBeforePlat)}→$availAfterPlat '
          'qty=${stockRowPlat?['quantity']}',
      result: 'HOLD',
    );
  } else if (!restoredPlat && (availAfterPlat ?? 0) <= (availOf(heldBeforePlat) ?? 0)) {
    c.hold(
      id: 'DK-C2.cancel_plat_stock',
      lens: 'DK5',
      severity: 'P1',
      title: 'cancel plataforma não restaura hold',
      actor: 'seller JWT',
      pre: 'reserva_pendente cancelado',
      repro: 'DK-C2.cancel_plat_stock',
      expected: 'available +1',
      obtained: 'avail ${availOf(heldBeforePlat)}→$availAfterPlat',
    );
    c.probe(
      id: 'DK-C2.cancel_plat_stock',
      matrix: 'DK-C',
      payload: 'S1 cancel reserva plataforma',
      http: c2.brief,
      bd: 'st=${c2After?['status']} avail ${availOf(heldBeforePlat)}→$availAfterPlat',
      result: 'HOLD',
    );
  } else {
    c.block('DK-C2.cancel_plat_stock', 'DK5', 'cancel plataforma restaura hold', {
      'hit': c2.brief,
      'avail': '${availOf(heldBeforePlat)}→$availAfterPlat',
    });
    c.probe(
      id: 'DK-C2.cancel_plat_stock',
      matrix: 'DK-C',
      payload: 'S1 cancel reserva plataforma',
      http: c2.brief,
      bd: 'st=${c2After?['status']} avail ${availOf(heldBeforePlat)}→$availAfterPlat '
          'qty=${stockRowPlat?['quantity']} excludeAvail=$availBeforePlat',
      result: 'FAIL',
    );
  }

  // C2b cancel off-platform
  final skuOff2 = await c.createProduct(qty: 1, title: '$prefix-off2');
  final oidOff2 = await c.insertOrder(
    productId: skuOff2!,
    jwt: c.buyerJwt,
    payment: 'MB WAY',
  );
  final heldOffB = await c.stockCheck(skuOff2);
  final c2b = await c.patchOrder(oidOff2!, {'status': 'cancelado'}, jwt: c.sellerJwt);
  final c2bAfter = await c.orderRow(oidOff2);
  final heldOffA = await c.stockCheck(skuOff2);
  final offCancelled = c2bAfter?['status']?.toString() == 'cancelado';
  final offRestored =
      offCancelled && (availOf(heldOffA) ?? 0) > (availOf(heldOffB) ?? -1);
  if (!offCancelled) {
    c.hold(
      id: 'DK-C2b.cancel_off_stock',
      lens: 'DK5',
      severity: 'P2',
      title: 'cancelar reserva MB WAY JWT negado',
      actor: 'seller JWT',
      pre: 'MB WAY reserva_pendente',
      repro: 'DK-C2b.cancel_off_stock',
      expected: 'cancelado + available sobe',
      obtained: c2b.brief,
    );
    c.probe(
      id: 'DK-C2b.cancel_off_stock',
      matrix: 'DK-C',
      payload: 'S1 cancel reserva MB WAY',
      http: c2b.brief,
      bd: 'st=${c2bAfter?['status']} avail ${availOf(heldOffB)}→${availOf(heldOffA)}',
      result: 'HOLD',
    );
  } else if (!offRestored) {
    c.hold(
      id: 'DK-C2b.cancel_off_stock',
      lens: 'DK5',
      severity: 'P1',
      title: 'cancel MB WAY não restaura hold',
      actor: 'seller JWT',
      pre: 'MB WAY cancelado',
      repro: 'DK-C2b.cancel_off_stock',
      expected: 'available +1',
      obtained: 'avail ${availOf(heldOffB)}→${availOf(heldOffA)}',
    );
    c.probe(
      id: 'DK-C2b.cancel_off_stock',
      matrix: 'DK-C',
      payload: 'S1 cancel reserva MB WAY',
      http: c2b.brief,
      bd: 'st=${c2bAfter?['status']} avail ${availOf(heldOffB)}→${availOf(heldOffA)}',
      result: 'HOLD',
    );
  } else {
    c.block('DK-C2b.cancel_off_stock', 'DK5', 'cancel MB WAY restaura hold', {
      'avail': '${availOf(heldOffB)}→${availOf(heldOffA)}',
    });
    c.probe(
      id: 'DK-C2b.cancel_off_stock',
      matrix: 'DK-C',
      payload: 'S1 cancel reserva MB WAY',
      http: c2b.brief,
      bd: 'st=${c2bAfter?['status']} avail ${availOf(heldOffB)}→${availOf(heldOffA)}',
      result: 'FAIL',
    );
  }

  // C2c pago plataforma NÃO cancela JWT
  final c2cBefore = await c.orderRow(paid.oid);
  final c2c = await c.patchOrder(paid.oid, {'status': 'cancelado'}, jwt: c.sellerJwt);
  final c2cAfter = await c.orderRow(paid.oid);
  record(
    id: 'DK-C2c.cancel_pago_denied',
    matrix: 'DK-C',
    lens: 'DK4',
    payload: 'S1 PATCH pago Stripe → cancelado',
    hit: c2c,
    bd: '${c2cBefore?['status']}→${c2cAfter?['status']}',
    held: c2cAfter?['status']?.toString() == 'cancelado',
    title: 'cancel pós-pago plataforma',
    severity: 'P1',
  );

  // C3 refund stock +1 não ×2
  final rfFix = await mustPay('DK5', qty: 1);
  final qtyPaid = await c.productRow(rfFix.pid);
  if (!await c.toEnviado(rfFix.oid)) {
    c.note('C3.env', 'enviado falhou — refund mesmo assim', rfFix.oid, lens: 'DK5');
  }
  final wA = await c.wallets();
  final rf1 = await c.refund(rfFix.oid, jwt: c.sellerJwt);
  final qtyR1 = await c.productRow(rfFix.pid);
  final rf2 = await c.refund(rfFix.oid, jwt: c.sellerJwt);
  final qtyR2 = await c.productRow(rfFix.pid);
  final wB = await c.wallets();
  final q0 = numOf(qtyPaid?['quantity'])?.round() ?? -1;
  final q1 = numOf(qtyR1?['quantity'])?.round() ?? -1;
  final q2 = numOf(qtyR2?['quantity'])?.round() ?? -1;
  final doubled = q2 >= q1 + 1 && q1 >= q0 + 1;
  final dSeller = (wB['seller'] ?? 0) - (wA['seller'] ?? 0);
  c.note('C3.refund', 'refund ×2 stock', {
    'rf1': rf1.brief,
    'rf2': rf2.brief,
    'qty': '$q0→$q1→$q2',
    'dSeller': dSeller,
  }, lens: 'DK5');
  if (doubled || q2 > q1) {
    c.hold(
      id: 'DK-C3.refund_stock_x2',
      lens: 'DK5',
      severity: 'P0',
      title: '2.º refund duplica stock',
      actor: 'seller JWT refund-order',
      pre: 'Stripe TEST pago qty=1',
      repro: 'refund-order twice',
      expected: 'stock +1 uma vez',
      obtained: 'qty $q0→$q1→$q2 Δs=$dSeller',
    );
    c.probe(
      id: 'DK-C3.refund_stock_x2',
      matrix: 'DK-C',
      payload: 'refund-order ×2 Stripe TEST',
      http: '${rf1.brief} || ${rf2.brief}',
      bd: 'qty $q0→$q1→$q2 Δs=$dSeller',
      result: 'HOLD',
    );
  } else {
    c.block('DK-C3.refund_stock_x2', 'DK5', 'refund stock +1 não ×2', {
      'qty': '$q0→$q1→$q2',
      'rf1': rf1.brief,
      'rf2': rf2.brief,
    });
    c.probe(
      id: 'DK-C3.refund_stock_x2',
      matrix: 'DK-C',
      payload: 'refund-order ×2 Stripe TEST',
      http: '${rf1.brief} || ${rf2.brief}',
      bd: 'qty $q0→$q1→$q2 Δs=$dSeller',
      result: 'FAIL',
    );
  }

  // C4 disputa aberta bloqueia release
  final rel = await mustPay('DK6', qty: 1);
  if (!await c.toEnviado(rel.oid)) throw StateError('env rel');
  if (!await c.toConcluido(rel.oid)) throw StateError('conc rel');
  final dOpen = await c.insertDispute(orderId: rel.oid);
  final wRelA = await c.wallets();
  final relHit = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': rel.oid},
    jwt: c.buyerJwt,
  );
  final wRelB = await c.wallets();
  final dS = (wRelB['seller'] ?? 0) - (wRelA['seller'] ?? 0);
  final releasedAnyway = relHit.ok &&
      relHit.body != 'false' &&
      relHit.json != false &&
      relHit.map?['ok'] != false &&
      dS > 0;
  // body "false" is success-deny
  final blockedRelease = !releasedAnyway && dS <= 0;
  record(
    id: 'DK-C4.release_com_disputa',
    matrix: 'DK-C',
    lens: 'DK6',
    payload: 'buyer RPC release com disputa aberta',
    hit: relHit,
    bd: 'dispute=${dOpen.brief} Δseller=$dS body=${clip(relHit.body, 80)}',
    held: releasedAnyway,
    title: 'release wallet com disputa aberta',
    severity: 'P0',
    happy: false,
  );
  if (blockedRelease) {
    // record() already treated held=false as FAIL/block. Good.
  }

  // C5 2.ª disputa
  final second = await c.insertDispute(orderId: rel.oid);
  record(
    id: 'DK-C5.segunda_disputa',
    matrix: 'DK-C',
    lens: 'DK6',
    payload: '2.ª POST order_disputes mesma order',
    hit: second,
    bd: 'first=${dOpen.firstId} second=${second.firstId} st=${second.status}',
    held: second.ok && second.firstId != null && second.firstId != dOpen.firstId,
    title: '2.ª disputa mesma order',
    severity: 'P1',
  );

  // Extra: seller2 PATCH paid order (not party)
  final x1 = await c.patchOrder(paid.oid, {'status': 'enviado'}, jwt: c.seller2Jwt);
  final x1After = await c.orderRow(paid.oid);
  record(
    id: 'DK-A1e.s2_patch_order',
    matrix: 'DK-A',
    lens: 'DK7',
    payload: 'S2 PATCH status=enviado order S1/B1',
    hit: x1,
    bd: 'status=${x1After?['status']}',
    held: x1After?['status']?.toString() == 'enviado' &&
        a1Before?['status']?.toString() != 'enviado',
    title: 'seller2 PATCH encomenda alheia',
    severity: 'P0',
  );

  await c.dumpAll('pass1.json');
  stdout.writeln('PROBES ${c.probes.length} FINDINGS ${c.findings.length} '
      'BLOCKED ${c.blocked.length}');
  stdout.writeln(jsonEncode({
    'probes': c.probes.length,
    'findings': c.findings.map((f) => f['id']).toList(),
    'lenses': c.lensesHit.toList()..sort(),
  }));
}
