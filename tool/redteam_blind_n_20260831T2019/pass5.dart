import 'dart:io';

import '_rtn.dart';

/// Pass 5 — chain P0: convert spoofed accept → order; buyer blocked after reserved_full.
void main() async {
  final c = Rtn.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{'pass': 5, 'stamp': stamp};

  const spoofId = 'bb15b97a-cd34-4be9-919f-224396f9679a';
  final convOld = await c.rpc(
    'batata_live_reservation_stripe_convert',
    {
      'p_request_id': spoofId,
      'p_order_id': '00000000-0000-0000-0000-000000000099',
    },
    jwt: c.seller2Jwt,
  );
  c.note('p5.conv.old', 'convert pass4 spoof (live maybe ended)', convOld.brief,
      lens: 'N8');
  out['conv.old'] = convOld.json ?? convOld.snippet;

  final liveA = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    muxPlayback: 'rtn5_pb_$stamp',
  );
  final itemH = await c.rest('POST', 'live_items', service: true, body: {
    'live_id': liveA,
    'ref_code': 'RTN5A',
    'title': '$prefix a',
    'price': 15,
    'is_active': true,
    'quantity': 1,
    'status': 'available',
  });
  final itemA = itemH.firstId;
  if (itemA != null) c.createdLiveItemIds.add(itemA);

  final spoof = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.seller2Jwt,
    body: {
      'live_id': liveA,
      'live_item_id': itemA,
      'seller_id': c.seller2Id,
      'buyer_id': c.seller2Id,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
    },
  );
  out['spoof'] = spoof.map;
  c.note('p5.spoof', 'S2 spoof accept qty1', spoof.brief, lens: 'N5');

  final conv = spoof.firstId == null
      ? null
      : await c.rpc(
          'batata_live_reservation_stripe_convert',
          {'p_request_id': spoof.firstId},
          jwt: c.seller2Jwt,
        );
  if (conv != null) {
    c.note('p5.conv', 'S2 stripe_convert without order', conv.brief, lens: 'N8');
    out['conv'] = conv.json ?? conv.snippet;
    if (conv.ok && conv.map?['ok'] == true) {
      c.finding(
        id: 'RTN-n8.convert.free',
        lens: 'N8',
        severity: 'P0',
        title: 'S2 converte reserva spoofed para converted sem pagamento Stripe',
        actor: 'seller2',
        pre: 'reserva accepted via seller_id spoof',
        repro: 'rpc batata_live_reservation_stripe_convert',
        expected: 'só webhook/Edge após captura',
        obtained: conv.brief,
      );
    }
  }

  final bagB = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveA,
      'live_item_id': itemA,
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
    },
  );
  c.note('p5.buyer.bag', 'legit buyer bag after spoof', bagB.brief, lens: 'N8');
  out['buyer.bag'] = bagB.map ?? bagB.snippet;

  final accOwner = spoof.firstId == null
      ? null
      : await c.rpc(
          'batata_process_live_reservation_request',
          {
            'p_request_id': spoof.firstId,
            'p_action': 'reject',
            'p_processed_by': c.sellerId,
          },
          jwt: c.sellerJwt,
        );
  if (accOwner != null) {
    c.note('p5.owner.reject', 'real seller reject spoof', accOwner.brief,
        lens: 'N5');
    out['owner.reject'] = accOwner.json ?? accOwner.snippet;
  }

  final stock = await c.rpc(
    'batata_live_item_stock',
    {'p_live_item_id': itemA},
    jwt: c.sellerJwt,
  );
  out['stock'] = stock.json;
  c.note('p5.stock', 'stock final', stock.brief, lens: 'N5');

  final pi = spoof.firstId == null
      ? null
      : await c.edge(
          'create-payment-intent',
          body: {
            'live_reservation_request_id': spoof.firstId,
            'live_item_id': itemA,
            'qty': 1,
          },
          jwt: c.seller2Jwt,
        );
  if (pi != null) {
    c.note('p5.pi', 'S2 create-payment-intent on spoof', pi.brief, lens: 'N8');
    out['pi'] = pi.brief;
  }

  await c.endLives();
  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  await dumpJson('${outDir()}/pass5.json', out);
  stdout.writeln('FINDINGS ${c.findings.length}');
  stdout.writeln('WROTE ${outDir()}/pass5.json');
}
