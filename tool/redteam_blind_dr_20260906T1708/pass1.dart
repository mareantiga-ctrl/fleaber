/// REDTEAM_BLIND_DR_TIP_RAFFLE_POS_DHDM_v1 — pass1
/// Staging only. No fixes. No Fase 4.
import 'dart:io';

import '_rtdr.dart';

Future<void> main() async {
  final c = Rtdr.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2(hubPublished: true);
  await c.restoreSeller1Published();

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;

  // Shared live for tip probes (broadcasting).
  final liveTip = await c.createLive(title: '$prefix tip-base');
  final liveS2 = await c.createLive(seller: s2, title: '$prefix tip-s2');
  if (liveTip == null) {
    stderr.writeln('fixture liveTip fail');
    exit(4);
  }

  // =====================================================================
  // DR-A Tip Edge
  // =====================================================================

  // A1 — amount hostil (incl. coerção JS array / 1e2) classe_nova vs 0/-1/501 clássico
  final a1hits = <String, String>{};
  var a1created = 0;
  var a1walletDelta = 0.0;
  final wA1before = await c.walletBal(s1);
  for (final entry in <Map<String, Object?>>[
    {'tag': 'zero', 'amount_eur': 0},
    {'tag': 'neg', 'amount_eur': -1},
    {'tag': 'half', 'amount_eur': 0.5},
    {'tag': 'over', 'amount_eur': 501},
    {'tag': 'sci', 'amount_eur': '1e2'},
    {'tag': 'arr', 'amount_eur': [2]},
    {'tag': 'cents_field', 'amount_eur': 2, 'amount_cents': 1},
  ]) {
    final tag = entry['tag'] as String;
    final extra = Map<String, Object?>.from(entry)..remove('tag');
    extra.remove('amount_eur');
    final h = liveTip == null
        ? null
        : await c.tipCheckout(
            liveId: liveTip,
            seller: s1,
            amountEur: entry['amount_eur'],
            jwt: c.buyer2Jwt,
            extra: extra,
          );
    a1hits[tag] = h?.brief ?? 'n/a';
    final tid = h?.tipId;
    if (tid != null) {
      a1created++;
      c.createdTipIds.add(tid);
    }
    if (h != null && h.ok && h.sessionId != null) {
      a1created++;
    }
  }
  final wA1after = await c.walletBal(s1);
  a1walletDelta = (wA1after - wA1before).toDouble();
  final a1fail = a1walletDelta > 0;
  // sci/arr may create Session if Number() coerces — unpaid is HOLD, credit is FAIL
  if (a1fail) {
    c.hold(
      id: 'A1.tip.amount.hostil',
      lens: 'DR1',
      severity: 'P0',
      title: 'Tip amount hostil creditou carteira',
      actor: 'buyer2 JWT',
      pre: 'live broadcasting',
      repro: 'POST create-live-tip-checkout amount_eur hostil',
      expected: '400; Δwallet=0',
      obtained: {'hits': a1hits, 'dWallet': a1walletDelta},
    );
  } else {
    c.block('A1.tip.amount.hostil', 'DR1', 'amounts hostis sem crédito', a1hits);
  }
  c.probe(
    id: 'A1.tip.amount.hostil',
    poco: 'DR-A',
    payload: 'amount 0/-1/0.5/501/"1e2"/[2]/amount_cents=1',
    http: a1hits.entries.map((e) => '${e.key}:${e.value}').join(' | '),
    bd: {'created_sessions_or_tips': a1created, 'dWallet': a1walletDelta},
    result: a1fail ? 'FAIL' : 'HOLD',
    lens: 'DR1',
    classeNova: true,
    countFinding: a1fail,
  );

  // A2 — tip_id cliente + live_id alheio (S2 live + seller S1)
  final fakeTip = '00000000-0000-4000-8000-0000000000aa';
  final a2id = await c.tipCheckout(
    liveId: liveS2 ?? liveTip,
    seller: s1,
    amountEur: 2,
    jwt: c.buyerJwt,
    extra: {'tip_id': fakeTip},
  );
  final a2live = liveS2 == null
      ? null
      : await c.tipCheckout(
          liveId: liveS2,
          seller: s1,
          amountEur: 2,
          jwt: c.buyerJwt,
        );
  final a2ok = a2id.ok || (a2live?.ok == true);
  if (a2ok) {
    c.hold(
      id: 'A2.tip_id.live_alheio',
      lens: 'DR1',
      severity: 'P1',
      title: 'tip_id cliente ou live alheia criou Session',
      actor: 'buyer JWT',
      pre: 'live S2 + seller_id S1 / tip_id UUID',
      repro: 'POST create-live-tip-checkout tip_id + live_id alheio',
      expected: '400 Client tip_id / Tip seller does not own',
      obtained: {'tip_id': a2id.brief, 'live': a2live?.brief},
    );
  } else {
    c.block('A2.tip_id.live_alheio', 'DR1', 'tip_id/live alheio recusado', {
      'tip_id': a2id.brief,
      'live': a2live?.brief,
    });
  }
  c.probe(
    id: 'A2.tip_id.live_alheio',
    poco: 'DR-A',
    payload: 'tip_id UUID cliente + live S2 seller_id S1',
    http: '${a2id.brief} | ${a2live?.brief ?? 'n/a'}',
    bd: {'tipId': a2id.tipId, 'liveTipId': a2live?.tipId},
    result: a2ok ? 'FAIL' : 'HOLD',
    lens: 'DR1',
    countFinding: a2ok,
  );

  // A3 — tip POST ∥ end_live + hub unpublish (race; não o unpaid sequencial clássico)
  final liveA3 = await c.createLive(title: '$prefix a3-race');
  final wA3b = await c.walletBal(s1);
  HttpHit? a3tip;
  if (liveA3 != null) {
    final raced = await Future.wait([
      c.tipCheckout(liveId: liveA3, seller: s1, amountEur: 2, jwt: c.buyer2Jwt),
      c.endLive(liveA3).then((_) async {
        await c.setHub(s1, false);
        return HttpHit(200, 'ended+unpublish', {'ok': true});
      }),
    ]);
    a3tip = raced[0];
    if (a3tip.tipId != null) c.createdTipIds.add(a3tip.tipId!);
  }
  await c.restoreSeller1Published();
  String a3status = '';
  if (a3tip?.tipId != null) {
    a3status = '${(await c.tipRow(a3tip!.tipId!))?['status'] ?? ''}';
  }
  final wA3a = await c.walletBal(s1);
  final a3credit = (wA3a - wA3b) > 0 ||
      a3status == 'paid' ||
      a3status == 'settled';
  if (a3credit) {
    c.hold(
      id: 'A3.tip.end_live.race',
      lens: 'DR4',
      severity: 'P0',
      title: 'Tip∥end_live creditou sem pagamento',
      actor: 'buyer2 ∥ service end+unpublish',
      pre: 'live broadcasting',
      repro: 'Future.wait tip POST + end_live + hub_published=false',
      expected: '400 broadcasting / pending unpaid Δ=0',
      obtained: {'http': a3tip?.brief, 'status': a3status, 'dWallet': wA3a - wA3b},
    );
  } else {
    c.block('A3.tip.end_live.race', 'DR4', 'race tip∥end sem crédito', {
      'http': a3tip?.brief,
      'status': a3status,
      'dWallet': wA3a - wA3b,
    });
  }
  c.probe(
    id: 'A3.tip.end_live.race',
    poco: 'DR-A',
    payload: 'POST tip ∥ end_live + hub unpublish',
    http: a3tip ?? 'n/a',
    bd: {'status': a3status, 'dWallet': wA3a - wA3b, 'hub_restored': true},
    result: a3credit ? 'FAIL' : 'HOLD',
    lens: 'DR4',
    classeNova: true,
    race: true,
    countFinding: a3credit,
  );

  // A4 — seller_id ≠ live owner
  final a4 = await c.tipCheckout(
    liveId: liveTip,
    seller: s2,
    amountEur: 2,
    jwt: c.buyerJwt,
  );
  if (a4.ok) {
    c.hold(
      id: 'A4.tip.seller_ne_owner',
      lens: 'DR1',
      severity: 'P1',
      title: 'Tip seller≠owner criou Session',
      actor: 'buyer JWT',
      pre: 'live S1; seller_id S2',
      repro: 'POST create-live-tip-checkout seller_id alheio',
      expected: '400 Tip seller does not own this live',
      obtained: a4.brief,
    );
  } else {
    c.block('A4.tip.seller_ne_owner', 'DR1', 'seller≠owner recusado', a4.brief);
  }
  c.probe(
    id: 'A4.tip.seller_ne_owner',
    poco: 'DR-A',
    payload: 'seller_id S2 na live S1',
    http: a4,
    bd: {'tipId': a4.tipId},
    result: a4.ok ? 'FAIL' : 'HOLD',
    lens: 'DR1',
    countFinding: a4.ok,
  );

  // =====================================================================
  // DR-B Rifa
  // =====================================================================

  // B1 — partilhar SEM rifa activa → sem prémio
  final liveB1 = await c.createLive(title: '$prefix b1-noraffle');
  final ghost = '00000000-0000-4000-8000-0000000000bb';
  final b1share = await c.rpc(
    'batata_claim_live_raffle_share_intent',
    {'p_raffle_id': ghost},
    jwt: c.buyerJwt,
  );
  final b1join = await c.rpc(
    'batata_join_live_raffle',
    {'p_raffle_id': ghost},
    jwt: c.buyerJwt,
  );
  // follow S1 (published) while this live has no raffle — tickets on ghost = 0
  await c.rest(
    'POST',
    'follows',
    jwt: c.buyer2Jwt,
    body: {'follower_id': b2, 'following_id': s1},
  );
  final b1tickets = await c.raffleTickets(ghost, b1);
  final b1win = await c.winnerCount(ghost);
  final b1prize = b1tickets > 0 || b1win > 0 || b1share.rpcOk || b1join.rpcOk;
  if (b1prize) {
    c.hold(
      id: 'B1.share.sem.rifa',
      lens: 'DR2',
      severity: 'P1',
      title: 'Partilhar/join sem rifa activa deu prémio',
      actor: 'buyer JWT',
      pre: 'live sem rifa; raffle_id fantasma',
      repro: 'rpc claim_share + join UUID inexistente',
      expected: 'raffle_not_found / not active; tickets=0',
      obtained: {
        'share': b1share.brief,
        'join': b1join.brief,
        'tickets': b1tickets,
        'winners': b1win,
      },
    );
  } else {
    c.block('B1.share.sem.rifa', 'DR2', 'sem rifa = sem prémio', {
      'share': b1share.brief,
      'join': b1join.brief,
    });
  }
  c.probe(
    id: 'B1.share.sem.rifa',
    poco: 'DR-B',
    payload: 'claim_share + join raffle_id inexistente; live sem rifa',
    http: '${b1share.brief} | ${b1join.brief}',
    bd: {'tickets': b1tickets, 'winners': b1win, 'live': liveB1},
    result: b1prize ? 'FAIL' : 'HOLD',
    lens: 'DR2',
    classeNova: true,
    countFinding: b1prize,
  );

  // B2 — partilhar COM rifa → elegível
  final liveB2 = await c.createLive(title: '$prefix b2-raffle');
  final rafB2 = liveB2 == null
      ? null
      : await c.rpc('batata_create_live_raffle', {
          'p_live_id': liveB2,
          'p_title': '$prefix rifa b2',
        }, jwt: c.sellerJwt);
  final rafB2id = rafB2?.map?['id']?.toString() ??
      rafB2?.map?['raffle_id']?.toString();
  if (rafB2id != null) c.createdRaffleIds.add(rafB2id);
  HttpHit? b2join;
  HttpHit? b2share;
  var ticketsJoin = 0;
  var ticketsShare = 0;
  if (rafB2id != null) {
    b2join = await c.rpc(
      'batata_join_live_raffle',
      {'p_raffle_id': rafB2id},
      jwt: c.buyerJwt,
    );
    ticketsJoin = await c.raffleTickets(rafB2id, b1);
    b2share = await c.rpc(
      'batata_claim_live_raffle_share_intent',
      {'p_raffle_id': rafB2id},
      jwt: c.buyerJwt,
    );
    ticketsShare = await c.raffleTickets(rafB2id, b1);
  }
  final b2ok = rafB2id != null && ticketsShare >= 1 && (b2share?.rpcOk == true);
  if (rafB2id != null && ticketsShare < 1) {
    c.hold(
      id: 'B2.share.com.rifa',
      lens: 'DR2',
      severity: 'P2',
      title: 'Partilhar com rifa activa não deixou elegível',
      actor: 'buyer JWT',
      pre: 'rifa active',
      repro: 'join + claim_share',
      expected: 'tickets≥1 elegível',
      obtained: {
        'join': b2join?.brief,
        'share': b2share?.brief,
        'tJoin': ticketsJoin,
        'tShare': ticketsShare,
      },
    );
  } else {
    c.block('B2.share.com.rifa', 'DR2', 'share com rifa elegível', {
      'ticketsJoin': ticketsJoin,
      'ticketsShare': ticketsShare,
      'share': b2share?.brief,
    });
  }
  c.probe(
    id: 'B2.share.com.rifa',
    poco: 'DR-B',
    payload: 'join + claim_share rifa active',
    http: '${b2join?.brief ?? 'n/a'} | ${b2share?.brief ?? 'n/a'}',
    bd: {'raffle': rafB2id, 'tJoin': ticketsJoin, 'tShare': ticketsShare},
    result: rafB2id == null
        ? 'SKIP'
        : (ticketsShare < 1 ? 'FAIL' : 'HOLD'),
    lens: 'DR2',
    countFinding: rafB2id != null && ticketsShare < 1,
  );

  // B3 — winner forge JWT / REST insert / double assign
  final liveB3 = await c.createLive(title: '$prefix b3-draw');
  final rafB3 = liveB3 == null
      ? null
      : await c.rpc('batata_create_live_raffle', {
          'p_live_id': liveB3,
          'p_title': '$prefix rifa b3',
        }, jwt: c.sellerJwt);
  final rafB3id = rafB3?.map?['id']?.toString() ??
      rafB3?.map?['raffle_id']?.toString();
  if (rafB3id != null) c.createdRaffleIds.add(rafB3id);
  HttpHit? b3join;
  HttpHit? b3close;
  HttpHit? b3drawBuyer;
  HttpHit? b3drawS2;
  HttpHit? b3ins;
  HttpHit? b3draw1;
  HttpHit? b3draw2;
  var winAfterForge = 0;
  var winAfterDouble = 0;
  if (rafB3id != null) {
    b3join = await c.rpc(
      'batata_join_live_raffle',
      {'p_raffle_id': rafB3id},
      jwt: c.buyerJwt,
    );
    b3close = await c.rpc(
      'batata_close_live_raffle',
      {'p_raffle_id': rafB3id},
      jwt: c.sellerJwt,
    );
    b3drawBuyer = await c.rpc(
      'batata_draw_live_raffle_winners',
      {'p_raffle_id': rafB3id},
      jwt: c.buyerJwt,
    );
    b3drawS2 = await c.rpc(
      'batata_draw_live_raffle_winners',
      {'p_raffle_id': rafB3id},
      jwt: c.seller2Jwt,
    );
    b3ins = await c.rest('POST', 'live_raffle_winners', jwt: c.buyerJwt, body: {
      'raffle_id': rafB3id,
      'user_id': b1,
      'rank': 1,
      'tickets_at_draw': 99,
      'draw_proof': {'forged': true},
    });
    winAfterForge = await c.winnerCount(rafB3id);
    b3draw1 = await c.rpc(
      'batata_draw_live_raffle_winners',
      {'p_raffle_id': rafB3id},
      jwt: c.sellerJwt,
    );
    b3draw2 = await c.rpc(
      'batata_draw_live_raffle_winners',
      {'p_raffle_id': rafB3id},
      jwt: c.sellerJwt,
    );
    winAfterDouble = await c.winnerCount(rafB3id);
  }
  final forgeOk = b3drawBuyer?.rpcOk == true ||
      b3drawS2?.rpcOk == true ||
      (b3ins?.ok == true);
  final doubleAssign = winAfterDouble > 1;
  if (forgeOk || doubleAssign) {
    c.hold(
      id: 'B3.winner.forge.double',
      lens: 'DR2',
      severity: 'P1',
      title: 'Forge JWT / insert winner / double assign',
      actor: 'buyer / S2 / seller draw×2',
      pre: 'rifa closed com 1 join',
      repro: 'draw buyer + draw S2 + POST winners + draw×2 seller',
      expected: 'draw foreign fail; insert RLS fail; 1 winner',
      obtained: {
        'buyer': b3drawBuyer?.brief,
        's2': b3drawS2?.brief,
        'ins': b3ins?.brief,
        'd1': b3draw1?.brief,
        'd2': b3draw2?.brief,
        'nWin': winAfterDouble,
      },
    );
  } else {
    c.block('B3.winner.forge.double', 'DR2', 'forge/double recusado', {
      'buyer': b3drawBuyer?.brief,
      'ins': b3ins?.brief,
      'nWin': winAfterDouble,
    });
  }
  c.probe(
    id: 'B3.winner.forge.double',
    poco: 'DR-B',
    payload: 'draw JWT buyer+S2; POST winners; draw seller×2',
    http:
        '${b3drawBuyer?.brief ?? 'n/a'} | ${b3ins?.brief ?? 'n/a'} | ${b3draw1?.brief ?? 'n/a'} | ${b3draw2?.brief ?? 'n/a'}',
    bd: {
      'nWinForge': winAfterForge,
      'nWinDouble': winAfterDouble,
      'close': b3close?.brief,
      'join': b3join?.brief,
    },
    result: (forgeOk || doubleAssign) ? 'FAIL' : 'HOLD',
    lens: 'DR2',
    classeNova: true,
    countFinding: forgeOk || doubleAssign,
  );

  // =====================================================================
  // DR-C Convert / hitch
  // =====================================================================

  // C1 — convert pending (não accepted) → order
  final liveC1 = await c.createLive(title: '$prefix c1-pending');
  final skuC1 =
      await c.createProduct(title: '$prefix c1 sku', qty: 1, live: true, price: 9);
  final itemC1 = (liveC1 == null || skuC1 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC1,
          title: '$prefix c1',
          ref: 'RTDR-C1',
          kind: 'live_only',
          checkoutProductId: skuC1,
          quantity: 1,
        );
  String? rC1;
  HttpHit? c1rpc;
  HttpHit? c1cpi;
  Map<String, dynamic>? c1row;
  Map<String, dynamic>? c1ord;
  if (liveC1 != null && itemC1 != null && skuC1 != null) {
    rC1 = await c.insertReservation(
      liveId: liveC1,
      liveItemId: itemC1,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    c1rpc = rC1 == null ? null : await c.convertRpc(rC1);
    final oid = await c.insertOrder(
      productId: skuC1,
      buyer: b1,
      jwt: c.buyerJwt,
      price: 9,
      liveId: liveC1,
      liveItemId: itemC1,
    );
    c1cpi = (oid == null || rC1 == null)
        ? null
        : await c.checkout(
            orderId: oid,
            buyer: b1,
            jwt: c.buyerJwt,
            amount: 1,
            productId: skuC1,
            seller: s1,
            extra: {
              'live_id': liveC1,
              'live_item_id': itemC1,
              'reservation_request_id': rC1,
              'is_live': true,
              'live_seller_id': s1,
            },
          );
    c1row = rC1 == null ? null : await c.resRow(rC1);
    c1ord = oid == null ? null : await c.orderRow(oid);
  }
  final c1converted = c1row?['status'] == 'converted';
  final c1paid = c1ord?['status'] == 'pago';
  if (c1converted || c1paid) {
    c.hold(
      id: 'C1.convert.pending',
      lens: 'DR3',
      severity: 'P0',
      title: 'Convert pending→order sem accept/PI',
      actor: 'seller RPC + buyer CPI',
      pre: 'reservation pending',
      repro: 'stripe_convert + CPI reservation_request_id pending',
      expected: 'convert_requires_paid_order / not accepted; ≠converted ≠pago',
      obtained: {
        'rpc': c1rpc?.brief,
        'cpi': c1cpi?.brief,
        'res': c1row,
        'ord': c1ord?['status'],
      },
    );
  } else {
    c.block('C1.convert.pending', 'DR3', 'pending não converteu', {
      'rpc': c1rpc?.brief,
      'cpi': c1cpi?.brief,
      'status': c1row?['status'],
    });
  }
  c.probe(
    id: 'C1.convert.pending',
    poco: 'DR-C',
    payload: 'convert RPC + CPI em reservation pending',
    http: '${c1rpc?.brief ?? 'n/a'} | ${c1cpi?.brief ?? 'n/a'}',
    bd: {'res': c1row, 'ord': c1ord?['status']},
    result: (c1converted || c1paid) ? 'FAIL' : 'HOLD',
    lens: 'DR3',
    classeNova: true,
    countFinding: c1converted || c1paid,
  );

  // C2 — convert∥convert 2 buyers (+ IDOR reservation alheia)
  final liveC2 = await c.createLive(title: '$prefix c2-race');
  final skuC2 =
      await c.createProduct(title: '$prefix c2 sku', qty: 1, live: true, price: 9);
  final itemC2 = (liveC2 == null || skuC2 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC2,
          title: '$prefix c2',
          ref: 'RTDR-C2',
          kind: 'live_only',
          checkoutProductId: skuC2,
          quantity: 1,
        );
  String? rC2a;
  String? rC2b;
  HttpHit? c2accA;
  if (liveC2 != null && itemC2 != null) {
    rC2a = await c.insertReservation(
      liveId: liveC2,
      liveItemId: itemC2,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    rC2b = await c.insertReservation(
      liveId: liveC2,
      liveItemId: itemC2,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
    if (rC2a != null) c2accA = await c.accept(rC2a);
  }
  HttpHit? c2cpi1;
  HttpHit? c2cpi2;
  HttpHit? c2rpc1;
  HttpHit? c2rpc2;
  String? oidC2a;
  String? oidC2b;
  if (skuC2 != null && liveC2 != null && itemC2 != null && rC2a != null) {
    oidC2a = await c.insertOrder(
      productId: skuC2,
      buyer: b1,
      jwt: c.buyerJwt,
      price: 9,
      liveId: liveC2,
      liveItemId: itemC2,
    );
    oidC2b = await c.insertOrder(
      productId: skuC2,
      buyer: b2,
      jwt: c.buyer2Jwt,
      price: 9,
      liveId: liveC2,
      liveItemId: itemC2,
    );
    final extraA = {
      'live_id': liveC2,
      'live_item_id': itemC2,
      'reservation_request_id': rC2a,
      'is_live': true,
      'live_seller_id': s1,
    };
    final extraB = {
      'live_id': liveC2,
      'live_item_id': itemC2,
      'reservation_request_id': rC2a, // IDOR: B2 usa res de B1
      'is_live': true,
      'live_seller_id': s1,
    };
    final raced = await Future.wait([
      oidC2a == null
          ? Future.value(HttpHit(0, 'no-oid-a', null))
          : c.checkout(
              orderId: oidC2a,
              buyer: b1,
              jwt: c.buyerJwt,
              amount: 1,
              productId: skuC2,
              seller: s1,
              extra: extraA,
            ),
      oidC2b == null
          ? Future.value(HttpHit(0, 'no-oid-b', null))
          : c.checkout(
              orderId: oidC2b,
              buyer: b2,
              jwt: c.buyer2Jwt,
              amount: 1,
              productId: skuC2,
              seller: s1,
              extra: extraB,
            ),
      c.convertRpc(rC2a),
      rC2b == null
          ? Future.value(HttpHit(0, 'no-res-b', null))
          : c.convertRpc(rC2b),
    ]);
    c2cpi1 = raced[0];
    c2cpi2 = raced[1];
    c2rpc1 = raced[2];
    c2rpc2 = raced[3];
  }
  final rowA = rC2a == null ? null : await c.resRow(rC2a);
  final rowB = rC2b == null ? null : await c.resRow(rC2b);
  final ordA = oidC2a == null ? null : await c.orderRow(oidC2a);
  final ordB = oidC2b == null ? null : await c.orderRow(oidC2b);
  final nConv = [
    rowA?['status'] == 'converted',
    rowB?['status'] == 'converted',
  ].where((x) => x).length;
  final nPago = [
    ordA?['status'] == 'pago',
    ordB?['status'] == 'pago',
  ].where((x) => x).length;
  final c2fail = nConv > 1 || nPago > 0 || rowB?['status'] == 'converted';
  if (c2fail) {
    c.hold(
      id: 'C2.convert.parallel',
      lens: 'DR4',
      severity: 'P0',
      title: 'convert∥convert / IDOR criou double order ou convert alheio',
      actor: 'B1 CPI ∥ B2 CPI(res B1) ∥ RPC×2',
      pre: 'qty=1; só B1 accepted',
      repro: 'Future.wait 2 CPI + 2 stripe_convert',
      expected: '≤1 convert; B2 não converted; nenhum pago unpaid',
      obtained: {
        'resA': rowA,
        'resB': rowB,
        'ordA': ordA?['status'],
        'ordB': ordB?['status'],
      },
    );
  } else {
    c.block('C2.convert.parallel', 'DR4', 'race convert sem double', {
      'resA': rowA?['status'],
      'resB': rowB?['status'],
      'nConv': nConv,
    });
  }
  c.probe(
    id: 'C2.convert.parallel',
    poco: 'DR-C',
    payload: 'CPI B1 ∥ CPI B2(res B1) ∥ convert RPC B1 ∥ convert RPC B2',
    http:
        '${c2cpi1?.brief ?? 'n/a'} | ${c2cpi2?.brief ?? 'n/a'} | ${c2rpc1?.brief ?? 'n/a'} | ${c2rpc2?.brief ?? 'n/a'} | acc=${c2accA?.brief}',
    bd: {
      'resA': rowA,
      'resB': rowB,
      'ordA': ordA?['status'],
      'ordB': ordB?['status'],
      'nConv': nConv,
    },
    result: c2fail ? 'FAIL' : 'HOLD',
    lens: 'DR4',
    classeNova: true,
    race: true,
    countFinding: c2fail,
  );

  // C3 — accept ∥ marketplace CPI qty=1 hitch
  final liveC3 = await c.createLive(title: '$prefix c3-hitch');
  final skuC3 = await c.createProduct(
      title: '$prefix c3 mkt', qty: 1, live: false, price: 9);
  final liM = (liveC3 == null || skuC3 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC3,
          title: '$prefix c3 mkt',
          ref: 'RTDR-C3M',
          kind: 'marketplace_product',
          productId: skuC3,
          checkoutProductId: skuC3,
        );
  final liL = (liveC3 == null || skuC3 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC3,
          title: '$prefix c3 live',
          ref: 'RTDR-C3L',
          kind: 'live_only',
          checkoutProductId: skuC3,
          quantity: 1,
        );
  String? rC3;
  HttpHit? c3acc;
  HttpHit? c3cpi;
  String? oidC3;
  if (liveC3 != null && liL != null) {
    rC3 = await c.insertReservation(
      liveId: liveC3,
      liveItemId: liL,
      jwt: c.buyerJwt,
      buyer: b1,
    );
  }
  if (skuC3 != null) {
    oidC3 = await c.insertOrder(
      productId: skuC3,
      buyer: b2,
      jwt: c.buyer2Jwt,
      price: 9,
    );
  }
  if (rC3 != null && oidC3 != null && skuC3 != null) {
    final raced = await Future.wait([
      c.accept(rC3),
      c.checkout(
        orderId: oidC3,
        buyer: b2,
        jwt: c.buyer2Jwt,
        amount: 1,
        productId: skuC3,
        seller: s1,
      ),
    ]);
    c3acc = raced[0];
    c3cpi = raced[1];
  }
  final rowC3 = rC3 == null ? null : await c.resRow(rC3);
  final ordC3 = oidC3 == null ? null : await c.orderRow(oidC3);
  final prodC3 = skuC3 == null ? null : await c.productQty(skuC3);
  final bothSold = rowC3?['status'] == 'converted' &&
      (ordC3?['status'] == 'pago' || c3cpi?.ok == true);
  // FAIL only if both paths consumed unique qty=1 as paid/converted
  final c3oversell = rowC3?['status'] == 'converted' &&
      ordC3?['status'] == 'pago';
  if (c3oversell) {
    c.hold(
      id: 'C3.accept.cpi.race',
      lens: 'DR4',
      severity: 'P0',
      title: 'accept∥CPI qty=1 oversell hitch',
      actor: 'seller accept ∥ B2 marketplace CPI',
      pre: 'SKU qty=1 hitch live_only+marketplace',
      repro: 'Future.wait PATCH accepted + create-payment-intent',
      expected: 'um lado recusa ou ambos unpaid/accepted sem double pago',
      obtained: {
        'res': rowC3,
        'ord': ordC3,
        'prod': prodC3,
        'acc': c3acc?.brief,
        'cpi': c3cpi?.brief,
      },
    );
  } else {
    c.block('C3.accept.cpi.race', 'DR4', 'accept∥CPI sem oversell pago', {
      'res': rowC3?['status'],
      'ord': ordC3?['status'],
      'cpiOk': c3cpi?.ok,
    });
  }
  c.probe(
    id: 'C3.accept.cpi.race',
    poco: 'DR-C',
    payload: 'accept live_only ∥ marketplace CPI mesmo SKU qty=1',
    http: '${c3acc?.brief ?? 'n/a'} | ${c3cpi?.brief ?? 'n/a'} liM=$liM',
    bd: {'res': rowC3, 'ord': ordC3?['status'], 'prod': prodC3, 'bothSold': bothSold},
    result: c3oversell ? 'FAIL' : 'HOLD',
    lens: 'DR4',
    classeNova: true,
    race: true,
    countFinding: c3oversell,
  );

  // C4 — convert após live ended
  final liveC4 = await c.createLive(title: '$prefix c4-ended');
  final skuC4 =
      await c.createProduct(title: '$prefix c4 sku', qty: 1, live: true, price: 9);
  final itemC4 = (liveC4 == null || skuC4 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC4,
          title: '$prefix c4',
          ref: 'RTDR-C4',
          kind: 'live_only',
          checkoutProductId: skuC4,
          quantity: 1,
        );
  String? rC4;
  HttpHit? c4acc;
  HttpHit? c4rpc;
  HttpHit? c4patch;
  HttpHit? c4cpi;
  if (liveC4 != null && itemC4 != null) {
    rC4 = await c.insertReservation(
      liveId: liveC4,
      liveItemId: itemC4,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    if (rC4 != null) c4acc = await c.accept(rC4);
    await c.endLive(liveC4);
    c4rpc = rC4 == null ? null : await c.convertRpc(rC4);
    c4patch = rC4 == null
        ? null
        : await c.rest(
            'PATCH',
            'live_reservation_requests?id=eq.$rC4',
            jwt: c.sellerJwt,
            body: {'status': 'converted'},
          );
    if (skuC4 != null && rC4 != null) {
      final oid = await c.insertOrder(
        productId: skuC4,
        buyer: b1,
        jwt: c.buyerJwt,
        price: 9,
        liveId: liveC4,
        liveItemId: itemC4,
      );
      c4cpi = oid == null
          ? null
          : await c.checkout(
              orderId: oid,
              buyer: b1,
              jwt: c.buyerJwt,
              amount: 1,
              productId: skuC4,
              seller: s1,
              extra: {
                'live_id': liveC4,
                'live_item_id': itemC4,
                'reservation_request_id': rC4,
                'is_live': true,
                'live_seller_id': s1,
              },
            );
    }
  }
  final rowC4 = rC4 == null ? null : await c.resRow(rC4);
  final c4conv = rowC4?['status'] == 'converted';
  if (c4conv) {
    c.hold(
      id: 'C4.convert.after.ended',
      lens: 'DR6',
      severity: 'P1',
      title: 'Convert após live ended',
      actor: 'seller RPC + PATCH + CPI',
      pre: 'accepted depois end_live',
      repro: 'end_live; stripe_convert; PATCH converted; CPI',
      expected: '≠converted (paid_order / live_ended)',
      obtained: {
        'rpc': c4rpc?.brief,
        'patch': c4patch?.brief,
        'cpi': c4cpi?.brief,
        'row': rowC4,
        'acc': c4acc?.brief,
      },
    );
  } else {
    c.block('C4.convert.after.ended', 'DR6', 'convert pós-ended recusado', {
      'rpc': c4rpc?.brief,
      'patch': c4patch?.brief,
      'status': rowC4?['status'],
    });
  }
  c.probe(
    id: 'C4.convert.after.ended',
    poco: 'DR-C',
    payload: 'end_live depois accepted; RPC+PATCH+CPI convert',
    http:
        '${c4rpc?.brief ?? 'n/a'} | ${c4patch?.brief ?? 'n/a'} | ${c4cpi?.brief ?? 'n/a'}',
    bd: rowC4,
    result: c4conv ? 'FAIL' : 'HOLD',
    lens: 'DR6',
    countFinding: c4conv,
  );

  // C5 — converted capacity vs stock
  final liveC5 = await c.createLive(title: '$prefix c5-cap');
  final skuC5 =
      await c.createProduct(title: '$prefix c5 sku', qty: 1, live: true, price: 9);
  final itemC5 = (liveC5 == null || skuC5 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC5,
          title: '$prefix c5',
          ref: 'RTDR-C5',
          kind: 'live_only',
          checkoutProductId: skuC5,
          quantity: 1,
        );
  String? rC5a;
  String? rC5b;
  HttpHit? c5acc;
  HttpHit? c5rpc;
  Map<String, dynamic>? stBefore;
  Map<String, dynamic>? stAfter;
  if (liveC5 != null && itemC5 != null) {
    rC5a = await c.insertReservation(
      liveId: liveC5,
      liveItemId: itemC5,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    if (rC5a != null) c5acc = await c.accept(rC5a);
    stBefore = await c.stock(itemC5);
    c5rpc = rC5a == null ? null : await c.convertRpc(rC5a);
    rC5b = await c.insertReservation(
      liveId: liveC5,
      liveItemId: itemC5,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
    stAfter = await c.stock(itemC5);
  }
  final rowC5a = rC5a == null ? null : await c.resRow(rC5a);
  final rowC5b = rC5b == null ? null : await c.resRow(rC5b);
  final c5convertedUnpaid = rowC5a?['status'] == 'converted';
  final c5double = rowC5b?['status'] == 'accepted' ||
      rowC5b?['status'] == 'converted';
  if (c5convertedUnpaid || c5double) {
    c.hold(
      id: 'C5.capacity.vs.stock',
      lens: 'DR5',
      severity: 'P0',
      title: 'Convert unpaid ou 2ª reserva aceita com qty=1',
      actor: 'seller convert + B2 reserve',
      pre: 'accepted qty=1 sem PI',
      repro: 'stripe_convert unpaid; 2ª reservation',
      expected: 'status=accepted; 2ª não accepted/converted',
      obtained: {
        'a': rowC5a,
        'b': rowC5b,
        'rpc': c5rpc?.brief,
        'stock0': stBefore,
        'stock1': stAfter,
      },
    );
  } else {
    c.block('C5.capacity.vs.stock', 'DR5', 'capacity coerente sem convert unpaid', {
      'a': rowC5a?['status'],
      'b': rowC5b?['status'],
      'acc': c5acc?.brief,
    });
  }
  c.probe(
    id: 'C5.capacity.vs.stock',
    poco: 'DR-C',
    payload: 'accepted qty=1; convert unpaid; 2º buyer reserve',
    http: '${c5rpc?.brief ?? 'n/a'} | acc=${c5acc?.brief}',
    bd: {'a': rowC5a, 'b': rowC5b, 'stock0': stBefore, 'stock1': stAfter},
    result: (c5convertedUnpaid || c5double) ? 'FAIL' : 'HOLD',
    lens: 'DR5',
    countFinding: c5convertedUnpaid || c5double,
  );

  // =====================================================================
  // DR-D Caixa
  // =====================================================================

  // D1 — tip Session TEST + settle unpaid + race tip∥unpublish
  final liveD1 = await c.createLive(title: '$prefix d1-session');
  final wD1b = await c.walletBal(s1);
  HttpHit? d1create;
  HttpHit? d1unpub;
  HttpHit? d1settle;
  if (liveD1 != null) {
    final raced = await Future.wait([
      c.tipCheckout(liveId: liveD1, seller: s1, amountEur: 2, jwt: c.buyerJwt),
      () async {
        await c.setHub(s1, false);
        return HttpHit(200, 'unpublish', {'ok': true});
      }(),
    ]);
    d1create = raced[0];
    d1unpub = raced[1];
    if (d1create.tipId != null) c.createdTipIds.add(d1create.tipId!);
    if (d1create.sessionId != null) {
      d1settle = await c.tipSettle(d1create.sessionId!);
    }
  }
  await c.restoreSeller1Published();
  Map<String, dynamic>? d1tip;
  if (d1create?.tipId != null) {
    d1tip = await c.tipRow(d1create!.tipId!);
  }
  final wD1a = await c.walletBal(s1);
  final d1paid = d1tip?['status'] == 'paid' ||
      d1tip?['status'] == 'settled' ||
      (wD1a - wD1b) > 0;
  if (d1paid) {
    c.hold(
      id: 'D1.tip.session.test',
      lens: 'DR7',
      severity: 'P0',
      title: 'Tip Session unpaid / race unpublish creditou',
      actor: 'buyer JWT',
      pre: 'live broadcasting; Stripe TEST sem captura 4242 (sem sk_test local)',
      repro: 'POST tip ∥ unpublish; GET settle unpaid',
      expected: 'cs_test pending; settle unpaid; Δ=0',
      obtained: {
        'create': d1create?.brief,
        'settle': d1settle?.brief,
        'tip': d1tip,
        'dWallet': wD1a - wD1b,
      },
    );
  } else {
    c.block('D1.tip.session.test', 'DR7', 'Session TEST pending Δ=0', {
      'create': d1create?.brief,
      'settle': d1settle?.brief,
      'status': d1tip?['status'],
      'dWallet': wD1a - wD1b,
    });
  }
  c.probe(
    id: 'D1.tip.session.test',
    poco: 'DR-D',
    payload: 'POST tip Session TEST ∥ hub unpublish; GET settle unpaid',
    http: '${d1create?.brief ?? 'n/a'} | ${d1settle?.brief ?? 'n/a'} | ${d1unpub?.brief}',
    bd: {
      'tip': d1tip,
      'dWallet': wD1a - wD1b,
      'sid': d1create?.sessionId,
      'skip_paid_4242': 'no_sk_test_local',
    },
    result: d1paid ? 'FAIL' : 'HOLD',
    lens: 'DR7',
    race: true,
    countFinding: d1paid,
  );

  // D2 — convert feliz + order ledger (CPI em accepted → order; unpaid ≠ converted)
  final liveD2 = await c.createLive(title: '$prefix d2-happy');
  final skuD2 =
      await c.createProduct(title: '$prefix d2 sku', qty: 2, live: true, price: 9);
  final itemD2 = (liveD2 == null || skuD2 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveD2,
          title: '$prefix d2',
          ref: 'RTDR-D2',
          kind: 'live_only',
          checkoutProductId: skuD2,
          quantity: 2,
        );
  String? rD2;
  HttpHit? d2acc;
  HttpHit? d2cpi;
  HttpHit? d2settle;
  String? oidD2;
  if (liveD2 != null && itemD2 != null && skuD2 != null) {
    rD2 = await c.insertReservation(
      liveId: liveD2,
      liveItemId: itemD2,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    if (rD2 != null) d2acc = await c.accept(rD2);
    oidD2 = await c.insertOrder(
      productId: skuD2,
      buyer: b1,
      jwt: c.buyerJwt,
      price: 9,
      liveId: liveD2,
      liveItemId: itemD2,
    );
    d2cpi = oidD2 == null || rD2 == null
        ? null
        : await c.checkout(
            orderId: oidD2,
            buyer: b1,
            jwt: c.buyerJwt,
            amount: 1,
            productId: skuD2,
            seller: s1,
            extra: {
              'live_id': liveD2,
              'live_item_id': itemD2,
              'reservation_request_id': rD2,
              'is_live': true,
              'live_seller_id': s1,
            },
          );
    if (d2cpi?.sessionId != null) {
      d2settle = await c.edge(
        'create-payment-intent',
        method: 'GET',
        qs: 'checkout_return=success&session_id=${d2cpi!.sessionId}',
      );
    }
  }
  final rowD2 = rD2 == null ? null : await c.resRow(rD2);
  final ordD2 = oidD2 == null ? null : await c.orderRow(oidD2);
  final d2ledger = oidD2 != null && ordD2 != null;
  final d2premature = rowD2?['status'] == 'converted' ||
      ordD2?['status'] == 'pago';
  if (d2premature) {
    c.hold(
      id: 'D2.convert.feliz.ledger',
      lens: 'DR3',
      severity: 'P0',
      title: 'Convert/ledger pago sem Stripe TEST paid',
      actor: 'buyer CPI accepted',
      pre: 'reservation accepted qty=2',
      repro: 'CPI + GET settle unpaid',
      expected: 'order reserva_pendente; res accepted ≠converted',
      obtained: {'res': rowD2, 'ord': ordD2, 'cpi': d2cpi?.brief},
    );
  } else if (!d2ledger) {
    c.note('D2.ledger.missing', 'CPI não criou order', {
      'acc': d2acc?.brief,
      'cpi': d2cpi?.brief,
      'oid': oidD2,
    }, lens: 'DR3');
  } else {
    c.block('D2.convert.feliz.ledger', 'DR3', 'order ledger unpaid; ≠converted', {
      'ord': ordD2?['status'],
      'res': rowD2?['status'],
      'sid': d2cpi?.sessionId,
    });
  }
  c.probe(
    id: 'D2.convert.feliz.ledger',
    poco: 'DR-D',
    payload: 'accepted → CPI live reservation → order ledger; settle unpaid',
    http:
        '${d2acc?.brief ?? 'n/a'} | ${d2cpi?.brief ?? 'n/a'} | ${d2settle?.brief ?? 'n/a'}',
    bd: {
      'res': rowD2,
      'ord': ordD2,
      'sid': d2cpi?.sessionId,
      'ledger': d2ledger,
    },
    result: d2premature
        ? 'FAIL'
        : (d2ledger ? 'HOLD' : 'SKIP'),
    lens: 'DR3',
    countFinding: d2premature,
  );

  await c.endAllCreatedLives();
  await c.restoreSeller1Published();
  for (final id in c.createdRaffleIds) {
    await c.rest(
      'PATCH',
      'live_raffles?id=eq.$id',
      service: true,
      body: {'status': 'cancelled'},
      prefer: 'return=minimal',
    );
  }

  final counted = c.findings.where((f) => f['proven'] == true).toList();
  final p0 = counted.where((f) => f['severity'] == 'P0').length;
  final p1 = counted.where((f) => f['severity'] == 'P1').length;
  final p2 = counted.where((f) => f['severity'] == 'P2').length;
  final p3 = counted.where((f) => f['severity'] == 'P3').length;
  final nova = c.probes.where((p) => p['classe_nova'] == true).length;
  final races = c.probes.where((p) => p['race'] == true).length;

  final out = {
    'auditor': 'REDTEAM_BLIND_DR_TIP_RAFFLE_POS_DHDM_v1',
    'prefix': prefix,
    'staging': projectMust,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'probes_na_tabela': c.probes.length,
    'classes_novas': nova,
    'races': races,
    'lentes': c.lensesHit.toList()..sort(),
    'P0': p0,
    'P1': p1,
    'P2': p2,
    'P3': p3,
    'TOTAL': p0 + p1 + p2 + p3,
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  };
  await dumpJson('${outDir()}/pass1.json', out);
  stdout.writeln(
    'DONE probes=${c.probes.length} nova=$nova races=$races '
    'P0=$p0 P1=$p1 P2=$p2 P3=$p3 findings=${c.findings.length}',
  );
}
