/// RED TEAM CEGO AM — pass 2. Aprofundar AM3/AM4/AM7/AM8. Não corrige.
import 'dart:io';
import '_rtam.dart';

Future<void> main() async {
  final c = Rtam.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  Future<Map<String, dynamic>> books(String oid, String pid) async => {
        'order': await c.orderRow(oid),
        'product': await c.productRow(pid),
        'wallets': await c.wallets(),
      };

  // -----------------------------------------------------------------------
  // AM3+AM8 — cadeia devolvida + 2.ª captura no mesmo SKU
  // -----------------------------------------------------------------------
  final paid = await c.payToPago(lens: 'AM8', initialQty: 1);
  if (paid == null) {
    c.skip('AM8.fixture', 'AM8', 'setup_paid_order falhou', 'null');
    await c.dumpAll('pass2.json');
    return;
  }
  final oid = paid.oid;
  final pid = paid.pid;
  final w0 = await c.wallets();
  await c.patchOrder(oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final dIns = await c.insertDispute(orderId: oid);
  final did = dIns.firstId;
  await c.patchOrder(oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  await c.patchOrder(oid, {'status': 'em_devolucao'}, jwt: c.sellerJwt);
  await c.patchOrder(oid, {'status': 'devolucao_entregue'}, jwt: c.sellerJwt);
  await c.patchOrder(oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
  final afterDev = await books(oid, pid);
  final oDev = afterDev['order'] as Map?;
  final pDev = afterDev['product'] as Map?;
  c.note('AM3.chain2', 'devolvida books', afterDev, lens: 'AM3');

  final refundHit = await c.refund(oid, jwt: c.sellerJwt);
  c.note('AM4.refund_devolvida2', 'refund-order após devolvida+shipped_at', {
    'hit': refundHit.brief,
    'status': oDev?['status'],
    'shipped_at': oDev?['shipped_at'],
    'stripe_refund': oDev?['stripe_refund_id'],
    'wallet_refund': oDev?['wallet_refund_processed_at'],
    'wallet_release': oDev?['wallet_release_processed_at'],
  }, lens: 'AM4');

  if (refundHit.status == 403 &&
      '${oDev?['status']}' == 'devolvida' &&
      '${oDev?['stripe_refund_id'] ?? ''}'.isEmpty &&
      oDev?['shipped_at'] != null) {
    c.hold(
      id: 'AM4.devolvida_refund_blocked_shipped',
      lens: 'AM4',
      severity: 'P1',
      title:
          'Após devolvida, refund-order Stripe continua bloqueado por shipped_at — buyer sem via JWT',
      actor: 'seller JWT',
      pre:
          'order enviada, depois cadeia até devolvida; wallet_refund_processed_at selado sem mint; PI capturado',
      repro: 'POST refund-order',
      expected:
          'gate terminal devolvida permite refund Stripe (shipped_at não manda após devolvida)',
      obtained: {
        'hit': refundHit.brief,
        'pi': oDev?['stripe_payment_intent_id'],
        'amount_paid_cents': oDev?['amount_paid_cents'],
        'stripe_refund_id': oDev?['stripe_refund_id'],
        'wallet_refund_processed_at': oDev?['wallet_refund_processed_at'],
      },
      evidence: afterDev,
    );
  }

  final wRefundRpc = await c.rpc(
    'batata_refund_buyer_wallet_for_order',
    {'p_order_id': oid},
    jwt: c.buyerJwt,
  );
  final w1 = await c.wallets();
  final dBuyer = (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0);
  c.note('AM4.wallet_refund_rpc', 'buyer rpc wallet refund pós-devolvida', {
    'rpc': wRefundRpc.brief,
    'dBuyer': dBuyer,
  }, lens: 'AM4');

  final avail = await c.rpc('batata_product_checkout_available', {
    'p_product_id': pid,
    'p_exclude_order_id': oid,
    'p_need_qty': 1,
  }, jwt: c.buyer2Jwt);
  c.note('AM8.avail2', 'checkout_available SKU restaurado', avail.brief,
      lens: 'AM8');

  final qty = pDev?['quantity'];
  final listed = pDev?['list_on_marketplace'] == true;
  final sold = pDev?['is_sold'] == true;
  if (avail.map?['ok'] == true || (qty is num && qty >= 1 && listed && !sold)) {
    final oid2 = await c.insertOrder(
      productId: pid,
      buyer: c.buyer2Id,
      jwt: c.buyer2Jwt,
      price: 5.9,
    );
    c.note('AM8.order2', 'B2 insert order SKU restaurado', oid2, lens: 'AM8');
    if (oid2 != null) {
      final ck = await c.checkout(
        orderId: oid2,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
        productId: pid,
        seller: c.sellerId,
        amount: 5.9,
      );
      c.note('AM8.checkout2', 'B2 create-payment-intent', {
        'status': ck.status,
        'brief': ck.brief,
        'session': ck.sessionId,
        'amount': ck.amountTotal,
      }, lens: 'AM8');

      String? pi2;
      var captured2 = false;
      final sid = ck.sessionId;
      if (sid != null && c.stripeTestKey != null) {
        final sess = await c.stripeSession(sid);
        pi2 = sess.map?['payment_intent']?.toString();
        if (pi2 != null && pi2.isNotEmpty) {
          final conf = await c.stripeConfirmPi(pi2);
          captured2 = conf.ok &&
              '${conf.map?['status']}' == 'succeeded';
          c.note('AM8.confirm2', 'Stripe confirm PI 2.ª venda', {
            'pi': pi2,
            'hit': conf.brief,
            'captured': captured2,
          }, lens: 'AM8');
        } else {
          c.note('AM8.session2', 'session sem PI ainda', sess.brief, lens: 'AM8');
        }
      } else if (ck.map?['paymentIntentId'] != null ||
          ck.map?['payment_intent'] != null) {
        pi2 = (ck.map?['paymentIntentId'] ?? ck.map?['payment_intent'])
            ?.toString();
        if (pi2 != null && c.stripeTestKey != null) {
          final conf = await c.stripeConfirmPi(pi2);
          captured2 = conf.ok && '${conf.map?['status']}' == 'succeeded';
          c.note('AM8.confirm2pi', 'confirm PI directo', conf.brief, lens: 'AM8');
        }
      }

      if (ck.ok) {
        c.hold(
          id: 'AM8.second_instrument_after_phantom_restore',
          lens: 'AM8',
          severity: captured2 ? 'P0' : 'P1',
          title: captured2
              ? 'Duas capturas Stripe no mesmo SKU: 1.ª devolvida sem refund + 2.ª paga'
              : 'SKU restaurado em devolvida sem refund aceita 2.º checkout Stripe TEST',
          actor: 'buyer2 JWT',
          pre:
              'order1 status=devolvida amount_paid_cents=590 stripe_refund_id null; product qty restaurado',
          repro:
              'B2 POST orders + create-payment-intent no product_id da 1.ª venda; confirm PI se sk_test_',
          expected:
              'available=0 / checkout recusado enquanto a 1.ª captura não for refunded',
          obtained: {
            'avail': avail.brief,
            'checkout': ck.brief,
            'session': sid,
            'pi2': pi2,
            'captured2': captured2,
            'order1_pi': oDev?['stripe_payment_intent_id'],
            'order1_refund': oDev?['stripe_refund_id'],
          },
          evidence: {
            'order1': oDev,
            'product': pDev,
            'order2': await c.orderRow(oid2),
          },
        );
      } else {
        c.block('AM8.second_checkout', 'AM8', '2.º checkout recusado', ck);
      }
    }
  } else {
    c.block('AM8.not_available', 'AM8', 'SKU não disponível após restore', {
      'avail': avail.brief,
      'product': pDev,
    });
  }

  // -----------------------------------------------------------------------
  // AM7 — PATCH proof_photos na disputa; hijack png; cross-seller storage
  // -----------------------------------------------------------------------
  if (did != null) {
    final patchPhotos = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.buyerJwt,
      body: {
        'proof_photos': [
          'javascript:alert(2)',
          'https://evil.example/upd.png',
        ],
      },
    );
    final afterP = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,proof_photos',
      service: true,
    );
    final ph = '${afterP.map?['proof_photos']}';
    if (ph.contains('evil') || ph.contains('javascript')) {
      c.hold(
        id: 'AM7.dispute_patch_photos',
        lens: 'AM7',
        severity: 'P2',
        title: 'PATCH order_disputes.proof_photos aceita URL arbitrária',
        actor: 'buyer JWT',
        pre: 'disputa aberta',
        repro: 'PATCH proof_photos=[javascript:, https://evil]',
        expected: 'mesmo deny do INSERT replies',
        obtained: {'hit': patchPhotos.brief, 'photos': ph},
      );
    } else {
      c.block('AM7.dispute_patch_photos', 'AM7', 'PATCH fotos disputa', {
        'hit': patchPhotos.brief,
        'photos': ph,
      });
    }
  }

  final hijack = await c.storage(
    'POST',
    'object/fleaber_private/order_disputes/${c.buyerId}/hijack-rtam.png',
    jwt: c.buyer2Jwt,
    bytes: <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A],
    contentType: 'image/png',
  );
  if (hijack.ok || hijack.status == 200) {
    c.hold(
      id: 'AM7.storage_path_hijack_png',
      lens: 'AM7',
      severity: 'P1',
      title: 'B2 escreve no prefixo order_disputes/{B1}/ (image/png)',
      actor: 'buyer2 JWT',
      pre: 'pasta B1',
      repro: 'POST storage order_disputes/B1/hijack-rtam.png',
      expected: '403',
      obtained: hijack.brief,
    );
  } else {
    c.block('AM7.storage_path_hijack_png', 'AM7', 'hijack png', hijack);
  }

  // Cross-seller: B1+S2 paid, upload prova, S1 (outra venda com B1) lê
  final paidS2 = await c.payToPago(
    lens: 'AM7',
    initialQty: 1,
    seller: c.seller2Id,
    buyer: c.buyerId,
  );
  if (paidS2 != null) {
    await c.patchOrder(paidS2.oid, {'status': 'enviado'}, jwt: c.seller2Jwt);
    await c.patchOrder(paidS2.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
    await c.insertDispute(orderId: paidS2.oid);
    final secretPath =
        'order_disputes/${c.buyerId}/${paidS2.oid}-s2-secret.png';
    final up = await c.storage(
      'POST',
      'object/fleaber_private/$secretPath',
      jwt: c.buyerJwt,
      bytes: <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      contentType: 'image/png',
    );
    c.note('AM7.up_s2', 'B1 upload prova disputa com S2', up.brief, lens: 'AM7');
    final s1read = await c.storage(
      'GET',
      'object/fleaber_private/$secretPath',
      jwt: c.sellerJwt,
    );
    final s2read = await c.storage(
      'GET',
      'object/fleaber_private/$secretPath',
      jwt: c.seller2Jwt,
    );
    c.note('AM7.cross_read', 'S1 vs S2 lêem prova da disputa B1-S2', {
      's1': s1read.status,
      's2': s2read.status,
      's1body': clip(s1read.body, 120),
      's2body': clip(s2read.body, 120),
    }, lens: 'AM7');
    if (s1read.status == 200) {
      c.hold(
        id: 'AM7.cross_seller_storage',
        lens: 'AM7',
        severity: 'P1',
        title:
            'Seller S1 lê provas de disputa de uma encomenda B1–S2 (pasta inteira do buyer)',
        actor: 'seller JWT (S1)',
        pre: 'S1 tem outra order com B1; B1 fez upload em disputa com S2',
        repro: 'GET storage order_disputes/{B1}/{orderS2}-s2-secret.png',
        expected: '403 — só o vendedor daquela encomenda lê as provas',
        obtained: {
          's1': s1read.brief,
          's2_ok': s2read.status,
          'path': secretPath,
        },
      );
    } else {
      c.block('AM7.cross_seller_storage', 'AM7', 'S1 lê prova S2', {
        's1': s1read.brief,
        's2': s2read.brief,
      });
    }
  }

  // AM5 — hop pedido_devolucao → concluido (já visto 200). Confirmar se UI-only.
  // AM1 — INSERT disputa já resolvida para desbloquear release
  final paid3 = await c.payToPago(lens: 'AM1', initialQty: 1);
  if (paid3 != null) {
    await c.patchOrder(paid3.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
    await c.patchOrder(paid3.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
    final resIns = await c.insertDispute(
      orderId: paid3.oid,
      status: 'resolvida',
    );
    c.note('AM1.insert_resolvida', 'INSERT disputa já resolvida', resIns.brief,
        lens: 'AM1');
    await c.patchOrder(paid3.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
    final rel = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': paid3.oid},
      jwt: c.buyerJwt,
    );
    final o3 = await c.orderRow(paid3.oid);
    final w3 = await c.wallets();
    final dS = (w3['seller'] ?? 0) - (w0['seller'] ?? 0);
    if (resIns.ok &&
        o3?['wallet_release_processed_at'] != null &&
        dS > 0) {
      c.hold(
        id: 'AM1.insert_resolvida_unblocks_release',
        lens: 'AM1',
        severity: 'P0',
        title:
            'Buyer insere disputa já resolvida e liberta carteira do vendedor sem ciclo real',
        actor: 'buyer JWT',
        pre: 'entregue, sem disputa prévia',
        repro: 'POST order_disputes status=resolvida; PATCH concluido; rpc release',
        expected: 'INSERT força status=aberta ou recusa; release não corre',
        obtained: {
          'insert': resIns.brief,
          'rpc': rel.brief,
          'release_at': o3?['wallet_release_processed_at'],
          'dSeller_vs_w0': dS,
        },
      );
    } else {
      c.block('AM1.insert_resolvida_unblocks_release', 'AM1',
          'insert resolvida+release', {
        'insert': resIns.brief,
        'rpc': rel.brief,
        'release': o3?['wallet_release_processed_at'],
        'dS': dS,
      });
    }
  }

  await c.dumpAll('pass2.json');
  stdout.writeln(
      'DONE findings=${c.findings.length} blocked=${c.blocked.length}');
}
