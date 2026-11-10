// ignore_for_file: avoid_print
/// Pass 3 — saturação: storage público, dual-pool qty, collusion review, role check.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const stamp = '20260829T1435';

late String base, anon, service, buyerId, sellerId, buyerJwt, sellerJwt;
late LiveOpsStagingClient sb;
final findings = <Map<String, dynamic>>[];
final rec = <String, dynamic>{};

String clip(String s, [int n = 400]) {
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

Map<String, String> hUser(String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
Map<String, String> hSvc() => {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
Map<String, String> hAnon() => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
    };

Future<http.Response> rest(
  String m,
  String path, {
  Map<String, String>? headers,
  Object? body,
}) {
  final uri = Uri.parse(path.startsWith('http') ? path : '$base$path');
  final h = headers ?? hAnon();
  final b = body == null ? null : jsonEncode(body);
  switch (m) {
    case 'GET':
      return http.get(uri, headers: h);
    case 'POST':
      return http.post(uri, headers: h, body: b);
    case 'PATCH':
      return http.patch(uri, headers: h, body: b);
    default:
      throw ArgumentError(m);
  }
}

dynamic dec(http.Response r) {
  if (r.body.isEmpty) return null;
  try {
    return jsonDecode(r.body);
  } catch (_) {
    return r.body;
  }
}

Map<String, dynamic>? row(dynamic d) {
  if (d is List && d.isNotEmpty && d.first is Map) {
    return Map<String, dynamic>.from(d.first as Map);
  }
  if (d is Map && d['id'] != null) return Map<String, dynamic>.from(d);
  return null;
}

void find(String id, String sev, String title, Map<String, dynamic> extra) {
  findings.add({'id': id, 'severity': sev, 'title': title, ...extra});
  print('FINDING $sev $id — $title');
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  sb = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: service,
  );
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  // Role leftover
  final me = await rest(
    'GET',
    '/rest/v1/profiles?id=eq.$buyerId&select=id,user_type',
    headers: hUser(buyerJwt),
  );
  rec['buyer_type_now'] = clip(me.body, 120);
  final t = row(dec(me));
  if ('${t?['user_type']}'.toLowerCase().contains('vend')) {
    await rest(
      'PATCH',
      '/rest/v1/profiles?id=eq.$buyerId',
      headers: hSvc(),
      body: {'user_type': 'comprador'},
    );
  }

  // Public CDN of chat_uploads we planted
  final pubPath =
      'chat_uploads/dc186402-cad0-42aa-bd1c-0a6d649c4f4f/rtb2_20260829T1435.txt';
  final pub = await http.get(
    Uri.parse('$base/storage/v1/object/public/chat_media/$pubPath'),
  );
  rec['public_chat_upload_get'] = {
    'http': pub.statusCode,
    'body': clip(pub.body, 120),
  };
  if (pub.statusCode == 200 && pub.body.contains('SECRET')) {
    find('RTB2-STOR-04', 'P1', 'Objecto chat_uploads no bucket público é GET anon', {
      'actor': 'anon',
      'result': {'http': 200, 'body_prefix': clip(pub.body, 40)},
      'impact': 'Quem souber o path lê media de chat (UUID + filename).',
    });
  }

  // JWT buyer upload to chat_media/chat_uploads/other
  final up = await http.post(
    Uri.parse(
      '$base/storage/v1/object/chat_media/chat_uploads/$sellerId/rtb2_jwt_$stamp.jpg',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'image/jpeg',
      'x-upsert': 'true',
    },
    body: [0xFF, 0xD8, 0xFF, 0xD9],
  );
  rec['buyer_upload_other_chat_media'] = {
    'http': up.statusCode,
    'body': clip(up.body, 200),
  };

  // live_items sample columns
  final lis = await sb.select('live_items', limit: 1);
  rec['live_item_keys'] = lis.isEmpty ? [] : lis.first.keys.toList();

  Map<String, dynamic>? liTpl = lis.isEmpty ? null : lis.first;
  if (liTpl != null) {
    final prodIns = await rest(
      'POST',
      '/rest/v1/products',
      headers: hUser(sellerJwt),
      body: {
        'seller_id': sellerId,
        'title': 'RTB2 dual3 $stamp',
        'price': 7.0,
        'quantity': 1,
      },
    );
    rec['p3_prod'] = {'http': prodIns.statusCode, 'body': clip(prodIns.body, 160)};
    final prod = row(dec(prodIns));
    if (prod != null) {
      final body = <String, dynamic>{
        'live_id': liTpl['live_id'],
        'seller_id': sellerId,
        'title': 'RTB2 p3',
        'price': 7.0,
        'product_id': prod['id'],
        'checkout_product_id': prod['id'],
        'ref_code': 'Z${Random().nextInt(899) + 100}',
        'item_kind': liTpl['item_kind'] ?? 'live_only',
      };
      for (final k in ['quantity', 'qty', 'stock', 'units', 'qty_total']) {
        if (liTpl.containsKey(k) && liTpl[k] != null) {
          body[k] = 1;
        }
      }
      final li = await rest(
        'POST',
        '/rest/v1/live_items',
        headers: hSvc(),
        body: body,
      );
      rec['p3_li'] = {'http': li.statusCode, 'body': clip(li.body, 280)};
      final item = row(dec(li));
      if (item != null) {
        final res = await rest(
          'POST',
          '/rest/v1/live_reservation_requests',
          headers: hUser(buyerJwt),
          body: {
            'live_id': item['live_id'],
            'live_item_id': item['id'],
            'buyer_id': buyerId,
            'seller_id': sellerId,
            'requested_qty': 1,
            'status': 'pending',
          },
        );
        rec['p3_res'] = {'http': res.statusCode, 'body': clip(res.body, 220)};
        final rr = row(dec(res));
        if (rr != null) {
          final acc = await rest(
            'PATCH',
            '/rest/v1/live_reservation_requests?id=eq.${rr['id']}',
            headers: hUser(sellerJwt),
            body: {'status': 'accepted'},
          );
          rec['p3_acc'] = {'http': acc.statusCode, 'body': clip(acc.body, 180)};
        }
        final mkt = await rest(
          'POST',
          '/rest/v1/orders',
          headers: hUser(buyerJwt),
          body: {
            'buyer_id': buyerId,
            'product_id': prod['id'],
            'quantity': 1,
            'price_total': 7.0,
            'status': 'reserva_pendente',
            'payment_method': 'MB WAY',
          },
        );
        rec['p3_mkt'] = {'http': mkt.statusCode, 'body': clip(mkt.body, 220)};
        final mo = row(dec(mkt));
        if (mo != null) {
          final pay = await rest(
            'PATCH',
            '/rest/v1/orders?id=eq.${mo['id']}',
            headers: hUser(sellerJwt),
            body: {'status': 'pago'},
          );
          rec['p3_pago'] = {'http': pay.statusCode, 'body': clip(pay.body, 220)};
          final paid = row(dec(pay));
          final resA = rr == null
              ? null
              : await sb.select(
                  'live_reservation_requests',
                  filter: 'id=eq.${rr['id']}',
                  limit: 1,
                );
          rec['p3_final'] = {
            'res': resA == null || resA.isEmpty ? null : resA.first['status'],
            'ord': paid?['status'] ?? mo['status'],
            'stock_applied': paid?['stock_units_applied'],
          };
          final liveOk = '${rec['p3_final']['res']}'.toLowerCase() == 'accepted';
          final mktOk = '${rec['p3_final']['ord']}'.toLowerCase() == 'pago';
          if (liveOk && mktOk) {
            find(
              'RTB2-STOCK-01',
              'P1',
              'Reserva LIVE aceite e order marketplace paga no mesmo produto stock=1',
              {
                'actor': 'buyer+seller',
                'after': rec['p3_final'],
                'impact': 'Dois caminhos consomem a mesma unidade.',
              },
            );
          }
          await rest(
            'PATCH',
            '/rest/v1/orders?id=eq.${mo['id']}',
            headers: hSvc(),
            body: {'status': 'cancelado'},
          );
        }
      }
    }
  }

  // Collusion: pago off-platform + concluido + review
  final prods = await sb.select(
    'products',
    filter: 'seller_id=eq.$sellerId',
    limit: 5,
  );
  Map<String, dynamic>? pr;
  for (final p in prods) {
    if ((num.tryParse('${p['price'] ?? 0}') ?? 0) > 0) {
      pr = p;
      break;
    }
  }
  if (pr != null) {
    final ins = await rest(
      'POST',
      '/rest/v1/orders',
      headers: hUser(buyerJwt),
      body: {
        'buyer_id': buyerId,
        'product_id': pr['id'],
        'quantity': 1,
        'price_total': pr['price'],
        'status': 'reserva_pendente',
        'payment_method': 'MB WAY',
      },
    );
    rec['col_ins'] = {'http': ins.statusCode, 'body': clip(ins.body, 200)};
    final o = row(dec(ins));
    if (o != null) {
      final pay = await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.${o['id']}',
        headers: hUser(sellerJwt),
        body: {'status': 'pago'},
      );
      rec['col_pago'] = {'http': pay.statusCode, 'body': clip(pay.body, 220)};
      final paid = row(dec(pay));
      rec['col_paid_status'] = paid?['status'] ?? o['status'];
      if ('${paid?['status'] ?? ''}'.toLowerCase() == 'pago') {
        final conc = await rest(
          'PATCH',
          '/rest/v1/orders?id=eq.${o['id']}',
          headers: hUser(buyerJwt),
          body: {'status': 'concluido'},
        );
        rec['col_conc'] = {'http': conc.statusCode, 'body': clip(conc.body, 180)};
        final rev = await rest(
          'POST',
          '/rest/v1/reviews',
          headers: hUser(buyerJwt),
          body: {
            'order_id': o['id'],
            'stars': 5,
            'comment': 'rtb2 p3',
            'target_id': sellerId,
            'author_role': 'comprador',
          },
        );
        rec['col_rev'] = {'http': rev.statusCode, 'body': clip(rev.body, 200)};
        if (rev.statusCode >= 200 &&
            rev.statusCode < 300 &&
            !rev.body.contains('unpaid')) {
          find(
            'RTB2-REP-01',
            'P1',
            'Conluio off-platform: seller→pago sem captura, buyer review 5★',
            {
              'actor': 'buyer+seller collusion',
              'after': {
                'order': o['id'],
                'review_http': rev.statusCode,
              },
              'impact': 'Reputação sem dinheiro na plataforma.',
            },
          );
        }
      }
      await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.${o['id']}',
        headers: hSvc(),
        body: {'status': 'cancelado'},
      );
    }
  }

  // GET settle with own session (should not mark others)
  final ev = await rest(
    'GET',
    '/rest/v1/stripe_checkout_events?select=session_id,buyer_id&session_id=not.is.null&limit=1',
    headers: hUser(buyerJwt),
  );
  rec['own_session_row'] = clip(ev.body, 200);

  Directory('tool/reports/redteam_blind_b_$stamp').createSync(recursive: true);
  File('tool/reports/redteam_blind_b_$stamp/pass3.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'findings': findings,
    'rec': rec,
  }));
  print('PASS3 findings=${findings.length}');
}
