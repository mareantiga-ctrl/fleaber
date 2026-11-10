import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '_http.dart';

const tables = [
  'orders',
  'products',
  'profiles',
  'wallets',
  'wallet_transactions',
  'wallet_payout_ledger',
  'fleaber_commissions',
  'reviews',
  'reviews_public_ratings',
  'disputes',
  'order_disputes',
  'return_requests',
  'chat_threads',
  'chat_messages',
  'messages',
  'conversations',
  'lives',
  'live_items',
  'live_reservation_requests',
  'live_raffles',
  'live_raffle_tickets',
  'live_raffle_winners',
  'live_tips',
  'live_messages',
  'product_offers',
  'product_bundles',
  'bundle_items',
  'notifications',
  'favorites',
  'follows',
  'seller_device_tokens',
  'device_tokens',
  'ps_pairing_codes',
  'ps_ingest_audit',
  'stripe_checkout_events',
  'app_logs',
  'storage_objects',
  'staff_invites',
  'user_roles',
  'admins',
];

const rpcCandidates = [
  'batata_credit_wallet_once',
  'batata_debit_wallet_once',
  'batata_ensure_wallet',
  'batata_release_seller_wallet_for_order',
  'batata_refund_buyer_wallet_for_order',
  'batata_clawback_seller_wallet_for_order',
  'batata_process_partial_refund_dispute',
  'batata_wallet_payout_debit',
  'batata_wallet_payout_finish',
  'batata_wallet_apply_tip_once',
  'batata_send_live_tip_from_wallet',
  'batata_find_user_id_by_email',
  'batata_seller_direct_payment_details',
  'batata_get_my_payout_details',
  'batata_mark_live_item_sold',
  'batata_live_reconcile_stripe_order',
  'batata_sync_live_item_for_order',
  'batata_lab_clear_all_fm_pending',
  'batata_lab_clear_fm_pending',
  'batata_generate_auto_feedback',
  'batata_create_raffle_prize_order',
  'batata_award_live_raffle_tickets',
  'batata_tick_live_raffle',
  'batata_create_seller_device_token',
  'batata_ps_claim_pairing',
  'batata_live_bag_update_qty',
  'batata_live_reservation_accept_available',
  'batata_live_item_stock',
  'batata_product_checkout_available',
  'batata_backfill_handle_suggestions',
  'batata_invoke_livekit_egress_cleanup',
  'batata_anon_rate_check',
  'batata_claim_handle',
  'batata_resolve_handle',
  'batata_publish_hub',
];

const edges = [
  'create-payment-intent',
  'create-live-tip-checkout',
  'refund-order',
  'create-connect-account',
  'create-mux-live',
  'complete-mux-live',
  'livekit-mux-publish',
  'ingest-ocr-reservation',
  'ps-pairing-claim',
  'ps-heartbeat',
  'ps-panel-log',
  'delete-test-account',
  'send-sms-bulkgate',
  'sec-fase2-e2e-oversell',
  'stripe-webhook',
  'resolve-mux-playback',
  'meta-data-deletion',
  'livekit-egress-cleanup',
];

Future<void> main() async {
  final ctx = await boot();
  final matrix = <Map<String, dynamic>>[];
  final findings = <Map<String, dynamic>>[];

  void row({
    required String surface,
    required String attack,
    required String identity,
    required String result,
    String impact = '',
    String severity = '',
    String evidence = '',
  }) {
    matrix.add({
      'surface': surface,
      'attack': attack,
      'identity': identity,
      'result': result,
      'impact': impact,
      'severity': severity,
      'evidence': evidence,
    });
  }

  void finding({
    required String id,
    required String severity,
    required String title,
    required String actor,
    required String pre,
    required String repro,
    required String impact,
    String state = 'OPEN',
  }) {
    findings.add({
      'id': id,
      'severity': severity,
      'title': title,
      'actor': actor,
      'preconditions': pre,
      'reproduction': repro,
      'impact': impact,
      'state': state,
    });
  }

  // ---- OpenAPI ----
  final oaAnon = await ctx.rest('GET', '/rest/v1/', extra: {
    'Accept': 'application/openapi+json',
  });
  final oaAuth = await ctx.rest('GET', '/rest/v1/', jwt: ctx.buyerJwt, extra: {
    'Accept': 'application/openapi+json',
  });
  Map<String, dynamic> spec = {};
  try {
    spec = jsonDecode(oaAuth.body is String && oaAuth.body.startsWith('{')
            ? oaAuth.body
            : oaAnon.body) as Map<String, dynamic>;
  } catch (_) {
    try {
      spec = jsonDecode(oaAnon.body) as Map<String, dynamic>;
    } catch (_) {}
  }
  final paths = (spec['paths'] as Map?)?.keys.map((e) => e.toString()).toList()
        ?? <String>[];
  final rpcLive = paths
      .where((p) => p.startsWith('/rpc/'))
      .map((p) => p.replaceFirst('/rpc/', ''))
      .toList()
    ..sort();
  final tableLive = paths
      .where((p) => !p.startsWith('/rpc/') && p != '/')
      .map((p) => p.replaceFirst('/', ''))
      .toList()
    ..sort();

  row(
    surface: 'OpenAPI',
    attack: 'dump paths',
    identity: 'buyer JWT',
    result:
        'tables=${tableLive.length} rpcs=${rpcLive.length} http=${oaAuth.status}',
    evidence: 'rpc_sample=${rpcLive.take(20).join(",")}',
  );

  // ---- RLS SELECT matrix ----
  final rlsSelect = <String, Map<String, dynamic>>{};
  final selectTables = <String>{...tables, ...tableLive}.toList()..sort();
  for (final t in selectTables) {
    if (t.isEmpty || t.contains('{')) continue;
    final anonH = await ctx.select(t, limit: 3);
    final buyerH = await ctx.select(t, jwt: ctx.buyerJwt, limit: 8);
    final sellerH = await ctx.select(t, jwt: ctx.sellerJwt, limit: 8);
    int count(Hit h) {
      final j = h.json;
      if (j is List) return j.length;
      return 0;
    }

    rlsSelect[t] = {
      'anon': '${anonH.status}/${count(anonH)} ${anonH.snippet}',
      'buyer': '${buyerH.status}/${count(buyerH)}',
      'seller': '${sellerH.status}/${count(sellerH)}',
    };

    // Flag: anon reads sensitive tables with rows
    final sensitive = {
      'orders',
      'wallets',
      'wallet_transactions',
      'wallet_payout_ledger',
      'chat_messages',
      'messages',
      'disputes',
      'order_disputes',
      'seller_device_tokens',
      'ps_pairing_codes',
      'stripe_checkout_events',
      'app_logs',
      'live_tips',
    };
    if (sensitive.contains(t) && anonH.ok && count(anonH) > 0) {
      finding(
        id: 'P1-ANON-SELECT-$t',
        severity: 'P1',
        title: 'Anon SELECT devolve linhas em $t',
        actor: 'anon',
        pre: 'sem JWT',
        repro: 'GET /rest/v1/$t',
        impact: 'leitura de dados potencialmente alheios',
      );
    }
    row(
      surface: 'RLS SELECT $t',
      attack: 'GET * limit',
      identity: 'anon/buyer/seller',
      result:
          'a=${anonH.status}/${count(anonH)} b=${buyerH.status}/${count(buyerH)} s=${sellerH.status}/${count(sellerH)}',
    );
  }

  // ---- Cross-user SELECT on orders/wallets/chat ----
  final otherOrders = await ctx.select(
    'orders',
    jwt: ctx.buyerJwt,
    filter: 'seller_id=eq.${ctx.sellerId}&buyer_id=neq.${ctx.buyerId}',
    select: 'id,buyer_id,seller_id,status,price_total,amount_paid_cents',
    limit: 20,
  );
  final buyerSawOthers = (otherOrders.json is List)
      ? (otherOrders.json as List).where((e) {
          final m = e as Map;
          return m['buyer_id'] != ctx.buyerId && m['seller_id'] != ctx.buyerId;
        }).length
      : 0;
  row(
    surface: 'ORDERS',
    attack: 'SELECT foreign seller orders',
    identity: 'buyer',
    result: 'http=${otherOrders.status} foreign_rows=$buyerSawOthers',
    impact: buyerSawOthers > 0 ? 'cross-user order leak' : 'none',
    severity: buyerSawOthers > 0 ? 'P1' : '',
    evidence: otherOrders.snippet,
  );
  if (buyerSawOthers > 0) {
    finding(
      id: 'P1-ORDERS-CROSS-SELECT',
      severity: 'P1',
      title: 'Buyer lê orders de outros buyers do mesmo seller',
      actor: 'buyer JWT',
      pre: 'IDs de seller conhecidos',
      repro: 'GET orders?seller_id=eq.<seller>&buyer_id=neq.<self>',
      impact: 'PII financeiro / estado de encomendas alheias',
    );
  }

  final sellerWalletAsBuyer = await ctx.select(
    'wallets',
    jwt: ctx.buyerJwt,
    filter: 'id=eq.${ctx.sellerId}',
    select: 'id,balance,stripe_account_id',
  );
  row(
    surface: 'WALLET',
    attack: 'SELECT seller wallet',
    identity: 'buyer',
    result:
        '${sellerWalletAsBuyer.status} ${sellerWalletAsBuyer.snippet}',
  );

  // ---- INSERT/UPDATE hostile ----
  // 1) wallet insert with balance
  final wIns = await ctx.rest('POST', '/rest/v1/wallets', jwt: ctx.buyerJwt, body: {
    'id': ctx.buyerId,
    'balance': 99999.99,
    'stripe_account_id': 'acct_attacker',
  });
  row(
    surface: 'WALLET',
    attack: 'INSERT balance 99999',
    identity: 'buyer',
    result: '${wIns.status} ${wIns.snippet}',
  );

  final wUpd = await ctx.rest(
    'PATCH',
    '/rest/v1/wallets?id=eq.${ctx.buyerId}',
    jwt: ctx.buyerJwt,
    body: {'balance': 88888.88},
  );
  final wAfter = await ctx.select(
    'wallets',
    jwt: ctx.buyerJwt,
    filter: 'id=eq.${ctx.buyerId}',
    select: 'id,balance',
    service: true,
  );
  row(
    surface: 'WALLET',
    attack: 'UPDATE own balance',
    identity: 'buyer',
    result: 'patch=${wUpd.status} ${wUpd.snippet} after=${wAfter.snippet}',
  );

  final wTx = await ctx.rest(
    'POST',
    '/rest/v1/wallet_transactions',
    jwt: ctx.buyerJwt,
    body: {
      'wallet_id': ctx.buyerId,
      'amount': 500,
      'type': 'reembolso',
      'description': 'cega-1243 mint',
    },
  );
  row(
    surface: 'WALLET_TX',
    attack: 'INSERT reembolso 500',
    identity: 'buyer',
    result: '${wTx.status} ${wTx.snippet}',
  );

  // profiles user_type elevation
  final profBefore = await ctx.select(
    'profiles',
    jwt: ctx.buyerJwt,
    filter: 'id=eq.${ctx.buyerId}',
    select: 'id,user_type,email,iban,mbway,phone',
    service: true,
  );
  final profUpd = await ctx.rest(
    'PATCH',
    '/rest/v1/profiles?id=eq.${ctx.buyerId}',
    jwt: ctx.buyerJwt,
    body: {'user_type': 'admin'},
  );
  final profAfter = await ctx.select(
    'profiles',
    jwt: ctx.buyerJwt,
    filter: 'id=eq.${ctx.buyerId}',
    select: 'id,user_type',
    service: true,
  );
  row(
    surface: 'PROFILES',
    attack: 'UPDATE user_type=admin',
    identity: 'buyer',
    result:
        'patch=${profUpd.status} before=${profBefore.snippet} after=${profAfter.snippet}',
  );

  // stream keys
  final livesBuyer = await ctx.select(
    'lives',
    jwt: ctx.buyerJwt,
    select: 'id,seller_id,mux_stream_key,stream_key,mux_playback_id,status',
    limit: 5,
  );
  final livesAnon = await ctx.select(
    'lives',
    select: 'id,mux_stream_key,stream_key,status',
    limit: 5,
  );
  row(
    surface: 'MUX',
    attack: 'SELECT stream keys',
    identity: 'buyer/anon',
    result: 'b=${livesBuyer.status} ${livesBuyer.snippet} a=${livesAnon.status} ${livesAnon.snippet}',
  );

  // draw_seed
  final raffle = await ctx.select(
    'live_raffles',
    jwt: ctx.buyerJwt,
    select: 'id,title,status,draw_seed,seller_id',
    limit: 5,
  );
  row(
    surface: 'RAFFLE',
    attack: 'SELECT draw_seed',
    identity: 'buyer',
    result: '${raffle.status} ${raffle.snippet}',
  );

  // banking
  final bankRpc = await ctx.rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': ctx.sellerId},
    jwt: ctx.buyerJwt,
  );
  row(
    surface: 'BANKING',
    attack: 'RPC seller_direct_payment_details of other',
    identity: 'buyer',
    result: '${bankRpc.status} ${bankRpc.snippet}',
  );
  final bankSeller = await ctx.rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': ctx.sellerId},
    jwt: ctx.sellerJwt,
  );
  row(
    surface: 'BANKING',
    attack: 'RPC own payout/direct details',
    identity: 'seller',
    result: '${bankSeller.status} ${bankSeller.snippet}',
  );

  // email enum
  final emailRpcB = await ctx.rpc(
    'batata_find_user_id_by_email',
    {'p_email': 'axinoqua@axinoquaa.pt'},
    jwt: ctx.buyerJwt,
  );
  final emailRpcS = await ctx.rpc(
    'batata_find_user_id_by_email',
    {'p_email': 'axinoqua@axinoquaa.pt'},
    jwt: ctx.sellerJwt,
  );
  row(
    surface: 'AUTH',
    attack: 'email→uuid',
    identity: 'buyer',
    result: '${emailRpcB.status} ${emailRpcB.snippet}',
  );
  row(
    surface: 'AUTH',
    attack: 'email→uuid',
    identity: 'seller',
    result: '${emailRpcS.status} ${emailRpcS.snippet}',
  );

  // ---- RPCs ----
  final rpcResults = <String, Map<String, String>>{};
  for (final fn in {...rpcCandidates, ...rpcLive}.toList()..sort()) {
    if (fn.isEmpty) continue;
    final params = _rpcParams(fn, ctx);
    final a = await ctx.rpc(fn, params);
    final b = await ctx.rpc(fn, params, jwt: ctx.buyerJwt);
    final s = await ctx.rpc(fn, params, jwt: ctx.sellerJwt);
    rpcResults[fn] = {
      'anon': '${a.status} ${a.snippet}',
      'buyer': '${b.status} ${b.snippet}',
      'seller': '${s.status} ${s.snippet}',
    };
    row(
      surface: 'RPC $fn',
      attack: 'EXECUTE default params',
      identity: 'anon/buyer/seller',
      result:
          'a=${a.status} b=${b.status} s=${s.status} bBody=${b.snippet}',
    );
    // Flag: wallet credit succeeded
    if (fn.contains('credit_wallet') ||
        fn.contains('payout_debit') ||
        fn.contains('release_seller') ||
        fn.contains('refund_buyer')) {
      if (b.ok && !b.snippet.contains('"ok":false') && !b.snippet.toLowerCase().contains('permission')) {
        finding(
          id: 'P0-RPC-$fn',
          severity: 'P0',
          title: 'RPC financeiro $fn executável por JWT buyer',
          actor: 'buyer JWT',
          pre: 'JWT autenticado',
          repro: 'POST /rest/v1/rpc/$fn',
          impact: 'possível mint/release/refund sem autoridade',
        );
      }
    }
  }

  // ---- Edges ----
  final edgeResults = <String, Map<String, String>>{};
  for (final fn in edges) {
    final a = await ctx.edge(fn, {'probe': true});
    final b = await ctx.edge(fn, _edgeBody(fn, ctx), jwt: ctx.buyerJwt);
    final s = await ctx.edge(fn, _edgeBody(fn, ctx), jwt: ctx.sellerJwt);
    edgeResults[fn] = {
      'anon': '${a.status} ${a.snippet}',
      'buyer': '${b.status} ${b.snippet}',
      'seller': '${s.status} ${s.snippet}',
    };
    row(
      surface: 'EDGE $fn',
      attack: 'POST hostile default',
      identity: 'anon/buyer/seller',
      result:
          'a=${a.status} ${a.snippet} | b=${b.status} ${b.snippet} | s=${s.status} ${s.snippet}',
    );
  }

  // fase2_e2e_settle with buyer JWT
  final e2e = await ctx.rest(
    'POST',
    '/functions/v1/create-payment-intent?fase2_e2e_settle=1',
    jwt: ctx.buyerJwt,
    body: {
      'order_id': '00000000-0000-0000-0000-000000000001',
      'payment_intent_id': 'pi_fake',
    },
  );
  row(
    surface: 'EDGE create-payment-intent',
    attack: 'fase2_e2e_settle JWT',
    identity: 'buyer',
    result: '${e2e.status} ${e2e.snippet}',
  );

  // webhook without signature
  final wh = await ctx.edge('stripe-webhook', {'type': 'checkout.session.completed'});
  row(
    surface: 'EDGE stripe-webhook',
    attack: 'POST unsigned',
    identity: 'anon',
    result: '${wh.status} ${wh.snippet}',
  );

  // storage list
  final buckets = await ctx.rest('GET', '/storage/v1/bucket', jwt: ctx.buyerJwt);
  row(
    surface: 'STORAGE',
    attack: 'list buckets',
    identity: 'buyer',
    result: '${buckets.status} ${buckets.snippet}',
  );
  for (final bkt in ['chat_media', 'avatars', 'product_photos', 'return_proofs', 'dispute_evidence']) {
    final list = await ctx.rest(
      'GET',
      '/storage/v1/object/list/$bkt',
      jwt: ctx.buyerJwt,
      body: {'prefix': '', 'limit': 20},
    );
    row(
      surface: 'STORAGE $bkt',
      attack: 'list objects',
      identity: 'buyer',
      result: '${list.status} ${list.snippet}',
    );
  }

  // notifications / follows
  final notif = await ctx.select('notifications', jwt: ctx.buyerJwt, limit: 5);
  row(
    surface: 'NOTIFICATIONS',
    attack: 'SELECT',
    identity: 'buyer',
    result: '${notif.status} ${notif.snippet}',
  );

  await writeOut('pass1.json', {
    'pass': 1,
    'tables_openapi': tableLive,
    'rpcs_openapi': rpcLive,
    'rls_select': rlsSelect,
    'rpc_results': rpcResults,
    'edge_results': edgeResults,
    'matrix': matrix,
    'findings': findings,
  });

  stdout.writeln('PASS1 done findings=${findings.length} matrix=${matrix.length}');
}

Map<String, dynamic> _rpcParams(String fn, ProbeCtx ctx) {
  switch (fn) {
    case 'batata_credit_wallet_once':
      return {
        'p_wallet_id': ctx.buyerId,
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 50,
        'p_type': 'reembolso',
        'p_description': 'cega',
      };
    case 'batata_debit_wallet_once':
      return {
        'p_wallet_id': ctx.sellerId,
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 1,
        'p_type': 'venda',
      };
    case 'batata_ensure_wallet':
      return {'p_user_id': ctx.buyerId};
    case 'batata_release_seller_wallet_for_order':
    case 'batata_refund_buyer_wallet_for_order':
    case 'batata_clawback_seller_wallet_for_order':
      return {'p_order_id': '00000000-0000-0000-0000-000000000001'};
    case 'batata_process_partial_refund_dispute':
      return {
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 1,
      };
    case 'batata_wallet_payout_debit':
      return {
        'p_user_id': ctx.buyerId,
        'p_amount_cents': 100,
        'p_idempotency_key': 'cega-1243-payout-debit',
      };
    case 'batata_wallet_payout_finish':
      return {
        'p_idempotency_key': 'cega-1243-payout-debit',
        'p_transfer_id': 'tr_fake',
        'p_ok': true,
      };
    case 'batata_wallet_apply_tip_once':
      return {
        'p_tip_id': '00000000-0000-0000-0000-000000000001',
        'p_seller_id': ctx.sellerId,
        'p_amount': 5,
        'p_source': 'stripe',
        'p_external_id': 'pi_fake',
      };
    case 'batata_send_live_tip_from_wallet':
      return {
        'p_live_id': '00000000-0000-0000-0000-000000000001',
        'p_seller_id': ctx.sellerId,
        'p_amount': 1,
        'p_message': 'x',
      };
    case 'batata_find_user_id_by_email':
      return {'p_email': 'axinoqua@axinoquaa.pt'};
    case 'batata_seller_direct_payment_details':
      return {'p_seller_id': ctx.sellerId};
    case 'batata_mark_live_item_sold':
      return {'p_live_item_id': '00000000-0000-0000-0000-000000000001'};
    case 'batata_live_reconcile_stripe_order':
      return {
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_live_item_id': '00000000-0000-0000-0000-000000000001',
      };
    case 'batata_sync_live_item_for_order':
      return {'p_order_id': '00000000-0000-0000-0000-000000000001'};
    case 'batata_lab_clear_fm_pending':
      return {'p_seller_id': ctx.sellerId};
    case 'batata_create_raffle_prize_order':
      return {
        'p_raffle_id': '00000000-0000-0000-0000-000000000001',
        'p_winner_id': ctx.buyerId,
        'p_qty': 1,
      };
    case 'batata_tick_live_raffle':
      return {'p_raffle_id': '00000000-0000-0000-0000-000000000001'};
    case 'batata_create_seller_device_token':
      return {'p_label': 'cega', 'p_app_version': '1'};
    case 'batata_ps_claim_pairing':
      return {
        'p_code': '000000',
        'p_device_id': 'attacker',
        'p_app_version': '1',
        'p_client_ip': '1.1.1.1',
      };
    case 'batata_live_bag_update_qty':
      return {
        'p_request_id': '00000000-0000-0000-0000-000000000001',
        'p_qty': 99,
      };
    case 'batata_product_checkout_available':
      return {
        'p_product_id': '00000000-0000-0000-0000-000000000001',
        'p_exclude_order_id': null,
        'p_qty': 1,
        'p_exclude_order_ids': null,
      };
    case 'batata_live_reservation_accept_available':
      return {
        'p_live_item_id': '00000000-0000-0000-0000-000000000001',
        'p_buyer_id': ctx.buyerId,
      };
    case 'batata_live_item_stock':
      return {'p_live_item_id': '00000000-0000-0000-0000-000000000001'};
    case 'batata_backfill_handle_suggestions':
      return {'p_force': true};
    case 'batata_claim_handle':
      return {'p_handle': 'cega1243'};
    case 'batata_resolve_handle':
      return {'p_handle': 'test'};
    case 'batata_publish_hub':
      return {'p_publish': true};
    default:
      return <String, dynamic>{};
  }
}

Map<String, dynamic> _edgeBody(String fn, ProbeCtx ctx) {
  switch (fn) {
    case 'create-payment-intent':
      return {
        'buyer_id': ctx.buyerId,
        'seller_id': ctx.sellerId,
        'amount': 50,
        'quantity': 1,
        'shipping_method': 'hand',
        'order_id': '00000000-0000-0000-0000-000000000001',
      };
    case 'create-live-tip-checkout':
      return {
        'live_id': '00000000-0000-0000-0000-000000000001',
        'seller_id': ctx.sellerId,
        'amount_eur': 1,
      };
    case 'refund-order':
      return {'order_id': '00000000-0000-0000-0000-000000000001'};
    case 'create-connect-account':
      return {
        'user_id': ctx.sellerId,
        'amount': 100,
        'idempotency_key': 'cega-1243-payout',
      };
    case 'create-mux-live':
      return {'title': 'cega-audit-live-title'};
    case 'complete-mux-live':
      return {'live_id': '00000000-0000-0000-0000-000000000001'};
    case 'livekit-mux-publish':
      return {
        'step': 'token',
        'live_id': '00000000-0000-0000-0000-000000000001',
        'stream_key': 'sk_attacker',
      };
    case 'ingest-ocr-reservation':
      return {
        'live_id': '00000000-0000-0000-0000-000000000001',
        'ocr_line_hash': 'abcdefgh',
        'detected_at': DateTime.now().toUtc().toIso8601String(),
        'ref_number': 1,
      };
    case 'ps-pairing-claim':
      return {'code': '000000', 'device_id': 'attacker'};
    case 'delete-test-account':
      return {'confirm': 'APAGAR TUDO'};
    case 'sec-fase2-e2e-oversell':
      return {'probe': '1'};
    default:
      return {'probe': true};
  }
}
