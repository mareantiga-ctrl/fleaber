/// PASS 5 — G5 via RPC upsert live item + convert expired reservation.
import 'dart:io';
import '_rtg.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtg.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();

  final live = await c.insertLive(active: true);
  final p = await c.insertProduct(
    title: '$prefix g5-upsert',
    qty: 2,
    live: true,
    listed: true,
  );
  final up = await c.rpc(
    'batata_upsert_marketplace_live_item',
    {
      'p_seller_id': c.sellerId,
      'p_product_id': p,
      'p_live_id': live,
    },
    jwt: c.sellerJwt,
  );
  c.note('p5.upsert', 'upsert live item', up.brief, lens: 'G5');
  final itemId = up.body.replaceAll('"', '').trim();
  final uuid = RegExp(
          r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
      .firstMatch(itemId)
      ?.group(0);

  if (uuid != null && live != null) {
    final resv = await c.rest(
      'POST',
      'live_reservation_requests',
      jwt: c.buyerJwt,
      body: {
        'live_id': live,
        'live_item_id': uuid,
        'seller_id': c.sellerId,
        'buyer_id': c.buyerId,
        'requested_qty': 1,
        'source': 'fleaber_live',
        'status': 'pending',
      },
    );
    c.note('p5.resv', 'INSERT resv', resv.brief, lens: 'G5');
    final rid = resv.firstId;
    if (rid != null) {
      await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rid',
        service: true,
        body: {
          'expires_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 12))
              .toIso8601String(),
        },
      );
      final acc = await c.rpc(
        'batata_process_live_reservation_request',
        {'p_request_id': rid, 'p_action': 'accept'},
        jwt: c.sellerJwt,
      );
      final conv = await c.rpc(
        'batata_live_reservation_stripe_convert',
        {'p_request_id': rid},
        jwt: c.buyerJwt,
      );
      final convX = await c.rpc(
        'batata_live_reservation_stripe_convert',
        {'p_request_id': rid},
        jwt: c.buyer2Jwt,
      );
      final row = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rid&select=id,status,expires_at,buyer_id',
        service: true,
      );
      c.note('p5.ttl', 'accept/convert expired', {
        'accept': acc.brief,
        'convert': conv.brief,
        'convert_b2': convX.brief,
        'row': row.map,
      }, lens: 'G5');
      final st = '${row.map?['status']}'.toLowerCase();
      if (st == 'accepted' || st == 'converted') {
        c.hold(
          id: 'RTG-G5-002',
          lens: 'G5',
          severity: 'P1',
          title: 'Reserva live aceite/convertida com expires_at no passado',
          actor: 'seller + buyer JWT',
          pre: 'expires_at -12m',
          repro: 'process accept; stripe_convert',
          expected: 'expired',
          obtained: row.map,
        );
      }
      if (convX.ok && convX.map?['ok'] == true) {
        c.hold(
          id: 'RTG-G5-004',
          lens: 'G5',
          severity: 'P1',
          title: '2.º buyer converte reserva alheia',
          actor: 'buyer2 JWT',
          pre: 'resv buyer1',
          repro: 'stripe_convert',
          expected: 'not_allowed',
          obtained: convX.brief,
        );
      }
    }
  }

  // Human review isolation (no cron race)
  final paid = await c.e2e('setup_paid_order', {'initial_qty': 2});
  final pm = paid.map ?? {};
  final oid = pm['order_id']?.toString();
  if (oid != null) {
    await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
      'status': 'enviado',
    });
    await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
      'status': 'concluido',
    });
    final rev = await c.rest('POST', 'reviews', jwt: c.buyerJwt, body: {
      'order_id': oid,
      'target_id': c.sellerId,
      'stars': 5,
      'author_role': 'comprador',
      'comment': '$prefix human-only',
    });
    final row = await c.orderRow(oid);
    c.note('p5.human_review', 'review sem cron', {
      'rev': rev.brief,
      'release': row?['wallet_release_processed_at'],
      'status': row?['status'],
    }, lens: 'G8');
    if (!rev.ok && rev.body.contains('wallet_release')) {
      c.hold(
        id: 'RTG-G8-004',
        lens: 'G8',
        severity: 'P1',
        title:
            'Review humana 5★ bloqueada — só o cron (service_role) liberta a carteira',
        actor: 'buyer JWT',
        pre: 'order concluido pago TEST; sem esperar 48h',
        repro: 'POST reviews stars=5 author_role=comprador',
        expected: '201 review + wallet_release_processed_at',
        obtained: {'rev': rev.brief, 'order': row},
      );
    }
  }

  await c.endLives();
  await dumpJson('tool/redteam_blind_g_20260831T1253/pass5.json', {
    'findings': c.findings,
    'notes': c.notes,
  });
  stdout.writeln('PASS5 findings=${c.findings.length}');
}
