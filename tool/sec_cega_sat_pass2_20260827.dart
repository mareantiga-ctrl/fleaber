/// Passagem 2 — variantes do P1, gaps de schema, composição, E2E Stripe TEST.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const tag = 'SAT27C2';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';
typedef Json = Map<String, dynamic>;

final findings = <Json>[];
final probes = <Json>[];
final notes = <String>[];
final createdProductIds = <String>[];
final createdOrderIds = <String>[];

void rec(String n, Object? d) => probes.add({'name': n, 'data': d});

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

String clip(Object? o, [int n = 350]) {
  final s = o is String ? o : jsonEncode(o);
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

int ni(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double nd(Object? v) => double.tryParse('${v ?? ''}') ?? 0;

Json? rowOf(Object? body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map && body['id'] != null) return Map<String, dynamic>.from(body);
  return null;
}

class H {
  H(this.url, this.anon, this.svc);
  final String url, anon, svc;
  Map<String, String> hdr(String tok) => {
        'apikey': tok == svc ? svc : anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<Json> req(String method, String path,
      {String? tok, Object? body, Map<String, String>? extra}) async {
    final token = tok ?? anon;
    final headers = hdr(token);
    if (extra != null) headers.addAll(extra);
    final uri = Uri.parse(path.startsWith('http') ? path : '$url$path');
    try {
      late http.Response r;
      final c = http.Client();
      try {
        r = switch (method) {
          'GET' => await c.get(uri, headers: headers).timeout(const Duration(seconds: 30)),
          'POST' => await c
              .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
              .timeout(const Duration(seconds: 45)),
          'PATCH' => await c
              .patch(uri, headers: headers, body: body == null ? null : jsonEncode(body))
              .timeout(const Duration(seconds: 30)),
          'DELETE' => await c.delete(uri, headers: headers).timeout(const Duration(seconds: 30)),
          _ => throw StateError(method),
        };
      } finally {
        c.close();
      }
      Object? parsed = r.body;
      try {
        parsed = r.body.isEmpty ? null : jsonDecode(r.body);
      } catch (_) {}
      return {'http': r.statusCode, 'body': parsed, 'raw': r.body};
    } catch (e) {
      return {'http': 0, 'body': '$e'};
    }
  }
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final e2eSecret = env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '';
  final h = H(url, anon, svc);
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final BH = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final SH = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final bUid = await sb.userIdForAccessToken(BH);
  final sUid = await sb.userIdForAccessToken(SH);
  stdout.writeln('PASS2 $tag b=$bUid s=$sUid');

  // restore buyer type first
  await h.req('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: svc, body: {
    'user_type': 'comprador',
  });

  Future<Json?> prod(String title, double price, int qty) async {
    final r = await h.req('POST', '$url/rest/v1/products', tok: SH, body: {
      'seller_id': sUid,
      'title': title,
      'price': price,
      'quantity': qty,
      'ref_code': '$tag-${DateTime.now().millisecondsSinceEpoch}-$qty',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
      'category': 'Outros',
      'state': 'Bom',
    });
    final row = rowOf(r['body']);
    if (row?['id'] != null) createdProductIds.add('${row!['id']}');
    rec('prod_$title', {'http': r['http'], 'id': row?['id']});
    return row;
  }

  Future<Json?> order(String tok, Json body) async {
    final r = await h.req('POST', '$url/rest/v1/orders', tok: tok, body: body);
    rec('order', {'http': r['http'], 'req_pm': body['payment_method'], 'body': clip(r['body'], 220)});
    final row = rowOf(r['body']);
    if (row?['id'] != null) createdOrderIds.add('${row!['id']}');
    return row;
  }

  // ========== PROFILES (colunas reais) ==========
  stdout.writeln('-- profiles --');
  final piiSel = 'id,full_name,iban,mb_way,phone,email,user_type,phone_verified_at,stripe_account_id';
  final anonP = await h.req('GET', '$url/rest/v1/profiles?select=$piiSel&limit=8');
  rec('anon_profiles', {'http': anonP['http'], 'n': anonP['body'] is List ? (anonP['body'] as List).length : 0, 'sample': clip(anonP['body'], 280)});
  void piiFind(String id, String ident, Json r) {
    if (r['http'] != 200 || r['body'] is! List) return;
    for (final row in (r['body'] as List).whereType<Map>()) {
      final leaks = <String>[];
      for (final c in ['iban', 'mb_way', 'phone', 'email', 'stripe_account_id']) {
        final v = row[c];
        if (v != null && '$v'.trim().isNotEmpty) leaks.add(c);
      }
      if (leaks.isNotEmpty) {
        finding(
          id: id,
          sev: 'P1',
          surface: 'PROFILES',
          pre: 'SELECT PII',
          identity: ident,
          request: 'GET profiles $piiSel',
          response: {'id': row['id'], 'leaks': leaks},
          before: null,
          after: row,
          impact: 'PII ${leaks.join(",")} visível.',
          confidence: 'alta',
          variant: ident,
          fp: 'full_name público não conta.',
        );
        break;
      }
    }
  }
  piiFind('SAT27C2-PII-ANON', 'anon', anonP);
  final bSeller = await h.req('GET', '$url/rest/v1/profiles?id=eq.$sUid&select=$piiSel', tok: BH);
  rec('buyer_seller_profile', {'http': bSeller['http'], 'row': rowOf(bSeller['body'])});
  piiFind('SAT27C2-PII-XUSER', 'buyer', bSeller);

  final beforeUt = rowOf((await h.req('GET', '$url/rest/v1/profiles?id=eq.$bUid&select=$piiSel', tok: svc))['body']);
  rec('buyer_profile_before', beforeUt);

  for (final ut in ['admin', 'vendedor', 'admim', 'administrador', 'seller']) {
    final r = await h.req('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: BH, body: {'user_type': ut});
    final live = rowOf((await h.req('GET', '$url/rest/v1/profiles?id=eq.$bUid&select=user_type', tok: svc))['body']);
    rec('ut_$ut', {'http': r['http'], 'live': live?['user_type'], 'raw': clip(r['body'], 160)});
    if ('${live?['user_type']}' == ut && ut != 'comprador') {
      finding(
        id: 'SAT27C2-UT-$ut',
        sev: ut == 'admin' || ut == 'administrador' ? 'P0' : 'P1',
        surface: 'AUTH',
        pre: 'buyer JWT own profile',
        identity: 'buyer',
        request: 'PATCH profiles user_type=$ut',
        response: live,
        before: beforeUt?['user_type'],
        after: live?['user_type'],
        impact: 'Buyer elevou user_type para $ut.',
        confidence: 'alta',
        variant: ut,
        fp: 'eco 200 com valor antigo = fechado.',
      );
    }
  }

  // composition: elevate vendedor → mux
  await h.req('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: BH, body: {'user_type': 'vendedor'});
  final utNow = rowOf((await h.req('GET', '$url/rest/v1/profiles?id=eq.$bUid&select=user_type', tok: svc))['body']);
  rec('ut_for_mux', utNow);
  final mux = await h.req('POST', '$url/functions/v1/create-mux-live', tok: BH, body: {'title': '$tag mux after elevate'});
  rec('mux_after_elevate', {'http': mux['http'], 'body': clip(mux['body'], 220)});
  if (mux['http'] == 200 && '${utNow?['user_type']}' == 'vendedor') {
    finding(
      id: 'SAT27C2-UT-MUX',
      sev: 'P1',
      surface: 'MUX',
      pre: 'buyer PATCH user_type=vendedor',
      identity: 'buyer',
      request: 'create-mux-live',
      response: clip(mux['body']),
      before: 'comprador/403',
      after: mux['http'],
      impact: 'Elevação de papel → cria stream Mux (custo).',
      confidence: 'alta',
      variant: 'composition AUTH+MUX',
      fp: '403 mesmo após elevate = trigger não persistiu.',
    );
  }
  final ibanBefore = beforeUt?['iban'];
  final ibanP = await h.req('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: BH, body: {
    'iban': 'PT50000201231234567890154',
    'phone_verified_at': DateTime.now().toUtc().toIso8601String(),
  });
  final ibanLive = rowOf((await h.req('GET', '$url/rest/v1/profiles?id=eq.$bUid&select=iban,phone_verified_at,user_type', tok: svc))['body']);
  rec('iban_phone_patch', {'http': ibanP['http'], 'live': ibanLive});
  if (ibanLive != null && '${ibanLive['iban']}' == 'PT50000201231234567890154' && '${ibanBefore ?? ''}' != 'PT50000201231234567890154') {
    finding(
      id: 'SAT27C2-IBAN-OWN',
      sev: 'P3',
      surface: 'PROFILES',
      pre: 'own-row',
      identity: 'buyer',
      request: 'PATCH iban',
      response: ibanLive,
      before: ibanBefore,
      after: ibanLive['iban'],
      impact: 'IBAN próprio gravável (pode ser produto).',
      confidence: 'alta',
      variant: 'own iban',
      fp: 'intencional para payout MB WAY — P3 info.',
    );
  }
  if (ibanLive?['phone_verified_at'] != null && beforeUt?['phone_verified_at'] == null) {
    finding(
      id: 'SAT27C2-PHONE-VER',
      sev: 'P1',
      surface: 'AUTH',
      pre: 'buyer JWT',
      identity: 'buyer',
      request: 'PATCH phone_verified_at',
      response: ibanLive,
      before: beforeUt?['phone_verified_at'],
      after: ibanLive?['phone_verified_at'],
      impact: 'Auto-verificação de telefone.',
      confidence: 'alta',
      variant: 'phone_verified_at',
      fp: 'coluna ignorada = after null.',
    );
  }
  final xname = await h.req('PATCH', '$url/rest/v1/profiles?id=eq.$sUid', tok: BH, body: {'full_name': 'HACKED $tag'});
  rec('cross_full_name', {'http': xname['http'], 'body': clip(xname['body'], 160)});
  if (xname['http'] == 200 && xname['body'] is List && (xname['body'] as List).isNotEmpty) {
    finding(
      id: 'SAT27C2-PII-XUPD',
      sev: 'P0',
      surface: 'PROFILES',
      pre: 'buyer JWT',
      identity: 'buyer',
      request: 'PATCH seller full_name',
      response: clip(xname['body']),
      before: null,
      after: rowOf(xname['body']),
      impact: 'Cross-row profile write.',
      confidence: 'alta',
      variant: 'full_name',
      fp: '200 [] = RLS.',
    );
  }

  // restore buyer
  await h.req('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: svc, body: {
    'user_type': 'comprador',
    'iban': ibanBefore,
    'phone_verified_at': beforeUt?['phone_verified_at'],
  });

  // ========== PM substring variants + wallet composition ==========
  stdout.writeln('-- pm variants --');
  final pPm = await prod('$tag pm', 11.0, 3);
  final methods = [
    'Pagamento na app (Seguro Fleaber) mb way/transf',
    'Pagamento na app (Seguro Fleaber) mb way / transf',
    'Seguro Fleaber xmb way/transfx',
    'pix',
    'crypto',
    '  ',
    'proposta aceite',
    'pagamento direto ao vendedor HACK',
    'MB WAY',
    'Pagamento na app (Seguro Fleaber)',
  ];
  Json? stuffed;
  for (final pm in methods) {
    final o = await order(BH, {
      'product_id': pPm?['id'],
      'buyer_id': bUid,
      'seller_id': sUid,
      'price_total': 11,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': pm,
    });
    if (o?['id'] == null) continue;
    final mark = await h.req('PATCH', '$url/rest/v1/orders?id=eq.${o!['id']}', tok: SH, body: {'status': 'pago'});
    final live = rowOf((await h.req(
      'GET',
      '$url/rest/v1/orders?id=eq.${o['id']}&select=id,status,payment_method,amount_paid_cents',
      tok: svc,
    ))['body']);
    rec('pm_pago', {'pm': pm, 'status': live?['status'], 'http': mark['http']});
    final becamePago = '${live?['status']}'.toLowerCase() == 'pago' && ni(live?['amount_paid_cents']) == 0;
    final isRealOff = pm.toLowerCase().contains('pagamento direto ao vendedor') ||
        pm.toLowerCase() == 'mb way';
    if (becamePago && !isRealOff && pm.trim().isNotEmpty && pm.toLowerCase() != 'pagamento na app (seguro fleaber)') {
      finding(
        id: 'SAT27C2-PM-${pm.hashCode}',
        sev: 'P1',
        surface: 'ORDERS',
        pre: 'payment_method="$pm"',
        identity: 'seller',
        request: 'PATCH status=pago',
        response: live,
        before: 'reserva_pendente',
        after: 'pago',
        impact: 'Classificação off-platform por substring/typo; pago sem captura.',
        confidence: 'alta',
        variant: pm,
        fp: 'allowlist explícita MB WAY real é desenho.',
      );
      stuffed ??= o;
    }
  }

  if (stuffed?['id'] != null) {
    final id = stuffed!['id'];
    final bal0 = rowOf((await h.req('GET', '$url/rest/v1/wallets?id=eq.$sUid&select=balance', tok: svc))['body']);
    await h.req('PATCH', '$url/rest/v1/orders?id=eq.$id', tok: SH, body: {'status': 'enviado'});
    await h.req('PATCH', '$url/rest/v1/orders?id=eq.$id', tok: BH, body: {'status': 'concluido'});
    final st = rowOf((await h.req(
      'GET',
      '$url/rest/v1/orders?id=eq.$id&select=id,status,amount_paid_cents,wallet_release_processed_at,stock_units_applied,product_id',
      tok: svc,
    ))['body']);
    rec('stuffed_states', st);
    final rel = await h.req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', tok: BH, body: {'p_order_id': id});
    rec('stuffed_release', {'http': rel['http'], 'body': clip(rel['body'])});
    final bal1 = rowOf((await h.req('GET', '$url/rest/v1/wallets?id=eq.$sUid&select=balance', tok: svc))['body']);
    rec('stuffed_wallet', {'before': bal0, 'after': bal1, 'delta': nd(bal1?['balance']) - nd(bal0?['balance'])});
    if (nd(bal1?['balance']) - nd(bal0?['balance']) > 0.009) {
      finding(
        id: 'SAT27C2-INV-F',
        sev: 'P0',
        surface: 'WALLET',
        pre: 'PM stuffed → pago → concluido → release',
        identity: 'buyer RPC',
        request: 'batata_release_seller_wallet_for_order',
        response: {'delta': nd(bal1?['balance']) - nd(bal0?['balance']), 'rel': clip(rel['body']), 'st': st},
        before: bal0,
        after: bal1,
        impact: 'Fundos Fleaber mintados sem captura Stripe (invariante F).',
        confidence: 'alta',
        variant: 'composition ORDERS+WALLET',
        fp: 'release false + delta 0 = F mantida.',
      );
    }
    if (st?['product_id'] != null) {
      final stock = rowOf((await h.req(
        'GET',
        '$url/rest/v1/products?id=eq.${st!['product_id']}&select=quantity,is_sold',
        tok: svc,
      ))['body']);
      rec('stuffed_stock', stock);
    }
    // checkout still possible on stuffed paid?
    final ck = await h.req('POST', '$url/functions/v1/create-payment-intent', tok: BH, body: {
      'order_id': id,
      'buyer_id': bUid,
      'shipping_method': 'hand',
    });
    rec('checkout_after_fake_pago', {'http': ck['http'], 'body': clip(ck['body'], 180)});
  }

  // real MB WAY path for invariant F
  final pMb = await prod('$tag mb', 9.0, 2);
  final oMb = await order(BH, {
    'product_id': pMb?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'price_total': 9,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento direto ao vendedor (MB WAY/transf)',
  });
  if (oMb?['id'] != null) {
    await h.req('PATCH', '$url/rest/v1/orders?id=eq.${oMb!['id']}', tok: SH, body: {'status': 'pago'});
    await h.req('PATCH', '$url/rest/v1/orders?id=eq.${oMb['id']}', tok: SH, body: {'status': 'enviado'});
    await h.req('PATCH', '$url/rest/v1/orders?id=eq.${oMb['id']}', tok: BH, body: {'status': 'concluido'});
    final mbSt = rowOf((await h.req(
      'GET',
      '$url/rest/v1/orders?id=eq.${oMb['id']}&select=status,amount_paid_cents,wallet_release_processed_at',
      tok: svc,
    ))['body']);
    rec('mb_real_states', mbSt);
    final b0 = rowOf((await h.req('GET', '$url/rest/v1/wallets?id=eq.$sUid&select=balance', tok: svc))['body']);
    final rel = await h.req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', tok: BH, body: {'p_order_id': oMb['id']});
    final b1 = rowOf((await h.req('GET', '$url/rest/v1/wallets?id=eq.$sUid&select=balance', tok: svc))['body']);
    rec('mb_real_release', {'http': rel['http'], 'body': clip(rel['body']), 'delta': nd(b1?['balance']) - nd(b0?['balance']), 'st': mbSt});
    if (nd(b1?['balance']) - nd(b0?['balance']) > 0.009) {
      finding(
        id: 'SAT27C2-INV-F-MB',
        sev: 'P0',
        surface: 'WALLET',
        pre: 'MB WAY real concluido',
        identity: 'buyer',
        request: 'release',
        response: {'delta': nd(b1?['balance']) - nd(b0?['balance'])},
        before: b0,
        after: b1,
        impact: 'MB WAY off-platform mintou wallet.',
        confidence: 'alta',
        variant: 'canonical MB WAY',
        fp: 'delta 0 = F OK.',
      );
    }
  }

  // ========== REVIEWS / DISPUTES ==========
  stdout.writeln('-- reviews/disputes --');
  final pRv = await prod('$tag rv', 7.0, 2);
  final oRv = await order(BH, {
    'product_id': pRv?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'price_total': 7,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
  });
  if (oRv?['id'] != null) {
    final rev = await h.req('POST', '$url/rest/v1/reviews', tok: BH, body: {
      'order_id': oRv!['id'],
      'buyer_id': bUid,
      'target_id': sUid,
      'stars': 5,
      'comment': '$tag premature',
      'author_role': 'comprador',
    });
    rec('review_unpaid', {'http': rev['http'], 'body': clip(rev['body'], 200)});
    if (rev['http'] == 201 || (rev['http'] == 200 && rev['body'] is List && (rev['body'] as List).isNotEmpty)) {
      finding(
        id: 'SAT27C2-REV-STATE',
        sev: 'P1',
        surface: 'REVIEWS',
        pre: 'order não concluida',
        identity: 'buyer',
        request: 'INSERT reviews',
        response: clip(rev['body']),
        before: oRv['status'],
        after: rowOf(rev['body']),
        impact: 'Review sem estado terminal.',
        confidence: 'alta',
        variant: 'unpaid',
        fp: '400 invalid status = fechado.',
      );
    }
    final dIns = await h.req('POST', '$url/rest/v1/order_disputes', tok: BH, body: {
      'order_id': oRv['id'],
      'buyer_id': bUid,
      'reason': 'outro',
      'description': '$tag',
      'status': 'resolvida',
      'seller_refund_percent': 100,
    });
    rec('dispute_insert', {'http': dIns['http'], 'body': clip(dIns['body'], 220)});
    final drow = rowOf(dIns['body']);
    if (drow?['id'] != null) {
      final dUpd = await h.req('PATCH', '$url/rest/v1/order_disputes?id=eq.${drow!['id']}', tok: BH, body: {
        'status': 'resolvida',
        'seller_refund_percent': 100,
      });
      rec('dispute_buyer_resolve', {'http': dUpd['http'], 'body': clip(dUpd['body'], 180)});
      if (dUpd['http'] == 200 && dUpd['body'] is List && (dUpd['body'] as List).isNotEmpty) {
        final after = rowOf(dUpd['body']);
        if ('${after?['status']}' == 'resolvida') {
          finding(
            id: 'SAT27C2-DSP-RESOLVE',
            sev: 'P1',
            surface: 'DISPUTE',
            pre: 'buyer JWT',
            identity: 'buyer',
            request: 'PATCH dispute status=resolvida',
            response: after,
            before: drow['status'],
            after: after?['status'],
            impact: 'Buyer fecha disputa / define percentagem.',
            confidence: 'alta',
            variant: 'buyer resolve',
            fp: 'trigger reverte status.',
          );
        }
      }
    }
  }

  // ========== STORAGE fleaber_private ==========
  stdout.writeln('-- storage --');
  final listB = await h.req('POST', '$url/storage/v1/object/list/fleaber_private', tok: BH, body: {
    'prefix': '',
    'limit': 20,
  });
  rec('priv_list_buyer_root', {'http': listB['http'], 'body': clip(listB['body'], 300)});
  final listX = await h.req('POST', '$url/storage/v1/object/list/fleaber_private', tok: BH, body: {
    'prefix': sUid,
    'limit': 20,
  });
  rec('priv_list_seller_prefix', {'http': listX['http'], 'n': listX['body'] is List ? (listX['body'] as List).length : 0, 'body': clip(listX['body'], 250)});
  if (listX['http'] == 200 && listX['body'] is List && (listX['body'] as List).isNotEmpty) {
    finding(
      id: 'SAT27C2-STO-PRIV',
      sev: 'P1',
      surface: 'STORAGE',
      pre: 'prefix=sellerId',
      identity: 'buyer',
      request: 'list fleaber_private',
      response: clip(listX['body'], 200),
      before: null,
      after: null,
      impact: 'Listagem private do vendedor.',
      confidence: 'alta',
      variant: 'prefix',
      fp: 'pastas vazias/id null sem ficheiros não é leak de conteúdo.',
    );
  }
  final pub = await h.req('GET', '$url/storage/v1/object/public/chat_media/live_item_photos');
  rec('public_url_probe', {'http': pub['http']});

  // ========== STATE MACHINE ==========
  stdout.writeln('-- state machine --');
  final pSm = await prod('$tag sm', 6.0, 2);
  final oSm = await order(BH, {
    'product_id': pSm?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'price_total': 6,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
  });
  if (oSm?['id'] != null) {
    final id = oSm!['id'];
    for (final st in [
      'pago', 'enviado', 'entregue', 'concluido', 'pedido_devolucao',
      'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor',
      'devolvida', 'cancelado', 'premio_rifa',
    ]) {
      await h.req('PATCH', '$url/rest/v1/orders?id=eq.$id', tok: BH, body: {'status': st});
      await h.req('PATCH', '$url/rest/v1/orders?id=eq.$id', tok: SH, body: {'status': st});
    }
    final live = rowOf((await h.req(
      'GET',
      '$url/rest/v1/orders?id=eq.$id&select=status,amount_paid_cents',
      tok: svc,
    ))['body']);
    rec('sm_final', live);
    final bad = {'pago', 'enviado', 'entregue', 'concluido', 'devolvida', 'premio_rifa'};
    if (live != null && bad.contains('${live['status']}'.toLowerCase()) && ni(live['amount_paid_cents']) == 0) {
      finding(
        id: 'SAT27C2-SM',
        sev: 'P0',
        surface: 'ORDERS',
        pre: 'sem captura',
        identity: 'jwt',
        request: 'status jumps',
        response: live,
        before: 'reserva_pendente',
        after: live['status'],
        impact: 'Salto para venda/terminal sem pagamento.',
        confidence: 'alta',
        variant: '${live['status']}',
        fp: 'cancelado OK.',
      );
    }
  }

  // ========== RESERVATIONS ==========
  stdout.writeln('-- reservations --');
  final lives = await h.req(
    'GET',
    '$url/rest/v1/live_items?select=id,live_id,seller_id,price,product_id&seller_id=not.is.null&limit=5',
    tok: svc,
  );
  rec('live_items_with_seller', {'http': lives['http'], 'n': lives['body'] is List ? (lives['body'] as List).length : 0});
  Json? li;
  if (lives['body'] is List && (lives['body'] as List).isNotEmpty) {
    li = Map<String, dynamic>.from((lives['body'] as List).first as Map);
  }
  if (li?['id'] != null && li?['seller_id'] != null) {
    final res = await h.req('POST', '$url/rest/v1/live_reservation_requests', tok: BH, body: {
      'live_id': li!['live_id'],
      'live_item_id': li['id'],
      'seller_id': li['seller_id'],
      'buyer_id': bUid,
      'requested_qty': 9,
      'source': 'fleaber_live',
      'status': 'accepted',
    });
    rec('res_insert', {'http': res['http'], 'body': clip(res['body'], 220)});
    final rr = rowOf(res['body']);
    if (rr != null && (ni(rr['requested_qty']) >= 9 || '${rr['status']}' == 'accepted')) {
      finding(
        id: 'SAT27C2-RES',
        sev: 'P1',
        surface: 'RESERVATIONS',
        pre: 'direct INSERT',
        identity: 'buyer',
        request: 'qty=9 status=accepted',
        response: rr,
        before: null,
        after: {'qty': rr['requested_qty'], 'st': rr['status']},
        impact: 'Reserva aceite/qty sem seller RPC.',
        confidence: 'alta',
        variant: 'INSERT',
        fp: 'trigger pending/qty1.',
      );
    }
  }

  // ========== USD checkout ==========
  stdout.writeln('-- usd --');
  final pUsd = await prod('$tag usd', 20.0, 1);
  final oUsd = await order(BH, {
    'product_id': pUsd?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'price_total': 20,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
  });
  if (oUsd?['id'] != null) {
    final ck = await h.req('POST', '$url/functions/v1/create-payment-intent', tok: BH, body: {
      'order_id': oUsd!['id'],
      'buyer_id': bUid,
      'shipping_method': 'hand',
      'currency': 'usd',
    });
    rec('usd_checkout', {'http': ck['http'], 'body': clip(ck['body'], 400)});
    if (ck['http'] == 200 && ck['body'] is Map) {
      final urlCk = '${(ck['body'] as Map)['checkoutUrl'] ?? ''}';
      if (urlCk.isNotEmpty) {
        final page = await http.get(Uri.parse(urlCk.split('#').first)).timeout(const Duration(seconds: 20));
        final text = page.body.toLowerCase();
        rec('usd_page', {
          'http': page.statusCode,
          'has_usd': text.contains('usd') || text.contains('\$'),
          'has_eur': text.contains('eur') || text.contains('€'),
        });
        if ((text.contains('usd') || text.contains('\$')) && !text.contains('eur')) {
          finding(
            id: 'SAT27C2-CUR-USD',
            sev: 'P1',
            surface: 'CHECKOUT',
            pre: 'body.currency=usd',
            identity: 'buyer',
            request: 'create-payment-intent currency=usd',
            response: {'page_usd': true},
            before: 'eur',
            after: 'usd',
            impact: 'Checkout em USD com preços EUR (cêntimos).',
            confidence: 'média',
            variant: 'usd',
            fp: 'página Stripe sempre menciona várias moedas.',
          );
        }
      }
    }
  }

  // ========== E2E bag via staging secret ==========
  stdout.writeln('-- e2e bag --');
  if (e2eSecret.length >= 16) {
    final e2e = await h.req(
      'POST',
      '$url/functions/v1/sec-fase2-e2e-oversell',
      tok: anon,
      extra: {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'x-fleaber-e2e-secret': e2eSecret,
        'Content-Type': 'application/json',
      },
      body: {'probe': 'setup_paid_bag', 'buyer_id': bUid, 'seller_id': sUid},
    );
    rec('e2e_bag', {'http': e2e['http'], 'body': clip(e2e['body'], 600)});
    if (e2e['body'] is Map) {
      final m = e2e['body'] as Map;
      if (m['ok'] == true && m['invariant_sum_eq_pi'] == false) {
        finding(
          id: 'SAT27C2-BAG-SUM',
          sev: 'P1',
          surface: 'BAG',
          pre: 'setup_paid_bag',
          identity: 'harness',
          request: 'sec-fase2-e2e-oversell',
          response: {'sum': m['sum_amount_paid_cents'], 'pi': m['pi_amount_cents']},
          before: m['pi_amount_cents'],
          after: m['sum_amount_paid_cents'],
          impact: 'Σ parcelas ≠ captura.',
          confidence: 'alta',
          variant: '2 linhas',
          fp: 'harness settle.',
        );
      }
      final orders = (m['orders'] as List?) ?? [];
      if (orders.isNotEmpty) {
        final oid = '${(orders.first as Map)['id']}';
        createdOrderIds.add(oid);
        final refB = await h.req('POST', '$url/functions/v1/refund-order', tok: BH, body: {'order_id': oid});
        rec('refund_buyer', {'http': refB['http'], 'body': clip(refB['body'], 200)});
        if (refB['http'] == 200 && refB['body'] is Map && (refB['body'] as Map)['ok'] == true && (refB['body'] as Map)['skipped'] != true) {
          finding(
            id: 'SAT27C2-REF-BUYER',
            sev: 'P0',
            surface: 'REFUND',
            pre: 'bag pago',
            identity: 'buyer',
            request: 'refund-order',
            response: clip(refB['body']),
            before: 'pago',
            after: clip(refB['body']),
            impact: 'Buyer reembolsa.',
            confidence: 'alta',
            variant: 'buyer',
            fp: '403/skipped.',
          );
        }
        final refS = await h.req('POST', '$url/functions/v1/refund-order', tok: SH, body: {'order_id': oid});
        rec('refund_seller_A', {'http': refS['http'], 'body': clip(refS['body'], 250)});
        final refS2 = await h.req('POST', '$url/functions/v1/refund-order', tok: SH, body: {'order_id': oid});
        rec('refund_seller_A_dup', {'http': refS2['http'], 'body': clip(refS2['body'], 200)});
        if (orders.length > 1) {
          final oidB = '${(orders[1] as Map)['id']}';
          createdOrderIds.add(oidB);
          final rB = await h.req('POST', '$url/functions/v1/refund-order', tok: SH, body: {'order_id': oidB});
          rec('refund_seller_B', {'http': rB['http'], 'body': clip(rB['body'], 250)});
        }
      }
    }
    final ov = await h.req(
      'POST',
      '$url/functions/v1/sec-fase2-e2e-oversell',
      tok: anon,
      extra: {
        'apikey': anon,
        'Authorization': 'Bearer $anon',
        'x-fleaber-e2e-secret': e2eSecret,
        'Content-Type': 'application/json',
      },
      body: {'probe': 'oversell', 'buyer_id': bUid, 'seller_id': sUid},
    );
    rec('e2e_oversell', {'http': ov['http'], 'body': clip(ov['body'], 400)});
  } else {
    notes.add('E2E secret ausente — bag/refund Stripe não corridos nesta passagem.');
  }

  // RPC credit with real-looking uuid still
  final cred = await h.req('POST', '$url/rest/v1/rpc/batata_credit_wallet_once', tok: BH, body: {
    'p_wallet_id': bUid,
    'p_order_id': oSm?['id'] ?? '00000000-0000-0000-0000-000000000001',
    'p_amount': 50,
    'p_type': 'reembolso',
    'p_description': 'x',
  });
  rec('credit_jwt', {'http': cred['http'], 'body': clip(cred['body'], 160)});

  // cleanup
  await h.req('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: svc, body: {'user_type': 'comprador'});
  for (final id in createdOrderIds.toSet()) {
    await h.req('DELETE', '$url/rest/v1/order_disputes?order_id=eq.$id', tok: svc);
    await h.req('DELETE', '$url/rest/v1/reviews?order_id=eq.$id', tok: svc);
    await h.req('DELETE', '$url/rest/v1/orders?id=eq.$id', tok: svc);
  }
  for (final id in createdProductIds.toSet()) {
    await h.req('DELETE', '$url/rest/v1/products?id=eq.$id', tok: svc);
  }

  final out = {
    'meta': {'tag': tag, 'when': DateTime.now().toUtc().toIso8601String()},
    'findings': findings,
    'notes': notes,
    'n_probes': probes.length,
  };
  File('tool/reports/SAT_CEGA_PASS2_RAW_20260827.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({...out, 'probes': probes}),
  );
  stdout.writeln('FINDINGS=${findings.length}');
  for (final f in findings) {
    stdout.writeln('  ${f['severity']} ${f['id']} — ${f['impact']}');
  }
}
