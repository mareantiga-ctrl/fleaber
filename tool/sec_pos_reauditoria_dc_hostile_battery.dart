// ignore_for_file: avoid_print
/// Pós-reauditoria DC — P2/P3 residuals + concorrência.
/// dart run tool/sec_pos_reauditoria_dc_hostile_battery.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: service,
  );
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final buyerToken = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerToken = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  // Stranger (outro JWT autenticado) — cria efémero se necessário.
  final strangerEmail =
      'dc-stranger-${DateTime.now().millisecondsSinceEpoch}@fleaber.test';
  final strangerPass = 'Stranger!${DateTime.now().millisecondsSinceEpoch}';
  late final String strangerToken;
  try {
    await sb.createAdminUser(email: strangerEmail, password: strangerPass);
    strangerToken = await sb.signIn(
      email: strangerEmail,
      password: strangerPass,
    );
  } catch (_) {
    strangerToken = buyerToken; // fallback: stranger checks still use wrong role
  }

  final results = <Map<String, dynamic>>[];
  void add(String id, bool pass, String detail) {
    results.add({'id': id, 'pass': pass, 'detail': detail});
    print('${pass ? "PASS" : "FAIL"} $id — $detail');
  }

  Future<double> bal(String uid) async {
    final rows = await sb.select('wallets', filter: 'id=eq.$uid', limit: 1);
    if (rows.isEmpty) return 0;
    return (rows.first['balance'] as num?)?.toDouble() ?? 0;
  }

  Future<double> netDisbursed(String orderId) async {
    final txs = await sb.select(
      'wallet_transactions',
      filter: 'order_id=eq.$orderId',
      limit: 50,
    );
    var s = 0.0;
    for (final t in txs) {
      final type = '${t['type']}';
      final amt = (t['amount'] as num?)?.toDouble() ?? 0;
      if (type == 'venda' || type == 'reembolso') s += amt;
      if (type == 'estorno') s -= amt;
    }
    return s < 0 ? 0 : s;
  }

  Future<List<Map<String, dynamic>>> txs(String orderId) => sb.select(
        'wallet_transactions',
        filter: 'order_id=eq.$orderId',
        limit: 50,
      );

  Future<String> orderStatus(String orderId) async {
    final rows = await sb.select('orders', filter: 'id=eq.$orderId', limit: 1);
    return '${rows.first['status']}'.toLowerCase();
  }

  Future<Map<String, dynamic>> product({int qty = 5, double price = 3.0}) {
    return sb.insert('products', {
      'seller_id': sellerId,
      'title': 'DC ${DateTime.now().microsecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'ref_code': 'DC-${DateTime.now().microsecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': true,
      'is_sold': false,
      'image_urls': <String>[],
    });
  }

  Future<Map<String, dynamic>> orderFor(
    String productId, {
    double price = 3.0,
    int qty = 1,
  }) {
    return sb.insertAsUser(
      'orders',
      {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': productId,
        'quantity': qty,
        'price_total': price,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
      },
      accessToken: buyerToken,
    );
  }

  Future<void> capture(String orderId, {int cents = 300}) async {
    await sb.patch('orders', 'id=eq.$orderId', {
      'status': 'pago',
      'amount_paid_cents': cents,
      'stock_units_applied': 1,
      'price_total': cents / 100.0,
    });
  }

  Future<void> cleanupOrder(String orderId, String productId) async {
    final tlist = await txs(orderId);
    for (final t in tlist) {
      await sb.deleteWhere('wallet_transactions', 'id=eq.${t['id']}');
    }
    await sb.deleteWhere('fleaber_commissions', 'order_id=eq.$orderId');
    await sb.deleteWhere('reviews', 'order_id=eq.$orderId');
    await sb.deleteWhere('order_disputes', 'order_id=eq.$orderId');
    await sb.deleteWhere('orders', 'id=eq.$orderId');
    await sb.deleteWhere('products', 'id=eq.$productId');
  }

  Future<void> restoreBals(double b0, double s0) async {
    await sb.patch('wallets', 'id=eq.$buyerId', {'balance': b0});
    await sb.patch('wallets', 'id=eq.$sellerId', {'balance': s0});
  }

  Future<Map<String, dynamic>> insertDispute(
    String orderId, {
    String? status,
  }) {
    return sb.insertAsUser(
      'order_disputes',
      {
        'order_id': orderId,
        'buyer_id': buyerId,
        'reason': 'outro',
        'description': 'dc-dispute',
        if (status != null) 'status': status,
      },
      accessToken: buyerToken,
    );
  }

  // =========================================================================
  // A) Máquina de estados — devolvida / pedido_devolucao
  // =========================================================================
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: sellerToken,
    );
    final st = await orderStatus(o['id'] as String);
    add(
      'A1_SELLER_DEVOLVIDA_SEM_DISPUTA',
      st != 'devolvida',
      'status=$st (esperado ≠ devolvida)',
    );
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('A1_SELLER_DEVOLVIDA_SEM_DISPUTA', false, '$e');
  }

  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final p2 = await product();
    final o2 = await orderFor(p2['id'] as String);
    await capture(o['id'] as String);
    await capture(o2['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await sb.patch('orders', 'id=eq.${o2['id']}', {'status': 'concluido'});
    await insertDispute(o2['id'] as String); // disputa de OUTRA order
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'devolucao_entregue',
    });
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: sellerToken,
    );
    final st = await orderStatus(o['id'] as String);
    add(
      'A2_SELLER_DEVOLVIDA_DISPUTA_OUTRA_ORDER',
      st != 'devolvida',
      'status=$st',
    );
    await cleanupOrder(o['id'] as String, p['id'] as String);
    await cleanupOrder(o2['id'] as String, p2['id'] as String);
  } catch (e) {
    add('A2_SELLER_DEVOLVIDA_DISPUTA_OUTRA_ORDER', false, '$e');
  }

  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    final d = await insertDispute(o['id'] as String);
    await sb.patch('order_disputes', 'id=eq.${d['id']}', {'status': 'recusada'});
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'devolucao_entregue',
    });
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: sellerToken,
    );
    final st = await orderStatus(o['id'] as String);
    add(
      'A3_SELLER_DEVOLVIDA_DISPUTA_RECUSADA',
      st != 'devolvida',
      'status=$st',
    );
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('A3_SELLER_DEVOLVIDA_DISPUTA_RECUSADA', false, '$e');
  }

  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await sb.insertAsUser(
      'reviews',
      {
        'order_id': o['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'dc-release',
        'author_role': 'comprador',
        'target_type': 'vendedor',
      },
      accessToken: buyerToken,
    );
    // Tentar fabricar devolvida após release sem cadeia
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: sellerToken,
    );
    final st = await orderStatus(o['id'] as String);
    final net = await netDisbursed(o['id'] as String);
    add(
      'A4_SELLER_DEVOLVIDA_APOS_RELEASE',
      st != 'devolvida' && net <= 3.01,
      'status=$st net=$net',
    );
    await restoreBals(b0, s0);
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('A4_SELLER_DEVOLVIDA_APOS_RELEASE', false, '$e');
  }

  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await insertDispute(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'devolucao_entregue',
    });
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: buyerToken,
    );
    final st = await orderStatus(o['id'] as String);
    add('A5_BUYER_DEVOLVIDA', st != 'devolvida', 'status=$st');
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('A5_BUYER_DEVOLVIDA', false, '$e');
  }

  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await insertDispute(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'devolucao_entregue',
    });
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: strangerToken,
    );
    final st = await orderStatus(o['id'] as String);
    add('A6_STRANGER_DEVOLVIDA', st != 'devolvida', 'status=$st');
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('A6_STRANGER_DEVOLVIDA', false, '$e');
  }

  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await insertDispute(o['id'] as String);
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'pedido_devolucao'},
      accessToken: buyerToken,
    );
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'em_devolucao'});
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'devolucao_entregue',
    });
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: sellerToken,
    );
    final st = await orderStatus(o['id'] as String);
    final net = await netDisbursed(o['id'] as String);
    final buyerDelta = (await bal(buyerId)) - b0;
    add(
      'A7_LEGITIMO_DEVOLUCAO',
      st == 'devolvida' && net <= 3.01 && buyerDelta <= 3.01,
      'status=$st net=$net buyerΔ=$buyerDelta',
    );
    await restoreBals(b0, s0);
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('A7_LEGITIMO_DEVOLUCAO', false, '$e');
  }

  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await insertDispute(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'devolucao_entregue',
    });
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: sellerToken,
    );
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: sellerToken,
    );
    final net = await netDisbursed(o['id'] as String);
    final tlist = await txs(o['id'] as String);
    final refunds =
        tlist.where((t) => '${t['type']}' == 'reembolso').length;
    add(
      'A8_RETRY_DEVOLVIDA',
      refunds <= 1 && net <= 3.01,
      'refunds=$refunds net=$net',
    );
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('A8_RETRY_DEVOLVIDA', false, '$e');
  }

  // =========================================================================
  // B) pedido_devolucao após release
  // =========================================================================
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await sb.insertAsUser(
      'reviews',
      {
        'order_id': o['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'dc-b',
        'author_role': 'comprador',
        'target_type': 'vendedor',
      },
      accessToken: buyerToken,
    );
    // Dispute insert deve falhar pós-release; mesmo assim tentar status
    try {
      await insertDispute(o['id'] as String);
    } catch (_) {}
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'pedido_devolucao'},
      accessToken: buyerToken,
    );
    final st = await orderStatus(o['id'] as String);
    add(
      'B1_BUYER_PEDIDO_DEVOLUCAO_APOS_RELEASE',
      st != 'pedido_devolucao',
      'status=$st',
    );
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('B1_BUYER_PEDIDO_DEVOLUCAO_APOS_RELEASE', false, '$e');
  }

  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'pedido_devolucao'},
      accessToken: buyerToken,
    );
    final st = await orderStatus(o['id'] as String);
    add(
      'B2_BUYER_PEDIDO_SEM_DISPUTA',
      st != 'pedido_devolucao',
      'status=$st',
    );
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('B2_BUYER_PEDIDO_SEM_DISPUTA', false, '$e');
  }

  // =========================================================================
  // C) Ledger append-only (venda + estorno)
  // =========================================================================
  // C) Ledger append-only — release sem disputa, depois devolvida via service_role
  // (JWT seller sem disputa já bloqueado; clawback cobre caminho ops/legado)
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await sb.insertAsUser(
      'reviews',
      {
        'order_id': o['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'dc-ledger',
        'author_role': 'comprador',
        'target_type': 'vendedor',
      },
      accessToken: buyerToken,
    );
    final sAfterRelease = await bal(sellerId);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'devolvida'});
    final tlist = await txs(o['id'] as String);
    final vendas = tlist.where((t) => '${t['type']}' == 'venda').length;
    final estornos = tlist.where((t) => '${t['type']}' == 'estorno').length;
    final net = await netDisbursed(o['id'] as String);
    add(
      'C1_LEDGER_APPEND_ONLY',
      (sAfterRelease - s0) > 0 &&
          vendas >= 1 &&
          estornos >= 1 &&
          net <= 3.01,
      'sellerCredit=${sAfterRelease - s0} vendas=$vendas estornos=$estornos net=$net '
      'types=${tlist.map((t) => t['type']).toList()}',
    );
    await restoreBals(b0, s0);
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('C1_LEDGER_APPEND_ONLY', false, '$e');
  }

  // =========================================================================
  // D) Stripe orphan × wallet
  // =========================================================================
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await insertDispute(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'devolucao_entregue',
      'stripe_refund_id': 're_orphan_dc_test',
    });
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: sellerToken,
    );
    final b1 = await bal(buyerId);
    final tlist = await txs(o['id'] as String);
    final refunds =
        tlist.where((t) => '${t['type']}' == 'reembolso').length;
    add(
      'D1_STRIPE_ORPHAN_NO_WALLET_MINT',
      (b1 - b0).abs() < 0.01 && refunds == 0,
      'buyerΔ=${b1 - b0} refunds=$refunds',
    );
    await restoreBals(b0, s0);
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('D1_STRIPE_ORPHAN_NO_WALLET_MINT', false, '$e');
  }

  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await sb.insertAsUser(
      'reviews',
      {
        'order_id': o['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'dc-d2',
        'author_role': 'comprador',
        'target_type': 'vendedor',
      },
      accessToken: buyerToken,
    );
    // Simula refund Stripe oficial (cancelado + stripe_refund_id)
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'cancelado',
      'stripe_refund_id': 're_official_dc',
    });
    final net = await netDisbursed(o['id'] as String);
    final b1 = await bal(buyerId);
    add(
      'D2_STRIPE_CANCEL_NO_WALLET_BUYER',
      (b1 - b0).abs() < 0.01 && net < 0.01,
      'buyerΔ=${b1 - b0} net=$net',
    );
    await restoreBals(b0, s0);
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('D2_STRIPE_CANCEL_NO_WALLET_BUYER', false, '$e');
  }

  // =========================================================================
  // E) Concorrência — races reais
  // =========================================================================
  Future<bool> raceInvariant({
    required String label,
    required Future<void> Function(String orderId) setup,
    required List<Future<void> Function(String orderId)> attacks,
    required double captureEur,
    int rounds = 8,
  }) async {
    var ok = true;
    final details = <String>[];
    for (var r = 0; r < rounds; r++) {
      final p = await product();
      final o = await orderFor(p['id'] as String);
      final oid = o['id'] as String;
      final b0 = await bal(buyerId);
      final s0 = await bal(sellerId);
      await capture(oid, cents: (captureEur * 100).round());
      await setup(oid);
      await Future.wait(attacks.map((fn) async {
        try {
          await fn(oid);
        } catch (_) {}
      }));
      final net = await netDisbursed(oid);
      final over = net > captureEur + 0.02;
      if (over) {
        ok = false;
        details.add('r$r net=$net > $captureEur');
      }
      await restoreBals(b0, s0);
      await cleanupOrder(oid, p['id'] as String);
    }
    add(
      label,
      ok,
      ok ? '${rounds}x net≤$captureEur' : details.join('; '),
    );
    return ok;
  }

  await raceInvariant(
    label: 'E1_CONC_RELEASE_REFUND',
    captureEur: 3.0,
    setup: (oid) async {
      await sb.patch('orders', 'id=eq.$oid', {'status': 'concluido'});
      await insertDispute(oid);
      await sb.patch('orders', 'id=eq.$oid', {'status': 'devolucao_entregue'});
    },
    attacks: [
      (oid) => sb.rpc(
            'batata_release_seller_wallet_for_order',
            {'p_order_id': oid},
            accessToken: buyerToken,
          ).then((_) {}),
      (oid) => sb
          .patchAsUser(
            'orders',
            'id=eq.$oid',
            {'status': 'devolvida'},
            accessToken: sellerToken,
          )
          .then((_) {}),
      (oid) => sb.rpc(
            'batata_release_seller_wallet_for_order',
            {'p_order_id': oid},
            accessToken: buyerToken,
          ).then((_) {}),
      (oid) => sb
          .patchAsUser(
            'orders',
            'id=eq.$oid',
            {'status': 'devolvida'},
            accessToken: sellerToken,
          )
          .then((_) {}),
    ],
  );

  await raceInvariant(
    label: 'E2_CONC_TWO_PARTIAL',
    captureEur: 4.0,
    rounds: 6,
    setup: (oid) async {
      await sb.patch('orders', 'id=eq.$oid', {'status': 'concluido'});
      final d = await insertDispute(oid);
      await sb.patch('order_disputes', 'id=eq.${d['id']}', {
        'seller_refund_percent': 40,
        'seller_offer_type': 'partial_refund',
        'seller_offer_set_by': sellerId,
      });
    },
    attacks: [
      (oid) => sb
          .rpc(
            'batata_process_partial_refund_dispute',
            {'p_order_id': oid},
            accessToken: buyerToken,
          )
          .then((_) {}),
      (oid) => sb
          .rpc(
            'batata_process_partial_refund_dispute',
            {'p_order_id': oid},
            accessToken: buyerToken,
          )
          .then((_) {}),
      (oid) => sb
          .rpc(
            'batata_process_partial_refund_dispute',
            {'p_order_id': oid},
            accessToken: buyerToken,
          )
          .then((_) {}),
    ],
  );

  await raceInvariant(
    label: 'E3_CONC_RELEASE_PARTIAL',
    captureEur: 5.0,
    rounds: 6,
    setup: (oid) async {
      await sb.patch('orders', 'id=eq.$oid', {'status': 'concluido'});
      final d = await insertDispute(oid);
      await sb.patch('order_disputes', 'id=eq.${d['id']}', {
        'seller_refund_percent': 50,
        'seller_offer_type': 'partial_refund',
        'seller_offer_set_by': sellerId,
      });
    },
    attacks: [
      (oid) => sb.rpc(
            'batata_release_seller_wallet_for_order',
            {'p_order_id': oid},
            accessToken: buyerToken,
          ).then((_) {}),
      (oid) => sb
          .rpc(
            'batata_process_partial_refund_dispute',
            {'p_order_id': oid},
            accessToken: buyerToken,
          )
          .then((_) {}),
      (oid) => sb.rpc(
            'batata_release_seller_wallet_for_order',
            {'p_order_id': oid},
            accessToken: buyerToken,
          ).then((_) {}),
    ],
  );

  await raceInvariant(
    label: 'E4_CONC_REVIEW_DEVOLVIDA',
    captureEur: 3.0,
    rounds: 6,
    setup: (oid) async {
      await sb.patch('orders', 'id=eq.$oid', {'status': 'concluido'});
      await insertDispute(oid);
      await sb.patch('orders', 'id=eq.$oid', {'status': 'devolucao_entregue'});
    },
    attacks: [
      (oid) async {
        try {
          await sb.insertAsUser(
            'reviews',
            {
              'order_id': oid,
              'buyer_id': buyerId,
              'target_id': sellerId,
              'stars': 5,
              'comment': 'race',
              'author_role': 'comprador',
              'target_type': 'vendedor',
            },
            accessToken: buyerToken,
          );
        } catch (_) {}
      },
      (oid) => sb
          .patchAsUser(
            'orders',
            'id=eq.$oid',
            {'status': 'devolvida'},
            accessToken: sellerToken,
          )
          .then((_) {}),
      (oid) async {
        try {
          await sb.insertAsUser(
            'reviews',
            {
              'order_id': oid,
              'buyer_id': buyerId,
              'target_id': sellerId,
              'stars': 4,
              'comment': 'race2',
              'author_role': 'comprador',
              'target_type': 'vendedor',
            },
            accessToken: buyerToken,
          );
        } catch (_) {}
      },
    ],
  );

  // =========================================================================
  // F) Payout × clawback
  // =========================================================================
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await capture(o['id'] as String, cents: 300);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await insertDispute(o['id'] as String);
    await sb.insertAsUser(
      'reviews',
      {
        'order_id': o['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'dc-payout',
        'author_role': 'comprador',
        'target_type': 'vendedor',
      },
      accessToken: buyerToken,
    );
    final s1 = await bal(sellerId);
    final credited = s1 - s0;
    await sb.patch('orders', 'id=eq.${o['id']}', {
      'status': 'devolucao_entregue',
    });
    await sb.patchAsUser(
      'orders',
      'id=eq.${o['id']}',
      {'status': 'devolvida'},
      accessToken: sellerToken,
    );
    final s2 = await bal(sellerId);
    final b1 = await bal(buyerId);
    final net = await netDisbursed(o['id'] as String);
    add(
      'F1_DISPUTE_BLOCKS_RELEASE',
      credited.abs() < 0.01 &&
          (s2 - s0).abs() < 0.01 &&
          (b1 - b0 - 3.0).abs() < 0.02 &&
          net <= 3.01,
      'credited=$credited sellerΔ=${s2 - s0} buyerΔ=${b1 - b0} net=$net',
    );
    await restoreBals(b0, s0);
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('F1_DISPUTE_BLOCKS_RELEASE', false, '$e');
  }

  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    final b0 = await bal(buyerId);
    final s0 = await bal(sellerId);
    await capture(o['id'] as String, cents: 300);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await sb.insertAsUser(
      'reviews',
      {
        'order_id': o['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'dc-payout2',
        'author_role': 'comprador',
        'target_type': 'vendedor',
      },
      accessToken: buyerToken,
    );
    final credited = (await bal(sellerId)) - s0;
    await sb.patch('wallets', 'id=eq.$sellerId', {'balance': 0});
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'devolvida'});
    final s2 = await bal(sellerId);
    final b1 = await bal(buyerId);
    final tlist = await txs(o['id'] as String);
    final hasEstorno = tlist.any((t) => '${t['type']}' == 'estorno');
    final net = await netDisbursed(o['id'] as String);
    add(
      'F2_LEGACY_PAYOUT_CLAWBACK_FLOOR',
      credited > 0 && s2 >= -0.001 && hasEstorno && net <= 3.01,
      'credited=$credited sellerAfter=$s2 buyerΔ=${b1 - b0} net=$net '
      'risco_ops=service_devolvida_after_payout_platform_may_absorb',
    );
    await restoreBals(b0, s0);
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('F2_LEGACY_PAYOUT_CLAWBACK_FLOOR', false, '$e');
  }

  // =========================================================================
  // G) Qty inválida fail-closed
  // =========================================================================
  try {
    final p = await product();
    var rejected = false;
    try {
      await sb.insertAsUser(
        'orders',
        {
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'product_id': p['id'],
          'quantity': 0,
          'price_total': 3.0,
          'status': 'reserva_pendente',
          'payment_method': 'Pagamento na app',
        },
        accessToken: buyerToken,
      );
    } catch (_) {
      rejected = true;
    }
    add('G1_QTY_ZERO_REJECT', rejected, 'rejected=$rejected');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('G1_QTY_ZERO_REJECT', false, '$e');
  }

  try {
    final p = await product();
    var rejected = false;
    try {
      await sb.insertAsUser(
        'orders',
        {
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'product_id': p['id'],
          'quantity': -2,
          'price_total': 3.0,
          'status': 'reserva_pendente',
          'payment_method': 'Pagamento na app',
        },
        accessToken: buyerToken,
      );
    } catch (_) {
      rejected = true;
    }
    add('G2_QTY_NEG_REJECT', rejected, 'rejected=$rejected');
    await sb.deleteWhere('products', 'id=eq.${p['id']}');
  } catch (e) {
    add('G2_QTY_NEG_REJECT', false, '$e');
  }

  // =========================================================================
  // H) Reviews públicas sem PII
  // =========================================================================
  try {
    final p = await product();
    final o = await orderFor(p['id'] as String);
    await capture(o['id'] as String);
    await sb.patch('orders', 'id=eq.${o['id']}', {'status': 'concluido'});
    await sb.insertAsUser(
      'reviews',
      {
        'order_id': o['id'],
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'dc-public',
        'author_role': 'comprador',
        'target_type': 'vendedor',
      },
      accessToken: buyerToken,
    );
    final pub = await sb.selectAsUser(
      'reviews_public_ratings',
      accessToken: strangerToken,
      filter: 'target_id=eq.$sellerId',
      limit: 20,
    );
    final hasStars = pub.any((r) => (r['stars'] as num?) == 5);
    final leaked = pub.any(
      (r) => r.containsKey('buyer_id') || r.containsKey('order_id'),
    );
    final tableAsStranger = await sb.selectAsUser(
      'reviews',
      accessToken: strangerToken,
      filter: 'order_id=eq.${o['id']}',
      limit: 5,
    );
    add(
      'H1_REVIEWS_PUBLIC_NO_PII',
      hasStars && !leaked && tableAsStranger.isEmpty,
      'pub=${pub.length} leaked=$leaked tableStranger=${tableAsStranger.length}',
    );
    await cleanupOrder(o['id'] as String, p['id'] as String);
  } catch (e) {
    add('H1_REVIEWS_PUBLIC_NO_PII', false, '$e');
  }

  // Cleanup stranger user best-effort
  try {
    final users = await http.get(
      Uri.parse('$url/auth/v1/admin/users?page=1&per_page=50'),
      headers: {
        'apikey': service,
        'Authorization': 'Bearer $service',
      },
    );
    if (users.statusCode < 400) {
      final body = jsonDecode(users.body);
      final list = body is Map ? body['users'] as List? : null;
      if (list != null) {
        for (final u in list) {
          final m = Map<String, dynamic>.from(u as Map);
          if ('${m['email']}' == strangerEmail) {
            await http.delete(
              Uri.parse('$url/auth/v1/admin/users/${m['id']}'),
              headers: {
                'apikey': service,
                'Authorization': 'Bearer $service',
              },
            );
          }
        }
      }
    }
  } catch (_) {}

  final failed = results.where((r) => r['pass'] != true).length;
  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'staging': 'fxdknzrqjenzqcvnwqqq',
    'total': results.length,
    'failed': failed,
    'pass': failed == 0,
    'results': results,
  };
  final path = File(
    'tool/reports/HARDENING_POS_REAUDITORIA_DC_HOSTILE.json',
  );
  await path.writeAsString(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  print('\nWrote ${path.path} failed=$failed/${results.length}');
  exit(failed == 0 ? 0 : 1);
}
