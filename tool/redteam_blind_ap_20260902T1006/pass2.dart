/// RED TEAM CEGO AP — pass 2. Aprofundar AP1-11 / AP3-06 / AP8 wallet. Não corrige.
import 'dart:io';
import '_rtap.dart';

Future<void> main() async {
  final rt = Rtap.fromEnv(loadEnv());
  await rt.loginActors();
  await rt.ensureBuyer2();
  await rt.ensureSeller2();

  Future<List<Map<String, dynamic>>> walletTx(String uid, {int limit = 8}) async {
    final h = await rt.rest(
      'GET',
      'wallet_transactions?user_id=eq.$uid&select=id,user_id,order_id,type,amount,created_at,description&order=created_at.desc&limit=$limit',
      service: true,
    );
    return h.list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // =========================================================================
  // AP8 — ledger: o Δ -2 € foi nosso exploit ou ruído/fixture?
  // =========================================================================
  final tx0 = await walletTx(rt.sellerId!);
  rt.note('AP8.tx.recent', 'últimos movimentos seller', tx0, lens: 'AP8');
  final w0 = await rt.walletBal(rt.sellerId);

  final sku = await rt.createProduct(title: '$prefix p2sku', qty: 2, price: 7);
  final wAfterSku = await rt.walletBal(rt.sellerId);
  rt.note('AP8.delta.sku', 'após createProduct', {
    'before': w0,
    'after': wAfterSku,
  }, lens: 'AP8');

  String? paidId;
  if (sku != null) {
    final w1 = await rt.walletBal(rt.sellerId);
    paidId = await rt.insertPaidOrder(
      productId: sku,
      price: 7,
      pi: 'pi_rtap_p2',
    );
    final w2 = await rt.walletBal(rt.sellerId);
    final tx1 = await walletTx(rt.sellerId!);
    rt.note('AP8.delta.paidFixture', 'insertPaidOrder service_role', {
      'oid': paidId,
      'before': w1,
      'after': w2,
      'delta': w2 - w1,
      'tx': tx1.take(3).toList(),
    }, lens: 'AP8');
    if ((w2 - w1).abs() > 0.009) {
      rt.hold(
        id: 'AP8-p2-fixture',
        lens: 'AP8',
        severity: 'P3',
        title: 'Fixture service_role pago altera wallet (não é JWT)',
        actor: 'service_role fixture',
        pre: 'insertPaidOrder',
        repro: 'POST orders status=pago service_role',
        expected: 'Δ=0 até captura real Stripe',
        obtained: {'delta': w2 - w1, 'tx': tx1.take(3).toList()},
        proven: true,
        evidence: {'oid': paidId},
      );
    } else {
      rt.block('AP8-p2-fixture', 'AP8', 'fixture pago não mexeu wallet', {
        'before': w1,
        'after': w2,
      });
    }
  }

  // =========================================================================
  // AP1-11 / AP7 — purchase_broadcast: mensagem falsa + spoof buyer + live alheia
  // =========================================================================
  final liveA = await rt.insertLive(title: '$prefix p2 A');
  final liveS2 = await rt.insertLive(seller: rt.seller2Id, title: '$prefix p2 B');
  final itemA = await rt.insertItem(
    liveId: liveA!,
    jwt: rt.sellerJwt,
    kind: 'live_only',
    qty: 1,
    title: '$prefix p2 itemA',
  );
  final itemS2 = await rt.insertItem(
    liveId: liveS2!,
    jwt: rt.seller2Jwt,
    kind: 'live_only',
    qty: 1,
    title: '$prefix p2 itemS2',
  );
  final idA = itemA.firstId;
  final idS2 = itemS2.firstId;

  if (idA != null) {
    final wBc0 = await rt.walletBal(rt.sellerId);
    final bc = await rt.rpc('batata_live_purchase_broadcast', {
      'p_live_id': liveA,
      'p_buyer_id': rt.buyerId,
      'p_live_item_id': idA,
    }, jwt: rt.buyerJwt);
    final wBc1 = await rt.walletBal(rt.sellerId);
    final msgs = await rt.rest(
      'GET',
      'live_messages?live_id=eq.$liveA&select=id,live_id,user_id,kind,body,sender_label,created_at&order=created_at.desc&limit=5',
      service: true,
    );
    rt.note('AP1.broadcast.msgs', 'mensagens após buyer broadcast', {
      'rpc': bc.brief,
      'walletDelta': wBc1 - wBc0,
      'msgs': msgs.list,
    }, lens: 'AP1');
    final fakeBuy = msgs.list.any((e) {
      if (e is! Map) return false;
      final body = '${e['body']}';
      return body.contains('comprou') && e['kind'] == 'system';
    });
    if (bc.ok && fakeBuy) {
      rt.hold(
        id: 'AP1-11b',
        lens: 'AP1',
        severity: 'P2',
        title: 'Buyer injeta system «comprou» no chat da live sem PI',
        actor: 'buyer JWT',
        pre: 'sem order paga, sem convert',
        repro: 'rpc batata_live_purchase_broadcast',
        expected: 'só após convert com PI (seller/staff)',
        obtained: {'rpc': bc.brief, 'msgs': msgs.list.take(2).toList()},
        evidence: {'walletDelta': wBc1 - wBc0},
      );
    } else {
      rt.block('AP1-11b', 'AP1', 'broadcast sem mensagem visível', {
        'rpc': bc.brief,
        'msgs': msgs.brief,
      });
    }

    final spoof = await rt.rpc('batata_live_purchase_broadcast', {
      'p_live_id': liveA,
      'p_buyer_id': rt.sellerId,
      'p_live_item_id': idA,
    }, jwt: rt.buyerJwt);
    final msgs2 = await rt.rest(
      'GET',
      'live_messages?live_id=eq.$liveA&body=like.*comprou*&select=id,user_id,body,sender_label&order=created_at.desc&limit=8',
      service: true,
    );
    final spoofed = msgs2.list.any((e) {
      if (e is! Map) return false;
      return e['user_id']?.toString() == rt.sellerId;
    });
    if (spoof.ok && spoofed) {
      rt.hold(
        id: 'AP1-11c',
        lens: 'AP1',
        severity: 'P2',
        title: 'Buyer spoofa p_buyer_id no purchase_broadcast (nome alheio)',
        actor: 'buyer JWT',
        pre: 'p_buyer_id = seller',
        repro: 'rpc broadcast com UUID alheio',
        expected: 'auth.uid() only',
        obtained: {'rpc': spoof.brief, 'msgs': msgs2.list.take(3).toList()},
      );
    } else {
      rt.block('AP1-11c', 'AP1', 'spoof p_buyer_id', {
        'rpc': spoof.brief,
        'msgs': msgs2.brief,
      });
    }
  }

  if (idS2 != null) {
    final alienBc = await rt.rpc('batata_live_purchase_broadcast', {
      'p_live_id': liveS2,
      'p_buyer_id': rt.buyerId,
      'p_live_item_id': idS2,
    }, jwt: rt.buyerJwt);
    final msgsS2 = await rt.rest(
      'GET',
      'live_messages?live_id=eq.$liveS2&select=id,kind,body,user_id&order=created_at.desc&limit=5',
      service: true,
    );
    final planted = msgsS2.list.any((e) {
      if (e is! Map) return false;
      return '${e['body']}'.contains('comprou');
    });
    if (alienBc.ok && planted) {
      rt.hold(
        id: 'AP7-09',
        lens: 'AP7',
        severity: 'P2',
        title: 'Buyer planta «comprou» na live de outro vendedor',
        actor: 'buyer JWT',
        pre: 'live S2',
        repro: 'purchase_broadcast live_id alheio',
        expected: 'not_allowed / só owner',
        obtained: {'rpc': alienBc.brief, 'msgs': msgsS2.list.take(3).toList()},
      );
    } else {
      rt.block('AP7-09', 'AP7', 'broadcast live alheia', {
        'rpc': alienBc.brief,
        'msgs': msgsS2.brief,
      });
    }
  }

  // =========================================================================
  // AP3-06 — reserva em ended: accept / convert / mark_sold / Hub
  // =========================================================================
  final ended = await rt.insertLive(
    status: 'ended',
    active: false,
    title: '$prefix p2 ended',
  );
  final eItem = await rt.insertItem(
    liveId: ended!,
    service: true,
    kind: 'live_only',
    qty: 1,
    title: '$prefix p2 ended item',
  );
  final eid = eItem.firstId;
  if (eid != null) {
    final res = await rt.insertRes(
      liveId: ended,
      itemId: eid,
      jwt: rt.buyerJwt,
      qty: 1,
    );
    final rid = res.firstId;
    rt.note('AP3.ended.insert', 'INSERT pending em ended', {
      'hit': res.brief,
      'row': rid == null ? null : await rt.resRow(rid),
    }, lens: 'AP3');

    if (rid != null) {
      final acc = await rt.processRes(rid, 'accept');
      final rAcc = await rt.resRow(rid);
      final itemAcc = await rt.itemRow(eid);
      if (acc.ok && '${rAcc?['status']}' == 'accepted') {
        rt.hold(
          id: 'AP3-06b',
          lens: 'AP3',
          severity: 'P1',
          title: 'Seller accept reserva em live already ended',
          actor: 'seller JWT',
          pre: 'live ended, pending INSERT do buyer',
          repro: 'process accept',
          expected: 'live_ended / item not live',
          obtained: {'hit': acc.brief, 'res': rAcc, 'item': itemAcc},
        );
      } else {
        rt.block('AP3-06b', 'AP3', 'accept em ended', {
          'hit': acc.brief,
          'res': rAcc,
          'item': itemAcc,
        });
      }

      final conv = await rt.processRes(rid, 'convert');
      final rConv = await rt.resRow(rid);
      rt.judge(
        id: 'AP3-06c',
        lens: 'AP3',
        title: 'Convert reserva de live ended sem PI',
        hit: conv,
        cracked: conv.ok && '${rConv?['status']}' == 'converted',
        actor: 'seller JWT',
        pre: 'ended + pending/accepted',
        repro: 'process convert',
        expected: 'convert_requires_paid_order ou live_ended',
      );

      final ms = await rt.markSold(eid);
      final itemMs = await rt.itemRow(eid);
      if (ms.ok && '${itemMs?['status']}' == 'sold') {
        rt.hold(
          id: 'AP3-06d',
          lens: 'AP3',
          severity: 'P2',
          title: 'mark_sold em item de live ended (sem PI)',
          actor: 'seller JWT',
          pre: 'live ended',
          repro: 'rpc mark_sold',
          expected: 'sold cosmética sem unlist catálogo; documentar',
          obtained: {'hit': ms.brief, 'item': itemMs},
        );
      } else {
        rt.block('AP3-06d', 'AP3', 'mark_sold ended', {
          'hit': ms.brief,
          'item': itemMs,
        });
      }
    }

    // Reabrir live e ver se a pending de ended entra na fila
    await rt.rest(
      'PATCH',
      'lives?id=eq.$ended',
      service: true,
      body: {'status': 'live', 'is_active': true},
      prefer: 'return=minimal',
    );
    if (rid != null) {
      final acc2 = await rt.processRes(rid, 'accept');
      final r2 = await rt.resRow(rid);
      if (acc2.ok && '${r2?['status']}' == 'accepted') {
        rt.hold(
          id: 'AP3-06e',
          lens: 'AP3',
          severity: 'P2',
          title: 'Pending criada em ended é aceite depois de reabrir o directo',
          actor: 'seller JWT',
          pre: 'INSERT while ended → live de novo',
          repro: 'accept após PATCH live=live',
          expected: 'pending de ended expirada / recusada',
          obtained: {'hit': acc2.brief, 'res': r2},
        );
      } else {
        rt.block('AP3-06e', 'AP3', 'accept após reopen', {
          'hit': acc2.brief,
          'res': r2,
        });
      }
    }
  }

  // Anon stock rpc ended: available_qty
  if (eid != null) {
    await rt.rest(
      'PATCH',
      'lives?id=eq.$ended',
      service: true,
      body: {'status': 'ended', 'is_active': false},
      prefer: 'return=minimal',
    );
    final st = await rt.rpc('batata_live_item_stock', {'p_live_item_id': eid});
    rt.note('AP3.ended.stock.p2', 'anon stock ended', st.map, lens: 'AP3');
    final avail = int.tryParse('${st.map?['available_qty'] ?? ''}');
    if (st.ok && avail != null && avail > 0) {
      rt.hold(
        id: 'AP3-07',
        lens: 'AP3',
        severity: 'P3',
        title: 'RPC stock anon mostra available_qty>0 em live ended',
        actor: 'anon',
        pre: 'live ended',
        repro: 'batata_live_item_stock',
        expected: 'available_qty=0 ou live_status ended sem oferta',
        obtained: st.map,
      );
    } else {
      rt.block('AP3-07', 'AP3', 'stock ended available', st);
    }
  }

  final txEnd = await walletTx(rt.sellerId!);
  final wEnd = await rt.walletBal(rt.sellerId);
  rt.note('AP8.tx.end', 'wallet fim pass2', {
    'balance': wEnd,
    'tx': txEnd.take(5).toList(),
  }, lens: 'AP8');

  await rt.cleanupSoft();
  await rt.dumpAll('pass2.json');
  stdout.writeln(
      'DONE p2 findings=${rt.findings.length} blocked=${rt.blocked.length}');
}
