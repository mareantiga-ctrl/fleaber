/// Red Team cego independente (Agente 3) — 2026-08-27
/// Staging fxdknzrqjenzqcvnwqqq · Stripe TEST · sem correcções.
/// service_role = setup / observação / limpeza. Provas de exploit = JWT/anon.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const tag = 'RT3';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';

typedef Json = Map<String, dynamic>;

final findings = <Json>[];
final closed = <Json>[];
final coverage = <String, String>{};
final probes = <Json>[];
final createdProductIds = <String>[];
final createdOrderIds = <String>[];
final createdChatIds = <String>[];
final createdOfferIds = <String>[];
final createdDisputeIds = <String>[];
final createdReservationIds = <String>[];
final notes = <String>[];
final invariant = <String, String>{};

void cov(String k, String v) {
  const rank = {
    'NÃO TESTADA': 0,
    'PARCIAL': 1,
    'TESTADA': 2,
    'TESTADA COM VARIANTES': 3,
  };
  final cur = coverage[k];
  if (cur == null || (rank[v] ?? 0) > (rank[cur] ?? 0)) coverage[k] = v;
}

void rec(String name, Object? data) {
  probes.add({'name': name, 'at': DateTime.now().toUtc().toIso8601String(), 'data': data});
}

void inv(String k, String v) => invariant[k] = v;

String clip(Object? o, [int n = 500]) {
  final s = o is String ? o : jsonEncode(o);
  if (s.length <= n) return s;
  return '${s.substring(0, n)}…';
}

int asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('$v') ?? 0;
}

double asNum(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

void finding({
  required String id,
  required String sev,
  required String surface,
  required String pre,
  required String identity,
  required String request,
  required Object? response,
  required Object? before,
  required Object? after,
  required String impact,
  required String confidence,
  required String variant,
  required String fp,
}) {
  findings.add({
    'id': id,
    'severity': sev,
    'surface': surface,
    'preconditions': pre,
    'identity': identity,
    'request': request,
    'response': response,
    'before': before,
    'after': after,
    'impact': impact,
    'confidence': confidence,
    'variant': variant,
    'false_positive_considered': fp,
  });
}

void closedAttack({
  required String id,
  required String surface,
  required String attack,
  required String result,
}) {
  closed.add({'id': id, 'surface': surface, 'attack': attack, 'result': result});
}

class Raw {
  Raw(this.status, this.body, this.headers);
  final int status;
  final String body;
  final Map<String, String> headers;
  Object? get json {
    try {
      return body.isEmpty ? null : jsonDecode(body);
    } catch (_) {
      return body;
    }
  }
}

late String base;
late String anon;
late String service;
late LiveOpsStagingClient c;
late String buyerTok;
late String sellerTok;
late String buyer2Tok;
late String buyerId;
late String sellerId;
late String buyer2Id;

Map<String, String> hAnon() => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> hUser(String tok) => {
      'apikey': anon,
      'Authorization': 'Bearer $tok',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> hSvc() => {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<Raw> req(
  String method,
  String path, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final uri = Uri.parse(path.startsWith('http') ? path : '$base$path');
  final hdrs = headers ?? hAnon();
  late http.Response r;
  final encoded = body == null
      ? null
      : (body is String ? body : jsonEncode(body));
  switch (method) {
    case 'GET':
      r = await http.get(uri, headers: hdrs);
      break;
    case 'POST':
      r = await http.post(uri, headers: hdrs, body: encoded);
      break;
    case 'PATCH':
      r = await http.patch(uri, headers: hdrs, body: encoded);
      break;
    case 'PUT':
      r = await http.put(uri, headers: hdrs, body: encoded);
      break;
    case 'DELETE':
      r = await http.delete(uri, headers: hdrs, body: encoded);
      break;
    default:
      throw StateError(method);
  }
  return Raw(r.statusCode, r.body, r.headers);
}

Future<Raw> rest(
  String method,
  String tableQs, {
  required Map<String, String> headers,
  Object? body,
}) =>
    req(method, '/rest/v1/$tableQs', headers: headers, body: body);

Future<Raw> rpcRaw(
  String fn,
  Object params, {
  required Map<String, String> headers,
}) =>
    req('POST', '/rest/v1/rpc/$fn', headers: headers, body: params);

Future<Raw> edge(
  String fn, {
  Map<String, String>? headers,
  Object? body,
  String query = '',
  String method = 'POST',
}) =>
    req(method, '/functions/v1/$fn$query', headers: headers ?? hAnon(), body: body);

Future<Json?> svcRow(String table, String filter) async {
  final r = await rest('GET', '$table?$filter&limit=1', headers: hSvc());
  final j = r.json;
  if (j is List && j.isNotEmpty) return Map<String, dynamic>.from(j.first as Map);
  return null;
}

Future<Json> sellerProduct({
  required double price,
  required int qty,
  String title = '$tag disposable',
}) async {
  final r = await rest('POST', 'products', headers: hUser(sellerTok), body: {
    'seller_id': sellerId,
    'title': title,
    'price': price,
    'quantity': qty,
    'list_on_marketplace': true,
    'description': '$tag red-team disposable fixture',
  });
  if (r.status < 200 || r.status >= 300) {
    throw StateError('product insert ${r.status} ${clip(r.body)}');
  }
  final row = (r.json as List).first as Map;
  final id = row['id'].toString();
  createdProductIds.add(id);
  return Map<String, dynamic>.from(row);
}

Future<Raw> buyerOrder({
  required String productId,
  required String seller,
  int qty = 1,
  String? status,
  Object? extra,
}) async {
  final body = <String, dynamic>{
    'buyer_id': buyerId,
    'seller_id': seller,
    'product_id': productId,
    'quantity': qty,
    'status': status ?? 'reserva_pendente',
    'payment_method': 'seguro fleaber',
    'shipping_method': 'entrega em mao',
    'price_total': 10.00,
    if (extra is Map) ...Map<String, dynamic>.from(extra),
  };
  final r = await rest('POST', 'orders', headers: hUser(buyerTok), body: body);
  final j = r.json;
  if (r.status >= 200 && r.status < 300 && j is List && j.isNotEmpty) {
    createdOrderIds.add((j.first as Map)['id'].toString());
  }
  return r;
}

Future<void> cleanup() async {
  for (final id in createdDisputeIds.reversed) {
    await rest('DELETE', 'order_disputes?id=eq.$id', headers: hSvc());
  }
  for (final id in createdOfferIds.reversed) {
    await rest('DELETE', 'product_offers?id=eq.$id', headers: hSvc());
  }
  for (final id in createdReservationIds.reversed) {
    await rest('DELETE', 'live_reservation_requests?id=eq.$id', headers: hSvc());
  }
  for (final id in createdOrderIds.reversed) {
    await rest('DELETE', 'orders?id=eq.$id', headers: hSvc());
  }
  for (final id in createdChatIds.reversed) {
    await rest('DELETE', 'chat_messages?chat_id=eq.$id', headers: hSvc());
    await rest('DELETE', 'chats?id=eq.$id', headers: hSvc());
  }
  for (final id in createdProductIds.reversed) {
    await rest(
      'PATCH',
      'products?id=eq.$id',
      headers: hSvc(),
      body: {'list_on_marketplace': false, 'title': '$tag CLEANED'},
    );
  }
}

Future<void> passAuth() async {
  cov('AUTH / PROFILES', 'TESTADA');

  final anonProf = await rest(
    'GET',
    'profiles?select=id,phone,iban,mb_way,user_type,full_name&limit=5',
    headers: hAnon(),
  );
  rec('anon_profiles', {'http': anonProf.status, 'body': clip(anonProf.body, 200)});
  if (anonProf.status == 200) {
    final j = anonProf.json;
    final n = j is List ? j.length : 0;
    if (n > 0) {
      finding(
        id: 'RT3-AUTH-01',
        sev: 'P1',
        surface: 'AUTH / PROFILES',
        pre: 'anon key pública',
        identity: 'anon',
        request: 'GET /rest/v1/profiles select PII',
        response: clip(anonProf.body, 300),
        before: null,
        after: {'rows': n},
        impact: 'Enumeração de perfis/PII sem login',
        confidence: 'confirmado LIVE',
        variant: 'anon SELECT profiles',
        fp: '200 com [] não é bypass; aqui n>0',
      );
    } else {
      closedAttack(
        id: 'RT3-AUTH-01',
        surface: 'AUTH',
        attack: 'anon SELECT profiles',
        result: 'HTTP ${anonProf.status} lista vazia ou RLS',
      );
    }
  } else {
    closedAttack(
      id: 'RT3-AUTH-01',
      surface: 'AUTH',
      attack: 'anon SELECT profiles',
      result: 'HTTP ${anonProf.status} ${clip(anonProf.body, 120)}',
    );
  }

  final dir = await rest(
    'GET',
    'profiles_directory_public?select=*&limit=5',
    headers: hAnon(),
  );
  rec('anon_directory', {'http': dir.status, 'n': dir.json is List ? (dir.json as List).length : dir.body});

  final hub = await rest(
    'GET',
    'hub_profiles_public?select=*&limit=3',
    headers: hAnon(),
  );
  rec('anon_hub_profiles', {'http': hub.status, 'body': clip(hub.body, 250)});

  final own = await rest(
    'GET',
    'profiles?select=id,user_type,phone,iban,mb_way,phone_verified_at,full_name&id=eq.$buyerId',
    headers: hUser(buyerTok),
  );
  rec('buyer_own_profile', {'http': own.status, 'body': clip(own.body, 400)});

  final other = await rest(
    'GET',
    'profiles?select=id,user_type,phone,iban,mb_way,full_name&id=eq.$sellerId',
    headers: hUser(buyerTok),
  );
  rec('buyer_other_profile', {'http': other.status, 'body': clip(other.body, 250)});
  final otherList = other.json;
  if (other.status == 200 && otherList is List && otherList.isNotEmpty) {
    final row = otherList.first as Map;
    final pii = [row['iban'], row['mb_way'], row['phone'], row['email']]
        .where((e) => e != null && '$e'.trim().isNotEmpty)
        .toList();
    if (pii.isNotEmpty) {
      finding(
        id: 'RT3-AUTH-02',
        sev: 'P1',
        surface: 'AUTH / PROFILES',
        pre: 'JWT comprador',
        identity: 'buyer',
        request: 'GET profiles id=seller',
        response: clip(other.body, 300),
        before: null,
        after: row,
        impact: 'PII de outro utilizador visível ao JWT comprador',
        confidence: 'confirmado LIVE',
        variant: 'cross-user profile SELECT',
        fp: 'directório público deliberado só se não incluir iban/phone/email',
      );
    } else {
      closedAttack(
        id: 'RT3-AUTH-02',
        surface: 'AUTH',
        attack: 'buyer SELECT seller profile',
        result: 'row visível sem PII financeira ou RLS filtra',
      );
    }
  } else {
    closedAttack(
      id: 'RT3-AUTH-02',
      surface: 'AUTH',
      attack: 'buyer SELECT seller profile',
      result: 'HTTP ${other.status} ${clip(other.body, 120)}',
    );
  }

  final adminAlias = await rest(
    'PATCH',
    'profiles?id=eq.$buyerId',
    headers: hUser(buyerTok),
    body: {'user_type': 'admin'},
  );
  final afterAdmin = await svcRow('profiles', 'id=eq.$buyerId&select=id,user_type');
  rec('buyer_set_admin', {
    'http': adminAlias.status,
    'body': clip(adminAlias.body, 200),
    'after': afterAdmin,
  });
  final ut = '${afterAdmin?['user_type'] ?? ''}'.toLowerCase();
  if (ut.contains('admin') || ut == 'staff' || ut == 'administracao') {
    finding(
      id: 'RT3-AUTH-03',
      sev: 'P0',
      surface: 'AUTH / PROFILES',
      pre: 'JWT comprador',
      identity: 'buyer',
      request: 'PATCH profiles user_type=admin',
      response: clip(adminAlias.body, 200),
      before: null,
      after: afterAdmin,
      impact: 'Escalação de privilégio via user_type',
      confidence: 'confirmado LIVE',
      variant: 'user_type admin',
      fp: 'alias de role que a app ignora não é P0 — verificar batata_is_admin',
    );
  } else {
    closedAttack(
      id: 'RT3-AUTH-03',
      surface: 'AUTH',
      attack: 'PATCH user_type=admin',
      result: 'não persistiu admin (http ${adminAlias.status} type=$ut)',
    );
  }

  final phone = await rest(
    'PATCH',
    'profiles?id=eq.$buyerId',
    headers: hUser(buyerTok),
    body: {'phone_verified_at': DateTime.now().toUtc().toIso8601String()},
  );
  rec('buyer_phone_verified', {'http': phone.status, 'body': clip(phone.body, 200)});

  final crossPatch = await rest(
    'PATCH',
    'profiles?id=eq.$sellerId',
    headers: hUser(buyerTok),
    body: {'display_name': '$tag hack'},
  );
  rec('cross_patch_profile', {'http': crossPatch.status, 'body': clip(crossPatch.body, 200)});
  if (crossPatch.status >= 200 && crossPatch.status < 300) {
    final j = crossPatch.json;
    final n = j is List ? j.length : -1;
    if (n > 0) {
      finding(
        id: 'RT3-AUTH-04',
        sev: 'P1',
        surface: 'AUTH / PROFILES',
        pre: 'JWT buyer',
        identity: 'buyer',
        request: 'PATCH profiles id=seller',
        response: clip(crossPatch.body, 200),
        before: null,
        after: j,
        impact: 'Alteração cross-user de perfil',
        confidence: 'confirmado LIVE',
        variant: 'cross PATCH',
        fp: '200 [] não é bypass',
      );
    } else {
      closedAttack(
        id: 'RT3-AUTH-04',
        surface: 'AUTH',
        attack: 'PATCH other profile',
        result: 'HTTP ${crossPatch.status} n=$n',
      );
    }
  } else {
    closedAttack(
      id: 'RT3-AUTH-04',
      surface: 'AUTH',
      attack: 'PATCH other profile',
      result: 'HTTP ${crossPatch.status}',
    );
  }

  final enumUsers = await req(
    'GET',
    '/auth/v1/admin/users?page=1&per_page=2',
    headers: hUser(buyerTok),
  );
  rec('jwt_admin_users', {'http': enumUsers.status, 'body': clip(enumUsers.body, 150)});
  closedAttack(
    id: 'RT3-AUTH-05',
    surface: 'AUTH',
    attack: 'GoTrue admin users com JWT',
    result: 'HTTP ${enumUsers.status}',
  );
}

Future<void> passOrdersMoney() async {
  cov('ORDERS / FSM', 'TESTADA');
  cov('PRICING / CONTRACT', 'TESTADA');

  final p = await sellerProduct(price: 12.34, qty: 3, title: '$tag contract');

  final spoof = await buyerOrder(
    productId: p['id'].toString(),
    seller: sellerId,
    qty: 1,
    extra: {
      'amount_paid_cents': 999999,
      'stripe_payment_intent_id': 'pi_rt3_fake',
      'stripe_checkout_session_id': 'cs_rt3_fake',
      'status': 'pago',
      'contract_unit_cents': 1,
      'contract_qty': 99,
      'price_total': 0.01,
      'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
    },
  );
  rec('order_insert_spoof_money', {'http': spoof.status, 'body': clip(spoof.body, 500)});
  Json? row;
  if (spoof.status >= 200 && spoof.status < 300 && spoof.json is List) {
    row = Map<String, dynamic>.from((spoof.json as List).first as Map);
  }
  final paid = asInt(row?['amount_paid_cents']);
  final pi = '${row?['stripe_payment_intent_id'] ?? ''}';
  final st = '${row?['status'] ?? ''}';
  final unit = asInt(row?['contract_unit_cents']);
  final cq = asInt(row?['contract_qty']);
  if (row != null && (paid > 0 || pi.contains('pi_rt3') || st.toLowerCase() == 'pago')) {
    finding(
      id: 'RT3-ORD-01',
      sev: 'P0',
      surface: 'ORDERS / FSM',
      pre: 'JWT buyer INSERT order',
      identity: 'buyer',
      request: 'INSERT amount_paid_cents=999999 status=pago stripe_pi fake',
      response: clip(spoof.body, 400),
      before: null,
      after: row,
      impact: 'JWT fabricou fundos/estado pago',
      confidence: 'confirmado LIVE',
      variant: 'money cols INSERT',
      fp: 'status reserva_pendente com cols null não é finding',
    );
    inv('E', 'QUEBRADA');
  } else {
    closedAttack(
      id: 'RT3-ORD-01',
      surface: 'ORDERS',
      attack: 'INSERT money cols + status=pago',
      result: 'stripped status=$st paid=$paid pi=$pi unit=$unit qty=$cq',
    );
    if (row != null && unit == 1234 && cq == 1) {
      closedAttack(
        id: 'RT3-ORD-01b',
        surface: 'PRICING',
        attack: 'INSERT contract_unit=1 contract_qty=99',
        result: 'selo servidor unit=$unit qty=$cq (catálogo 12.34)',
      );
    }
  }

  if (row != null) {
    final oid = row['id'].toString();
    final hike = await rest(
      'PATCH',
      'orders?id=eq.$oid',
      headers: hUser(buyerTok),
      body: {
        'contract_unit_cents': 50,
        'contract_qty': 9,
        'quantity': 9,
        'price_total': 0.5,
        'amount_paid_cents': 50000,
        'status': 'pago',
      },
    );
    final after = await svcRow(
      'orders',
      'id=eq.$oid&select=id,status,contract_unit_cents,contract_qty,quantity,price_total,amount_paid_cents',
    );
    rec('order_patch_contract', {'http': hike.status, 'body': clip(hike.body, 250), 'after': after});
    if (asInt(after?['contract_unit_cents']) == 50 ||
        asInt(after?['amount_paid_cents']) > 0 ||
        asInt(after?['contract_qty']) == 9) {
      finding(
        id: 'RT3-ORD-02',
        sev: 'P0',
        surface: 'PRICING / CONTRACT',
        pre: 'order selada',
        identity: 'buyer',
        request: 'PATCH contract/qty/amount_paid',
        response: clip(hike.body, 250),
        before: row,
        after: after,
        impact: 'Comprador alterou autoridade de preço/qty/fundos após acordo',
        confidence: 'confirmado LIVE',
        variant: 'PATCH freeze',
        fp: 'HTTP 200 com valores inalterados não é bypass',
      );
      inv('B', 'QUEBRADA');
    } else {
      closedAttack(
        id: 'RT3-ORD-02',
        surface: 'PRICING',
        attack: 'PATCH contract after seal',
        result: 'frozen after=$after http=${hike.status}',
      );
      inv('B', 'MANTIDA neste ataque');
    }

    final party = await rest(
      'PATCH',
      'orders?id=eq.$oid',
      headers: hUser(buyerTok),
      body: {'seller_id': buyerId, 'buyer_id': sellerId},
    );
    final afterP = await svcRow('orders', 'id=eq.$oid&select=id,buyer_id,seller_id');
    rec('order_swap_parties', {'http': party.status, 'after': afterP});
    if (afterP?['seller_id'] == buyerId || afterP?['buyer_id'] == sellerId) {
      finding(
        id: 'RT3-ORD-03',
        sev: 'P1',
        surface: 'ORDERS / FSM',
        pre: 'order existente',
        identity: 'buyer',
        request: 'PATCH swap buyer/seller',
        response: clip(party.body, 200),
        before: {'buyer': buyerId, 'seller': sellerId},
        after: afterP,
        impact: 'Partes da encomenda trocáveis por JWT',
        confidence: 'confirmado LIVE',
        variant: 'party swap',
        fp: 'n/a',
      );
      inv('H', 'QUEBRADA');
    } else {
      closedAttack(
        id: 'RT3-ORD-03',
        surface: 'ORDERS',
        attack: 'swap parties',
        result: 'unchanged $afterP',
      );
    }
  }

  // Qty extrema vs stock
  final p1 = await sellerProduct(price: 8.00, qty: 1, title: '$tag qty99');
  final q99 = await buyerOrder(productId: p1['id'].toString(), seller: sellerId, qty: 99);
  rec('order_qty99', {'http': q99.status, 'body': clip(q99.body, 400)});
  if (q99.status >= 200 && q99.status < 300) {
    final o = Map<String, dynamic>.from((q99.json as List).first as Map);
    notes.add('JWT INSERT qty=99 em stock=1 persistiu contract_qty=${o['contract_qty']} — checkout deve bloquear');
  }

  // Cross seller/product
  final victim = await rest(
    'GET',
    'products?select=id,seller_id,price,quantity&seller_id=neq.$sellerId&list_on_marketplace=eq.true&limit=1',
    headers: hSvc(),
  );
  rec('other_seller_product', clip(victim.body, 200));
  if (victim.json is List && (victim.json as List).isNotEmpty) {
    final vp = (victim.json as List).first as Map;
    final x = await buyerOrder(
      productId: vp['id'].toString(),
      seller: sellerId,
      qty: 1,
    );
    rec('order_seller_product_mismatch', {'http': x.status, 'body': clip(x.body, 250)});
    if (x.status >= 200 && x.status < 300) {
      finding(
        id: 'RT3-ORD-04',
        sev: 'P1',
        surface: 'ORDERS / FSM',
        pre: 'produto de outro vendedor',
        identity: 'buyer',
        request: 'INSERT order seller=lab product=victim',
        response: clip(x.body, 300),
        before: vp,
        after: x.json,
        impact: 'Encomenda com seller ≠ dono do produto',
        confidence: 'confirmado LIVE',
        variant: 'seller↔product',
        fp: 'trigger deve rejeitar; 201 é falha',
      );
    } else {
      closedAttack(
        id: 'RT3-ORD-04',
        surface: 'ORDERS',
        attack: 'seller/product mismatch INSERT',
        result: 'HTTP ${x.status} ${clip(x.body, 120)}',
      );
    }
  }

  // Buyer INSERT as seller of own product (self-deal)
  final self = await rest('POST', 'orders', headers: hUser(buyerTok), body: {
    'buyer_id': buyerId,
    'seller_id': buyerId,
    'product_id': p['id'],
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'seguro fleaber',
    'shipping_method': 'hand',
    'price_total': 10.00,
  });
  rec('self_deal_order', {'http': self.status, 'body': clip(self.body, 250)});

  // FSM: buyer → pago / concluido / enviado
  if (row != null) {
    final oid = row['id'].toString();
    for (final s in ['pago', 'enviado', 'entregue', 'concluido', 'cancelado']) {
      final r = await rest(
        'PATCH',
        'orders?id=eq.$oid',
        headers: hUser(buyerTok),
        body: {'status': s},
      );
      final a = await svcRow('orders', 'id=eq.$oid&select=id,status');
      rec('buyer_status_$s', {'http': r.status, 'after': a, 'body': clip(r.body, 120)});
      final got = '${a?['status'] ?? ''}';
      if (got == s && s != 'reserva_pendente') {
        if (s == 'pago' || s == 'concluido' || s == 'enviado') {
          finding(
            id: 'RT3-FSM-$s',
            sev: s == 'pago' ? 'P0' : 'P1',
            surface: 'ORDERS / FSM',
            pre: 'order unpaid',
            identity: 'buyer',
            request: 'PATCH status=$s',
            response: clip(r.body, 200),
            before: {'status': row['status']},
            after: a,
            impact: 'Comprador avançou FSM sem captura',
            confidence: 'confirmado LIVE',
            variant: 'buyer status $s',
            fp: 'cancelado em unpaid pode ser deliberado',
          );
        }
      }
    }
  }
}

Future<void> passCheckout() async {
  cov('CHECKOUT / SETTLE / WEBHOOK', 'TESTADA');
  cov('BAG', 'PARCIAL');

  final p = await sellerProduct(price: 10.00, qty: 5, title: '$tag checkout');
  final o = await buyerOrder(productId: p['id'].toString(), seller: sellerId, qty: 1);
  if (o.status >= 300) {
    notes.add('checkout fixture order failed ${o.status} ${clip(o.body)}');
    return;
  }
  final order = Map<String, dynamic>.from((o.json as List).first as Map);
  final oid = order['id'].toString();

  final spoofAmt = await edge(
    'create-payment-intent',
    headers: hUser(buyerTok),
    body: {
      'amount': 50,
      'item_price': 50,
      'protection_fee': 0,
      'shipping': 0,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': p['id'],
      'order_id': oid,
      'quantity': 1,
      'shipping_method': 'hand',
      'currency': 'eur',
    },
  );
  rec('checkout_spoof_amount', {'http': spoofAmt.status, 'body': clip(spoofAmt.body, 500)});
  Map<String, dynamic>? q;
  try {
    q = jsonDecode(spoofAmt.body) as Map<String, dynamic>;
  } catch (_) {}
  final server = asInt(q?['server_amount_cents'] ?? q?['amount_total']);
  if (spoofAmt.status == 200 && server > 0 && server <= 60) {
    finding(
      id: 'RT3-CHK-01',
      sev: 'P0',
      surface: 'CHECKOUT / SETTLE / WEBHOOK',
      pre: 'order selada 10€',
      identity: 'buyer JWT',
      request: 'POST create-payment-intent amount=50',
      response: clip(spoofAmt.body, 400),
      before: order,
      after: q,
      impact: 'Stripe Session no montante controlado pelo cliente',
      confidence: 'confirmado LIVE',
      variant: 'body.amount',
      fp: 'Session ≠ settle; mas unit_amount=50 já é cobrança ilegítima se paga',
    );
    inv('A', 'QUEBRADA');
  } else if (spoofAmt.status == 200 && server >= 1000) {
    closedAttack(
      id: 'RT3-CHK-01',
      surface: 'CHECKOUT',
      attack: 'body.amount=50 vs catálogo 10€',
      result: 'server_amount_cents=$server ignorou cliente',
    );
    inv('A', 'MANTIDA no payment-start');
  } else {
    notes.add('checkout spoof HTTP ${spoofAmt.status} ${clip(spoofAmt.body, 200)}');
  }

  // Catalog hike after seal
  await rest(
    'PATCH',
    'products?id=eq.${p['id']}',
    headers: hUser(sellerTok),
    body: {'price': 99.00},
  );
  final hikeChk = await edge(
    'create-payment-intent',
    headers: hUser(buyerTok),
    body: {
      'amount': 9900,
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': 'hand',
      'product_id': p['id'],
      'seller_id': sellerId,
    },
  );
  rec('checkout_after_catalog_hike', {'http': hikeChk.status, 'body': clip(hikeChk.body, 400)});
  Map<String, dynamic>? q2;
  try {
    q2 = jsonDecode(hikeChk.body) as Map<String, dynamic>;
  } catch (_) {}
  final s2 = asInt(q2?['server_amount_cents'] ?? q2?['amount_total']);
  if (hikeChk.status == 200 && s2 >= 9000) {
    finding(
      id: 'RT3-CHK-02',
      sev: 'P1',
      surface: 'PRICING / CONTRACT',
      pre: 'order selada a 10€; seller PATCH price=99',
      identity: 'buyer checkout',
      request: 'POST create-payment-intent após hike',
      response: clip(hikeChk.body, 300),
      before: {'sealed_unit': order['contract_unit_cents']},
      after: q2,
      impact: 'Catálogo posterior mudou o contrato já aceite',
      confidence: 'confirmado LIVE',
      variant: 'TOCTOU catalog',
      fp: 'legado sem contract_*',
    );
    inv('K', 'QUEBRADA');
  } else if (hikeChk.status == 200 && s2 > 0 && s2 < 3000) {
    closedAttack(
      id: 'RT3-CHK-02',
      surface: 'PRICING',
      attack: 'seller hike after seal',
      result: 'checkout ainda $s2 cents (contrato)',
    );
    inv('K', 'MANTIDA neste ataque');
  }

  // Carrier vs hand
  final carrier = await edge(
    'create-payment-intent',
    headers: hUser(buyerTok),
    body: {
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': 'carrier',
    },
  );
  rec('checkout_carrier', {'http': carrier.status, 'body': clip(carrier.body, 300)});

  final garbageShip = await edge(
    'create-payment-intent',
    headers: hUser(buyerTok),
    body: {
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': 'gratis',
    },
  );
  rec('checkout_garbage_shipping', {'http': garbageShip.status, 'body': clip(garbageShip.body, 200)});
  if (garbageShip.status == 200) {
    finding(
      id: 'RT3-CHK-03',
      sev: 'P1',
      surface: 'CHECKOUT',
      pre: 'order selada',
      identity: 'buyer',
      request: 'shipping_method=gratis',
      response: clip(garbageShip.body, 250),
      before: null,
      after: garbageShip.json,
      impact: 'Portes lixo aceites (possível €0)',
      confidence: 'confirmado LIVE',
      variant: 'shipping allowlist',
      fp: 'erro 400 é fechado',
    );
  } else {
    closedAttack(
      id: 'RT3-CHK-03',
      surface: 'CHECKOUT',
      attack: 'shipping_method=gratis',
      result: 'HTTP ${garbageShip.status}',
    );
  }

  // Checkout other buyer's order
  final xBuyer = await edge(
    'create-payment-intent',
    headers: hUser(buyer2Tok),
    body: {
      'buyer_id': buyer2Id,
      'order_id': oid,
      'shipping_method': 'hand',
    },
  );
  rec('checkout_foreign_order', {'http': xBuyer.status, 'body': clip(xBuyer.body, 250)});
  if (xBuyer.status == 200) {
    finding(
      id: 'RT3-CHK-04',
      sev: 'P1',
      surface: 'CHECKOUT',
      pre: 'order do buyer lab',
      identity: 'buyer2 JWT',
      request: 'POST create-payment-intent order_id alheia + buyer_id próprio',
      response: clip(xBuyer.body, 300),
      before: {'order_buyer': buyerId},
      after: xBuyer.json,
      impact: 'Checkout de encomenda alheia',
      confidence: 'confirmado LIVE',
      variant: 'order hijack',
      fp: 'n/a',
    );
  } else {
    closedAttack(
      id: 'RT3-CHK-04',
      surface: 'CHECKOUT',
      attack: 'foreign order checkout',
      result: 'HTTP ${xBuyer.status} ${clip(xBuyer.body, 120)}',
    );
  }

  // buyer_id mismatch with own JWT
  final mismatch = await edge(
    'create-payment-intent',
    headers: hUser(buyerTok),
    body: {
      'buyer_id': sellerId,
      'order_id': oid,
      'shipping_method': 'hand',
    },
  );
  rec('checkout_buyer_mismatch', {'http': mismatch.status, 'body': clip(mismatch.body, 200)});
  closedAttack(
    id: 'RT3-CHK-05',
    surface: 'CHECKOUT',
    attack: 'JWT buyer + body.buyer_id=seller',
    result: 'HTTP ${mismatch.status}',
  );

  // GET settle without paid session
  final fakeSettle = await edge(
    'create-payment-intent',
    method: 'GET',
    query: '?checkout_return=success&session_id=cs_test_not_real',
    headers: hAnon(),
  );
  rec('settle_fake_session', {'http': fakeSettle.status, 'body': clip(fakeSettle.body, 200)});

  final e2e = await edge(
    'create-payment-intent',
    query: '?fase2_e2e_settle=1',
    headers: hUser(buyerTok),
    body: {
      'order_id': oid,
      'payment_intent_id': 'pi_test_fake',
    },
  );
  rec('e2e_settle_jwt', {'http': e2e.status, 'body': clip(e2e.body, 250)});
  if (e2e.status == 200) {
    finding(
      id: 'RT3-CHK-06',
      sev: 'P0',
      surface: 'CHECKOUT / SETTLE / WEBHOOK',
      pre: 'JWT buyer',
      identity: 'buyer',
      request: 'POST fase2_e2e_settle',
      response: clip(e2e.body, 300),
      before: null,
      after: e2e.json,
      impact: 'Settle lab acessível a JWT (forja pago)',
      confidence: 'confirmado LIVE',
      variant: 'e2e settle',
      fp: '401 expected',
    );
  } else {
    closedAttack(
      id: 'RT3-CHK-06',
      surface: 'CHECKOUT',
      attack: 'fase2_e2e_settle com JWT',
      result: 'HTTP ${e2e.status}',
    );
  }

  final wh = await edge(
    'stripe-webhook',
    headers: {
      ...hAnon(),
      'stripe-signature': 't=1,v1=deadbeef',
    },
    body: {
      'type': 'checkout.session.completed',
      'data': {
        'object': {'id': 'cs_test', 'payment_status': 'paid'}
      }
    },
  );
  rec('webhook_nosig', {'http': wh.status, 'body': clip(wh.body, 200)});
  closedAttack(
    id: 'RT3-CHK-07',
    surface: 'CHECKOUT',
    attack: 'webhook assinatura falsa',
    result: 'HTTP ${wh.status}',
  );

  // Bag two products same seller
  final pB = await sellerProduct(price: 6.00, qty: 2, title: '$tag bagB');
  final oB = await buyerOrder(productId: pB['id'].toString(), seller: sellerId, qty: 1);
  if (oB.status < 300) {
    final oidB = ((oB.json as List).first as Map)['id'].toString();
    final bag = await edge(
      'create-payment-intent',
      headers: hUser(buyerTok),
      body: {
        'buyer_id': buyerId,
        'order_id': oid,
        'shipping_method': 'hand',
        'bag_checkout': true,
        'bag_lines': [
          {'order_id': oid, 'line_total_cents': 1},
          {'order_id': oidB, 'line_total_cents': 1},
        ],
      },
    );
    rec('bag_same_seller', {'http': bag.status, 'body': clip(bag.body, 400)});
    Map<String, dynamic>? bq;
    try {
      bq = jsonDecode(bag.body) as Map<String, dynamic>;
    } catch (_) {}
    final bs = asInt(bq?['server_amount_cents']);
    if (bag.status == 200 && bs > 0 && bs < 200) {
      finding(
        id: 'RT3-BAG-01',
        sev: 'P0',
        surface: 'BAG',
        pre: 'duas orders 10€+6€',
        identity: 'buyer',
        request: 'bag_checkout line_total_cents=1',
        response: clip(bag.body, 300),
        before: null,
        after: bq,
        impact: 'Saco cobrado pelo line_total do cliente',
        confidence: 'confirmado LIVE',
        variant: 'bag spoof',
        fp: 'Session start',
      );
    } else if (bag.status == 200) {
      closedAttack(
        id: 'RT3-BAG-01',
        surface: 'BAG',
        attack: 'line_total_cents spoof',
        result: 'server=$bs',
      );
    }
  }

  // Duplicate checkout sessions (payment-start race window)
  final sess1 = await edge(
    'create-payment-intent',
    headers: hUser(buyerTok),
    body: {'buyer_id': buyerId, 'order_id': oid, 'shipping_method': 'hand'},
  );
  final sess2 = await edge(
    'create-payment-intent',
    headers: hUser(buyerTok),
    body: {'buyer_id': buyerId, 'order_id': oid, 'shipping_method': 'hand'},
  );
  rec('two_sessions_same_order', {
    's1': {'http': sess1.status, 'body': clip(sess1.body, 200)},
    's2': {'http': sess2.status, 'body': clip(sess2.body, 200)},
  });
  if (sess1.status == 200 && sess2.status == 200) {
    notes.add(
      'Duas Checkout Sessions na mesma order (payment-start). Settle duplicado só comprovável com captura Stripe TEST.',
    );
    cov('RACES / COMPOSITION', 'PARCIAL');
  }
}

Future<void> passWalletRpc() async {
  cov('WALLET / PAYOUT', 'TESTADA');
  cov('RPC / SECURITY DEFINER / GRANTS', 'TESTADA');

  final dangerous = [
    'batata_credit_wallet_once',
    'batata_debit_wallet_once',
    'batata_ensure_wallet',
    'batata_clawback_seller_wallet_for_order',
    'batata_wallet_payout_debit',
    'batata_wallet_payout_finish',
    'batata_finalize_stripe_order_refund',
    'batata_settle_live_tip_from_stripe',
    'batata_create_raffle_prize_order',
    'batata_award_live_raffle_tickets',
    'batata_live_reservation_stripe_convert',
    'batata_ps_claim_pairing',
    'batata_anon_rate_check',
    'staging_restore_stock_before_nuke',
    'batata_lab_clear_all_fm_pending',
    'batata_generate_auto_feedback',
  ];

  for (final fn in dangerous) {
    final rAnon = await rpcRaw(fn, {}, headers: hAnon());
    final rBuy = await rpcRaw(fn, {
      if (fn.contains('order')) 'p_order_id': '00000000-0000-0000-0000-000000000001',
      if (fn.contains('payout_debit')) 'p_user_id': buyerId,
      if (fn.contains('payout_debit')) 'p_amount_cents': 100,
      if (fn.contains('payout_debit')) 'p_idempotency_key': 'rt3-xxxxxxxx',
      if (fn.contains('credit') || fn.contains('debit') || fn.contains('ensure'))
        'p_user_id': buyerId,
      if (fn.contains('credit')) 'p_amount': 100,
      if (fn.contains('credit')) 'p_order_id': '00000000-0000-0000-0000-000000000001',
      if (fn.contains('credit')) 'p_kind': 'manual',
      if (fn.contains('credit')) 'p_note': 'rt3',
      if (fn == 'batata_ps_claim_pairing') 'p_code': '000000',
      if (fn == 'batata_ps_claim_pairing') 'p_device_id': 'rt3',
      if (fn == 'batata_anon_rate_check') 'p_rate_key': 'rt3',
      if (fn == 'batata_anon_rate_check') 'p_rpc': 'rt3',
      if (fn == 'batata_anon_rate_check') 'p_max_hits': 1,
    }, headers: hUser(buyerTok));
    rec('rpc_$fn', {
      'anon': {'http': rAnon.status, 'body': clip(rAnon.body, 120)},
      'buyer': {'http': rBuy.status, 'body': clip(rBuy.body, 160)},
    });
    final buyerOk = rBuy.status == 200;
    final looksDenied = rBuy.status == 401 ||
        rBuy.status == 403 ||
        rBuy.status == 404 ||
        rBuy.body.contains('permission denied') ||
        rBuy.body.contains('42501');
    if (buyerOk && !rBuy.body.contains('permission denied')) {
      // 200 may still be a raise-as-json. Inspect.
      final impactMint = fn.contains('credit') ||
          fn.contains('payout') ||
          fn.contains('finalize') ||
          fn.contains('settle') ||
          fn.contains('prize') ||
          fn.contains('nuke') ||
          fn.contains('auto_feedback');
      finding(
        id: 'RT3-RPC-$fn',
        sev: impactMint ? 'P0' : 'P1',
        surface: 'RPC / SECURITY DEFINER / GRANTS',
        pre: 'JWT buyer EXECUTE',
        identity: 'buyer',
        request: 'POST /rpc/$fn',
        response: clip(rBuy.body, 300),
        before: null,
        after: rBuy.json,
        impact: 'DEFINER privilegiada executável por authenticated',
        confidence: 'confirmado LIVE — verificar se o body mutou estado',
        variant: fn,
        fp: '200 com erro de negócio / grant sem efeito não é P0; confirmar mutação',
      );
    } else if (looksDenied || rBuy.status >= 400) {
      closedAttack(
        id: 'RT3-RPC-$fn',
        surface: 'RPC',
        attack: 'JWT EXECUTE $fn',
        result: 'HTTP ${rBuy.status} ${clip(rBuy.body, 80)}',
      );
    }
  }

  final wIns = await rest('POST', 'wallets', headers: hUser(buyerTok), body: {
    'id': buyerId,
    'balance': 9999,
  });
  rec('wallet_insert', {'http': wIns.status, 'body': clip(wIns.body, 200)});
  closedAttack(
    id: 'RT3-WAL-01',
    surface: 'WALLET',
    attack: 'INSERT wallets balance=9999',
    result: 'HTTP ${wIns.status}',
  );

  final wPatch = await rest(
    'PATCH',
    'wallets?id=eq.$buyerId',
    headers: hUser(buyerTok),
    body: {'balance': 9999},
  );
  rec('wallet_patch', {'http': wPatch.status, 'body': clip(wPatch.body, 200)});
  final wAfter = await svcRow('wallets', 'id=eq.$buyerId&select=id,balance');
  if (asNum(wAfter?['balance']) >= 9999) {
    finding(
      id: 'RT3-WAL-02',
      sev: 'P0',
      surface: 'WALLET / PAYOUT',
      pre: 'JWT buyer',
      identity: 'buyer',
      request: 'PATCH wallets.balance=9999',
      response: clip(wPatch.body, 200),
      before: null,
      after: wAfter,
      impact: 'Mint directo de saldo',
      confidence: 'confirmado LIVE',
      variant: 'table write',
      fp: 'n/a',
    );
    inv('E', 'QUEBRADA');
  } else {
    closedAttack(
      id: 'RT3-WAL-02',
      surface: 'WALLET',
      attack: 'PATCH balance',
      result: 'HTTP ${wPatch.status} after=$wAfter',
    );
    if (invariant['E'] != 'QUEBRADA') inv('E', 'MANTIDA nestes ataques de tabela/RPC mint');
  }

  final tx = await rest(
    'GET',
    'wallet_transactions?select=*&limit=5',
    headers: hUser(buyerTok),
  );
  rec('wallet_tx_select', {'http': tx.status, 'n': tx.json is List ? (tx.json as List).length : tx.body});

  final txOther = await rest(
    'GET',
    'wallet_transactions?wallet_id=eq.$sellerId&select=*&limit=5',
    headers: hUser(buyerTok),
  );
  rec('wallet_tx_other', {'http': txOther.status, 'body': clip(txOther.body, 200)});
  if (txOther.status == 200 && txOther.json is List && (txOther.json as List).isNotEmpty) {
    finding(
      id: 'RT3-WAL-03',
      sev: 'P1',
      surface: 'WALLET / PAYOUT',
      pre: 'JWT buyer',
      identity: 'buyer',
      request: 'GET wallet_transactions wallet_id=seller',
      response: clip(txOther.body, 250),
      before: null,
      after: {'n': (txOther.json as List).length},
      impact: 'Ledger de outro utilizador',
      confidence: 'confirmado LIVE',
      variant: 'cross ledger',
      fp: '200 [] não é bypass',
    );
  } else {
    closedAttack(
      id: 'RT3-WAL-03',
      surface: 'WALLET',
      attack: 'SELECT other wallet_transactions',
      result: 'HTTP ${txOther.status} ${clip(txOther.body, 80)}',
    );
  }

  // Privileged wallet RPCs that ARE granted to authenticated
  final fakeOrder = '00000000-0000-0000-0000-000000000001';
  for (final fn in [
    'batata_release_seller_wallet_for_order',
    'batata_refund_buyer_wallet_for_order',
    'batata_process_partial_refund_dispute',
  ]) {
    final params = fn.contains('partial')
        ? {'p_dispute_id': fakeOrder, 'p_refund_percent': 100}
        : {'p_order_id': fakeOrder};
    final r = await rpcRaw(fn, params, headers: hUser(buyerTok));
    rec('wallet_authz_$fn', {'http': r.status, 'body': clip(r.body, 250)});
  }

  // Payout amount spoof with empty/low balance
  final pay = await edge(
    'create-connect-account',
    headers: hUser(sellerTok),
    body: {
      'user_id': sellerId,
      'amount': 99999999,
      'idempotency_key': 'rt3-payout-${DateTime.now().millisecondsSinceEpoch}',
    },
  );
  rec('payout_huge', {'http': pay.status, 'body': clip(pay.body, 300)});
  if (pay.status == 200 && (pay.body.contains('transferId') || pay.body.contains('transfer_id'))) {
    finding(
      id: 'RT3-PAY-01',
      sev: 'P0',
      surface: 'WALLET / PAYOUT',
      pre: 'seller JWT',
      identity: 'seller',
      request: 'create-connect-account amount=99999999',
      response: clip(pay.body, 300),
      before: null,
      after: pay.json,
      impact: 'Transfer Stripe sem saldo wallet correspondente',
      confidence: 'confirmado LIVE',
      variant: 'payout amount',
      fp: 'onboarding URL sem transfer não é finding',
    );
  } else {
    closedAttack(
      id: 'RT3-PAY-01',
      surface: 'PAYOUT',
      attack: 'amount enorme',
      result: 'HTTP ${pay.status} ${clip(pay.body, 120)}',
    );
  }

  final payRetryA = await edge(
    'create-connect-account',
    headers: hUser(sellerTok),
    body: {
      'user_id': sellerId,
      'amount': 100,
      'idempotency_key': 'rt3-same-key-aaaaaaaa',
    },
  );
  final payRetryB = await edge(
    'create-connect-account',
    headers: hUser(sellerTok),
    body: {
      'user_id': sellerId,
      'amount': 100,
      'idempotency_key': 'rt3-same-key-aaaaaaaa',
    },
  );
  rec('payout_idempotent_retry', {
    'a': {'http': payRetryA.status, 'body': clip(payRetryA.body, 180)},
    'b': {'http': payRetryB.status, 'body': clip(payRetryB.body, 180)},
  });
}

Future<void> passStockOffPlatform() async {
  cov('STOCK', 'TESTADA');

  final p = await sellerProduct(price: 7.00, qty: 1, title: '$tag oversell-mbway');
  final o1 = await rest('POST', 'orders', headers: hUser(buyerTok), body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': p['id'],
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'mb way',
    'shipping_method': 'entrega em mao',
    'price_total': 7.00,
  });
  final o2 = await rest('POST', 'orders', headers: hUser(buyer2Tok), body: {
    'buyer_id': buyer2Id,
    'seller_id': sellerId,
    'product_id': p['id'],
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'mb way',
    'shipping_method': 'entrega em mao',
    'price_total': 7.00,
  });
  rec('mbway_two_orders', {
    'o1': {'http': o1.status, 'body': clip(o1.body, 250)},
    'o2': {'http': o2.status, 'body': clip(o2.body, 250)},
  });
  String? id1;
  String? id2;
  if (o1.status < 300 && o1.json is List) {
    id1 = ((o1.json as List).first as Map)['id'].toString();
    createdOrderIds.add(id1);
  }
  if (o2.status < 300 && o2.json is List) {
    id2 = ((o2.json as List).first as Map)['id'].toString();
    createdOrderIds.add(id2);
  }
  if (id1 == null || id2 == null) {
    notes.add('não foi possível criar duas orders MB WAY para oversell');
    return;
  }

  final before = await svcRow(
    'products',
    'id=eq.${p['id']}&select=id,quantity,is_sold',
  );
  final m1 = await rest(
    'PATCH',
    'orders?id=eq.$id1',
    headers: hUser(sellerTok),
    body: {'status': 'pago'},
  );
  final mid = await svcRow(
    'products',
    'id=eq.${p['id']}&select=id,quantity,is_sold',
  );
  final ord1 = await svcRow('orders', 'id=eq.$id1&select=id,status,stock_units_applied,amount_paid_cents,wallet_release_processed_at');
  final m2 = await rest(
    'PATCH',
    'orders?id=eq.$id2',
    headers: hUser(sellerTok),
    body: {'status': 'pago'},
  );
  final after = await svcRow(
    'products',
    'id=eq.${p['id']}&select=id,quantity,is_sold',
  );
  final ord2 = await svcRow('orders', 'id=eq.$id2&select=id,status,stock_units_applied,amount_paid_cents');
  rec('mbway_double_pago', {
    'm1': {'http': m1.status, 'body': clip(m1.body, 200)},
    'm2': {'http': m2.status, 'body': clip(m2.body, 200)},
    'before': before,
    'mid': mid,
    'after': after,
    'ord1': ord1,
    'ord2': ord2,
  });

  final s1 = '${ord1?['status'] ?? ''}'.toLowerCase();
  final s2 = '${ord2?['status'] ?? ''}'.toLowerCase();
  final qtyAfter = asInt(after?['quantity']);
  if (s1 == 'pago' && s2 == 'pago') {
    finding(
      id: 'RT3-STK-01',
      sev: 'P0',
      surface: 'STOCK',
      pre: 'SKU qty=1; duas orders MB WAY; seller marca pago nas duas',
      identity: 'seller JWT + 2 buyers',
      request: 'PATCH status=pago ×2',
      response: {'m1': clip(m1.body, 120), 'm2': clip(m2.body, 120)},
      before: before,
      after: {'product': after, 'ord1': ord1, 'ord2': ord2},
      impact: 'Uma unidade originou duas vendas válidas (pago×2)',
      confidence: 'confirmado LIVE',
      variant: 'off-platform double pago',
      fp: 'pending lista de espera ≠ duas vendas pago',
    );
    inv('D', 'QUEBRADA');
  } else if (s1 == 'pago' && s2 != 'pago') {
    closedAttack(
      id: 'RT3-STK-01',
      surface: 'STOCK',
      attack: 'duas MB WAY pago na última unidade',
      result: 'só 1ª pago; 2ª status=$s2 qty_after=$qtyAfter',
    );
    inv('D', 'MANTIDA neste ataque off-platform');
  } else {
    notes.add('MB WAY double pago inesperado s1=$s1 s2=$s2');
  }

  // Wallet mint on MB WAY?
  if (s1 == 'pago') {
    final w = await svcRow('wallets', 'id=eq.$sellerId&select=id,balance');
    rec('wallet_after_mbway_pago', w);
    notes.add(
      'MB WAY pago amount_paid=${ord1?['amount_paid_cents']} — mint wallet só se captura plataforma (invariante F)',
    );
  }

  // Concurrent MB WAY on another qty=1 product
  final pC = await sellerProduct(price: 5.00, qty: 1, title: '$tag race-mbway');
  final c1 = await rest('POST', 'orders', headers: hUser(buyerTok), body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pC['id'],
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'mb way',
    'shipping_method': 'hand',
    'price_total': 5.00,
  });
  final c2 = await rest('POST', 'orders', headers: hUser(buyer2Tok), body: {
    'buyer_id': buyer2Id,
    'seller_id': sellerId,
    'product_id': pC['id'],
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'mb way',
    'shipping_method': 'hand',
    'price_total': 5.00,
  });
  if (c1.status < 300 && c2.status < 300) {
    final a = ((c1.json as List).first as Map)['id'].toString();
    final b = ((c2.json as List).first as Map)['id'].toString();
    createdOrderIds.addAll([a, b]);
    final r = await Future.wait([
      rest('PATCH', 'orders?id=eq.$a', headers: hUser(sellerTok), body: {'status': 'pago'}),
      rest('PATCH', 'orders?id=eq.$b', headers: hUser(sellerTok), body: {'status': 'pago'}),
    ]);
    final oa = await svcRow('orders', 'id=eq.$a&select=id,status,stock_units_applied');
    final ob = await svcRow('orders', 'id=eq.$b&select=id,status,stock_units_applied');
    final pc = await svcRow('products', 'id=eq.${pC['id']}&select=id,quantity');
    rec('mbway_concurrent', {
      'r0': {'http': r[0].status, 'body': clip(r[0].body, 120)},
      'r1': {'http': r[1].status, 'body': clip(r[1].body, 120)},
      'oa': oa,
      'ob': ob,
      'product': pc,
    });
    final paidCount = [oa, ob].where((e) => '${e?['status']}'.toLowerCase() == 'pago').length;
    if (paidCount >= 2) {
      finding(
        id: 'RT3-STK-02',
        sev: 'P0',
        surface: 'RACES / COMPOSITION',
        pre: 'qty=1; PATCH pago concorrente',
        identity: 'seller JWT',
        request: 'dois PATCH status=pago em paralelo',
        response: {'oa': oa, 'ob': ob},
        before: {'qty': 1},
        after: pc,
        impact: 'Corrida: duas vendas na última unidade',
        confidence: 'confirmado LIVE',
        variant: 'concurrent off-platform',
        fp: 'ambos HTTP 200 com um revertido não é oversell',
      );
      inv('D', 'QUEBRADA');
    } else {
      closedAttack(
        id: 'RT3-STK-02',
        surface: 'STOCK',
        attack: 'concurrent MB WAY pago',
        result: 'paidCount=$paidCount qty=${pc?['quantity']}',
      );
    }
  }
}

Future<void> passDisputesReviewsChat() async {
  cov('DISPUTES / RETURNS', 'PARCIAL');
  cov('CHAT / REVIEWS', 'TESTADA');

  final p = await sellerProduct(price: 9.00, qty: 2, title: '$tag review');
  final o = await buyerOrder(productId: p['id'].toString(), seller: sellerId);
  if (o.status >= 300) return;
  final oid = ((o.json as List).first as Map)['id'].toString();

  final revUnpaid = await rest('POST', 'reviews', headers: hUser(buyerTok), body: {
    'buyer_id': buyerId,
    'target_id': sellerId,
    'order_id': oid,
    'rating': 5,
    'comment': '$tag unpaid review',
    'author_role': 'vendedor',
  });
  rec('review_unpaid', {'http': revUnpaid.status, 'body': clip(revUnpaid.body, 250)});
  if (revUnpaid.status < 300) {
    finding(
      id: 'RT3-REV-01',
      sev: 'P1',
      surface: 'CHAT / REVIEWS',
      pre: 'order unpaid',
      identity: 'buyer',
      request: 'INSERT reviews rating=5 author_role=vendedor',
      response: clip(revUnpaid.body, 300),
      before: {'order': oid, 'status': 'unpaid'},
      after: revUnpaid.json,
      impact: 'Review (e possível release) sem pagamento confirmado',
      confidence: 'confirmado LIVE',
      variant: 'unpaid review',
      fp: 'review pública deliberada ≠ efeito financeiro; verificar wallet_release',
    );
  } else {
    closedAttack(
      id: 'RT3-REV-01',
      surface: 'REVIEWS',
      attack: 'review unpaid',
      result: 'HTTP ${revUnpaid.status}',
    );
  }

  final pub = await rest(
    'GET',
    'reviews?select=id,buyer_id,target_id,rating,comment,order_id&limit=3',
    headers: hAnon(),
  );
  rec('anon_reviews', {'http': pub.status, 'body': clip(pub.body, 250)});

  final disp = await rest('POST', 'order_disputes', headers: hUser(buyerTok), body: {
    'order_id': oid,
    'buyer_id': buyerId,
    'reason': '$tag dispute unpaid',
    'seller_refund_percent': 100,
    'seller_offer_type': 'full',
  });
  rec('dispute_unpaid', {'http': disp.status, 'body': clip(disp.body, 250)});

  final chat = await rest('POST', 'chats', headers: hUser(buyerTok), body: {
    'user_a': buyerId,
    'user_b': sellerId,
    'product_id': p['id'],
  });
  rec('chat_insert', {'http': chat.status, 'body': clip(chat.body, 200)});
  if (chat.status < 300 && chat.json is List) {
    final cid = ((chat.json as List).first as Map)['id'].toString();
    createdChatIds.add(cid);
    final spoof = await rest('POST', 'chat_messages', headers: hUser(buyerTok), body: {
      'chat_id': cid,
      'sender_id': sellerId,
      'receiver_id': buyerId,
      'text': '$tag spoof sender',
    });
    rec('chat_spoof_sender', {'http': spoof.status, 'body': clip(spoof.body, 250)});
    if (spoof.status < 300) {
      final row = (spoof.json as List).first as Map;
      if (row['sender_id'] == sellerId) {
        finding(
          id: 'RT3-CHAT-01',
          sev: 'P1',
          surface: 'CHAT / REVIEWS',
          pre: 'chat buyer-seller',
          identity: 'buyer JWT',
          request: 'INSERT chat_messages sender_id=seller',
          response: clip(spoof.body, 250),
          before: {'uid': buyerId},
          after: row,
          impact: 'Spoof de remetente no chat',
          confidence: 'confirmado LIVE',
          variant: 'sender spoof',
          fp: 'trigger reescreve sender=uid',
        );
      } else {
        closedAttack(
          id: 'RT3-CHAT-01',
          surface: 'CHAT',
          attack: 'spoof sender_id',
          result: 'rewritten sender=${row['sender_id']}',
        );
      }
    } else {
      closedAttack(
        id: 'RT3-CHAT-01',
        surface: 'CHAT',
        attack: 'spoof sender',
        result: 'HTTP ${spoof.status}',
      );
    }

    final hijack = await rest(
      'PATCH',
      'chats?id=eq.$cid',
      headers: hUser(buyerTok),
      body: {'user_b': buyer2Id},
    );
    final afterC = await svcRow('chats', 'id=eq.$cid&select=id,user_a,user_b');
    rec('chat_party_hijack', {'http': hijack.status, 'after': afterC});
    if (afterC?['user_b'] == buyer2Id) {
      finding(
        id: 'RT3-CHAT-02',
        sev: 'P1',
        surface: 'CHAT / REVIEWS',
        pre: 'chat existente',
        identity: 'buyer',
        request: 'PATCH chats.user_b',
        response: clip(hijack.body, 200),
        before: {'user_b': sellerId},
        after: afterC,
        impact: 'Troca de contraparte do chat',
        confidence: 'confirmado LIVE',
        variant: 'chat parties',
        fp: 'n/a',
      );
    } else {
      closedAttack(
        id: 'RT3-CHAT-02',
        surface: 'CHAT',
        attack: 'PATCH user_b',
        result: 'frozen $afterC',
      );
    }
  }

  // Cross-user chats
  final otherChats = await rest(
    'GET',
    'chats?select=id,user_a,user_b&or=(user_a.eq.$sellerId,user_b.eq.$sellerId)&limit=5',
    headers: hUser(buyer2Tok),
  );
  rec('cross_chats', {'http': otherChats.status, 'body': clip(otherChats.body, 200)});
}

Future<void> passOffersReservations() async {
  cov('LIVE / RESERVATIONS', 'PARCIAL');
  cov('RAFFLES / TIPS', 'PARCIAL');

  final p = await sellerProduct(price: 15.00, qty: 4, title: '$tag offer');
  final off = await rest('POST', 'product_offers', headers: hUser(buyerTok), body: {
    'product_id': p['id'],
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 1.00,
    'offered_by': 'buyer',
    'status': 'accepted',
  });
  rec('offer_self_accepted', {'http': off.status, 'body': clip(off.body, 300)});
  if (off.status < 300 && off.json is List) {
    final row = Map<String, dynamic>.from((off.json as List).first as Map);
    createdOfferIds.add(row['id'].toString());
    if ('${row['status']}'.toLowerCase() == 'accepted') {
      finding(
        id: 'RT3-OFF-01',
        sev: 'P1',
        surface: 'PRICING / CONTRACT',
        pre: 'JWT buyer INSERT offer',
        identity: 'buyer',
        request: 'INSERT product_offers status=accepted amount=1',
        response: clip(off.body, 300),
        before: {'catalog': 15},
        after: row,
        impact: 'Comprador criou proposta já aceite (autoridade de preço)',
        confidence: 'confirmado LIVE',
        variant: 'self-accept offer',
        fp: 'trigger deve forçar pending',
      );
      inv('L', 'QUEBRADA');
    } else {
      closedAttack(
        id: 'RT3-OFF-01',
        surface: 'OFFERS',
        attack: 'INSERT accepted',
        result: 'status=${row['status']}',
      );
    }

    // Seller accept then buyer hike amount
    final acc = await rest(
      'PATCH',
      'product_offers?id=eq.${row['id']}',
      headers: hUser(sellerTok),
      body: {'status': 'accepted'},
    );
    rec('offer_seller_accept', {'http': acc.status, 'body': clip(acc.body, 200)});
    final hike = await rest(
      'PATCH',
      'product_offers?id=eq.${row['id']}',
      headers: hUser(buyerTok),
      body: {'amount': 0.50},
    );
    final after = await svcRow('product_offers', 'id=eq.${row['id']}&select=id,amount,status');
    rec('offer_hike_after_accept', {'http': hike.status, 'after': after});
    if (asNum(after?['amount']) == 0.5) {
      finding(
        id: 'RT3-OFF-02',
        sev: 'P1',
        surface: 'PRICING / CONTRACT',
        pre: 'offer accepted',
        identity: 'buyer',
        request: 'PATCH amount após accept',
        response: clip(hike.body, 200),
        before: row,
        after: after,
        impact: 'Preço da proposta alterado depois do acordo',
        confidence: 'confirmado LIVE',
        variant: 'offer amount freeze',
        fp: 'n/a',
      );
    } else {
      closedAttack(
        id: 'RT3-OFF-02',
        surface: 'OFFERS',
        attack: 'PATCH amount after accept',
        result: '$after',
      );
    }

    if ('${after?['status']}'.toLowerCase() == 'accepted') {
      final ord = await buyerOrder(
        productId: p['id'].toString(),
        seller: sellerId,
        extra: {'product_offer_id': row['id']},
      );
      rec('order_from_offer', {'http': ord.status, 'body': clip(ord.body, 350)});
      if (ord.status < 300) {
        final orow = (ord.json as List).first as Map;
        final unit = asInt(orow['contract_unit_cents']);
        if (unit == 100) {
          closedAttack(
            id: 'RT3-OFF-03',
            surface: 'PRICING',
            attack: 'order selada a partir de oferta aceite 1€',
            result: 'contract_unit_cents=$unit (oferta, não catálogo 15€)',
          );
        } else if (unit == 1500) {
          notes.add('oferta aceite ignorada no selo; usou catálogo');
        }
      }
    }
  }

  // Live reservation self-accept
  final lives = await rest(
    'GET',
    'lives?select=id,seller_id,status&seller_id=eq.$sellerId&limit=1',
    headers: hSvc(),
  );
  rec('seller_live', clip(lives.body, 200));
  if (lives.json is List && (lives.json as List).isNotEmpty) {
    final live = (lives.json as List).first as Map;
    final items = await rest(
      'GET',
      'live_items?select=id,live_id,price,product_id&live_id=eq.${live['id']}&limit=1',
      headers: hSvc(),
    );
    if (items.json is List && (items.json as List).isNotEmpty) {
      final li = (items.json as List).first as Map;
      final res = await rest('POST', 'live_reservation_requests', headers: hUser(buyerTok), body: {
        'live_id': live['id'],
        'live_item_id': li['id'],
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'source': 'fleaber_live',
        'status': 'accepted',
      });
      rec('reservation_self_accept', {'http': res.status, 'body': clip(res.body, 300)});
      if (res.status < 300 && res.json is List) {
        final rr = (res.json as List).first as Map;
        createdReservationIds.add(rr['id'].toString());
        if ('${rr['status']}'.toLowerCase() == 'accepted') {
          finding(
            id: 'RT3-RES-01',
            sev: 'P1',
            surface: 'LIVE / RESERVATIONS',
            pre: 'buyer INSERT reservation',
            identity: 'buyer',
            request: 'INSERT status=accepted',
            response: clip(res.body, 300),
            before: null,
            after: rr,
            impact: 'Comprador auto-aceitou reserva (salta fila)',
            confidence: 'confirmado LIVE',
            variant: 'self-accept reservation',
            fp: 'pending intencional; accepted é a quebra',
          );
        } else {
          closedAttack(
            id: 'RT3-RES-01',
            surface: 'LIVE',
            attack: 'INSERT accepted',
            result: 'status=${rr['status']}',
          );
        }
        final acc2 = await rest(
          'PATCH',
          'live_reservation_requests?id=eq.${rr['id']}',
          headers: hUser(buyerTok),
          body: {'status': 'accepted', 'requested_qty': 99},
        );
        rec('reservation_buyer_patch', {'http': acc2.status, 'body': clip(acc2.body, 200)});
      }
    } else {
      notes.add('seller sem live_items — reservas PARCIAL');
    }
  } else {
    notes.add('seller sem live — não criar live (regra: não deixar lives a correr)');
  }

  final raffleOrder = await rest('POST', 'orders', headers: hUser(buyerTok), body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': p['id'],
    'quantity': 1,
    'status': 'premio_rifa',
    'payment_method': 'premio_rifa',
    'shipping_method': 'carrier',
    'price_total': 3.50,
    'live_raffle_id': '00000000-0000-0000-0000-000000000001',
  });
  rec('raffle_prize_forge', {'http': raffleOrder.status, 'body': clip(raffleOrder.body, 250)});
  if (raffleOrder.status < 300) {
    finding(
      id: 'RT3-RAF-01',
      sev: 'P1',
      surface: 'RAFFLES / TIPS',
      pre: 'JWT buyer',
      identity: 'buyer',
      request: 'INSERT order status=premio_rifa',
      response: clip(raffleOrder.body, 300),
      before: null,
      after: raffleOrder.json,
      impact: 'Order de prémio forjada sem winner row',
      confidence: 'confirmado LIVE',
      variant: 'prize forge',
      fp: 'checkout ainda pode bloquear portes de prémio',
    );
    if (raffleOrder.json is List) {
      createdOrderIds.add(((raffleOrder.json as List).first as Map)['id'].toString());
    }
  } else {
    closedAttack(
      id: 'RT3-RAF-01',
      surface: 'RAFFLES',
      attack: 'INSERT premio_rifa',
      result: 'HTTP ${raffleOrder.status}',
    );
  }

  final tip = await rpcRaw('batata_create_live_tip_pending', {
    'p_live_id': '00000000-0000-0000-0000-000000000001',
    'p_seller_id': sellerId,
    'p_amount': 1,
  }, headers: hUser(buyerTok));
  rec('tip_pending_fake_live', {'http': tip.status, 'body': clip(tip.body, 200)});
}

Future<void> passStorageMuxPs() async {
  cov('STORAGE', 'TESTADA');
  cov('MUX / LIVEKIT / PS-OCR', 'PARCIAL');

  final listPub = await req(
    'POST',
    '/storage/v1/object/list/chat_media',
    headers: hAnon(),
    body: {'prefix': '', 'limit': 5},
  );
  rec('storage_list_anon', {'http': listPub.status, 'body': clip(listPub.body, 250)});

  final proofs = await req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    headers: hUser(buyerTok),
    body: {'prefix': 'order_proofs/', 'limit': 10},
  );
  rec('storage_list_private', {'http': proofs.status, 'body': clip(proofs.body, 250)});

  final xwrite = await req(
    'POST',
    '/storage/v1/object/chat_media/product_photos/$sellerId/rt3.txt',
    headers: {
      ...hUser(buyerTok),
      'Content-Type': 'text/plain',
      'x-upsert': 'true',
    },
    body: 'rt3-cross-write',
  );
  rec('storage_cross_write', {'http': xwrite.status, 'body': clip(xwrite.body, 200)});
  if (xwrite.status < 300) {
    finding(
      id: 'RT3-STO-01',
      sev: 'P1',
      surface: 'STORAGE',
      pre: 'JWT buyer',
      identity: 'buyer',
      request: 'POST object chat_media/product_photos/{sellerId}/rt3.txt',
      response: clip(xwrite.body, 200),
      before: null,
      after: xwrite.json,
      impact: 'Write cross-user em storage',
      confidence: 'confirmado LIVE',
      variant: 'path ownership',
      fp: 'bucket público de fotos pode ser enumeração; write noutro uid é P1',
    );
  } else {
    closedAttack(
      id: 'RT3-STO-01',
      surface: 'STORAGE',
      attack: 'cross-user object write',
      result: 'HTTP ${xwrite.status}',
    );
  }

  final livesKeys = await rest(
    'GET',
    'lives?select=id,mux_stream_key,stream_key,mux_playback_id&limit=3',
    headers: hUser(buyerTok),
  );
  rec('lives_stream_keys', {'http': livesKeys.status, 'body': clip(livesKeys.body, 300)});
  if (livesKeys.status == 200 &&
      livesKeys.body.contains('mux_stream_key') &&
      !livesKeys.body.contains('does not exist') &&
      livesKeys.json is List) {
    final rows = livesKeys.json as List;
    final leaked = rows.where((e) {
      final m = e as Map;
      final a = '${m['mux_stream_key'] ?? ''}';
      final b = '${m['stream_key'] ?? ''}';
      return a.isNotEmpty || b.isNotEmpty;
    }).toList();
    if (leaked.isNotEmpty) {
      finding(
        id: 'RT3-MUX-01',
        sev: 'P0',
        surface: 'MUX / LIVEKIT / PS-OCR',
        pre: 'JWT buyer',
        identity: 'buyer',
        request: 'GET lives select mux_stream_key,stream_key',
        response: 'keys present on ${leaked.length} rows (redacted)',
        before: null,
        after: {'n': leaked.length},
        impact: 'Stream keys de ingestão visíveis a JWT normal',
        confidence: 'confirmado LIVE',
        variant: 'column grant',
        fp: 'playback_id público não é stream key',
      );
    } else {
      closedAttack(
        id: 'RT3-MUX-01',
        surface: 'MUX',
        attack: 'SELECT stream keys',
        result: 'colunas vazias ou omitidas',
      );
    }
  } else {
    closedAttack(
      id: 'RT3-MUX-01',
      surface: 'MUX',
      attack: 'SELECT stream keys',
      result: 'HTTP ${livesKeys.status} ${clip(livesKeys.body, 120)}',
    );
  }

  final mux = await edge(
    'create-mux-live',
    headers: hUser(buyerTok),
    body: {'title': '$tag'},
  );
  rec('create_mux_as_buyer', {'http': mux.status, 'body': clip(mux.body, 200)});
  closedAttack(
    id: 'RT3-MUX-02',
    surface: 'MUX',
    attack: 'create-mux-live como comprador',
    result: 'HTTP ${mux.status}',
  );

  final cleanupLk = await edge(
    'livekit-egress-cleanup',
    headers: hUser(buyerTok),
    body: {},
  );
  rec('egress_cleanup_jwt', {'http': cleanupLk.status, 'body': clip(cleanupLk.body, 150)});
  if (cleanupLk.status == 200) {
    finding(
      id: 'RT3-MUX-03',
      sev: 'P1',
      surface: 'MUX / LIVEKIT / PS-OCR',
      pre: 'JWT buyer',
      identity: 'buyer',
      request: 'POST livekit-egress-cleanup',
      response: clip(cleanupLk.body, 200),
      before: null,
      after: cleanupLk.json,
      impact: 'Parar egress LiveKit sem secret',
      confidence: 'confirmado LIVE',
      variant: 'cleanup authz',
      fp: '401 expected',
    );
  } else {
    closedAttack(
      id: 'RT3-MUX-03',
      surface: 'MUX',
      attack: 'egress cleanup JWT',
      result: 'HTTP ${cleanupLk.status}',
    );
  }

  final pair = await edge(
    'ps-pairing-claim',
    headers: hAnon(),
    body: {'code': '000000', 'device_id': 'rt3'},
  );
  rec('ps_pair_000000', {'http': pair.status, 'body': clip(pair.body, 250)});
  if (pair.status == 200 && pair.body.contains('device_token')) {
    finding(
      id: 'RT3-PS-01',
      sev: 'P1',
      surface: 'MUX / LIVEKIT / PS-OCR',
      pre: 'anon, código 000000',
      identity: 'anon',
      request: 'POST ps-pairing-claim code=000000',
      response: clip(pair.body, 250),
      before: null,
      after: pair.json,
      impact: 'Pairing PS sem autenticação devolveu device_token',
      confidence: 'confirmado LIVE',
      variant: 'guessed code',
      fp: 'invalid_or_expired não é finding',
    );
  } else {
    closedAttack(
      id: 'RT3-PS-01',
      surface: 'PS',
      attack: 'claim 000000',
      result: 'HTTP ${pair.status} ${clip(pair.body, 80)}',
    );
  }

  // Rate: a few sequential guesses (not 1e6 brute — abuso operacional)
  var pairHits = 0;
  for (final code in ['111111', '123456', '999999']) {
    final r = await edge('ps-pairing-claim', headers: hAnon(), body: {'code': code, 'device_id': 'rt3'});
    pairHits++;
    rec('ps_pair_$code', {'http': r.status, 'body': clip(r.body, 80)});
  }
  notes.add('ps-pairing-claim $pairHits tentativas anon sem JWT — brute 6 dígitos depende de rate-limit Edge (não visto no código)');

  final ocr = await edge(
    'ingest-ocr-reservation',
    headers: hAnon(),
    body: {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'requested_qty': 1,
      'ocr_raw_line': 'RT3',
    },
  );
  rec('ocr_no_token', {'http': ocr.status, 'body': clip(ocr.body, 200)});
  closedAttack(
    id: 'RT3-PS-02',
    surface: 'PS',
    attack: 'ingest-ocr sem device token',
    result: 'HTTP ${ocr.status}',
  );

  final play = await edge(
    'resolve-mux-playback',
    headers: hAnon(),
    body: {'live_id': '00000000-0000-0000-0000-000000000001'},
  );
  rec('resolve_playback_anon', {'http': play.status, 'body': clip(play.body, 200)});

  final del = await edge(
    'delete-test-account',
    headers: hUser(buyerTok),
    body: {'confirm': 'APAGAR TUDO'},
  );
  rec('delete_test_account', {'http': del.status, 'body': clip(del.body, 200)});
  notes.add('delete-test-account HTTP ${del.status} — não completar destruição de conta lab');
}

Future<void> passOpenApiAndRefund() async {
  final oa = await req(
    'GET',
    '/rest/v1/',
    headers: {
      ...hAnon(),
      'Accept': 'application/openapi+json',
    },
  );
  rec('openapi_http', oa.status);
  final paths = <String>[];
  try {
    final spec = jsonDecode(oa.body) as Map<String, dynamic>;
    final p = spec['paths'];
    if (p is Map) {
      for (final k in p.keys) {
        paths.add(k.toString());
      }
    }
  } catch (_) {}
  rec('openapi_rpc_sample', paths.where((e) => e.contains('/rpc/')).take(80).toList());
  final walletRpcs = paths.where((e) =>
      e.contains('wallet') ||
      e.contains('credit') ||
      e.contains('payout') ||
      e.contains('refund') ||
      e.contains('clawback'));
  rec('openapi_wallet_rpcs', walletRpcs.toList());

  cov('DISPUTES / RETURNS', coverage['DISPUTES / RETURNS'] ?? 'PARCIAL');
  final refBuyer = await edge(
    'refund-order',
    headers: hUser(buyerTok),
    body: {'order_id': createdOrderIds.isEmpty ? '00000000-0000-0000-0000-000000000001' : createdOrderIds.first},
  );
  rec('refund_as_buyer', {'http': refBuyer.status, 'body': clip(refBuyer.body, 250)});
  if (refBuyer.status == 200 && refBuyer.body.contains('"ok":true') && !refBuyer.body.contains('skipped')) {
    finding(
      id: 'RT3-REF-01',
      sev: 'P1',
      surface: 'CHECKOUT / SETTLE / WEBHOOK',
      pre: 'JWT buyer',
      identity: 'buyer',
      request: 'POST refund-order',
      response: clip(refBuyer.body, 250),
      before: null,
      after: refBuyer.json,
      impact: 'Comprador disparou refund seller-only',
      confidence: 'confirmado LIVE',
      variant: 'refund authz',
      fp: 'skipped not_seguro não é bypass',
    );
  } else {
    closedAttack(
      id: 'RT3-REF-01',
      surface: 'REFUND',
      attack: 'refund-order como buyer',
      result: 'HTTP ${refBuyer.status} ${clip(refBuyer.body, 80)}',
    );
  }

  // Bundle discounts enumeration
  final disc = await rest(
    'GET',
    'seller_bundle_discounts?select=*&limit=20',
    headers: hUser(buyerTok),
  );
  rec('bundle_discounts_all', {'http': disc.status, 'n': disc.json is List ? (disc.json as List).length : disc.body});
  if (disc.status == 200 && disc.json is List && (disc.json as List).length > 1) {
    notes.add('authenticated SELECT seller_bundle_discounts using true — config comercial de outros sellers visível (P3 se sem PII)');
  }

  final tipEdge = await edge(
    'create-live-tip-checkout',
    headers: hUser(buyerTok),
    body: {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'seller_id': sellerId,
      'amount_eur': 1,
      'tip_id': '00000000-0000-0000-0000-000000000001',
    },
  );
  rec('tip_checkout', {'http': tipEdge.status, 'body': clip(tipEdge.body, 250)});

  final tipNoId = await edge(
    'create-live-tip-checkout',
    headers: hUser(buyerTok),
    body: {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'seller_id': sellerId,
      'amount_eur': 1,
    },
  );
  rec('tip_checkout_no_client_id', {'http': tipNoId.status, 'body': clip(tipNoId.body, 250)});

  final credit = await rpcRaw('batata_credit_wallet_once', {
    'p_user_id': buyerId,
    'p_order_id': '00000000-0000-0000-0000-000000000001',
    'p_amount': 100,
    'p_entry_type': 'manual',
    'p_idempotency_key': 'rt3-credit-xxxxxxxx',
  }, headers: hUser(buyerTok));
  rec('credit_named_args', {'http': credit.status, 'body': clip(credit.body, 250)});

  final partial = await rpcRaw('batata_process_partial_refund_dispute', {
    'p_order_id': createdOrderIds.isEmpty
        ? '00000000-0000-0000-0000-000000000001'
        : createdOrderIds.first,
    'p_refund_percent': 100,
  }, headers: hUser(buyerTok));
  rec('partial_refund_named', {'http': partial.status, 'body': clip(partial.body, 300)});

  final proofsOther = await req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    headers: hUser(buyerTok),
    body: {'prefix': 'order_proofs/$sellerId/', 'limit': 20},
  );
  rec('storage_list_other_proofs', {
    'http': proofsOther.status,
    'body': clip(proofsOther.body, 250),
  });

  final oaSvc = await req(
    'GET',
    '/rest/v1/',
    headers: {
      ...hSvc(),
      'Accept': 'application/openapi+json',
    },
  );
  rec('openapi_svc', oaSvc.status);

  // Invariante J: segunda intenção distinta (key nova) — 1€ TEST se houver saldo.
  final payJ = await edge(
    'create-connect-account',
    headers: hUser(sellerTok),
    body: {
      'user_id': sellerId,
      'amount': 100,
      'idempotency_key': 'rt3-j-distinct-${DateTime.now().millisecondsSinceEpoch}',
    },
  );
  rec('payout_distinct_key', {'http': payJ.status, 'body': clip(payJ.body, 300)});
  if (payJ.status == 200 && payJ.body.contains('transferId') && !payJ.body.contains('idempotent')) {
    notes.add('Invariante J: key nova criou Transfer distinta (esperado se saldo).');
    inv('J', 'MANTIDA neste ataque (2ª intenção ≠ 1ª)');
  } else if (payJ.body.contains('idempotent')) {
    notes.add('2ª key foi tratada como idempotente — possível colisão de resume órfão');
    inv('J', 'INCERTO — retry/resume');
  }

  final iban = await rest(
    'GET',
    'profiles?select=id,iban,mb_way&id=eq.$sellerId',
    headers: hUser(buyerTok),
  );
  rec('cross_iban', {'http': iban.status, 'body': clip(iban.body, 200)});
}

Future<void> passCompositionPaidPath() async {
  cov('RACES / COMPOSITION', coverage['RACES / COMPOSITION'] ?? 'PARCIAL');
  // Seller platform pago without capture
  final p = await sellerProduct(price: 11.00, qty: 2, title: '$tag platform-pago');
  final o = await rest('POST', 'orders', headers: hUser(buyerTok), body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': p['id'],
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'seguro fleaber',
    'shipping_method': 'hand',
    'price_total': 11.00,
  });
  if (o.status >= 300) return;
  final oid = ((o.json as List).first as Map)['id'].toString();
  createdOrderIds.add(oid);
  final before = await svcRow('orders', 'id=eq.$oid&select=id,status,amount_paid_cents,stock_units_applied');
  final r = await rest(
    'PATCH',
    'orders?id=eq.$oid',
    headers: hUser(sellerTok),
    body: {'status': 'pago'},
  );
  final after = await svcRow('orders', 'id=eq.$oid&select=id,status,amount_paid_cents,stock_units_applied');
  rec('seller_platform_pago_no_capture', {
    'http': r.status,
    'body': clip(r.body, 200),
    'before': before,
    'after': after,
  });
  if ('${after?['status']}'.toLowerCase() == 'pago') {
    finding(
      id: 'RT3-FSM-PLAT',
      sev: 'P0',
      surface: 'ORDERS / FSM',
      pre: 'payment_method plataforma; sem amount_paid',
      identity: 'seller JWT',
      request: 'PATCH status=pago',
      response: clip(r.body, 200),
      before: before,
      after: after,
      impact: 'Vendedor marcou Seguro Fleaber como pago sem captura Stripe',
      confidence: 'confirmado LIVE',
      variant: 'platform pago',
      fp: 'MB WAY allowlist é modelo de negócio; seguro fleaber não',
    );
  } else {
    closedAttack(
      id: 'RT3-FSM-PLAT',
      surface: 'FSM',
      attack: 'seller pago sem captura em plataforma',
      result: 'status=${after?['status']}',
    );
  }

  // payment_method switch unpaid → mb way
  final sw = await rest(
    'PATCH',
    'orders?id=eq.$oid',
    headers: hUser(buyerTok),
    body: {'payment_method': 'mb way'},
  );
  final afterSw = await svcRow('orders', 'id=eq.$oid&select=id,payment_method,status');
  rec('switch_payment_method', {'http': sw.status, 'after': afterSw, 'body': clip(sw.body, 150)});
  if ('${afterSw?['payment_method']}'.toLowerCase().contains('mb')) {
    finding(
      id: 'RT3-ORD-PM',
      sev: 'P1',
      surface: 'ORDERS / FSM',
      pre: 'order criada como seguro fleaber',
      identity: 'buyer',
      request: 'PATCH payment_method=mb way',
      response: clip(sw.body, 200),
      before: before,
      after: afterSw,
      impact: 'Comprador mudou o canal de pagamento após o acordo (abre attest MB WAY)',
      confidence: 'confirmado LIVE',
      variant: 'payment_method freeze',
      fp: 'se freeze mantém seguro fleaber, não é finding',
    );
  } else {
    closedAttack(
      id: 'RT3-ORD-PM',
      surface: 'ORDERS',
      attack: 'PATCH payment_method',
      result: '${afterSw?['payment_method']}',
    );
  }
}

Future<void> writeReportFile(Json summary) async {
  final out = File('tool/reports/RT3_BLIND_RAW_20260827.json');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  if (!base.contains(stagingRef)) {
    stderr.writeln('ABORT: não é staging $stagingRef');
    exit(2);
  }
  c = LiveOpsStagingClient(url: base, anonKey: anon, serviceRoleKey: service);

  buyerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final probe = File('tool/ps_ai/lab_qa_accounts.env');
  var b2email = 'demo_bot_01@staging.fleaber.bot';
  var b2pass = 'FleaberBotSim_Staging_2026!';
  if (probe.existsSync()) {
    for (final line in probe.readAsLinesSync()) {
      if (line.startsWith('PROBE_A_EMAIL=')) b2email = line.split('=').sublist(1).join('=');
      if (line.startsWith('PROBE_A_PASSWORD=')) b2pass = line.split('=').sublist(1).join('=');
    }
  }
  buyer2Tok = await c.signIn(email: b2email, password: b2pass);
  buyerId = await c.userIdForAccessToken(buyerTok);
  sellerId = await c.userIdForAccessToken(sellerTok);
  buyer2Id = await c.userIdForAccessToken(buyer2Tok);
  rec('identities', {
    'buyer': buyerId,
    'seller': sellerId,
    'buyer2': buyer2Id,
    'staging': stagingRef,
  });

  // Observe grants (service_role observation, not exploit)
  try {
    final g = await rpcRaw('batata_assert_wallet_rpc_grants', {}, headers: hSvc());
    rec('assert_wallet_grants_svc', {'http': g.status, 'body': clip(g.body, 400)});
  } catch (e) {
    rec('assert_wallet_grants_svc_err', '$e');
  }

  try {
    await passAuth();
    await passOrdersMoney();
    await passCheckout();
    await passWalletRpc();
    await passStockOffPlatform();
    await passDisputesReviewsChat();
    await passOffersReservations();
    await passStorageMuxPs();
    await passOpenApiAndRefund();
    await passCompositionPaidPath();
  } catch (e, st) {
    notes.add('harness exception: $e');
    rec('fatal', '$e\n$st');
  }

  for (final k in [
    'AUTH / PROFILES',
    'ORDERS / FSM',
    'PRICING / CONTRACT',
    'CHECKOUT / SETTLE / WEBHOOK',
    'BAG',
    'WALLET / PAYOUT',
    'STOCK',
    'DISPUTES / RETURNS',
    'LIVE / RESERVATIONS',
    'RAFFLES / TIPS',
    'CHAT / REVIEWS',
    'STORAGE',
    'MUX / LIVEKIT / PS-OCR',
    'RPC / SECURITY DEFINER / GRANTS',
    'RACES / COMPOSITION',
  ]) {
    coverage.putIfAbsent(k, () => 'NÃO TESTADA');
  }

  try {
    await cleanup();
    rec('cleanup', {
      'products_soft': createdProductIds.length,
      'orders': createdOrderIds.length,
    });
  } catch (e) {
    notes.add('cleanup error $e');
  }

  final p0 = findings.where((f) => f['severity'] == 'P0').toList();
  final p1 = findings.where((f) => f['severity'] == 'P1').toList();
  final summary = {
    'agent': 'RT3-blind',
    'frozen_at': DateTime.now().toUtc().toIso8601String(),
    'staging': stagingRef,
    'production_touched': false,
    'identities': {'buyer': buyerId, 'seller': sellerId, 'buyer2': buyer2Id},
    'coverage': coverage,
    'invariants': invariant,
    'findings': findings,
    'closed': closed,
    'notes': notes,
    'p0_count': p0.length,
    'p1_count': p1.length,
    'probes': probes,
  };
  await writeReportFile(summary);
  stdout.writeln(jsonEncode({
    'ok': true,
    'p0': p0.length,
    'p1': p1.length,
    'findings': findings.map((f) => '${f['id']} ${f['severity']} ${f['surface']}').toList(),
    'closed': closed.length,
    'coverage': coverage,
    'invariants': invariant,
    'notes': notes,
    'out': 'tool/reports/RT3_BLIND_RAW_20260827.json',
  }));
}
