/// PASS 5 — hostile sweep of high-risk RPCs from live OpenAPI inventory.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '_http.dart';

const targets = [
  'batata_order_payment_confirmed',
  'batata_admin_resolve_dispute',
  'batata_process_partial_refund_dispute',
  'staging_restore_stock_before_nuke',
  'staging_nuke_user_data',
  'batata_staging_h_v1_ux_demo_seed',
  'batata_staging_set_fleahub_test_state',
  'batata_admin_list_profiles',
  'batata_is_admin',
  'batata_clawback_seller_wallet_for_order',
  'batata_create_raffle_prize_order',
  'batata_debit_wallet_once',
  'batata_credit_wallet_once',
  'batata_wallet_payout_finish',
  'batata_record_buyer_purchase_ledger',
  'batata_record_buyer_refund_ledger',
  'batata_record_fleaber_commission_once',
  'batata_wallet_apply_tip_once',
  'batata_live_reservation_stripe_convert',
  'batata_lab_clear_fm_pending',
  'batata_lab_clear_all_fm_pending',
  'batata_invoke_livekit_egress_cleanup',
  'batata_migrate_live_catalog',
  'batata_expire_product_offers',
  'batata_live_reconcile_stripe_order',
  'batata_claim_external_reservations',
  'set_active_live_item',
  'batata_update_live_item',
  'batata_close_live_raffle',
  'batata_activate_live_raffle',
  'batata_draw_live_raffle_winners',
  'batata_award_live_raffle_tickets',
  'batata_create_live_raffle',
  'batata_mark_live_item_sold',
  'batata_sync_live_item_for_order',
  'batata_confirm_ps_reservation',
  'batata_confirm_ps_reservation_v2',
  'batata_ingest_ocr_reservation',
  'batata_ingest_ocr_reservation_v2',
  'batata_process_live_reservation_request',
  'batata_live_bag_update_qty',
  'batata_live_reservation_accept_available',
  'batata_live_reservation_accept_broadcast',
  'batata_live_reservation_force_pending_manual',
  'batata_upsert_marketplace_live_item',
  'batata_remove_marketplace_live_item',
  'batata_publish_hub',
  'batata_backfill_handle_suggestions',
  'batata_anon_rate_check',
  'batata_create_seller_device_token',
  'batata_validate_seller_device_token',
];

Future<void> main() async {
  final c = await boot();
  final spec = await http.get(
    Uri.parse('${c.url}/rest/v1/'),
    headers: {...c.svcH, 'Accept': 'application/openapi+json'},
  );
  if (spec.statusCode != 200) {
    stderr.writeln('openapi ${spec.statusCode}');
    exit(1);
  }
  final specMap = jsonDecode(spec.body) as Map;
  final paths = specMap['paths'] as Map;

  Map<String, dynamic> paramsFor(String fn) {
    final path = paths['/rpc/$fn'];
    if (path is! Map) return {};
    final post = path['post'];
    if (post is! Map) return {};
    final params = <String, dynamic>{};
    final list = post['parameters'];
    if (list is List) {
      for (final p in list) {
        if (p is Map && p['in'] == 'query') continue;
        if (p is Map && p['name'] != null) {
          params[p['name'].toString()] = _fill(p['name'].toString(), c);
        }
      }
    }
    final body = post['requestBody'];
    if (body is Map) {
      final content = body['content'];
      if (content is Map) {
        final app = content['application/json'] ?? content['application/vnd.pgrst.object+json'];
        if (app is Map && app['schema'] is Map) {
          final schema = app['schema'] as Map;
          final props = schema['properties'];
          if (props is Map) {
            for (final k in props.keys) {
              params[k.toString()] = _fill(k.toString(), c);
            }
          }
        }
      }
    }
    return params;
  }

  for (final fn in targets) {
    final p = paramsFor(fn);
    for (final ident in ['anon', 'buyer', 'seller']) {
      final h = ident == 'anon'
          ? c.anonH
          : ident == 'buyer'
              ? c.buyerH
              : c.sellerH;
      final r = await rpcRaw(c.url, fn, p, headers: h);
      rec(
        surface: 'RPC $fn',
        attack: 'hostile ${p.keys.take(8).join(",")}',
        identity: ident,
        result: brief(r, 240),
      );
      if (looksOk(r) && _isDangerousSuccess(fn, r.body, ident)) {
        finding(
          id: 'RT1752-RPC-$fn-$ident',
          severity: _sev(fn),
          title: 'RPC $fn executada com sucesso por $ident',
          actor: ident,
          pre: 'OpenAPI params preenchidos de forma hostil',
          repro: 'POST /rpc/$fn $p',
          impact: fn,
          evidence: brief(r),
        );
      }
    }
  }

  await dumpJson(
    'tool/redteam_blind_indep_20260830T1752/out/pass5.json',
    {
      'project': projectMust,
      'pass': 5,
      'matrix': matrix,
      'findings': findings,
      'gaps': gaps,
    },
  );
  stdout.writeln('PASS5 done matrix=${matrix.length} findings=${findings.length}');
}

dynamic _fill(String name, Ctx c) {
  final n = name.toLowerCase();
  if (n.contains('email')) return 'axinoqua@axinoquaa.pt';
  if (n.contains('buyer')) return c.buyerId;
  if (n.contains('seller') || n.contains('user_id') || n.contains('wallet')) {
    return c.sellerId;
  }
  if (n.contains('amount') || n.contains('cents') || n.contains('qty') || n.contains('quantity')) {
    return 1;
  }
  if (n.contains('token') || n.contains('code') || n.contains('key')) {
    return 'abcdefghijkl';
  }
  if (n.contains('status')) return 'pago';
  if (n.contains('live_id')) return '00000000-0000-0000-0000-000000000001';
  if (n.contains('order')) return '00000000-0000-0000-0000-000000000001';
  if (n.contains('product') || n.contains('item') || n.contains('raffle') || n.contains('id')) {
    return '00000000-0000-0000-0000-000000000001';
  }
  if (n.contains('title') || n.contains('name') || n.contains('msg') || n.contains('text')) {
    return prefix;
  }
  if (n.startsWith('p_') || n.startsWith('has') || n.startsWith('is')) return true;
  return 1;
}

bool _isDangerousSuccess(String fn, String body, String ident) {
  if (fn == 'batata_is_admin' || fn == 'batata_staff_has_permission') {
    return body.trim() == 'true';
  }
  if (fn.contains('admin_list') && ident != 'observe' && body.contains('[')) {
    return body.length > 8 && body != '[]' && !body.contains('permission');
  }
  const alwaysDanger = [
    'payment_confirmed',
    'nuke',
    'seed',
    'credit',
    'debit',
    'clawback',
    'commission',
    'payout_finish',
    'prize_order',
    'mark_live_item_sold',
    'stripe_convert',
    'reconcile',
    'partial_refund',
    'resolve_dispute',
  ];
  return alwaysDanger.any(fn.contains);
}

String _sev(String fn) {
  if (fn.contains('nuke') ||
      fn.contains('credit') ||
      fn.contains('payment_confirmed') ||
      fn.contains('payout') ||
      fn.contains('commission') ||
      fn.contains('admin_resolve')) {
    return 'P0';
  }
  return 'P1';
}
